/*
=====================================================================
S4 FINAL — MIMIC-IV v3.1 RAW DATABASE TO ANALYTIC DATASETS
=====================================================================

This is the canonical MIMIC extraction pipeline for the final manuscript.

RAW SOURCE TABLES
-----------------
mimiciv_hosp.diagnoses_icd
mimiciv_hosp.admissions
mimiciv_hosp.patients
mimiciv_hosp.labevents
mimiciv_icu.icustays
mimiciv_derived.charlson
mimiciv_derived.first_day_gcs
mimiciv_derived.ventilation
mimiciv_derived.vasoactive_agent

PRIMARY COHORT
--------------
Principal ICD-10 I63* only; adult; first ICU stay per hospitalization;
first qualifying AIS ICU hospitalization per patient; no ICU-LOS exclusion.

FINAL PRIMARY OUTPUTS
---------------------
C:/temp/H92_analysis_base_all.csv
C:/temp/H93_primary_FI_analysis_cohort.csv
C:/temp/H94_primary_model_completecase.csv
C:/temp/10a_MIMIC_Core18_FROZEN_ALIGNED.csv
C:/temp/MIMIC_S4_CANONICAL_QC.csv

The same pipeline also constructs the prespecified broader AIS sensitivity
definitions S1-S3 and exports their audit files.

HARD QC
-------
H92 n=1741 / deaths=189
H93 n=1666 / deaths=183
H94 n=1665 / deaths=183

This code is derived from the SQL that was actually rerun during final
pre-submission QC; P0 was subsequently verified row-by-row against frozen H94.
=====================================================================
*/

/*
FIX v1.1
--------
Step 7 FI-Lab build now explicitly selects the 18 laboratory columns instead
of using l.*, preventing duplicate subject_id/hadm_id/stay_id column names in
CREATE TABLE AS.
*/

/*
=====================================================================
03 — MIMIC-IV broader AIS case-definition sensitivity
ONE CLICK: BUILD + QC + EXPORT
=====================================================================

PURPOSE
-------
Evaluate whether the frozen primary MIMIC result depends on the relatively
strict AIS case definition.

Four prespecified definitions are built independently:

P0_PRIMARY_FROZEN
  Principal diagnosis only
  ICD-10 I63*
  This MUST reproduce the frozen V5 primary cohort.

S1_PRINCIPAL_STRICT_XV
  Principal diagnosis only
  ICD-10 I63* OR strict ICD-9 433.x1 / 434.x1

S2_ANYPOS_STRICT_XV
  Any diagnosis position
  ICD-10 I63* OR strict ICD-9 433.x1 / 434.x1

S3_ANYPOS_BROAD_436
  Any diagnosis position
  ICD-10 I63* OR strict ICD-9 433.x1 / 434.x1 OR ICD-9 436

For EACH definition:
- age >=18
- first ICU stay per hospitalization
- first qualifying AIS ICU hospitalization per patient
- no ICU LOS <24 h exclusion
- Core-18 earliest numeric laboratory value in ICU -6 h to +24 h
- FI-Lab = abnormal deficits / measured items
- FI valid if >=15/18 evaluable
- modified CCI excludes cerebrovascular disease and paralysis/paraplegia
- age is separate, not included in modified CCI
- first-day GCS from mimiciv_derived.first_day_gcs
- invasive ventilation in -6 h/+24 h from mimiciv_derived.ventilation
- vasopressor in -6 h/+24 h from mimiciv_derived.vasoactive_agent
- hospital mortality from admissions.hospital_expire_flag

OUTPUT LOCATION
---------------
C:\temp\

REQUIRED FOR R:
C:\temp\mimic_SENS03_primary_model_completecase_all_defs.csv

STRONGLY RECOMMENDED AUDIT FILE:
C:\temp\mimic_SENS03_analysis_base_all_defs.csv

IMPORTANT
---------
This script does NOT modify any frozen V5 table or exposure definition.
It creates only new frailty_work.mimic_sens03_* objects.

Expected P0 benchmark:
- all cohort n = 1741
- FI valid n = 1666
- primary complete-case n = 1665
- primary complete-case hospital deaths = 183

=====================================================================
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;


/* ================================================================
   STEP 1. Normalize diagnosis codes
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_dx_norm;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_dx_norm AS
SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    d.icd_version,
    upper(replace(trim(d.icd_code), '.', '')) AS code_norm,

    CASE
      WHEN d.icd_version = 10
       AND upper(replace(trim(d.icd_code), '.', '')) LIKE 'I63%'
      THEN 1 ELSE 0
    END::integer AS is_i63_icd10,

    CASE
      WHEN d.icd_version = 9
       AND (
            upper(replace(trim(d.icd_code), '.', '')) ~ '^433[0-9]1$'
         OR upper(replace(trim(d.icd_code), '.', '')) ~ '^434[0-9]1$'
       )
      THEN 1 ELSE 0
    END::integer AS is_strict_ais_icd9,

    CASE
      WHEN d.icd_version = 9
       AND upper(replace(trim(d.icd_code), '.', '')) = '436'
      THEN 1 ELSE 0
    END::integer AS is_icd9_436

FROM mimiciv_hosp.diagnoses_icd d
;

CREATE INDEX mimic_sens03_dx_norm_hadm
  ON frailty_work.mimic_sens03_dx_norm (hadm_id, seq_num);

CREATE INDEX mimic_sens03_dx_norm_subject
  ON frailty_work.mimic_sens03_dx_norm (subject_id, hadm_id);

ANALYZE frailty_work.mimic_sens03_dx_norm;


/* ================================================================
   STEP 2. Build qualifying hospitalization rows for four definitions
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_qualifying_hadm;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_qualifying_hadm AS
WITH all_defs AS (

    /* P0 frozen primary */
    SELECT
        'P0_PRIMARY_FROZEN'::text AS cohort_def,
        0::integer AS cohort_order,
        x.*
    FROM frailty_work.mimic_sens03_dx_norm x
    WHERE x.seq_num = 1
      AND x.is_i63_icd10 = 1

    UNION ALL

    /* S1: principal, strict cross-version */
    SELECT
        'S1_PRINCIPAL_STRICT_XV'::text,
        1::integer,
        x.*
    FROM frailty_work.mimic_sens03_dx_norm x
    WHERE x.seq_num = 1
      AND (x.is_i63_icd10 = 1 OR x.is_strict_ais_icd9 = 1)

    UNION ALL

    /* S2: any position, strict cross-version */
    SELECT
        'S2_ANYPOS_STRICT_XV'::text,
        2::integer,
        x.*
    FROM frailty_work.mimic_sens03_dx_norm x
    WHERE x.is_i63_icd10 = 1
       OR x.is_strict_ais_icd9 = 1

    UNION ALL

    /* S3: any position + ICD-9 436 */
    SELECT
        'S3_ANYPOS_BROAD_436'::text,
        3::integer,
        x.*
    FROM frailty_work.mimic_sens03_dx_norm x
    WHERE x.is_i63_icd10 = 1
       OR x.is_strict_ais_icd9 = 1
       OR x.is_icd9_436 = 1
)

