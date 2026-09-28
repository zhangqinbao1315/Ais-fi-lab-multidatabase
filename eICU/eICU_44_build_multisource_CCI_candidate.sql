/*
eICU - 44
Build diagnosis + structured pastHistory + selected APACHE chronic-flag
Charlson candidate.

No mortality/outcome data are referenced.
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_44_multisource_cci_candidate_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_44_multisource_cci_candidate_v1 AS
WITH cohort AS (
    SELECT
        patientunitstayid,
        patienthealthsystemstayid
    FROM frailty_work.eicu_25_primary_ais_cohort_v1
),

/* All ICU unit stays belonging to the same hospital stay */
hospital_units AS (
    SELECT
        c.patientunitstayid AS index_patientunitstayid,
        p.patientunitstayid
    FROM cohort c
    JOIN eicu_crd.patient p
      ON p.patienthealthsystemstayid = c.patienthealthsystemstayid
),

/* Structured chronic past-history flags */
ph AS (
    SELECT
        h.index_patientunitstayid AS patientunitstayid,

        MAX(CASE WHEN ph.pasthistorypath ILIKE '%/Myocardial Infarction/%'
                 THEN 1 ELSE 0 END) AS ph_myocardial_infarct,

        MAX(CASE WHEN ph.pasthistorypath ILIKE '%/Congestive Heart Failure/%'
                 THEN 1 ELSE 0 END) AS ph_congestive_heart_failure,

        MAX(CASE WHEN ph.pasthistorypath ILIKE '%/Peripheral Vascular Disease/%'
                 THEN 1 ELSE 0 END) AS ph_peripheral_vascular_disease,

        MAX(CASE WHEN ph.pasthistorypath ILIKE '%/Neurologic/Dementia/%'
                 THEN 1 ELSE 0 END) AS ph_dementia,

        MAX(CASE WHEN
                    ph.pasthistorypath ILIKE '%/Pulmonary/COPD/%'
                 OR ph.pasthistorypath ILIKE '%/Pulmonary/Asthma/%'
                 THEN 1 ELSE 0 END) AS ph_chronic_pulmonary_disease,

        MAX(CASE WHEN
                    ph.pasthistorypath ILIKE '%/Rheumatic/Rheumatoid Arthritis/%'
                 OR ph.pasthistorypath ILIKE '%/Rheumatic/SLE/%'
                 THEN 1 ELSE 0 END) AS ph_rheumatic_disease,

        MAX(CASE WHEN ph.pasthistorypath ILIKE '%/Peptic Ulcer Disease/%'
                 THEN 1 ELSE 0 END) AS ph_peptic_ulcer_disease,

        MAX(CASE WHEN
                    ph.pasthistorypath ILIKE '%/Gastrointestinal (R)/Cirrhosis/%'
                 OR ph.pasthistorypath ILIKE '%/s/p Liver Transplant/%'
                 THEN 1 ELSE 0 END) AS ph_mild_liver_disease,

        MAX(CASE WHEN
                    ph.pasthistorypath ILIKE '%/Cirrhosis/ascites%'
                 OR ph.pasthistorypath ILIKE '%/Cirrhosis/encephalopathy%'
                 OR ph.pasthistorypath ILIKE '%/Cirrhosis/UGI bleeding%'
                 THEN 1 ELSE 0 END) AS ph_severe_liver_disease,

        MAX(CASE WHEN
                    ph.pasthistorypath ILIKE '%/Non-Insulin Dependent Diabetes/%'
                 OR ph.pasthistorypath ILIKE '%/Insulin Dependent Diabetes/%'
                 THEN 1 ELSE 0 END) AS ph_diabetes_without_cc,

        /* No reliable structured pastHistory item distinguishes chronic
           diabetic end-organ complication from uncomplicated diabetes. */
        0::integer AS ph_diabetes_with_cc,

        MAX(CASE WHEN
                    ph.pasthistorypath ILIKE '%/Renal  (R)/Renal Insufficiency/%'
                 OR ph.pasthistorypath ILIKE '%/Renal  (R)/Renal Failure/%'
                 OR ph.pasthistorypath ILIKE '%/Renal  (R)/s/p Renal Transplant/%'
                 THEN 1 ELSE 0 END) AS ph_renal_disease,

        MAX(CASE WHEN
                    ph.pasthistorypath ILIKE '%/Cancer/Cancer-Primary Site/%'
                 OR ph.pasthistorypath ILIKE '%/Cancer/Hematologic Malignancy/%'
                 THEN 1 ELSE 0 END) AS ph_malignant_cancer,

        MAX(CASE WHEN ph.pasthistorypath ILIKE '%/Cancer/Metastases/%'
                 THEN 1 ELSE 0 END) AS ph_metastatic_solid_tumor,

        /* HIV positive is not equivalent to AIDS */
        0::integer AS ph_aids,

        1::integer AS has_any_pasthistory

    FROM hospital_units h
    JOIN eicu_crd.pasthistory ph
      ON ph.patientunitstayid = h.patientunitstayid
    GROUP BY h.index_patientunitstayid
),

