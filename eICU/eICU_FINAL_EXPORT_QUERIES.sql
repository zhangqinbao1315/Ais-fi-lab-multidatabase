/*
=====================================================================
S4 eICU FINAL — NAVICAT EXPORT QUERIES
=====================================================================

Run after:
eICU_00_ONE_CLICK_RAW_TO_ANALYTIC_EXACT_FINAL.sql

Use Navicat "Export Result / 导出结果" for each result grid.
No PostgreSQL server-side COPY TO is used.
=====================================================================
*/

/* Save as eICU_S4_FINAL_QC.csv */
SELECT *
FROM frailty_work.eicu_s4_final_qc;


/* Save as eICU_S4_FIELD_ALIGNMENT_QC.csv */
SELECT *
FROM frailty_work.eicu_s4_field_alignment_qc;


/* Save as eicu_48_analysis_base_all.csv */
SELECT *
FROM frailty_work.eicu_48_analysis_base_all
ORDER BY patientunitstayid;


/* Save as eicu_49_primary_FI_analysis_cohort.csv */
SELECT *
FROM frailty_work.eicu_49_primary_fi_analysis_cohort
ORDER BY patientunitstayid;


/* Save as eicu_50_primary_model_completecase.csv */
SELECT *
FROM frailty_work.eicu_50_primary_model_completecase
ORDER BY patientunitstayid;