SELECT
    cohort_def,
    cohort_order,
    subject_id,
    hadm_id,

    MIN(seq_num)::integer AS first_qualifying_seq_num,

    MAX(CASE WHEN is_i63_icd10 = 1 THEN 1 ELSE 0 END)::integer
        AS has_i63_icd10,
    MAX(CASE WHEN is_strict_ais_icd9 = 1 THEN 1 ELSE 0 END)::integer
        AS has_strict_ais_icd9,
    MAX(CASE WHEN is_icd9_436 = 1 THEN 1 ELSE 0 END)::integer
        AS has_icd9_436,

    MAX(CASE WHEN seq_num = 1 AND is_i63_icd10 = 1 THEN 1 ELSE 0 END)::integer
        AS principal_i63_icd10,
    MAX(CASE WHEN seq_num = 1 AND is_strict_ais_icd9 = 1 THEN 1 ELSE 0 END)::integer
        AS principal_strict_ais_icd9,
    MAX(CASE WHEN seq_num = 1 AND is_icd9_436 = 1 THEN 1 ELSE 0 END)::integer
        AS principal_icd9_436

FROM all_defs
GROUP BY
    cohort_def,
    cohort_order,
    subject_id,
    hadm_id
;

CREATE INDEX mimic_sens03_qualifying_hadm_key
  ON frailty_work.mimic_sens03_qualifying_hadm
  (cohort_def, subject_id, hadm_id);

ANALYZE frailty_work.mimic_sens03_qualifying_hadm;