/* APACHE chronic comorbidity flags */
ap AS (
    SELECT DISTINCT ON (a.patientunitstayid)
        a.patientunitstayid,

        CASE WHEN a.diabetes = 1 THEN 1 ELSE 0 END
            AS ap_diabetes_without_cc,

        CASE WHEN a.cirrhosis = 1 THEN 1 ELSE 0 END
            AS ap_mild_liver_disease,

        CASE WHEN a.hepaticfailure = 1 THEN 1 ELSE 0 END
            AS ap_severe_liver_disease,

        CASE WHEN a.lymphoma = 1 OR a.leukemia = 1
             THEN 1 ELSE 0 END AS ap_malignant_cancer,

        CASE WHEN a.metastaticcancer = 1
             THEN 1 ELSE 0 END AS ap_metastatic_solid_tumor,

        CASE WHEN a.aids = 1 THEN 1 ELSE 0 END AS ap_aids,

        1::integer AS has_apachepredvar

    FROM cohort c
    JOIN eicu_crd.apachepredvar a
      ON a.patientunitstayid = c.patientunitstayid
    ORDER BY a.patientunitstayid, a.apachepredvarid
),

base AS (
    SELECT
        c.patientunitstayid,

        /* diagnosis source */
        d.myocardial_infarct AS dx_myocardial_infarct,
        d.congestive_heart_failure AS dx_congestive_heart_failure,
        d.peripheral_vascular_disease AS dx_peripheral_vascular_disease,
        d.dementia AS dx_dementia,
        d.chronic_pulmonary_disease AS dx_chronic_pulmonary_disease,
        d.rheumatic_disease AS dx_rheumatic_disease,
        d.peptic_ulcer_disease AS dx_peptic_ulcer_disease,
        d.mild_liver_disease AS dx_mild_liver_disease,
        d.severe_liver_disease AS dx_severe_liver_disease,
        d.diabetes_without_cc AS dx_diabetes_without_cc,
        d.diabetes_with_cc AS dx_diabetes_with_cc,
        d.renal_disease AS dx_renal_disease,
        d.malignant_cancer AS dx_malignant_cancer,
        d.metastatic_solid_tumor AS dx_metastatic_solid_tumor,
        d.aids AS dx_aids,

        d.cci_chronic_burden_no_age AS cci_dx_only,

        /* pastHistory source, absent source -> no documented flag */
        COALESCE(p.ph_myocardial_infarct,0) AS ph_myocardial_infarct,
        COALESCE(p.ph_congestive_heart_failure,0) AS ph_congestive_heart_failure,
        COALESCE(p.ph_peripheral_vascular_disease,0) AS ph_peripheral_vascular_disease,
        COALESCE(p.ph_dementia,0) AS ph_dementia,
        COALESCE(p.ph_chronic_pulmonary_disease,0) AS ph_chronic_pulmonary_disease,
        COALESCE(p.ph_rheumatic_disease,0) AS ph_rheumatic_disease,
        COALESCE(p.ph_peptic_ulcer_disease,0) AS ph_peptic_ulcer_disease,
        COALESCE(p.ph_mild_liver_disease,0) AS ph_mild_liver_disease,
        COALESCE(p.ph_severe_liver_disease,0) AS ph_severe_liver_disease,
        COALESCE(p.ph_diabetes_without_cc,0) AS ph_diabetes_without_cc,
        COALESCE(p.ph_diabetes_with_cc,0) AS ph_diabetes_with_cc,
        COALESCE(p.ph_renal_disease,0) AS ph_renal_disease,
        COALESCE(p.ph_malignant_cancer,0) AS ph_malignant_cancer,
        COALESCE(p.ph_metastatic_solid_tumor,0) AS ph_metastatic_solid_tumor,
        COALESCE(p.ph_aids,0) AS ph_aids,
        COALESCE(p.has_any_pasthistory,0) AS has_any_pasthistory,

        /* selected APACHE source */
        COALESCE(a.ap_diabetes_without_cc,0) AS ap_diabetes_without_cc,
        COALESCE(a.ap_mild_liver_disease,0) AS ap_mild_liver_disease,
        COALESCE(a.ap_severe_liver_disease,0) AS ap_severe_liver_disease,
        COALESCE(a.ap_malignant_cancer,0) AS ap_malignant_cancer,
        COALESCE(a.ap_metastatic_solid_tumor,0) AS ap_metastatic_solid_tumor,
        COALESCE(a.ap_aids,0) AS ap_aids,
        COALESCE(a.has_apachepredvar,0) AS has_apachepredvar

    FROM cohort c
    JOIN frailty_work.eicu_38_cci_v1 d
      ON d.patientunitstayid = c.patientunitstayid
    LEFT JOIN ph p
      ON p.patientunitstayid = c.patientunitstayid
    LEFT JOIN ap a
      ON a.patientunitstayid = c.patientunitstayid
),

