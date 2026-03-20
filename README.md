# PatentsView Snapshots

This directory contains bulk snapshots of the [PatentsView](https://patentsview.org/) database,
downloaded from the USPTO/PatentsView public data distribution. All data are tab-delimited TSV
files (`.tsv`) distributed as ZIP archives (`.tsv.zip`).

> **Note (March 2026):** PatentsView is migrating to the
> [USPTO Open Data Portal](https://data.uspto.gov) on March 20, 2026. Future snapshots will
> originate from `data.uspto.gov`.

---

## Directory Layout

```
PatentsView_Snapshots/
├── download_patentsview.sh      # Script that produces each snapshot (see below)
├── latest -> 20260319/          # Symlink pointing to the most recent snapshot
├── 20260319/                    # Snapshot taken 2026-03-19 (YYYYMMDD)
│   ├── data/                    # All downloaded .tsv.zip files (≈239 GB uncompressed)
│   ├── download.log             # Full stdout/stderr log of the download run
│   ├── download_page.html       # Scraped granted-patent download page (cached)
│   ├── pg_download_page.html    # Scraped pre-grant download page (cached)
│   ├── fulltext_<table>.html    # Scraped sub-pages for each year-split full-text table
│   ├── urls.txt                 # Deduplicated list of all .zip URLs downloaded
│   └── failed_downloads.txt     # URLs that failed (empty = all succeeded)
└── uspto_bulk/
    └── 20260319/                # Partial snapshot (download was interrupted; data/ is empty)
```

Each new snapshot goes into a `YYYYMMDD/` folder; `latest` is updated to point to it.

---

## Downloading / Updating

```bash
bash download_patentsview.sh            # full download
bash download_patentsview.sh --dry-run  # preview URLs only, no downloads
```

The script:
1. Scrapes the PatentsView granted and pre-grant download pages to find all current `.zip` URLs.
2. Separately fetches each full-text sub-page (which require a `Referer` header to expose links).
3. Downloads all files in parallel (`N_JOBS=4`) using `wget -c` (resume-safe).
4. Skips files whose local size already matches the server `Content-Length`.
5. Updates the `latest` symlink on success.

Re-running the script is safe — it resumes partial downloads and skips complete ones.

---

## File Format

| Property       | Value                         |
|----------------|-------------------------------|
| Encoding       | UTF-8                         |
| Field separator | Tab (`\t`)                   |
| Quoting        | Double-quote; all non-numeric fields quoted |
| Compression    | ZIP (one TSV per archive)     |

Quick access example:
```bash
unzip -p latest/data/g_patent.tsv.zip | head -5
```

---

## Data Coverage

| Dataset prefix | Coverage |
|----------------|----------|
| `g_*`  (granted patents) | Granted U.S. patents from **1976** to present |
| `pg_*` (pre-grant publications) | Published patent applications from **2001** to present |

Data through **September 30, 2025**; release date **December 10, 2025**. Licensed under
[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).

---

## Tables Reference

### Naming conventions

- **`g_`** prefix → granted patent tables; primary key is `patent_id`.
- **`pg_`** prefix → pre-grant (published application) tables; primary key is `pgpub_id`.
- **`_disambiguated`** suffix → entity IDs have been cleaned and de-duplicated by PatentsView's disambiguation algorithms.
- **`_not_disambiguated`** suffix → raw strings exactly as they appear in the USPTO source XML.

---

### Granted Patents (`g_*`)

#### Core

| File | Description | Key columns |
|------|-------------|-------------|
| `g_patent.tsv.zip` | One row per granted patent. The central table. | `patent_id`, `patent_type`, `patent_date`, `patent_title`, `wipo_kind`, `num_claims`, `withdrawn` |
| `g_application.tsv.zip` | USPTO application record for each granted patent. | `application_id`, `patent_id`, `filing_date`, `series_code` |
| `g_patent_abstract.tsv.zip` | Full abstract text. One row per patent. | `patent_id`, `patent_abstract` |
| `g_figures.tsv.zip` | Number of figures and drawing sheets. | `patent_id`, `num_figures`, `num_sheets` |
| `g_us_term_of_grant.tsv.zip` | Term-of-grant and disclaimer information. | `patent_id`, `disclaimer_date`, `term_grant`, `term_extension` |
| `g_botanic.tsv.zip` | Plant patent details (Latin name, variety). ~21 k rows. | `patent_id`, `latin_name`, `plant_variety` |

#### Inventors

| File | Description | Key columns |
|------|-------------|-------------|
| `g_inventor_disambiguated.tsv.zip` | Disambiguated inventor records. | `patent_id`, `inventor_id`, `disambig_inventor_name_first/last`, `gender_code`, `location_id` |
| `g_inventor_not_disambiguated.tsv.zip` | Raw inventor strings from USPTO XML. | `patent_id`, `inventor_id`, `raw_inventor_name_first/last`, `rawlocation_id` |
| `g_persistent_inventor.tsv.zip` | Crosswalk of inventor `inventor_id` values across every historical PatentsView release, allowing longitudinal tracking. One column per release snapshot (named `disamb_inventor_id_YYYYMMDD`). | `patent_id`, `inventor_sequence`, `disamb_inventor_id_YYYYMMDD`, … |

#### Assignees

| File | Description | Key columns |
|------|-------------|-------------|
| `g_assignee_disambiguated.tsv.zip` | Disambiguated assignee records. | `patent_id`, `assignee_id`, `disambig_assignee_organization`, `assignee_type`, `location_id` |
| `g_assignee_not_disambiguated.tsv.zip` | Raw assignee strings. | `patent_id`, `assignee_id`, `raw_assignee_organization`, `rawlocation_id` |
| `g_applicant_not_disambiguated.tsv.zip` | Raw non-inventor applicant data (e.g., corporate applicants on design patents). | `patent_id`, `raw_applicant_name_first/last`, `raw_applicant_organization` |
| `g_persistent_assignee.tsv.zip` | Crosswalk of assignee `assignee_id` values across every historical release (one column per release). | `patent_id`, `assignee_sequence`, `disamb_assignee_id_YYYYMMDD`, … |

#### Attorneys & Examiners

| File | Description | Key columns |
|------|-------------|-------------|
| `g_attorney_disambiguated.tsv.zip` | Disambiguated attorney/agent records. | `patent_id`, `attorney_id`, `disambig_attorney_name_first/last`, `disambig_attorney_organization` |
| `g_attorney_not_disambiguated.tsv.zip` | Raw attorney/agent strings. | `attorney_id`, `patent_id`, `raw_attorney_name_first/last`, `raw_attorney_organization` |
| `g_examiner_not_disambiguated.tsv.zip` | USPTO patent examiner (not disambiguated). | `patent_id`, `raw_examiner_name_first/last`, `examiner_role`, `art_group` |

#### Locations

| File | Description | Key columns |
|------|-------------|-------------|
| `g_location_disambiguated.tsv.zip` | Cleaned, geocoded locations (city, state, country, lat/lon). | `location_id`, `disambig_city`, `disambig_state`, `disambig_country`, `latitude`, `longitude` |
| `g_location_not_disambiguated.tsv.zip` | Raw location strings from USPTO XML, mapped to a `location_id`. | `rawlocation_id`, `location_id`, `raw_city`, `raw_state`, `raw_country` |

#### Classifications

| File | Description | Key columns |
|------|-------------|-------------|
| `g_cpc_current.tsv.zip` | Current CPC (Cooperative Patent Classification) assignments — retrospectively applied to all patents. | `patent_id`, `cpc_section/class/subclass/group`, `cpc_type` |
| `g_cpc_at_issue.tsv.zip` | CPC classifications as they were at the time the patent was granted. | `patent_id`, `cpc_sequence`, `cpc_version_indicator`, …, `cpc_action_date` |
| `g_cpc_title.tsv.zip` | CPC hierarchy lookup table (subclass/group titles). | `cpc_subclass`, `cpc_subclass_title`, `cpc_group`, `cpc_group_title` |
| `g_ipc_at_issue.tsv.zip` | International Patent Classification (IPC) at the time of grant. | `patent_id`, `section`, `ipc_class`, `subclass`, `main_group`, `subgroup` |
| `g_uspc_at_issue.tsv.zip` | US Patent Classification (USPC, legacy) at grant. | `patent_id`, `uspc_mainclass_id/title`, `uspc_subclass_id/title` |
| `g_wipo_technology.tsv.zip` | WIPO 35-field technology classification. | `patent_id`, `wipo_field_id`, `wipo_sector_title`, `wipo_field_title` |

#### Citations & References

| File | Description | Key columns |
|------|-------------|-------------|
| `g_us_patent_citation.tsv.zip` | U.S. granted-patent citations made by U.S. granted patents. ~151 M rows. | `patent_id`, `citation_patent_id`, `citation_date`, `citation_category` |
| `g_us_application_citation.tsv.zip` | Citations to U.S. published applications made by U.S. patents. ~77 M rows. | `patent_id`, `citation_document_number`, `citation_date`, `citation_category` |
| `g_foreign_citation.tsv.zip` | Citations to foreign patents. ~45 M rows. | `patent_id`, `citation_application_id`, `citation_date`, `citation_country` |
| `g_other_reference.tsv.zip` | Non-patent literature citations (journal articles, books, etc.). ~64 M rows. | `patent_id`, `other_reference_sequence`, `other_reference_text` |

#### Related Documents & Priority

| File | Description | Key columns |
|------|-------------|-------------|
| `g_us_rel_doc.tsv.zip` | U.S. related-document relationships (continuations, divisionals, etc.) for patents from 2002+. | `patent_id`, `related_doc_number`, `related_doc_type`, `related_doc_kind` |
| `g_foreign_priority.tsv.zip` | Foreign priority claims (Paris Convention). | `patent_id`, `foreign_application_id`, `filing_date`, `foreign_country_filed` |
| `g_pct_data.tsv.zip` | PCT (Patent Cooperation Treaty) filing information. | `patent_id`, `pct_doc_number`, `pct_371_date`, `filed_country` |
| `g_rel_app_text.tsv.zip` | Free-text "related applications" section verbatim from the patent. | `patent_id`, `rel_app_text` |

#### Government Interest

| File | Description | Key columns |
|------|-------------|-------------|
| `g_gov_interest.tsv.zip` | Raw government-interest statement text from patents. | `patent_id`, `gi_statement` |
| `g_gov_interest_org.tsv.zip` | Parsed federal agency associated with each government-interest patent. | `patent_id`, `gi_organization_id`, `fedagency_name`, `level_one/two/three` |
| `g_gov_interest_contracts.tsv.zip` | Federal contract/award numbers extracted from government-interest statements. | `patent_id`, `contract_award_number` |

---

### Granted Patents — Full-Text (year-split, `g_*_YEAR`)

These four tables contain long text fields and are **split into one file per grant year
(1976–2025)**. Each file is named `<table>_YYYY.tsv.zip`.

| File pattern | Description | Key columns |
|---|---|---|
| `g_brf_sum_text_{YEAR}.tsv.zip` | Brief summary of the invention. | `patent_id`, `summary_text` |
| `g_claims_{YEAR}.tsv.zip` | Full claim text, one row per claim. | `patent_id`, `claim_sequence`, `claim_text`, `dependent`, `claim_number`, `exemplary` |
| `g_detail_desc_text_{YEAR}.tsv.zip` | Detailed description section text. | `patent_id`, `description_text`, `description_length` |
| `g_draw_desc_text_{YEAR}.tsv.zip` | Drawing description text. | `patent_id`, `draw_desc_sequence`, `draw_desc_text` |

---

### Pre-Grant Publications (`pg_*`)

These mirror the granted-patent tables but cover **published patent applications** (PGPubs, MPEP §1120)
filed since 2001. The primary key is `pgpub_id` (the 18-digit publication number, e.g. `20210355555`)
instead of `patent_id`.

#### Core

| File | Description | Key columns |
|------|-------------|-------------|
| `pg_published_application.tsv.zip` | One row per published application. | `pgpub_id`, `application_id`, `filing_date`, `patent_type`, `published_date`, `application_title` |
| `pg_published_application_abstract.tsv.zip` | Abstract text. | `pgpub_id`, `application_abstract` |
| `pg_granted_pgpubs_crosswalk.tsv.zip` | Links `pgpub_id` to `patent_id` for applications that were ultimately granted. | `pgpub_id`, `application_id`, `patent_id` |

#### People

| File | Description |
|------|-------------|
| `pg_inventor_disambiguated.tsv.zip` | Disambiguated inventor records for published applications. |
| `pg_inventor_not_disambiguated.tsv.zip` | Raw inventor strings. |
| `pg_persistent_inventor.tsv.zip` | Crosswalk of inventor IDs across historical releases (one column per release date). |
| `pg_assignee_disambiguated.tsv.zip` | Disambiguated assignee records. |
| `pg_assignee_not_disambiguated.tsv.zip` | Raw assignee strings. |
| `pg_persistent_assignee.tsv.zip` | Crosswalk of assignee IDs across historical releases. |
| `pg_applicant_not_disambiguated.tsv.zip` | Raw applicant data (non-inventor applicants). |

#### Locations

| File | Description |
|------|-------------|
| `pg_location_disambiguated.tsv.zip` | Cleaned, geocoded locations. |
| `pg_location_not_disambiguated.tsv.zip` | Raw location strings mapped to a `location_id`. |

#### Classifications

| File | Description |
|------|-------------|
| `pg_cpc_current.tsv.zip` | Current CPC classifications (retrospectively applied). |
| `pg_cpc_at_issue.tsv.zip` | CPC classifications at the time of application submission. |
| `pg_cpc_title.tsv.zip` | CPC hierarchy lookup (identical to `g_cpc_title`). |
| `pg_ipc_at_issue.tsv.zip` | IPC classifications as of application date. |
| `pg_uspc_at_issue.tsv.zip` | Legacy USPC classifications. |
| `pg_wipo_technology.tsv.zip` | WIPO 35-field technology classification. |

#### Related Documents & Priority

| File | Description |
|------|-------------|
| `pg_foreign_priority.tsv.zip` | Foreign priority claims. |
| `pg_pct_data.tsv.zip` | PCT filing data. |
| `pg_us_rel_doc.tsv.zip` | U.S. related-document relationships (post-2005 applications). |
| `pg_rel_app_text.tsv.zip` | Verbatim "related applications" text. |

#### Government Interest

| File | Description |
|------|-------------|
| `pg_gov_interest.tsv.zip` | Raw government-interest statement text. |
| `pg_gov_interest_org.tsv.zip` | Federal agency parsed from government-interest statement. |
| `pg_gov_interest_contracts.tsv.zip` | Contract/award numbers extracted from government-interest statements. |

---

### Pre-Grant — Full-Text (year-split, `pg_*_YEAR`)

Mirrors the granted full-text tables but covering published applications **2001–2025**.

| File pattern | Description | Key columns |
|---|---|---|
| `pg_brf_sum_text_{YEAR}.tsv.zip` | Brief summary text. | `pgpub_id`, `summary_text` |
| `pg_claims_{YEAR}.tsv.zip` | Full claim text, one row per claim. | `pgpub_id`, `claim_sequence`, `claim_text`, `dependent`, `claim_number` |
| `pg_detail_desc_text_{YEAR}.tsv.zip` | Detailed description text. | `pgpub_id`, `description_text`, `description_length` |
| `pg_draw_desc_text_{YEAR}.tsv.zip` | Drawing description text. | `pgpub_id`, `draw_desc_sequence`, `draw_desc_text` |

---

## Snapshot Metadata Files

Each `YYYYMMDD/` snapshot folder also contains the following auxiliary files:

| File | Description |
|------|-------------|
| `download.log` | Full console log from the download run (timestamps, file sizes, success/failure summary). |
| `urls.txt` | Deduplicated list of all `.zip` URLs that were scraped and downloaded. |
| `failed_downloads.txt` | URLs that failed to download (empty if all succeeded). |
| `download_page.html` | Cached HTML of the PatentsView granted-patent download page at scrape time. |
| `pg_download_page.html` | Cached HTML of the pre-grant download page. |
| `fulltext_<table>.html` | Cached HTML of each full-text sub-page (one per year-split table). |

---

## Linking Tables

The tables join on the following keys:

- **`patent_id`** — links all `g_*` tables to `g_patent`.
- **`pgpub_id`** — links all `pg_*` tables to `pg_published_application`.
- **`location_id`** — links `g_location_disambiguated` / `pg_location_disambiguated` to the `*_disambiguated` people tables.
- **`rawlocation_id`** — links `g_location_not_disambiguated` / `pg_location_not_disambiguated` to the `*_not_disambiguated` people tables.
- **`assignee_id` / `inventor_id`** — persistent entity identifiers used in the `*_persistent_*` crosswalk tables.
- **`pgpub_id` ↔ `patent_id`** — use `pg_granted_pgpubs_crosswalk` to join pre-grant and granted data.

---

## Sources & Attribution

- **Data source:** U.S. Patent and Trademark Office public bulk data, redistributed by PatentsView.
- **Original download pages:**
  - Granted patents: `https://patentsview.org/download/data-download-tables`
  - Pre-grant publications: `https://patentsview.org/download/pg-download-tables`
- **License:** [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- **Attribution:** U.S. Patent and Trademark Office. "Data Download Tables." PatentsView. `https://patentsview.org/download/data-download-tables`
- **Data dictionary:** `https://patentsview.org/download/data-download-tables` (see "Data Dictionaries Homepage")
- **Code examples:** `https://github.com/PatentsView/PatentsView-Code-Examples`