/* ================================================================
   STEP 3. First ICU stay per hospitalization
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_first_icu;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_first_icu AS
SELECT *
FROM (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.first_careunit,
        i.last_careunit,
        row_number() OVER (
            PARTITION BY i.hadm_id
            ORDER BY i.intime, i.stay_id
        ) AS rn_icu
    FROM mimiciv_icu.icustays i
) x
WHERE rn_icu = 1
;

CREATE UNIQUE INDEX mimic_sens03_first_icu_hadm
  ON frailty_work.mimic_sens03_first_icu (hadm_id);

ANALYZE frailty_work.mimic_sens03_first_icu;


/* ================================================================
   STEP 4. Select first qualifying AIS ICU hospitalization per patient
            separately inside each case-definition
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_cohort_defs;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_cohort_defs AS
WITH adult_candidates AS (
    SELECT
        q.cohort_def,
        q.cohort_order,
        q.subject_id,
        q.hadm_id,
        i.stay_id,

        q.first_qualifying_seq_num,
        q.has_i63_icd10,
        q.has_strict_ais_icd9,
        q.has_icd9_436,
        q.principal_i63_icd10,
        q.principal_strict_ais_icd9,
        q.principal_icd9_436,

        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,

        i.intime,
        i.outtime,
        i.first_careunit,
        i.last_careunit,

        CASE
            WHEN p.gender = 'F' THEN 1
            WHEN p.gender = 'M' THEN 0
            ELSE NULL
        END::integer AS female,

        (
          p.anchor_age
          + extract(year FROM a.admittime)::int
          - p.anchor_year
        )::numeric AS age

    FROM frailty_work.mimic_sens03_qualifying_hadm q

    JOIN mimiciv_hosp.admissions a
      ON a.subject_id = q.subject_id
     AND a.hadm_id = q.hadm_id

    JOIN mimiciv_hosp.patients p
      ON p.subject_id = q.subject_id

    JOIN frailty_work.mimic_sens03_first_icu i
      ON i.subject_id = q.subject_id
     AND i.hadm_id = q.hadm_id

    WHERE (
          p.anchor_age
          + extract(year FROM a.admittime)::int
          - p.anchor_year
    ) >= 18
),

ranked AS (
    SELECT
        c.*,
        row_number() OVER (
            PARTITION BY c.cohort_def, c.subject_id
            ORDER BY c.admittime, c.intime, c.hadm_id, c.stay_id
        ) AS rn_patient
    FROM adult_candidates c
)

SELECT *
FROM ranked
WHERE rn_patient = 1
;

CREATE UNIQUE INDEX mimic_sens03_cohort_defs_pk
  ON frailty_work.mimic_sens03_cohort_defs
  (cohort_def, subject_id);

CREATE INDEX mimic_sens03_cohort_defs_stay
  ON frailty_work.mimic_sens03_cohort_defs (stay_id);

CREATE INDEX mimic_sens03_cohort_defs_hadm
  ON frailty_work.mimic_sens03_cohort_defs (hadm_id);

ANALYZE frailty_work.mimic_sens03_cohort_defs;


/* ================================================================
   STEP 5. Unique ICU stays across definitions
   Avoid re-scanning labs four times.
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_unique_stays;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_unique_stays AS
SELECT DISTINCT
    subject_id,
    hadm_id,
    stay_id,
    female,
    age,
    admittime,
    dischtime,
    intime,
    outtime,
    hospital_expire_flag
FROM frailty_work.mimic_sens03_cohort_defs
;

CREATE UNIQUE INDEX mimic_sens03_unique_stays_pk
  ON frailty_work.mimic_sens03_unique_stays (stay_id);

CREATE INDEX mimic_sens03_unique_stays_subject_hadm
  ON frailty_work.mimic_sens03_unique_stays
  (subject_id, hadm_id);

ANALYZE frailty_work.mimic_sens03_unique_stays;


/* ================================================================
   STEP 6. Core-18 earliest labs, ICU -6 h to +24 h
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_core18_earliest;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_core18_earliest AS
WITH item_map(item, itemid) AS (
    VALUES
      ('wbc',         51300),
      ('wbc',         51301),
      ('hemoglobin',  51222),
      ('hematocrit',  51221),
      ('platelet',    51265),
      ('rbc',         51279),
      ('mcv',         51250),
      ('sodium',      50983),
      ('potassium',   50971),
      ('chloride',    50902),
      ('bicarbonate', 50882),
      ('bun',         51006),
      ('creatinine',  50912),
      ('glucose',     50931),
      ('calcium',     50893),
      ('magnesium',   50960),
      ('phosphate',   50970),
      ('inr',         51237),
      ('aptt',        51275)
),

lab_candidates AS (
    SELECT
        u.subject_id,
        u.hadm_id,
        u.stay_id,
        m.item,
        le.itemid,
        le.valuenum,
        le.valueuom,
        le.charttime,
        le.labevent_id,

        row_number() OVER (
            PARTITION BY u.stay_id, m.item
            ORDER BY le.charttime, le.labevent_id
        ) AS rn

    FROM frailty_work.mimic_sens03_unique_stays u

    JOIN mimiciv_hosp.labevents le
      ON le.subject_id = u.subject_id
     AND (le.hadm_id = u.hadm_id OR le.hadm_id IS NULL)
     AND le.valuenum IS NOT NULL
     AND le.charttime >= u.intime - interval '6 hours'
     AND le.charttime <= u.intime + interval '24 hours'

    JOIN item_map m
      ON m.itemid = le.itemid
),

earliest AS (
    SELECT *
    FROM lab_candidates
    WHERE rn = 1
)

SELECT
    u.subject_id,
    u.hadm_id,
    u.stay_id,

    max(e.valuenum) FILTER (WHERE e.item='wbc')         AS wbc,
    max(e.valuenum) FILTER (WHERE e.item='hemoglobin')  AS hemoglobin,
    max(e.valuenum) FILTER (WHERE e.item='hematocrit')  AS hematocrit,
    max(e.valuenum) FILTER (WHERE e.item='platelet')    AS platelet,
    max(e.valuenum) FILTER (WHERE e.item='rbc')         AS rbc,
    max(e.valuenum) FILTER (WHERE e.item='mcv')         AS mcv,
    max(e.valuenum) FILTER (WHERE e.item='sodium')      AS sodium,
    max(e.valuenum) FILTER (WHERE e.item='potassium')   AS potassium,
    max(e.valuenum) FILTER (WHERE e.item='chloride')    AS chloride,
    max(e.valuenum) FILTER (WHERE e.item='bicarbonate') AS bicarbonate,
    max(e.valuenum) FILTER (WHERE e.item='bun')         AS bun,
    max(e.valuenum) FILTER (WHERE e.item='creatinine')  AS creatinine,
    max(e.valuenum) FILTER (WHERE e.item='glucose')     AS glucose,
    max(e.valuenum) FILTER (WHERE e.item='calcium')     AS calcium,
    max(e.valuenum) FILTER (WHERE e.item='magnesium')   AS magnesium,
    max(e.valuenum) FILTER (WHERE e.item='phosphate')   AS phosphate,
    max(e.valuenum) FILTER (WHERE e.item='inr')         AS inr,
    max(e.valuenum) FILTER (WHERE e.item='aptt')        AS aptt

FROM frailty_work.mimic_sens03_unique_stays u

LEFT JOIN earliest e
  ON e.stay_id = u.stay_id

GROUP BY
    u.subject_id,
    u.hadm_id,
    u.stay_id
;

CREATE UNIQUE INDEX mimic_sens03_core18_earliest_pk
  ON frailty_work.mimic_sens03_core18_earliest (stay_id);

ANALYZE frailty_work.mimic_sens03_core18_earliest;


/* ================================================================
   STEP 7. FI-Lab scoring with frozen V5 thresholds
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_filab;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_filab AS
WITH x AS (
    SELECT
        u.subject_id,
        u.hadm_id,
        u.stay_id,
        u.female,

        l.wbc,
        l.hemoglobin,
        l.hematocrit,
        l.platelet,
        l.rbc,
        l.mcv,
        l.sodium,
        l.potassium,
        l.chloride,
        l.bicarbonate,
        l.bun,
        l.creatinine,
        l.glucose,
        l.calcium,
        l.magnesium,
        l.phosphate,
        l.inr,
        l.aptt,

        (
          CASE WHEN l.wbc         IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.hemoglobin  IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.hematocrit  IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.platelet    IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.rbc         IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.mcv         IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.sodium      IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.potassium   IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.chloride    IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.bicarbonate IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.bun         IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.creatinine  IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.glucose     IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.calcium     IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.magnesium   IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.phosphate   IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.inr         IS NOT NULL THEN 1 ELSE 0 END +
          CASE WHEN l.aptt        IS NOT NULL THEN 1 ELSE 0 END
        )::integer AS n_measured,

        (
          CASE WHEN l.wbc IS NULL THEN 0
               WHEN l.wbc < 4.0 OR l.wbc > 10.0 THEN 1 ELSE 0 END +

          CASE WHEN l.hemoglobin IS NULL THEN 0
               WHEN u.female = 1
                    AND (l.hemoglobin < 11.2 OR l.hemoglobin > 15.7)
                    THEN 1
               WHEN u.female = 0
                    AND (l.hemoglobin < 13.7 OR l.hemoglobin > 17.5)
                    THEN 1
               ELSE 0 END +

          CASE WHEN l.hematocrit IS NULL THEN 0
               WHEN u.female = 1
                    AND (l.hematocrit < 34 OR l.hematocrit > 45)
                    THEN 1
               WHEN u.female = 0
                    AND (l.hematocrit < 40 OR l.hematocrit > 51)
                    THEN 1
               ELSE 0 END +

          CASE WHEN l.platelet IS NULL THEN 0
               WHEN l.platelet < 150 OR l.platelet > 400 THEN 1 ELSE 0 END +

          CASE WHEN l.rbc IS NULL THEN 0
               WHEN u.female = 1
                    AND (l.rbc < 3.9 OR l.rbc > 5.2)
                    THEN 1
               WHEN u.female = 0
                    AND (l.rbc < 4.6 OR l.rbc > 6.1)
                    THEN 1
               ELSE 0 END +

          CASE WHEN l.mcv IS NULL THEN 0
               WHEN l.mcv < 82 OR l.mcv > 98 THEN 1 ELSE 0 END +

          CASE WHEN l.sodium IS NULL THEN 0
               WHEN l.sodium < 135 OR l.sodium > 145 THEN 1 ELSE 0 END +

          CASE WHEN l.potassium IS NULL THEN 0
               WHEN l.potassium < 3.5 OR l.potassium > 5.1 THEN 1 ELSE 0 END +

          CASE WHEN l.chloride IS NULL THEN 0
               WHEN l.chloride < 96 OR l.chloride > 108 THEN 1 ELSE 0 END +

          CASE WHEN l.bicarbonate IS NULL THEN 0
               WHEN l.bicarbonate < 22 OR l.bicarbonate > 32 THEN 1 ELSE 0 END +

          CASE WHEN l.bun IS NULL THEN 0
               WHEN l.bun < 6 OR l.bun > 20 THEN 1 ELSE 0 END +

          CASE WHEN l.creatinine IS NULL THEN 0
               WHEN u.female = 1
                    AND (l.creatinine < 0.4 OR l.creatinine > 1.1)
                    THEN 1
               WHEN u.female = 0
                    AND (l.creatinine < 0.5 OR l.creatinine > 1.2)
                    THEN 1
               ELSE 0 END +

          CASE WHEN l.glucose IS NULL THEN 0
               WHEN l.glucose < 70 OR l.glucose > 100 THEN 1 ELSE 0 END +

          CASE WHEN l.calcium IS NULL THEN 0
               WHEN l.calcium < 8.4 OR l.calcium > 10.3 THEN 1 ELSE 0 END +

          CASE WHEN l.magnesium IS NULL THEN 0
               WHEN l.magnesium < 1.6 OR l.magnesium > 2.6 THEN 1 ELSE 0 END +

          CASE WHEN l.phosphate IS NULL THEN 0
               WHEN l.phosphate < 2.7 OR l.phosphate > 4.5 THEN 1 ELSE 0 END +

          CASE WHEN l.inr IS NULL THEN 0
               WHEN l.inr < 0.9 OR l.inr > 1.1 THEN 1 ELSE 0 END +

          CASE WHEN l.aptt IS NULL THEN 0
               WHEN l.aptt < 25 OR l.aptt > 36.5 THEN 1 ELSE 0 END

        )::integer AS n_deficits

    FROM frailty_work.mimic_sens03_unique_stays u

    JOIN frailty_work.mimic_sens03_core18_earliest l
      ON l.stay_id = u.stay_id
)

SELECT
    x.*,

    CASE WHEN n_measured >= 15 THEN 1 ELSE 0 END::integer
        AS filab18_valid,

    CASE
      WHEN n_measured >= 15
      THEN n_deficits::numeric / NULLIF(n_measured,0)
      ELSE NULL
    END AS filab18_score,

    CASE
      WHEN n_measured >= 15
      THEN 10.0 * n_deficits::numeric / NULLIF(n_measured,0)
      ELSE NULL
    END AS filab18_per_0_1

FROM x
;

CREATE UNIQUE INDEX mimic_sens03_filab_pk
  ON frailty_work.mimic_sens03_filab (stay_id);

ANALYZE frailty_work.mimic_sens03_filab;


/* ================================================================
   STEP 8. Modified CCI, excluding CVD and paralysis/paraplegia
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_cci;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_cci AS
SELECT
    u.subject_id,
    u.hadm_id,
    u.stay_id,

    (
        COALESCE(ch.myocardial_infarct,0)
      + COALESCE(ch.congestive_heart_failure,0)
      + COALESCE(ch.peripheral_vascular_disease,0)
      + COALESCE(ch.dementia,0)
      + COALESCE(ch.chronic_pulmonary_disease,0)
      + COALESCE(ch.rheumatic_disease,0)
      + COALESCE(ch.peptic_ulcer_disease,0)
      + GREATEST(
            COALESCE(ch.mild_liver_disease,0),
            3 * COALESCE(ch.severe_liver_disease,0)
        )
      + GREATEST(
            COALESCE(ch.diabetes_without_cc,0),
            2 * COALESCE(ch.diabetes_with_cc,0)
        )
      + 2 * COALESCE(ch.renal_disease,0)
      + GREATEST(
            2 * COALESCE(ch.malignant_cancer,0),
            6 * COALESCE(ch.metastatic_solid_tumor,0)
        )
      + 6 * COALESCE(ch.aids,0)
    )::integer AS cci_chronic_burden_no_age

FROM frailty_work.mimic_sens03_unique_stays u

LEFT JOIN mimiciv_derived.charlson ch
  ON ch.subject_id = u.subject_id
 AND ch.hadm_id = u.hadm_id
;

CREATE UNIQUE INDEX mimic_sens03_cci_pk
  ON frailty_work.mimic_sens03_cci (stay_id);

ANALYZE frailty_work.mimic_sens03_cci;


/* ================================================================
   STEP 9. GCS
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_gcs;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_gcs AS
SELECT
    u.subject_id,
    u.hadm_id,
    u.stay_id,
    g.gcs_min
FROM frailty_work.mimic_sens03_unique_stays u
LEFT JOIN mimiciv_derived.first_day_gcs g
  ON g.stay_id = u.stay_id
;

CREATE UNIQUE INDEX mimic_sens03_gcs_pk
  ON frailty_work.mimic_sens03_gcs (stay_id);

ANALYZE frailty_work.mimic_sens03_gcs;


/* ================================================================
   STEP 10. Invasive ventilation in ICU -6 h to +24 h
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_vent;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_vent AS
SELECT
    u.stay_id,

    MAX(
      CASE
        WHEN v.ventilation_status = 'InvasiveVent'
         AND v.starttime <= u.intime + interval '24 hours'
         AND v.endtime   >= u.intime - interval '6 hours'
        THEN 1 ELSE 0
      END
    )::integer AS any_invasive_vent_m6p24

FROM frailty_work.mimic_sens03_unique_stays u

LEFT JOIN mimiciv_derived.ventilation v
  ON v.stay_id = u.stay_id
 AND v.starttime <= u.intime + interval '24 hours'
 AND v.endtime   >= u.intime - interval '6 hours'

GROUP BY u.stay_id
;

CREATE UNIQUE INDEX mimic_sens03_vent_pk
  ON frailty_work.mimic_sens03_vent (stay_id);

ANALYZE frailty_work.mimic_sens03_vent;


/* ================================================================
   STEP 11. Vasopressor in ICU -6 h to +24 h
   Main vasopressors only; dobutamine/milrinone are not counted here.
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_vaso;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_vaso AS
SELECT
    u.stay_id,

    MAX(
      CASE
        WHEN va.starttime <= u.intime + interval '24 hours'
         AND va.endtime   >= u.intime - interval '6 hours'
         AND (
              va.dopamine       IS NOT NULL
           OR va.epinephrine    IS NOT NULL
           OR va.norepinephrine IS NOT NULL
           OR va.phenylephrine  IS NOT NULL
           OR va.vasopressin    IS NOT NULL
         )
        THEN 1 ELSE 0
      END
    )::integer AS any_vasopressor_m6p24

FROM frailty_work.mimic_sens03_unique_stays u

LEFT JOIN mimiciv_derived.vasoactive_agent va
  ON va.stay_id = u.stay_id
 AND va.starttime <= u.intime + interval '24 hours'
 AND va.endtime   >= u.intime - interval '6 hours'

GROUP BY u.stay_id
;

CREATE UNIQUE INDEX mimic_sens03_vaso_pk
  ON frailty_work.mimic_sens03_vaso (stay_id);

ANALYZE frailty_work.mimic_sens03_vaso;


/* ================================================================
   STEP 12. Final analysis base across all four definitions
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_analysis_base;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_analysis_base AS
SELECT
    c.cohort_def,
    c.cohort_order,

    c.subject_id,
    c.hadm_id,
    c.stay_id,

    c.age,
    c.female,

    c.admittime,
    c.dischtime,
    c.deathtime,
    c.intime,
    c.outtime,

    EXTRACT(EPOCH FROM (c.outtime - c.intime)) / 86400.0
        AS icu_los_days,

    CASE
      WHEN c.deathtime IS NOT NULL
      THEN EXTRACT(EPOCH FROM (c.deathtime - c.intime)) / 86400.0
      ELSE NULL
    END AS days_to_death_from_icu,

    CASE
      WHEN c.deathtime IS NOT NULL
       AND c.deathtime >= c.intime
       AND c.deathtime <= c.outtime
      THEN 1 ELSE 0
    END::integer AS icu_mortality,

    c.hospital_expire_flag,

    c.first_qualifying_seq_num,
    c.has_i63_icd10,
    c.has_strict_ais_icd9,
    c.has_icd9_436,
    c.principal_i63_icd10,
    c.principal_strict_ais_icd9,
    c.principal_icd9_436,

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

    f.n_measured,
    f.n_deficits,
    f.filab18_valid,
    f.filab18_score,
    f.filab18_per_0_1,

    cc.cci_chronic_burden_no_age,

    g.gcs_min,

    COALESCE(v.any_invasive_vent_m6p24,0)::integer
        AS any_invasive_vent_m6p24,

    COALESCE(va.any_vasopressor_m6p24,0)::integer
        AS any_vasopressor_m6p24,

    CASE
      WHEN f.filab18_valid = 1
       AND g.gcs_min IS NOT NULL
       AND c.age IS NOT NULL
       AND c.female IS NOT NULL
       AND cc.cci_chronic_burden_no_age IS NOT NULL
      THEN 1 ELSE 0
    END::integer AS primary_model_completecase

FROM frailty_work.mimic_sens03_cohort_defs c

LEFT JOIN frailty_work.mimic_sens03_filab f
  ON f.stay_id = c.stay_id

LEFT JOIN frailty_work.mimic_sens03_cci cc
  ON cc.stay_id = c.stay_id

LEFT JOIN frailty_work.mimic_sens03_gcs g
  ON g.stay_id = c.stay_id

LEFT JOIN frailty_work.mimic_sens03_vent v
  ON v.stay_id = c.stay_id

LEFT JOIN frailty_work.mimic_sens03_vaso va
  ON va.stay_id = c.stay_id
;

CREATE UNIQUE INDEX mimic_sens03_analysis_base_pk
  ON frailty_work.mimic_sens03_analysis_base
  (cohort_def, subject_id);

CREATE INDEX mimic_sens03_analysis_base_stay
  ON frailty_work.mimic_sens03_analysis_base (stay_id);

ANALYZE frailty_work.mimic_sens03_analysis_base;


/* ================================================================
   STEP 13. QC tables
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_sens03_flow_qc;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_flow_qc AS
SELECT
    cohort_order,
    cohort_def,
    COUNT(*)::integer AS n_cohort,
    SUM(filab18_valid)::integer AS n_fi_valid,
    ROUND(100.0 * AVG(filab18_valid::numeric),2) AS pct_fi_valid,
    SUM(primary_model_completecase)::integer AS n_primary_completecase,
    SUM(
      CASE WHEN primary_model_completecase=1
           THEN hospital_expire_flag ELSE 0 END
    )::integer AS deaths_primary_completecase,
    ROUND(
      100.0 * AVG(
        CASE WHEN primary_model_completecase=1
             THEN hospital_expire_flag::numeric ELSE NULL END
      ),2
    ) AS mortality_pct_primary_completecase
FROM frailty_work.mimic_sens03_analysis_base
GROUP BY cohort_order, cohort_def
ORDER BY cohort_order
;


DROP TABLE IF EXISTS frailty_work.mimic_sens03_code_mix_qc;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_code_mix_qc AS
SELECT
    cohort_order,
    cohort_def,
    COUNT(*)::integer AS n,

    SUM(has_i63_icd10)::integer AS n_with_i63_icd10,
    SUM(has_strict_ais_icd9)::integer AS n_with_strict_ais_icd9,
    SUM(has_icd9_436)::integer AS n_with_icd9_436,

    SUM(principal_i63_icd10)::integer AS n_principal_i63_icd10,
    SUM(principal_strict_ais_icd9)::integer AS n_principal_strict_ais_icd9,
    SUM(principal_icd9_436)::integer AS n_principal_icd9_436,

    SUM(CASE WHEN first_qualifying_seq_num = 1 THEN 1 ELSE 0 END)::integer
        AS n_first_qualifying_in_principal_position,
    SUM(CASE WHEN first_qualifying_seq_num > 1 THEN 1 ELSE 0 END)::integer
        AS n_first_qualifying_nonprincipal

FROM frailty_work.mimic_sens03_analysis_base
GROUP BY cohort_order, cohort_def
ORDER BY cohort_order
;


DROP TABLE IF EXISTS frailty_work.mimic_sens03_fi_coverage_qc;

CREATE UNLOGGED TABLE frailty_work.mimic_sens03_fi_coverage_qc AS
SELECT
    cohort_order,
    cohort_def,
    n_measured,
    COUNT(*)::integer AS n,
    ROUND(
      100.0 * COUNT(*) /
      SUM(COUNT(*)) OVER (PARTITION BY cohort_def), 3
    ) AS pct
FROM frailty_work.mimic_sens03_analysis_base
GROUP BY cohort_order, cohort_def, n_measured
ORDER BY cohort_order, n_measured
;


/* ================================================================
   STEP 14. DISPLAY benchmark QC in Navicat
   ================================================================ */

