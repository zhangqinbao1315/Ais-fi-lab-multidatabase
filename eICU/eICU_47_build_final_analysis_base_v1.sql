/*
eICU - 47
Build the final one-row-per-patient analysis base.

Requires:
  eicu_25_primary_ais_cohort_v1
  eicu_29_filab18_v1
  eicu_44_multisource_cci_candidate_v1
  eicu_42_severity_candidates_v1
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_47_analysis_base_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_47_analysis_base_v1 AS
SELECT
    /* Keys */
    c.patientunitstayid,
    c.patienthealthsystemstayid,
    c.uniquepid,
    c.hospitalid,
    c.wardid,

    /* Cohort / demographics */
    c.gender,
    c.age,
    c.age_numeric,

    CASE
        WHEN LOWER(BTRIM(COALESCE(c.gender,''))) = 'female' THEN 1
        WHEN LOWER(BTRIM(COALESCE(c.gender,''))) = 'male' THEN 0
        ELSE NULL
    END AS sex_female,

    c.apacheadmissiondx,
    c.hospitaldischargeyear,
    c.unittype,
    c.unitvisitnumber,
    c.unitstaytype,
    c.unitadmitsource,
    c.unitdischargeoffset,

    c.n_qualifying_hospitalizations_for_patient,
    c.earliest_qualifying_discharge_year,

    /* Outcomes */
    CASE
        WHEN LOWER(BTRIM(COALESCE(c.hospitaldischargestatus,'')))='expired'
            THEN 1
        WHEN LOWER(BTRIM(COALESCE(c.hospitaldischargestatus,'')))='alive'
            THEN 0
        ELSE NULL
    END AS hospital_mortality,

    CASE
        WHEN LOWER(BTRIM(COALESCE(c.unitdischargestatus,'')))='expired'
            THEN 1
        WHEN LOWER(BTRIM(COALESCE(c.unitdischargestatus,'')))='alive'
            THEN 0
        ELSE NULL
    END AS icu_mortality,

    c.hospitaldischargestatus,
    c.unitdischargestatus,

    /* Primary multimorbidity */
    m.cci_multisource_chronic_no_age
        AS cci_chronic_burden_no_age,

    m.high_comorbidity_ge3_multisource
        AS high_comorbidity_ge3,

    m.charlson_domain_count_multisource_non_neuro
        AS charlson_domain_count_non_neuro,

    /* CCI sensitivity variants */
    m.cci_dx_only
        AS cci_chronic_burden_no_age_dx_only,

    m.cci_pasthistory_only
        AS cci_chronic_burden_no_age_pasthistory_only,

    m.has_any_pasthistory,
    m.has_apachepredvar,

    /* Final non-neurological Charlson domains */
    m.myocardial_infarct,
    m.congestive_heart_failure,
    m.peripheral_vascular_disease,
    m.dementia,
    m.chronic_pulmonary_disease,
    m.rheumatic_disease,
    m.peptic_ulcer_disease,
    m.mild_liver_disease,
    m.severe_liver_disease,
    m.diabetes_without_cc,
    m.diabetes_with_cc,
    m.renal_disease,
    m.malignant_cancer,
    m.metastatic_solid_tumor,
    m.aids,

    /* Core-18 earliest values */
    f.wbc,
    f.hemoglobin,
    f.hematocrit,
    f.platelet,
    f.rbc,
    f.mcv,
    f.sodium,
    f.potassium,
    f.chloride,
    f.bicarbonate,
    f.bun,
    f.creatinine,
    f.glucose,
    f.calcium,
    f.magnesium,
    f.phosphate,
    f.inr,
    f.aptt,

    /* Core-18 deficits */
    f.d_wbc,
    f.d_hemoglobin,
    f.d_hematocrit,
    f.d_platelet,
    f.d_rbc,
    f.d_mcv,
    f.d_sodium,
    f.d_potassium,
    f.d_chloride,
    f.d_bicarbonate,
    f.d_bun,
    f.d_creatinine,
    f.d_glucose,
    f.d_calcium,
    f.d_magnesium,
    f.d_phosphate,
    f.d_inr,
    f.d_aptt,

    f.n_measured AS filab18_n_measured,
    f.n_evaluable AS filab18_n_evaluable,
    f.n_deficits AS filab18_n_deficits,
    f.filab18,
    f.filab18_per_0_1,

    /* Primary severity adjustment */
    s.gcs_total AS gcs,

    s.imv_oobintubday1
        AS invasive_ventilation_day1,

    s.vasopressor_recorded_any
        AS vasopressor_use_firstday,

    /* Severity / source sensitivity */
    s.aps_intubated,
    s.imv_day1_fallback,
    s.any_mechanical_assist_day1,

    s.vasopressor_infusion,
    s.vasopressor_treatment,

    s.norepinephrine_infusion,
    s.epinephrine_infusion,
    s.dopamine_infusion,
    s.phenylephrine_infusion,
    s.vasopressin_infusion,

    s.dobutamine_any,
    s.milrinone_any,
    s.any_inotrope,

    s.has_any_infusiondrug_record_firstday,
    s.has_any_treatment_record_firstday,

    s.apache_iva_score,
    s.apache_iva_aps

