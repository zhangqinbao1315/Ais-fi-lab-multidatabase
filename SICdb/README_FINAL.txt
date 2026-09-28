S4 SICdb RAW -> ANALYTIC — EXACT FINAL
======================================

USE THIS PACKAGE ONLY
---------------------
This package supersedes the earlier SICdb discovery, snapshot, candidate,
PatientID-fix, QC-fix, and floating-point-alignment packages.

PRIMARY RUN
-----------
Run in Navicat:

SQL/SICdb_00_ONE_CLICK_RAW_TO_ANALYTIC_EXACT_FINAL.sql

The final result grid is:
frailty_work.sicdb_s4_final_qc

Expected:
  cohort_n = 33
  filab_variant_rows = 66
  cohort_hospital_deaths = 9
  primary_fi_n = 30
  primary_fi_hospital_deaths = 8
  available_completecase_n = 30
  all_locked_counts_pass = 1


EXPORT
------
Use:

SQL/SICdb_FINAL_EXPORT_QUERIES.sql

The export SQL uses ordinary SELECT statements only.
It does NOT use PostgreSQL server-side COPY TO paths.

Recommended CSV names:
  sicdb_43_analysis_base_all.csv
  sicdb_44_primary_FI_analysis_cohort.csv
  sicdb_45_available_covariate_completecase.csv
  sicdb_46_transportability_qc.csv
  sicdb_47_dictionary_final_audit.csv
  SICdb_S4_FINAL_QC.csv


ANALYSIS
--------
Analysis/SICdb_transportability_reproduce_V2_AUTOFILE.R

The R script expects the 43/44/45 CSV files in one folder.


FINAL VALIDATION
----------------
The recovered raw-to-analytic pipeline was independently compared against
the preserved historical frozen SICdb intermediate tables.

Every validated stage had:
  exact_id_pass = 1
  exact_fullrow_pass = 1
  fullrow_mismatch_n = 0

See:
  Documentation/EXACT_VALIDATION_MANIFEST.tsv
  Documentation/FINAL_EXACT_REPRODUCTION_REPORT.txt


IMPORTANT SCIENTIFIC INTERPRETATION
-----------------------------------
SICdb is an exploratory FI-Lab transportability dataset in this study.

available_charlson_domain_count3 is only a partial available chronic-domain
proxy. It must not be described as a full or harmonized Charlson index.

Raw reconstructable GCS is unavailable in this SICdb workflow, and the small
event count does not support treating SICdb as a full third external
validation of the complete MIMIC/eICU model.


METHODS WORDING
---------------
Recommended exact cohort wording:

"In SICdb, adults with a principal ICD-10 diagnosis beginning with I63 were
identified, and for patients with multiple qualifying admissions, the first
qualifying admission was selected by OffsetAfterFirstAdmission, with CaseID
as a deterministic tie-breaker."

Recommended FI-Lab wording:

"Core-18 FI-Lab used the earliest numeric value from 6 hours before through
24 hours after ICU admission. The preferred central-laboratory mapping was
used for the primary SICdb analysis; a central-plus-blood-gas fallback
mapping was retained as a sensitivity variant. FI-Lab was computed when at
least 15 of 18 items were evaluable."

SICdb Firth code correction after final pre-submission audit
----------------------------------------------------------
The authoritative SICdb transportability script now directly uses logistf::logistf(..., firth=TRUE, pl=TRUE) and outputs the reported profile-likelihood confidence intervals for the frozen FI-Lab-only and FI-Lab+age models. The previously archived ordinary-GLM copy was an outdated script and has been replaced without changing the frozen manuscript results.

Final executed SICdb verification
---------------------------------
The corrected logistf script was executed on the frozen SICdb inputs using
R 4.6.0 and logistf 1.26.1. It reproduced FI-Lab OR 1.897992
(profile-likelihood 95% CI 1.094603-3.783797; p=0.021328) and the
age-adjusted FI-Lab OR 2.284600 (1.173258-6.056660; p=0.012484).
A non-statistical CSV row-duplication issue in the first corrected script
was subsequently fixed by writing scalar method labels; estimates were unchanged.