SELECT *
FROM frailty_work.mimic_sens03_flow_qc
ORDER BY cohort_order;

SELECT *
FROM frailty_work.mimic_sens03_code_mix_qc
ORDER BY cohort_order;


/* ================================================================
   STEP 15. AUTO-EXPORT ALL RESULTS TO C:\temp\
   ================================================================ */

/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */



/* ================================================================
   S4 CANONICAL PRIMARY DATASETS
   These are the actual inputs expected by the final analysis code.
   Built ONLY from P0_PRIMARY_FROZEN.
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_s4_h92_analysis_base_all;
CREATE UNLOGGED TABLE frailty_work.mimic_s4_h92_analysis_base_all AS
SELECT *
FROM frailty_work.mimic_sens03_analysis_base
WHERE cohort_def = 'P0_PRIMARY_FROZEN'
ORDER BY subject_id, hadm_id, stay_id
;

CREATE UNIQUE INDEX mimic_s4_h92_pk
  ON frailty_work.mimic_s4_h92_analysis_base_all (stay_id);

ANALYZE frailty_work.mimic_s4_h92_analysis_base_all;


DROP TABLE IF EXISTS frailty_work.mimic_s4_h93_primary_fi;
CREATE UNLOGGED TABLE frailty_work.mimic_s4_h93_primary_fi AS
SELECT *
FROM frailty_work.mimic_s4_h92_analysis_base_all
WHERE filab18_valid = 1
ORDER BY subject_id, hadm_id, stay_id
;

CREATE UNIQUE INDEX mimic_s4_h93_pk
  ON frailty_work.mimic_s4_h93_primary_fi (stay_id);

ANALYZE frailty_work.mimic_s4_h93_primary_fi;


DROP TABLE IF EXISTS frailty_work.mimic_s4_h94_primary_completecase;
CREATE UNLOGGED TABLE frailty_work.mimic_s4_h94_primary_completecase AS
SELECT *
FROM frailty_work.mimic_s4_h92_analysis_base_all
WHERE primary_model_completecase = 1
ORDER BY subject_id, hadm_id, stay_id
;

CREATE UNIQUE INDEX mimic_s4_h94_pk
  ON frailty_work.mimic_s4_h94_primary_completecase (stay_id);

ANALYZE frailty_work.mimic_s4_h94_primary_completecase;


/* Canonical exports used by R / Python analysis scripts */