FROM frailty_work.eicu_25_primary_ais_cohort_v1 c

LEFT JOIN frailty_work.eicu_29_filab18_v1 f
  ON f.patientunitstayid = c.patientunitstayid

LEFT JOIN frailty_work.eicu_44_multisource_cci_candidate_v1 m
  ON m.patientunitstayid = c.patientunitstayid

LEFT JOIN frailty_work.eicu_42_severity_candidates_v1 s
  ON s.patientunitstayid = c.patientunitstayid
;

CREATE UNIQUE INDEX eicu_47_analysis_base_v1_pk
    ON frailty_work.eicu_47_analysis_base_v1 (patientunitstayid);

CREATE UNIQUE INDEX eicu_47_analysis_base_v1_pid
    ON frailty_work.eicu_47_analysis_base_v1 (uniquepid);

ANALYZE frailty_work.eicu_47_analysis_base_v1;


/* Primary FI analysis cohort */
DROP TABLE IF EXISTS frailty_work.eicu_47_primary_fi_cohort_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_47_primary_fi_cohort_v1 AS
SELECT *
FROM frailty_work.eicu_47_analysis_base_v1
WHERE filab18 IS NOT NULL
;

CREATE UNIQUE INDEX eicu_47_primary_fi_cohort_v1_pk
    ON frailty_work.eicu_47_primary_fi_cohort_v1 (patientunitstayid);


/* Primary model complete-case cohort */
DROP TABLE IF EXISTS frailty_work.eicu_47_primary_model_completecase_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_47_primary_model_completecase_v1 AS
SELECT *
FROM frailty_work.eicu_47_analysis_base_v1
WHERE hospital_mortality IS NOT NULL
  AND filab18 IS NOT NULL
  AND cci_chronic_burden_no_age IS NOT NULL
  AND age_numeric IS NOT NULL
  AND sex_female IS NOT NULL
  AND gcs IS NOT NULL
  AND invasive_ventilation_day1 IS NOT NULL
  AND vasopressor_use_firstday IS NOT NULL
;

CREATE UNIQUE INDEX eicu_47_primary_model_completecase_v1_pk
    ON frailty_work.eicu_47_primary_model_completecase_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_47_primary_fi_cohort_v1;
ANALYZE frailty_work.eicu_47_primary_model_completecase_v1;


/* Immediate one-to-one QC */
SELECT
    (SELECT COUNT(*) FROM frailty_work.eicu_47_analysis_base_v1)
        AS n_all,
    (SELECT COUNT(DISTINCT uniquepid)
     FROM frailty_work.eicu_47_analysis_base_v1)
        AS n_unique_patients,
    (SELECT COUNT(*) FROM frailty_work.eicu_47_primary_fi_cohort_v1)
        AS n_valid_fi,
    (SELECT COUNT(*) FROM frailty_work.eicu_47_primary_model_completecase_v1)
        AS n_primary_model_completecase
;
