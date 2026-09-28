/*
MIMIC final Navicat/UI export queries.
Run MIMIC_00_RAW_TO_ANALYTIC_EXACT_FINAL.sql first.
Export each result grid using the filename shown in the comment.
*/

/* H92_analysis_base_all.csv */
SELECT *
FROM frailty_work.mimic_s4_h92_analysis_base_all
ORDER BY subject_id, hadm_id, stay_id;

/* H93_primary_FI_analysis_cohort.csv */
SELECT *
FROM frailty_work.mimic_s4_h93_primary_fi
ORDER BY subject_id, hadm_id, stay_id;

/* H94_primary_model_completecase.csv */
SELECT *
FROM frailty_work.mimic_s4_h94_primary_completecase
ORDER BY subject_id, hadm_id, stay_id;

/* 10a_MIMIC_Core18_FROZEN_ALIGNED.csv */
SELECT
    subject_id,
    hadm_id,
    stay_id,
    age,
    female,
    wbc,
    hemoglobin,
    hematocrit,
    platelet,
    rbc,
    mcv,
    sodium,
    potassium,
    chloride,
    bicarbonate,
    bun,
    creatinine,
    glucose,
    calcium,
    magnesium,
    phosphate,
    inr,
    aptt,
    n_measured,
    n_deficits,
    filab18_valid,
    filab18_score,
    filab18_per_0_1
FROM frailty_work.mimic_s4_h92_analysis_base_all
ORDER BY subject_id, hadm_id, stay_id;

/* MIMIC_S4_FINAL_QC.csv */
SELECT *
FROM frailty_work.mimic_s4_final_qc;

/* mimic_SENS03_analysis_base_all_defs.csv */
SELECT *
FROM frailty_work.mimic_sens03_analysis_base
ORDER BY cohort_order, subject_id, hadm_id, stay_id;

/* mimic_SENS03_primary_model_completecase_all_defs.csv */
SELECT *
FROM frailty_work.mimic_sens03_analysis_base
WHERE primary_model_completecase=1
ORDER BY cohort_order, subject_id, hadm_id, stay_id;

/* mimic_SENS03_flow_QC.csv */
SELECT *
FROM frailty_work.mimic_sens03_flow_qc
ORDER BY cohort_order;

/* mimic_SENS03_code_mix_QC.csv */
SELECT *
FROM frailty_work.mimic_sens03_code_mix_qc
ORDER BY cohort_order;

/* mimic_SENS03_FI_coverage_QC.csv */
SELECT *
FROM frailty_work.mimic_sens03_fi_coverage_qc
ORDER BY cohort_order, n_measured;