/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/*
Item-level frozen Core-18 export.
This file is sufficient for same-sample Core17/Core16 recalculation.
*/
/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


/* Canonical S4 reproduction QC */

/* Portable S4 version: server-side COPY removed; use MIMIC_FINAL_EXPORT_QUERIES.sql. */


SELECT
    (SELECT COUNT(*)
       FROM frailty_work.mimic_s4_h92_analysis_base_all) AS h92_n,
    (SELECT SUM(hospital_expire_flag)
       FROM frailty_work.mimic_s4_h92_analysis_base_all) AS h92_deaths,

    (SELECT COUNT(*)
       FROM frailty_work.mimic_s4_h93_primary_fi) AS h93_n,
    (SELECT SUM(hospital_expire_flag)
       FROM frailty_work.mimic_s4_h93_primary_fi) AS h93_deaths,

    (SELECT COUNT(*)
       FROM frailty_work.mimic_s4_h94_primary_completecase) AS h94_n,
    (SELECT SUM(hospital_expire_flag)
       FROM frailty_work.mimic_s4_h94_primary_completecase) AS h94_deaths
;

/*
EXPECTED:
H92  n=1741, deaths=189
H93  n=1666, deaths=183
H94  n=1665, deaths=183

The H94 patient IDs and all primary-model variables have already been
independently cross-checked against the frozen V5 H94 in the broader-AIS
sensitivity workflow.
*/