combined AS (
    SELECT
        b.*,

        GREATEST(dx_myocardial_infarct,
                 ph_myocardial_infarct)
            AS myocardial_infarct,

        GREATEST(dx_congestive_heart_failure,
                 ph_congestive_heart_failure)
            AS congestive_heart_failure,

        GREATEST(dx_peripheral_vascular_disease,
                 ph_peripheral_vascular_disease)
            AS peripheral_vascular_disease,

        GREATEST(dx_dementia,
                 ph_dementia)
            AS dementia,

        GREATEST(dx_chronic_pulmonary_disease,
                 ph_chronic_pulmonary_disease)
            AS chronic_pulmonary_disease,

        GREATEST(dx_rheumatic_disease,
                 ph_rheumatic_disease)
            AS rheumatic_disease,

        GREATEST(dx_peptic_ulcer_disease,
                 ph_peptic_ulcer_disease)
            AS peptic_ulcer_disease,

        GREATEST(dx_mild_liver_disease,
                 ph_mild_liver_disease,
                 ap_mild_liver_disease)
            AS mild_liver_disease,

        GREATEST(dx_severe_liver_disease,
                 ph_severe_liver_disease,
                 ap_severe_liver_disease)
            AS severe_liver_disease,

        GREATEST(dx_diabetes_without_cc,
                 ph_diabetes_without_cc,
                 ap_diabetes_without_cc)
            AS diabetes_without_cc,

        dx_diabetes_with_cc AS diabetes_with_cc,

        GREATEST(dx_renal_disease,
                 ph_renal_disease)
            AS renal_disease,

        GREATEST(dx_malignant_cancer,
                 ph_malignant_cancer,
                 ap_malignant_cancer)
            AS malignant_cancer,

        GREATEST(dx_metastatic_solid_tumor,
                 ph_metastatic_solid_tumor,
                 ap_metastatic_solid_tumor)
            AS metastatic_solid_tumor,

        GREATEST(dx_aids, ph_aids, ap_aids)
            AS aids,

        /* Past-history-only score for source sensitivity */
        ph_myocardial_infarct
        + ph_congestive_heart_failure
        + ph_peripheral_vascular_disease
        + ph_dementia
        + ph_chronic_pulmonary_disease
        + ph_rheumatic_disease
        + ph_peptic_ulcer_disease
        + GREATEST(ph_mild_liver_disease, 3*ph_severe_liver_disease)
        + GREATEST(ph_diabetes_without_cc, 2*ph_diabetes_with_cc)
        + 2*ph_renal_disease
        + GREATEST(2*ph_malignant_cancer, 6*ph_metastatic_solid_tumor)
        + 6*ph_aids
        AS cci_pasthistory_only

    FROM base b
)

SELECT
    c.*,

    myocardial_infarct
    + congestive_heart_failure
    + peripheral_vascular_disease
    + dementia
    + chronic_pulmonary_disease
    + rheumatic_disease
    + peptic_ulcer_disease
    + GREATEST(mild_liver_disease, 3*severe_liver_disease)
    + GREATEST(diabetes_without_cc, 2*diabetes_with_cc)
    + 2*renal_disease
    + GREATEST(2*malignant_cancer, 6*metastatic_solid_tumor)
    + 6*aids
    AS cci_multisource_chronic_no_age,

    myocardial_infarct
    + congestive_heart_failure
    + peripheral_vascular_disease
    + dementia
    + chronic_pulmonary_disease
    + rheumatic_disease
    + peptic_ulcer_disease
    + mild_liver_disease
    + severe_liver_disease
    + diabetes_without_cc
    + diabetes_with_cc
    + renal_disease
    + malignant_cancer
    + metastatic_solid_tumor
    + aids
    AS charlson_domain_count_multisource_non_neuro

FROM combined c
;

ALTER TABLE frailty_work.eicu_44_multisource_cci_candidate_v1
ADD COLUMN high_comorbidity_ge3_multisource integer;

UPDATE frailty_work.eicu_44_multisource_cci_candidate_v1
SET high_comorbidity_ge3_multisource =
    CASE WHEN cci_multisource_chronic_no_age >= 3 THEN 1 ELSE 0 END
;

CREATE UNIQUE INDEX eicu_44_multisource_cci_candidate_v1_pk
    ON frailty_work.eicu_44_multisource_cci_candidate_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_44_multisource_cci_candidate_v1;

SELECT
    COUNT(*) AS n,
    AVG(cci_dx_only) AS mean_dx_only,
    AVG(cci_pasthistory_only) AS mean_pasthistory_only,
    AVG(cci_multisource_chronic_no_age) AS mean_multisource,
    COUNT(*) FILTER (WHERE high_comorbidity_ge3_multisource=1)
        AS n_multisource_ge3
FROM frailty_work.eicu_44_multisource_cci_candidate_v1;
