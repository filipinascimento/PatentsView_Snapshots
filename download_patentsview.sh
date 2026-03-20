#!/bin/bash
set -euo pipefail

# =============================================================================
# PatentsView Bulk Data Downloader
#
# Scrapes the PatentsView download page to discover current URLs, then
# downloads all tables in parallel into a timestamped snapshot directory.
#
# Usage: bash download_patentsview.sh [--dry-run]
# =============================================================================

# -----------------------------
# Config
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}"
DATESTAMP=$(date +"%Y%m%d")
TARGET_DIR="${BASE_DIR}/${DATESTAMP}"
LATEST_LINK="${BASE_DIR}/latest"

GRANTED_PAGE="https://patentsview.org/download/data-download-tables"
PREGRANT_PAGE="https://patentsview.org/download/pg-download-tables"

# Full-text tables are split by year and live on individual sub-pages.
# Each sub-page requires a Referer header to return download links.
FULLTEXT_GRANTED_TABLES=(brf_sum_text claims detail_desc_text draw_desc_text)
FULLTEXT_PREGRANT_TABLES=(pg_brf_sum_text pg_claims pg_detail_desc_text pg_draw_desc_text)

USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
N_JOBS=4
DRY_RUN=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# -----------------------------
# Dependency checks
# -----------------------------
for cmd in curl wget grep sort wc; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' is not installed."
    exit 1
  fi
done

# -----------------------------
# Create directory structure
# -----------------------------
mkdir -p "${TARGET_DIR}/data"

# -----------------------------
# Logging
# -----------------------------
exec > >(tee "${TARGET_DIR}/download.log") 2>&1

echo "=================================================="
echo "PatentsView bulk data snapshot"
echo "Started   : $(date)"
echo "Snapshot  : ${TARGET_DIR} (reusing if exists)"
echo "Dry run   : ${DRY_RUN}"
echo "Workers   : ${N_JOBS}"
echo "=================================================="

# -----------------------------
# Scrape all download pages for URLs
# -----------------------------
: > "${TARGET_DIR}/urls.txt"

# Helper: fetch a page and append .zip URLs to urls.txt
scrape_page() {
  local url="$1"
  local referer="${2:-}"
  local label="$3"
  local page_file="$4"

  echo
  echo "Fetching ${label}: ${url}"
  curl -fsSL \
    -H "User-Agent: ${USER_AGENT}" \
    -H "Accept: text/html" \
    ${referer:+-H "Referer: ${referer}"} \
    "${url}" \
    -o "${page_file}"

  local n
  n=$(grep -oE 'https://[^"<> ]+\.zip[^"<> ]*' "${page_file}" | sort -u | tee -a "${TARGET_DIR}/urls.txt" | wc -l)
  echo "  -> ${n} .zip URL(s) found ($(wc -c < "${page_file}") bytes)"
}

# 1. Granted patent metadata (single-file tables)
scrape_page \
  "${GRANTED_PAGE}" "" \
  "Granted Patent Metadata page" \
  "${TARGET_DIR}/download_page.html"

# 2. Pre-grant publication metadata (single-file tables)
scrape_page \
  "${PREGRANT_PAGE}" "${GRANTED_PAGE}" \
  "Pre-Grant Publications Metadata page" \
  "${TARGET_DIR}/pg_download_page.html"

# 3. Full-text tables — granted (split by year; require Referer to expose links)
echo
echo "Fetching full-text sub-pages for granted patents..."
for table in "${FULLTEXT_GRANTED_TABLES[@]}"; do
  scrape_page \
    "https://patentsview.org/download/${table}" "${GRANTED_PAGE}" \
    "Granted full-text: ${table}" \
    "${TARGET_DIR}/fulltext_${table}.html"
done

# 4. Full-text tables — pre-grant (split by year; require Referer to expose links)
echo
echo "Fetching full-text sub-pages for pre-grant publications..."
for table in "${FULLTEXT_PREGRANT_TABLES[@]}"; do
  scrape_page \
    "https://patentsview.org/download/${table}" "${PREGRANT_PAGE}" \
    "Pre-grant full-text: ${table}" \
    "${TARGET_DIR}/fulltext_${table}.html"