/* ================================================================
   FINAL CHECK
   ================================================================ */

SELECT
    'DONE' AS status,
    COUNT(*) FILTER (WHERE cohort_def='P0_PRIMARY_FROZEN')
        AS p0_all_n,
    COUNT(*) FILTER (
        WHERE cohort_def='P0_PRIMARY_FROZEN'
          AND filab18_valid=1
    ) AS p0_fi_valid_n,
    COUNT(*) FILTER (
        WHERE cohort_def='P0_PRIMARY_FROZEN'
          AND primary_model_completecase=1
    ) AS p0_completecase_n,
    SUM(
      CASE WHEN cohort_def='P0_PRIMARY_FROZEN'
             AND primary_model_completecase=1
           THEN hospital_expire_flag ELSE 0 END
    ) AS p0_completecase_deaths
FROM frailty_work.mimic_sens03_analysis_base
;

/*
EXPECTED FINAL CHECK:
P0 all n              = 1741
P0 FI valid n         = 1666
P0 complete-case n    = 1665
P0 complete-case deaths = 183

If ANY of these four benchmark values differs:
STOP.
Do not interpret S1-S3 yet.
Upload the SQL result/error and the exported QC files.
*/

/* ================================================================
   S4 FINAL LOCKED QC — portable public-code version
   ================================================================ */

