MIMIC-IV v3.1 — authoritative S4 source/derived-tables-to-analytic code
=====================================================


DERIVED-CONCEPT PROVENANCE
--------------------------
The analytic SQL uses locally available mimiciv_derived concept tables for
Charlson comorbidity, first-day GCS, ventilation, and vasoactive-agent
variables in addition to source MIMIC-IV tables. The exact historical MIMIC
Code release/commit used to construct that local derived schema was not
archived contemporaneously, so this package does not assert a retrospective
version that cannot be verified. The historical filename
MIMIC_00_RAW_TO_ANALYTIC_EXACT_FINAL.sql is retained for manifest continuity,
but the reproducible scope is source/derived database tables to the locked
analytic datasets.

For a fresh reconstruction against MIMIC-IV v3.1, use a MIMIC Code release
documented as aligned with v3.1 and archive its metadata. Official MIMIC Code
v3.0.0 (commit e8658d5) was released to rebuild mimiciv_derived using
MIMIC-IV v3.1; v3.0.1 (commit c7e0756) added mimiciv_derived._metadata with
mimic_version, mimic_code_version, and mimic_code_commit_hash. These release
identifiers are provided as forward-looking reconstruction guidance, not as a
claim about the historical local build used in this study.

Release information: https://github.com/MIT-LCP/mimic-code/releases

Run:
  MIMIC_00_RAW_TO_ANALYTIC_EXACT_FINAL.sql

Then export with:
  MIMIC_FINAL_EXPORT_QUERIES.sql

Primary frozen cohort:
  principal ICD-10 I63*
  adult
  first ICU stay within the hospitalization
  first qualifying I63* ICU admission per patient
  no ICU LOS exclusion

Locked checkpoints:
  H92 n=1741, deaths=189
  H93 n=1666, deaths=183
  H94 n=1665, deaths=183
  all_locked_counts_pass=1

The same SQL also materializes the broader AIS case-definition sensitivity
cohorts used in the final revision-stage sensitivity analysis.

This public-code version contains no PostgreSQL server-side COPY TO path.

Revision-stage addition: MIMIC_01_export_OASIS_sensitivity_input.sql joins frozen H94 to mimiciv_derived.oasis by stay_id for the alternative severity-adjustment sensitivity; H94 remained 1665/183 and OASIS was complete for all 1665 stays.