done

# Deduplicate the combined URL list
sort -u "${TARGET_DIR}/urls.txt" -o "${TARGET_DIR}/urls.txt"

URL_COUNT=$(wc -l < "${TARGET_DIR}/urls.txt" | tr -d ' ')
echo
echo "Total unique .zip download URLs across all pages: ${URL_COUNT}"

if [ "${URL_COUNT}" -eq 0 ]; then
  echo "ERROR: No download URLs found. The page layout may have changed."
  exit 1
fi

echo
echo "URLs to download:"
cat "${TARGET_DIR}/urls.txt"

if [ "${DRY_RUN}" = true ]; then
  echo
  echo "Dry run — skipping downloads."
  echo "URL list: ${TARGET_DIR}/urls.txt"
  exit 0
fi

# -----------------------------
# Parallel downloads (resume-safe)
# -----------------------------
echo
echo "Downloading ${URL_COUNT} files with ${N_JOBS} parallel workers..."
echo "(wget -c resumes partial downloads; --no-clobber skips completed ones)"
echo

FAIL_LOG="${TARGET_DIR}/failed_downloads.txt"
: > "${FAIL_LOG}"

download_one() {
  local url="$1"
  local filename
  filename=$(basename "${url%%\?*}")
  local dest="${TARGET_DIR}/data/${filename}"

  # Skip only if local file size matches server Content-Length (truly complete).
  # Partial files will be resumed by wget -c; empty/missing files downloaded fresh.
  # Note: --no-clobber is intentionally omitted; it exits non-zero when a file
  # exists, causing false failures.
  local local_size=0
  [[ -f "${dest}" ]] && local_size=$(stat -c%s "${dest}")
  local remote_size
  remote_size=$(curl -sI "${url}" | grep -i '^content-length' | tail -1 | awk '{print $2}' | tr -d '\r')
  if [[ -n "${remote_size}" && "${local_size}" -eq "${remote_size}" ]]; then
    echo "[SKIP]  ${filename}  ($(du -h "${dest}" | cut -f1), already complete)"
    return 0
  fi

  echo "[START] ${filename}"
  if wget -c --show-progress --progress=bar:force \
       -O "${dest}" "${url}" 2>/dev/tty; then
    echo "[OK]    ${filename}  ($(du -h "${dest}" | cut -f1))"
  else
    echo "[FAIL]  ${filename}"
    echo "${url}" >> "${FAIL_LOG}"
  fi
}
export -f download_one
export TARGET_DIR FAIL_LOG

xargs -P "${N_JOBS}" -n 1 -I {} bash -c 'download_one "$@"' _ {} \
  < "${TARGET_DIR}/urls.txt"

# -----------------------------
# Summary
# -----------------------------
FAIL_COUNT=$(wc -l < "${FAIL_LOG}" | tr -d ' ')
SUCCESS_COUNT=$(( URL_COUNT - FAIL_COUNT ))
TOTAL_SIZE=$(du -sh "${TARGET_DIR}/data" 2>/dev/null | cut -f1)

echo
echo "=================================================="
echo "Download complete"
echo "  Succeeded : ${SUCCESS_COUNT} / ${URL_COUNT}"
echo "  Failed    : ${FAIL_COUNT}"
echo "  Total size: ${TOTAL_SIZE}"
echo "=================================================="

if [ "${FAIL_COUNT}" -gt 0 ]; then
  echo
  echo "Failed URLs saved to: ${FAIL_LOG}"
  echo "Re-run the script to retry (wget -c resumes partial downloads)."
fi

# -----------------------------
# Update 'latest' symlink
# -----------------------------
echo
ln -sfn "${DATESTAMP}" "${LATEST_LINK}"
echo "Latest symlink: ${LATEST_LINK} -> ${DATESTAMP}"
echo "Snapshot folder: ${TARGET_DIR}"
echo "Log file: ${TARGET_DIR}/download.log"
echo "Finished: $(date)"

if [ "${FAIL_COUNT}" -gt 0 ]; then
  exit 1
fi