DROP TABLE IF EXISTS frailty_work.mimic_s4_final_qc;

CREATE UNLOGGED TABLE frailty_work.mimic_s4_final_qc AS
SELECT
    (SELECT COUNT(*) FROM frailty_work.mimic_s4_h92_analysis_base_all)
        AS h92_n,
    (SELECT SUM(hospital_expire_flag) FROM frailty_work.mimic_s4_h92_analysis_base_all)
        AS h92_deaths,

    (SELECT COUNT(*) FROM frailty_work.mimic_s4_h93_primary_fi)
        AS h93_n,
    (SELECT SUM(hospital_expire_flag) FROM frailty_work.mimic_s4_h93_primary_fi)
        AS h93_deaths,

    (SELECT COUNT(*) FROM frailty_work.mimic_s4_h94_primary_completecase)
        AS h94_n,
    (SELECT SUM(hospital_expire_flag) FROM frailty_work.mimic_s4_h94_primary_completecase)
        AS h94_deaths,

    1741::bigint AS expected_h92_n,
    189::bigint  AS expected_h92_deaths,
    1666::bigint AS expected_h93_n,
    183::bigint  AS expected_h93_deaths,
    1665::bigint AS expected_h94_n,
    183::bigint  AS expected_h94_deaths,

    CASE WHEN
        (SELECT COUNT(*) FROM frailty_work.mimic_s4_h92_analysis_base_all)=1741
    AND (SELECT SUM(hospital_expire_flag) FROM frailty_work.mimic_s4_h92_analysis_base_all)=189
    AND (SELECT COUNT(*) FROM frailty_work.mimic_s4_h93_primary_fi)=1666
    AND (SELECT SUM(hospital_expire_flag) FROM frailty_work.mimic_s4_h93_primary_fi)=183
    AND (SELECT COUNT(*) FROM frailty_work.mimic_s4_h94_primary_completecase)=1665
    AND (SELECT SUM(hospital_expire_flag) FROM frailty_work.mimic_s4_h94_primary_completecase)=183
    THEN 1 ELSE 0 END AS all_locked_counts_pass
;

ANALYZE frailty_work.mimic_s4_final_qc;
