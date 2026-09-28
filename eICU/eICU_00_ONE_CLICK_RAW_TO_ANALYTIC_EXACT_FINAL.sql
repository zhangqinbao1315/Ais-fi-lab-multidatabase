/*
=====================================================================
S4 eICU RAW -> ANALYTIC — AUTHORITATIVE EXACT FINAL
=====================================================================

This file supersedes all earlier eICU repair / rule-lock / patch files.

Final verified definitions
--------------------------
Cohort:
- adult age >=18
- within each patientHealthSystemStayID, select the FIRST AVAILABLE ICU
  unit row: minimum unitVisitNumber, patientUnitStayID tie-breaker
- do NOT hard-require unitVisitNumber = 1
- exact APACHE admission diagnosis:
    CVA, cerebrovascular accident/stroke
- strict same-unit ischemic-stroke ICD-9 token:
    433.x1 or 434.x1
- patient-level chronology remains in eICU_25

FI-Lab:
- Core-18
- earliest value in the harmonized first-day window
- >=15/18 evaluable

Key exact-reproduction fixes:
- eICU_29: explicit Core-18 columns; no w.* duplicate key
- eICU_42: APACHE IVa identified by apacheVersion='IVa'
- APACHE IVa score/APS value -1 is treated as missing (NULL)
- historical frozen definitions for support/sensitivity fields retained

Verified final outputs:
- eICU_15 candidate: 2855
- eICU_25 primary: 2807; deaths 261; unitVisitNumber>1 = 193
- eICU_48: 2807; deaths 261
- eICU_49: 2091; deaths 205
- eICU_50: 2015; deaths 197; IMV 314; vasopressor 115

Independent file-level audit:
- eICU_48: 2807 rows x 105 columns, 0 cell mismatches vs frozen file
- eICU_49: 2091 rows x 105 columns, exact frozen-derived subset
- eICU_50: 2015 rows x 105 columns, exact frozen-derived subset

Required final switches:
  frailty_work.eicu_s4_final_qc.all_locked_counts_pass = 1
  frailty_work.eicu_s4_field_alignment_qc.all_field_proxy_checks_pass = 1

No server-side COPY TO path is used.
=====================================================================
*/


/* ================================================================
   BEGIN 15_MAIN_AIS_CANDIDATE
   ================================================================ */

/*
=====================================================================
eICU S4 FINAL — 15
Build the main AIS candidate hospitalization/unit-stay table.

FINAL LOCKED COHORT RULE
------------------------
This rule was independently locked against the frozen analytic cohort:

- candidate qualifying hospitalizations: 2,855
- final primary cohort: 2,807
- exact frozen patientUnitStayID overlap: 2,807 / 2,807
- frozen missing: 0
- reconstructed extra: 0
- audit-field match: 2,807 / 2,807
- final rows with unitVisitNumber > 1: 193
- hospital deaths: 261

Operational definition
----------------------
Within each patientHealthSystemStayID:

1. Select the FIRST AVAILABLE ICU unit row in the database:
   minimum unitVisitNumber;
   patientUnitStayID is the deterministic tie-breaker.

   IMPORTANT:
   This is NOT the same as requiring unitVisitNumber = 1.
   Some hospital stays have no unitVisitNumber=1 row in the available
   eICU extract. The first available row can therefore have
   unitVisitNumber 2, 3, or 4.

2. On that selected first-available ICU unit require:
   - adult age >=18
   - APACHE admission diagnosis EXACT:
       "CVA, cerebrovascular accident/stroke"
   - at least one strict ischemic-stroke ICD token on the SAME ICU unit:
       ICD-9 433.x1 or 434.x1

3. Do not exclude short ICU stays.

A patient may still have more than one qualifying hospitalization here.
Patient-level chronology/deduplication remains in eICU_25 and is unchanged.
=====================================================================
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_15_main_ais_candidate_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_15_main_ais_candidate_v1 AS
WITH first_available_unit_ids AS (
    SELECT
        patienthealthsystemstayid,
        patientunitstayid
    FROM (
        SELECT
            p.patienthealthsystemstayid,
            p.patientunitstayid,
            ROW_NUMBER() OVER (
                PARTITION BY p.patienthealthsystemstayid
                ORDER BY
                    p.unitvisitnumber NULLS LAST,
                    p.patientunitstayid
            ) AS rn
        FROM eicu_crd.patient p
        WHERE p.patienthealthsystemstayid IS NOT NULL
    ) q
    WHERE rn = 1
),
p0 AS (
    SELECT
        p.*,

        CASE
            WHEN BTRIM(p.age::text) = '> 89' THEN 90
            WHEN BTRIM(p.age::text) ~ '^[0-9]+$'
                THEN BTRIM(p.age::text)::integer
            ELSE NULL
        END AS age_numeric

    FROM eicu_crd.patient p

    JOIN first_available_unit_ids f
      ON f.patienthealthsystemstayid = p.patienthealthsystemstayid
     AND f.patientunitstayid = p.patientunitstayid

    WHERE LOWER(BTRIM(COALESCE(p.apacheadmissiondx::text,'')))
          = 'cva, cerebrovascular accident/stroke'
),
strict_dx AS (
    SELECT DISTINCT
        p.patientunitstayid

    FROM p0 p

    JOIN eicu_crd.diagnosis d
      ON d.patientunitstayid = p.patientunitstayid

    CROSS JOIN LATERAL
        regexp_split_to_table(
            COALESCE(d.icd9code::text,''),
            ','
        ) AS tok(code_token)

    WHERE
      UPPER(
        REGEXP_REPLACE(
            BTRIM(tok.code_token),
            '[^A-Za-z0-9]',
            '',
            'g'
        )
      ) ~ '^(433[0-9]1|434[0-9]1)$'
)

SELECT
    p.*
FROM p0 p
JOIN strict_dx d
  ON d.patientunitstayid = p.patientunitstayid
WHERE p.age_numeric >= 18
;

CREATE UNIQUE INDEX eicu_15_main_ais_candidate_v1_pk
    ON frailty_work.eicu_15_main_ais_candidate_v1 (patientunitstayid);

CREATE INDEX eicu_15_main_ais_candidate_v1_pid
    ON frailty_work.eicu_15_main_ais_candidate_v1 (uniquepid);

CREATE INDEX eicu_15_main_ais_candidate_v1_hs
    ON frailty_work.eicu_15_main_ais_candidate_v1
       (patienthealthsystemstayid);

ANALYZE frailty_work.eicu_15_main_ais_candidate_v1;


/* Locked stage-level QC */
SELECT
    COUNT(*) AS n_candidate_rows,
    COUNT(DISTINCT uniquepid) AS n_candidate_patients,
    COUNT(DISTINCT patienthealthsystemstayid)
        AS n_candidate_hospital_stays,
    COUNT(*) FILTER (WHERE unitvisitnumber > 1)
        AS n_candidate_unitvisit_gt1
FROM frailty_work.eicu_15_main_ais_candidate_v1
;

/*
LOCKED expected:
n_candidate_rows = 2855
*/

/* ================================================================
   END 15_MAIN_AIS_CANDIDATE
   ================================================================ */


/* ================================================================
   BEGIN 20_LAB_WINDOW
   ================================================================ */

/*
eICU S4 FINAL - 20
Materialize first-day laboratory rows for the qualifying AIS candidate stays.

Window:
  ICU admission -360 to +1440 minutes.

This intentionally retains raw eICU lab names.
Strict Core-18 mapping occurs in eICU_27.
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_20_lab_window_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_20_lab_window_v1 AS
SELECT
    l.labid,
    l.patientunitstayid,
    l.labresultoffset,
    l.labtypeid,
    l.labname,
    l.labresult,
    l.labresulttext,
    l.labmeasurenamesystem,
    l.labmeasurenameinterface
FROM eicu_crd.lab l
JOIN frailty_work.eicu_15_main_ais_candidate_v1 c
  ON c.patientunitstayid = l.patientunitstayid
WHERE l.labresultoffset BETWEEN -360 AND 1440
  AND l.labresult IS NOT NULL
;

CREATE INDEX eicu_20_lab_window_v1_stay_item_time
    ON frailty_work.eicu_20_lab_window_v1
       (patientunitstayid, labname, labresultoffset, labid);

ANALYZE frailty_work.eicu_20_lab_window_v1;

SELECT
    COUNT(*) AS n_lab_rows,
    COUNT(DISTINCT patientunitstayid) AS n_stays_with_any_lab,
    COUNT(DISTINCT labname) AS n_distinct_lab_names
FROM frailty_work.eicu_20_lab_window_v1;

/* ================================================================
   END 20_LAB_WINDOW
   ================================================================ */


/* ================================================================
   BEGIN 25_PRIMARY_UNIQUE_AIS
   ================================================================ */

/*
eICU - 25
Freeze one-row-per-patient primary AIS cohort as far as chronology permits.

Requires:
  frailty_work.eicu_15_main_ais_candidate_v1
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_25_primary_ais_cohort_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_25_primary_ais_cohort_v1 AS
WITH pstat AS (
    SELECT
        uniquepid,
        COUNT(*) AS n_qualifying,
        MIN(hospitaldischargeyear) AS earliest_year
    FROM frailty_work.eicu_15_main_ais_candidate_v1
    GROUP BY uniquepid
),
earliest_counts AS (
    SELECT
        c.uniquepid,
        s.n_qualifying,
        s.earliest_year,
        COUNT(*) FILTER (
            WHERE c.hospitaldischargeyear = s.earliest_year
        ) AS n_in_earliest_year
    FROM frailty_work.eicu_15_main_ais_candidate_v1 c
    JOIN pstat s
      ON s.uniquepid = c.uniquepid
    GROUP BY
        c.uniquepid,
        s.n_qualifying,
        s.earliest_year
)
SELECT
    c.*,
    e.n_qualifying AS n_qualifying_hospitalizations_for_patient,
    e.earliest_year AS earliest_qualifying_discharge_year,
    e.n_in_earliest_year
FROM frailty_work.eicu_15_main_ais_candidate_v1 c
JOIN earliest_counts e
  ON e.uniquepid = c.uniquepid
WHERE
      e.n_qualifying = 1
   OR (
        e.n_qualifying > 1
        AND e.earliest_year IS NOT NULL
        AND e.n_in_earliest_year = 1
        AND c.hospitaldischargeyear = e.earliest_year
   )
;

CREATE UNIQUE INDEX eicu_25_primary_ais_cohort_v1_pk
    ON frailty_work.eicu_25_primary_ais_cohort_v1 (patientunitstayid);

CREATE UNIQUE INDEX eicu_25_primary_ais_cohort_v1_pid
    ON frailty_work.eicu_25_primary_ais_cohort_v1 (uniquepid);

ANALYZE frailty_work.eicu_25_primary_ais_cohort_v1;


/* Strict sensitivity: exclude every patient with >1 qualifying hospitalization */
DROP TABLE IF EXISTS frailty_work.eicu_25_primary_ais_cohort_strict_unique_sens;

CREATE UNLOGGED TABLE frailty_work.eicu_25_primary_ais_cohort_strict_unique_sens AS
WITH counts AS (
    SELECT uniquepid, COUNT(*) AS n
    FROM frailty_work.eicu_15_main_ais_candidate_v1
    GROUP BY uniquepid
)
SELECT c.*
FROM frailty_work.eicu_15_main_ais_candidate_v1 c
JOIN counts x
  ON x.uniquepid = c.uniquepid
WHERE x.n = 1
;

CREATE UNIQUE INDEX eicu_25_primary_ais_cohort_strict_unique_sens_pk
    ON frailty_work.eicu_25_primary_ais_cohort_strict_unique_sens (patientunitstayid);

SELECT
    (SELECT COUNT(*)
     FROM frailty_work.eicu_15_main_ais_candidate_v1)
        AS n_candidate_hospitalizations,

    (SELECT COUNT(DISTINCT uniquepid)
     FROM frailty_work.eicu_15_main_ais_candidate_v1)
        AS n_candidate_unique_patients,

    (SELECT COUNT(*)
     FROM frailty_work.eicu_25_primary_ais_cohort_v1)
        AS n_primary_unique_patient_cohort,

    (SELECT COUNT(*)
     FROM frailty_work.eicu_25_primary_ais_cohort_strict_unique_sens)
        AS n_strict_unique_sensitivity
;

/* ================================================================
   END 25_PRIMARY_UNIQUE_AIS
   ================================================================ */


/* ================================================================
   BEGIN 27_CORE18_EARLIEST
   ================================================================ */

/*
eICU - 27
Build earliest Core-18 values in the frozen primary unique-patient cohort.

Uses existing small table:
  frailty_work.eicu_20_lab_window_v1

Primary mapping is deliberately strict:
- serum/central-lab glucose only
- bicarbonate only
- excludes bedside glucose, Total CO2, HCO3
*/

DROP TABLE IF EXISTS frailty_work.eicu_27_core18_earliest_long_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_27_core18_earliest_long_v1 AS
WITH mapped AS (
    SELECT
        l.patientunitstayid,
        l.labid,
        l.labresultoffset,
        l.labname,
        l.labresult::double precision AS value,

        CASE
            WHEN l.labname = 'WBC x 1000' THEN 'WBC'
            WHEN l.labname = 'Hgb' THEN 'Hemoglobin'
            WHEN l.labname = 'Hct' THEN 'Hematocrit'
            WHEN l.labname = 'platelets x 1000' THEN 'Platelet'
            WHEN l.labname = 'RBC' THEN 'RBC'
            WHEN l.labname = 'MCV' THEN 'MCV'
            WHEN l.labname = 'sodium' THEN 'Sodium'
            WHEN l.labname = 'potassium' THEN 'Potassium'
            WHEN l.labname = 'chloride' THEN 'Chloride'
            WHEN l.labname = 'bicarbonate' THEN 'Bicarbonate'
            WHEN l.labname = 'BUN' THEN 'BUN'
            WHEN l.labname = 'creatinine' THEN 'Creatinine'
            WHEN l.labname = 'glucose' THEN 'Glucose'
            WHEN l.labname = 'calcium' THEN 'Calcium'
            WHEN l.labname = 'magnesium' THEN 'Magnesium'
            WHEN l.labname = 'phosphate' THEN 'Phosphate'
            WHEN l.labname = 'PT - INR' THEN 'INR'
            WHEN l.labname = 'PTT' THEN 'aPTT'
            ELSE NULL
        END AS core18_item

    FROM frailty_work.eicu_20_lab_window_v1 l
    JOIN frailty_work.eicu_25_primary_ais_cohort_v1 c
      ON c.patientunitstayid = l.patientunitstayid

    WHERE l.labresultoffset BETWEEN -360 AND 1440
      AND l.labresult IS NOT NULL
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY patientunitstayid, core18_item
            ORDER BY labresultoffset ASC, labid ASC
        ) AS rn
    FROM mapped
    WHERE core18_item IS NOT NULL
)
SELECT
    patientunitstayid,
    core18_item,
    labname,
    value,
    labresultoffset,
    labid
FROM ranked
WHERE rn = 1
;

CREATE UNIQUE INDEX eicu_27_core18_earliest_long_v1_pk
    ON frailty_work.eicu_27_core18_earliest_long_v1
       (patientunitstayid, core18_item);


DROP TABLE IF EXISTS frailty_work.eicu_27_core18_earliest_wide_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_27_core18_earliest_wide_v1 AS
SELECT
    c.patientunitstayid,

    MAX(v.value) FILTER (WHERE v.core18_item='WBC') AS wbc,
    MAX(v.value) FILTER (WHERE v.core18_item='Hemoglobin') AS hemoglobin,
    MAX(v.value) FILTER (WHERE v.core18_item='Hematocrit') AS hematocrit,
    MAX(v.value) FILTER (WHERE v.core18_item='Platelet') AS platelet,
    MAX(v.value) FILTER (WHERE v.core18_item='RBC') AS rbc,
    MAX(v.value) FILTER (WHERE v.core18_item='MCV') AS mcv,
    MAX(v.value) FILTER (WHERE v.core18_item='Sodium') AS sodium,
    MAX(v.value) FILTER (WHERE v.core18_item='Potassium') AS potassium,
    MAX(v.value) FILTER (WHERE v.core18_item='Chloride') AS chloride,
    MAX(v.value) FILTER (WHERE v.core18_item='Bicarbonate') AS bicarbonate,
    MAX(v.value) FILTER (WHERE v.core18_item='BUN') AS bun,
    MAX(v.value) FILTER (WHERE v.core18_item='Creatinine') AS creatinine,
    MAX(v.value) FILTER (WHERE v.core18_item='Glucose') AS glucose,
    MAX(v.value) FILTER (WHERE v.core18_item='Calcium') AS calcium,
    MAX(v.value) FILTER (WHERE v.core18_item='Magnesium') AS magnesium,
    MAX(v.value) FILTER (WHERE v.core18_item='Phosphate') AS phosphate,
    MAX(v.value) FILTER (WHERE v.core18_item='INR') AS inr,
    MAX(v.value) FILTER (WHERE v.core18_item='aPTT') AS aptt

FROM frailty_work.eicu_25_primary_ais_cohort_v1 c
LEFT JOIN frailty_work.eicu_27_core18_earliest_long_v1 v
  ON v.patientunitstayid = c.patientunitstayid
GROUP BY c.patientunitstayid
;

CREATE UNIQUE INDEX eicu_27_core18_earliest_wide_v1_pk
    ON frailty_work.eicu_27_core18_earliest_wide_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_27_core18_earliest_long_v1;
ANALYZE frailty_work.eicu_27_core18_earliest_wide_v1;

SELECT
    COUNT(*) AS n_primary_rows,
    COUNT(*) FILTER (
        WHERE
          (wbc IS NOT NULL)::int +
          (hemoglobin IS NOT NULL)::int +
          (hematocrit IS NOT NULL)::int +
          (platelet IS NOT NULL)::int +
          (rbc IS NOT NULL)::int +
          (mcv IS NOT NULL)::int +
          (sodium IS NOT NULL)::int +
          (potassium IS NOT NULL)::int +
          (chloride IS NOT NULL)::int +
          (bicarbonate IS NOT NULL)::int +
          (bun IS NOT NULL)::int +
          (creatinine IS NOT NULL)::int +
          (glucose IS NOT NULL)::int +
          (calcium IS NOT NULL)::int +
          (magnesium IS NOT NULL)::int +
          (phosphate IS NOT NULL)::int +
          (inr IS NOT NULL)::int +
          (aptt IS NOT NULL)::int >= 15
    ) AS n_with_at_least_15_of_18
FROM frailty_work.eicu_27_core18_earliest_wide_v1;

/* ================================================================
   END 27_CORE18_EARLIEST
   ================================================================ */


/* ================================================================
   BEGIN 29_FILAB18
   ================================================================ */

/*
FIX v1.2
--------
Replaced w.* with an explicit list of the 18 laboratory columns.
This prevents duplicate patientunitstayid in CREATE TABLE AS because
eicu_27_core18_earliest_wide_v1 already contains patientunitstayid while
the cohort keys are selected explicitly from c.
*/

/*
eICU - 29
Build Core-18 FI-Lab using MIMIC-frozen v1 thresholds.

Primary FI requires:
- gender Male/Female because Hb/Hct/RBC/creatinine use sex-specific thresholds
- >=15 measured Core-18 items

Missing labs are NULL and are NOT counted as normal.
*/

DROP TABLE IF EXISTS frailty_work.eicu_29_filab18_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_29_filab18_v1 AS
WITH x AS (
    SELECT
        c.patientunitstayid,
        c.patienthealthsystemstayid,
        c.uniquepid,
        c.gender,
        c.age_numeric,
        c.hospitaldischargestatus,

        CASE
            WHEN LOWER(BTRIM(COALESCE(c.hospitaldischargestatus,'')))='expired'
                THEN 1
            WHEN LOWER(BTRIM(COALESCE(c.hospitaldischargestatus,'')))='alive'
                THEN 0
            ELSE NULL
        END AS hospital_mortality,

        w.wbc,
        w.hemoglobin,
        w.hematocrit,
        w.platelet,
        w.rbc,
        w.mcv,
        w.sodium,
        w.potassium,
        w.chloride,
        w.bicarbonate,
        w.bun,
        w.creatinine,
        w.glucose,
        w.calcium,
        w.magnesium,
        w.phosphate,
        w.inr,
        w.aptt,

        (w.wbc IS NOT NULL)::int +
        (w.hemoglobin IS NOT NULL)::int +
        (w.hematocrit IS NOT NULL)::int +
        (w.platelet IS NOT NULL)::int +
        (w.rbc IS NOT NULL)::int +
        (w.mcv IS NOT NULL)::int +
        (w.sodium IS NOT NULL)::int +
        (w.potassium IS NOT NULL)::int +
        (w.chloride IS NOT NULL)::int +
        (w.bicarbonate IS NOT NULL)::int +
        (w.bun IS NOT NULL)::int +
        (w.creatinine IS NOT NULL)::int +
        (w.glucose IS NOT NULL)::int +
        (w.calcium IS NOT NULL)::int +
        (w.magnesium IS NOT NULL)::int +
        (w.phosphate IS NOT NULL)::int +
        (w.inr IS NOT NULL)::int +
        (w.aptt IS NOT NULL)::int AS n_measured

    FROM frailty_work.eicu_25_primary_ais_cohort_v1 c
    JOIN frailty_work.eicu_27_core18_earliest_wide_v1 w
      ON w.patientunitstayid = c.patientunitstayid
),
d AS (
    SELECT
        x.*,

        CASE WHEN wbc IS NULL THEN NULL
             WHEN wbc < 4.0 OR wbc > 10.0 THEN 1 ELSE 0 END AS d_wbc,

        CASE
            WHEN hemoglobin IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN hemoglobin < 11.2 OR hemoglobin > 15.7 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN hemoglobin < 13.7 OR hemoglobin > 17.5 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_hemoglobin,

        CASE
            WHEN hematocrit IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN hematocrit < 34 OR hematocrit > 45 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN hematocrit < 40 OR hematocrit > 51 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_hematocrit,

        CASE WHEN platelet IS NULL THEN NULL
             WHEN platelet < 150 OR platelet > 400 THEN 1 ELSE 0 END AS d_platelet,

        CASE
            WHEN rbc IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN rbc < 3.9 OR rbc > 5.2 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN rbc < 4.6 OR rbc > 6.1 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_rbc,

        CASE WHEN mcv IS NULL THEN NULL
             WHEN mcv < 82 OR mcv > 98 THEN 1 ELSE 0 END AS d_mcv,

        CASE WHEN sodium IS NULL THEN NULL
             WHEN sodium < 135 OR sodium > 145 THEN 1 ELSE 0 END AS d_sodium,

        CASE WHEN potassium IS NULL THEN NULL
             WHEN potassium < 3.5 OR potassium > 5.1 THEN 1 ELSE 0 END AS d_potassium,

        CASE WHEN chloride IS NULL THEN NULL
             WHEN chloride < 96 OR chloride > 108 THEN 1 ELSE 0 END AS d_chloride,

        CASE WHEN bicarbonate IS NULL THEN NULL
             WHEN bicarbonate < 22 OR bicarbonate > 32 THEN 1 ELSE 0 END AS d_bicarbonate,

        CASE WHEN bun IS NULL THEN NULL
             WHEN bun < 6 OR bun > 20 THEN 1 ELSE 0 END AS d_bun,

        CASE
            WHEN creatinine IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN creatinine < 0.4 OR creatinine > 1.1 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN creatinine < 0.5 OR creatinine > 1.2 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_creatinine,

        CASE WHEN glucose IS NULL THEN NULL
             WHEN glucose < 70 OR glucose > 100 THEN 1 ELSE 0 END AS d_glucose,

        CASE WHEN calcium IS NULL THEN NULL
             WHEN calcium < 8.4 OR calcium > 10.3 THEN 1 ELSE 0 END AS d_calcium,

        CASE WHEN magnesium IS NULL THEN NULL
             WHEN magnesium < 1.6 OR magnesium > 2.6 THEN 1 ELSE 0 END AS d_magnesium,

        CASE WHEN phosphate IS NULL THEN NULL
             WHEN phosphate < 2.7 OR phosphate > 4.5 THEN 1 ELSE 0 END AS d_phosphate,

        CASE WHEN inr IS NULL THEN NULL
             WHEN inr < 0.9 OR inr > 1.1 THEN 1 ELSE 0 END AS d_inr,

        CASE WHEN aptt IS NULL THEN NULL
             WHEN aptt < 25 OR aptt > 36.5 THEN 1 ELSE 0 END AS d_aptt

    FROM x
),
s AS (
    SELECT
        d.*,

        COALESCE(d_wbc,0) +
        COALESCE(d_hemoglobin,0) +
        COALESCE(d_hematocrit,0) +
        COALESCE(d_platelet,0) +
        COALESCE(d_rbc,0) +
        COALESCE(d_mcv,0) +
        COALESCE(d_sodium,0) +
        COALESCE(d_potassium,0) +
        COALESCE(d_chloride,0) +
        COALESCE(d_bicarbonate,0) +
        COALESCE(d_bun,0) +
        COALESCE(d_creatinine,0) +
        COALESCE(d_glucose,0) +
        COALESCE(d_calcium,0) +
        COALESCE(d_magnesium,0) +
        COALESCE(d_phosphate,0) +
        COALESCE(d_inr,0) +
        COALESCE(d_aptt,0) AS n_deficits,

        (d_wbc IS NOT NULL)::int +
        (d_hemoglobin IS NOT NULL)::int +
        (d_hematocrit IS NOT NULL)::int +
        (d_platelet IS NOT NULL)::int +
        (d_rbc IS NOT NULL)::int +
        (d_mcv IS NOT NULL)::int +
        (d_sodium IS NOT NULL)::int +
        (d_potassium IS NOT NULL)::int +
        (d_chloride IS NOT NULL)::int +
        (d_bicarbonate IS NOT NULL)::int +
        (d_bun IS NOT NULL)::int +
        (d_creatinine IS NOT NULL)::int +
        (d_glucose IS NOT NULL)::int +
        (d_calcium IS NOT NULL)::int +
        (d_magnesium IS NOT NULL)::int +
        (d_phosphate IS NOT NULL)::int +
        (d_inr IS NOT NULL)::int +
        (d_aptt IS NOT NULL)::int AS n_evaluable

    FROM d
)
SELECT
    s.*,

    CASE
        WHEN LOWER(BTRIM(COALESCE(gender,''))) IN ('female','male')
         AND n_measured >= 15
         AND n_evaluable >= 15
        THEN n_deficits::double precision / NULLIF(n_evaluable,0)
        ELSE NULL
    END AS filab18,

    CASE
        WHEN LOWER(BTRIM(COALESCE(gender,''))) IN ('female','male')
         AND n_measured >= 15
         AND n_evaluable >= 15
        THEN 10.0 * n_deficits::double precision / NULLIF(n_evaluable,0)
        ELSE NULL
    END AS filab18_per_0_1

FROM s
;

CREATE UNIQUE INDEX eicu_29_filab18_v1_pk
    ON frailty_work.eicu_29_filab18_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_29_filab18_v1;

SELECT
    COUNT(*) AS n_total,
    COUNT(filab18) AS n_valid_filab18
FROM frailty_work.eicu_29_filab18_v1;

/* ================================================================
   END 29_FILAB18
   ================================================================ */


/* ================================================================
   BEGIN 38_DIAGNOSIS_CCI
   ================================================================ */

/*
eICU - 38
Diagnosis-based Charlson reconstruction.

The ICD logic mirrors the MIMIC/Quan Charlson concept.
eICU diagnosis.icd9Code commonly stores comma-separated paired ICD-9/ICD-10
representations. Tokens are cleaned by removing punctuation.

CCI is aggregated across ALL ICU unit stays belonging to the same
patientHealthSystemStayID, approximating hospital-level diagnosis ascertainment.
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_38_cci_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_38_cci_v1 AS
WITH cohort AS (
    SELECT
        patientunitstayid AS index_patientunitstayid,
        patienthealthsystemstayid
    FROM frailty_work.eicu_25_primary_ais_cohort_v1
),
hospital_units AS (
    SELECT
        c.index_patientunitstayid,
        c.patienthealthsystemstayid,
        p.patientunitstayid
    FROM cohort c
    JOIN eicu_crd.patient p
      ON p.patienthealthsystemstayid = c.patienthealthsystemstayid
),
diag_token AS (
    SELECT
        h.index_patientunitstayid,
        UPPER(
            REGEXP_REPLACE(BTRIM(tok.code_token), '[^A-Za-z0-9]', '', 'g')
        ) AS code
    FROM hospital_units h
    JOIN eicu_crd.diagnosis d
      ON d.patientunitstayid = h.patientunitstayid
    CROSS JOIN LATERAL
        regexp_split_to_table(COALESCE(d.icd9code,''), ',') AS tok(code_token)
    WHERE BTRIM(tok.code_token) <> ''
),
com AS (
    SELECT
        c.patientunitstayid,

        /* Myocardial infarction */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('410','412')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('I21','I22')
              OR SUBSTRING(t.code FROM 1 FOR 4) = 'I252'
            THEN 1 ELSE 0 END
        ) AS myocardial_infarct,

        /* Congestive heart failure */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) = '428'
              OR SUBSTRING(t.code FROM 1 FOR 5) IN
                 ('39891','40201','40211','40291',
                  '40401','40403','40411','40413','40491','40493')
              OR SUBSTRING(t.code FROM 1 FOR 4) BETWEEN '4254' AND '4259'
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('I43','I50')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('I099','I110','I130','I132','I255',
                  'I420','I425','I426','I427','I428','I429','P290')
            THEN 1 ELSE 0 END
        ) AS congestive_heart_failure,

        /* Peripheral vascular disease */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('440','441')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('0930','4373','4471','5571','5579','V434')
              OR SUBSTRING(t.code FROM 1 FOR 4) BETWEEN '4431' AND '4439'
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('I70','I71')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('I731','I738','I739','I771','I790','I792',
                  'K551','K558','K559','Z958','Z959')
            THEN 1 ELSE 0 END
        ) AS peripheral_vascular_disease,

        /* Cerebrovascular disease - computed, excluded from main chronic burden */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) BETWEEN '430' AND '438'
              OR SUBSTRING(t.code FROM 1 FOR 5) = '36234'
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('G45','G46')
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'I60' AND 'I69'
              OR SUBSTRING(t.code FROM 1 FOR 4) = 'H340'
            THEN 1 ELSE 0 END
        ) AS cerebrovascular_disease,

        /* Dementia */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) = '290'
              OR SUBSTRING(t.code FROM 1 FOR 4) IN ('2941','3312')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN
                 ('F00','F01','F02','F03','G30')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN ('F051','G311')
            THEN 1 ELSE 0 END
        ) AS dementia,

        /* Chronic pulmonary disease */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) BETWEEN '490' AND '505'
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('4168','4169','5064','5081','5088')
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'J40' AND 'J47'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'J60' AND 'J67'
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('I278','I279','J684','J701','J703')
            THEN 1 ELSE 0 END
        ) AS chronic_pulmonary_disease,

        /* Rheumatic disease */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) = '725'
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('4465','7100','7101','7102','7103','7104',
                  '7140','7141','7142','7148')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN
                 ('M05','M06','M32','M33','M34')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('M315','M351','M353','M360')
            THEN 1 ELSE 0 END
        ) AS rheumatic_disease,

        /* Peptic ulcer disease */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('531','532','533','534')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('K25','K26','K27','K28')
            THEN 1 ELSE 0 END
        ) AS peptic_ulcer_disease,

        /* Mild liver disease */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('570','571')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('0706','0709','5733','5734','5738','5739','V427')
              OR SUBSTRING(t.code FROM 1 FOR 5) IN
                 ('07022','07023','07032','07033','07044','07054')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('B18','K73','K74')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('K700','K701','K702','K703','K709',
                  'K713','K714','K715','K717',
                  'K760','K762','K763','K764','K768','K769','Z944')
            THEN 1 ELSE 0 END
        ) AS mild_liver_disease,

        /* Diabetes without chronic complication */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('2500','2501','2502','2503','2508','2509')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('E100','E101','E106','E108','E109',
                  'E110','E111','E116','E118','E119',
                  'E120','E121','E126','E128','E129',
                  'E130','E131','E136','E138','E139',
                  'E140','E141','E146','E148','E149')
            THEN 1 ELSE 0 END
        ) AS diabetes_without_cc,

        /* Diabetes with chronic complication */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('2504','2505','2506','2507')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('E102','E103','E104','E105','E107',
                  'E112','E113','E114','E115','E117',
                  'E122','E123','E124','E125','E127',
                  'E132','E133','E134','E135','E137',
                  'E142','E143','E144','E145','E147')
            THEN 1 ELSE 0 END
        ) AS diabetes_with_cc,

        /* Hemiplegia/paraplegia - computed, excluded from main chronic burden */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('342','343')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('3341','3440','3441','3442','3443','3444',
                  '3445','3446','3449')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('G81','G82')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('G041','G114','G801','G802',
                  'G830','G831','G832','G833','G834','G839')
            THEN 1 ELSE 0 END
        ) AS paraplegia,

        /* Renal disease */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('582','585','586','V56')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN ('5880','V420','V451')
              OR SUBSTRING(t.code FROM 1 FOR 4) BETWEEN '5830' AND '5837'
              OR SUBSTRING(t.code FROM 1 FOR 5) IN
                 ('40301','40311','40391',
                  '40402','40403','40412','40413','40492','40493')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('N18','N19')
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('I120','I131',
                  'N032','N033','N034','N035','N036','N037',
                  'N052','N053','N054','N055','N056','N057',
                  'N250','Z490','Z491','Z492','Z940','Z992')
            THEN 1 ELSE 0 END
        ) AS renal_disease,

        /* Any malignancy including lymphoma/leukemia except skin */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) BETWEEN '140' AND '172'
              OR SUBSTRING(t.code FROM 1 FOR 4) BETWEEN '1740' AND '1958'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN '200' AND '208'
              OR SUBSTRING(t.code FROM 1 FOR 4) = '2386'
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('C43','C88')
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'C00' AND 'C26'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'C30' AND 'C34'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'C37' AND 'C41'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'C45' AND 'C58'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'C60' AND 'C76'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'C81' AND 'C85'
              OR SUBSTRING(t.code FROM 1 FOR 3) BETWEEN 'C90' AND 'C97'
            THEN 1 ELSE 0 END
        ) AS malignant_cancer,

        /* Moderate/severe liver disease */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 4) IN ('4560','4561','4562')
              OR SUBSTRING(t.code FROM 1 FOR 4) BETWEEN '5722' AND '5728'
              OR SUBSTRING(t.code FROM 1 FOR 4) IN
                 ('I850','I859','I864','I982',
                  'K704','K711','K721','K729','K765','K766','K767')
            THEN 1 ELSE 0 END
        ) AS severe_liver_disease,

        /* Metastatic solid tumor */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('196','197','198','199')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('C77','C78','C79','C80')
            THEN 1 ELSE 0 END
        ) AS metastatic_solid_tumor,

        /* AIDS/HIV */
        MAX(CASE
            WHEN SUBSTRING(t.code FROM 1 FOR 3) IN ('042','043','044')
              OR SUBSTRING(t.code FROM 1 FOR 3) IN ('B20','B21','B22','B24')
            THEN 1 ELSE 0 END
        ) AS aids

    FROM frailty_work.eicu_25_primary_ais_cohort_v1 c
    LEFT JOIN diag_token t
      ON t.index_patientunitstayid = c.patientunitstayid
    GROUP BY c.patientunitstayid
),
score AS (
    SELECT
        com.*,

        /* Standard comorbidity-only CCI, no age */
        myocardial_infarct
        + congestive_heart_failure
        + peripheral_vascular_disease
        + cerebrovascular_disease
        + dementia
        + chronic_pulmonary_disease
        + rheumatic_disease
        + peptic_ulcer_disease
        + GREATEST(mild_liver_disease, 3 * severe_liver_disease)
        + GREATEST(2 * diabetes_with_cc, diabetes_without_cc)
        + 2 * paraplegia
        + 2 * renal_disease
        + GREATEST(2 * malignant_cancer, 6 * metastatic_solid_tumor)
        + 6 * aids
        AS cci_standard_no_age,

        /* Exclude cerebrovascular only */
        myocardial_infarct
        + congestive_heart_failure
        + peripheral_vascular_disease
        + dementia
        + chronic_pulmonary_disease
        + rheumatic_disease
        + peptic_ulcer_disease
        + GREATEST(mild_liver_disease, 3 * severe_liver_disease)
        + GREATEST(2 * diabetes_with_cc, diabetes_without_cc)
        + 2 * paraplegia
        + 2 * renal_disease
        + GREATEST(2 * malignant_cancer, 6 * metastatic_solid_tumor)
        + 6 * aids
        AS cci_excl_cvd_no_age,

        /* Project main: exclude cerebrovascular AND paralysis */
        myocardial_infarct
        + congestive_heart_failure
        + peripheral_vascular_disease
        + dementia
        + chronic_pulmonary_disease
        + rheumatic_disease
        + peptic_ulcer_disease
        + GREATEST(mild_liver_disease, 3 * severe_liver_disease)
        + GREATEST(2 * diabetes_with_cc, diabetes_without_cc)
        + 2 * renal_disease
        + GREATEST(2 * malignant_cancer, 6 * metastatic_solid_tumor)
        + 6 * aids
        AS cci_chronic_burden_no_age,

        myocardial_infarct
        + congestive_heart_failure
        + peripheral_vascular_disease
        + dementia
        + chronic_pulmonary_disease
        + rheumatic_disease
        + peptic_ulcer_disease
        + mild_liver_disease
        + diabetes_without_cc
        + diabetes_with_cc
        + renal_disease
        + malignant_cancer
        + severe_liver_disease
        + metastatic_solid_tumor
        + aids
        AS charlson_domain_count_non_neuro

    FROM com
)
SELECT
    *,
    CASE WHEN cci_chronic_burden_no_age >= 3 THEN 1 ELSE 0 END
        AS high_comorbidity_ge3
FROM score
;

CREATE UNIQUE INDEX eicu_38_cci_v1_pk
    ON frailty_work.eicu_38_cci_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_38_cci_v1;

SELECT
    COUNT(*) AS n_rows,
    AVG(cci_chronic_burden_no_age) AS mean_cci,
    percentile_cont(0.5)
        WITHIN GROUP (ORDER BY cci_chronic_burden_no_age) AS median_cci,
    COUNT(*) FILTER (WHERE high_comorbidity_ge3=1) AS n_high_ge3
FROM frailty_work.eicu_38_cci_v1;

/* ================================================================
   END 38_DIAGNOSIS_CCI
   ================================================================ */


/* ================================================================
   BEGIN 42_SEVERITY_SUPPORT
   ================================================================ */

/*
=====================================================================
FINAL APACHE SENTINEL PATCH
=====================================================================

Full file-level comparison against the authoritative frozen eICU_48 file
showed that all remaining differences were confined to:

  apache_iva_score
  apache_iva_aps

Every remaining mismatch was:
  rebuilt = -1
  frozen  = NULL

Counts:
  eICU_48: 24 rows
  eICU_49: 20 rows
  eICU_50: 17 rows

Therefore -1 is treated as a missing-value sentinel for these two APACHE IVa
descriptive fields.

This patch applies NULLIF(value, -1) before aggregation.

No cohort, outcome, FI-Lab, CCI, GCS, invasive-ventilation, vasopressor,
or primary-model definition is changed.
=====================================================================
*/

/*
=====================================================================
FIELD-ALIGNMENT PATCH — FINAL
=====================================================================

This script supersedes the prior eICU_42 stage for exact reproduction of
the authoritative frozen analytic files.

File-level comparison after the R4 cohort lock showed that:
- all 2,807 eICU_48 IDs were exact;
- all 105 columns existed in identical order;
- 99/105 columns were already exact;
- only six auxiliary/support fields differed:
    vasopressor_use_firstday      1 row
    imv_day1_fallback           235 rows
    vasopressor_treatment         8 rows
    epinephrine_infusion         44 rows
    apache_iva_score           2481 rows
    apache_iva_aps             2481 rows

Primary eICU_50 model variables were already 100% row-wise identical.

This patch reproduces the historical frozen field definitions:
1. APACHE IVa rows use apacheVersion='IVa' (case-normalized).
2. Historical epinephrine substring matching is retained for exact frozen
   reproduction; this duplicates norepinephrine-positive rows in the
   epinephrine component but does not alter the union vasopressor indicator.
3. Historical imv_day1_fallback equals oOBIntubDay1, including missingness.
4. The primary treatment-derived vasopressor indicator uses only named
   vasopressor agents; the generic parent treatment pathway is not counted.

No cohort, FI-Lab, CCI, GCS, primary IMV, or outcome definition is changed.
=====================================================================
*/

/*
FIX v1.3
--------
eICU local schema stores apacheversion as character varying.
All apacheversion comparisons in this script are now cast to text explicitly
(e.g., BTRIM(apacheversion::text) = '4'), preventing varchar = integer errors.
*/

/*
eICU S4 FINAL - 42
Build the frozen first-day severity/support covariates.

Primary constructs (as reported in S1 Appendix)
------------------------------------------------
GCS:
  APACHE APS eyes + motor + verbal.
  Medication-coded/unscorable observations are excluded.

Invasive ventilation:
  apachePredVar oOBIntubDay1.
  This is the PRIMARY eICU IMV variable.

Vasopressor:
  first-day (-6 h/+24 h) union of infusionDrug and treatment evidence for:
  norepinephrine, epinephrine, dopamine, phenylephrine, vasopressin.

Dobutamine and milrinone are retained only as inotrope sensitivity fields,
not counted in the primary vasopressor indicator.

No outcome fields are used to define these covariates.
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_42_severity_candidates_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_42_severity_candidates_v1 AS
WITH cohort AS (
    SELECT patientunitstayid
    FROM frailty_work.eicu_25_primary_ais_cohort_v1
),

/* APACHE APS: worst GCS components in the APACHE day */
aps AS (
    SELECT DISTINCT ON (a.patientunitstayid)
        a.patientunitstayid,
        a.apacheapsvarid,
        a.intubated AS aps_intubated,
        a.vent AS aps_vent,
        a.meds AS aps_meds,
        a.eyes AS aps_eyes,
        a.motor AS aps_motor,
        a.verbal AS aps_verbal,

        CASE
            WHEN COALESCE(a.meds,0) <> 1
             AND a.eyes BETWEEN 1 AND 4
             AND a.motor BETWEEN 1 AND 6
             AND a.verbal BETWEEN 1 AND 5
            THEN a.eyes + a.motor + a.verbal
            ELSE NULL
        END::integer AS gcs_total

    FROM cohort c
    JOIN eicu_crd.apacheapsvar a
      ON a.patientunitstayid = c.patientunitstayid
    ORDER BY a.patientunitstayid, a.apacheapsvarid
),

/* APACHE day-1 ventilation/intubation variables */
pred AS (
    SELECT DISTINCT ON (p.patientunitstayid)
        p.patientunitstayid,
        p.apachepredvarid,
        p.oobintubday1,
        p.oobventday1,
        p.ventday1
    FROM cohort c
    JOIN eicu_crd.apachepredvar p
      ON p.patientunitstayid = c.patientunitstayid
    ORDER BY p.patientunitstayid, p.apachepredvarid
),

/* Respiratory-care fallback retained for sensitivity/QC only */
resp AS (
    SELECT
        c.patientunitstayid,

        MAX(CASE
            WHEN rc.airwaytype IN ('Oral ETT','Tracheostomy')
             AND (
                  (
                    rc.ventstartoffset IS NOT NULL
                    AND rc.ventstartoffset <= 1440
                    AND (
                         rc.ventendoffset IS NULL
                         OR rc.ventendoffset >= -360
                    )
                  )
                  OR
                  (
                    rc.priorventstartoffset IS NOT NULL
                    AND rc.priorventstartoffset <= 1440
                    AND (
                         rc.priorventendoffset IS NULL
                         OR rc.priorventendoffset >= -360
                    )
                  )
             )
            THEN 1 ELSE 0 END
        )::integer AS rc_invasive_airway_overlap

    FROM cohort c
    LEFT JOIN eicu_crd.respiratorycare rc
      ON rc.patientunitstayid = c.patientunitstayid
    GROUP BY c.patientunitstayid
),

/* Any first-day infusion record: source-availability flag */
inf_any AS (
    SELECT
        c.patientunitstayid,
        CASE WHEN COUNT(i.infusiondrugid) > 0 THEN 1 ELSE 0 END::integer
            AS has_any_infusiondrug_record_firstday
    FROM cohort c
    LEFT JOIN eicu_crd.infusiondrug i
      ON i.patientunitstayid = c.patientunitstayid
     AND i.infusionoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* Drug-specific infusion evidence */
inf AS (
    SELECT
        c.patientunitstayid,

        MAX(CASE
            WHEN (
                 LOWER(i.drugname) LIKE '%norepinephrine%'
                 OR LOWER(i.drugname) LIKE '%levophed%'
            ) THEN 1 ELSE 0 END)::integer AS norepinephrine_infusion,

        MAX(CASE
            WHEN (
                 LOWER(i.drugname) LIKE '%epinephrine%'
                 OR LOWER(i.drugname) LIKE '%adrenaline%'
            ) THEN 1 ELSE 0 END)::integer AS epinephrine_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%dopamine%'
            THEN 1 ELSE 0 END)::integer AS dopamine_infusion,

        MAX(CASE
            WHEN (
                 LOWER(i.drugname) LIKE '%phenylephrine%'
                 OR LOWER(i.drugname) LIKE '%neo-synephrine%'
                 OR LOWER(i.drugname) LIKE '%neosynephrine%'
            ) THEN 1 ELSE 0 END)::integer AS phenylephrine_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%vasopressin%'
            THEN 1 ELSE 0 END)::integer AS vasopressin_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%dobutamine%'
            THEN 1 ELSE 0 END)::integer AS dobutamine_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%milrinone%'
            THEN 1 ELSE 0 END)::integer AS milrinone_infusion

    FROM cohort c
    LEFT JOIN eicu_crd.infusiondrug i
      ON i.patientunitstayid = c.patientunitstayid
     AND i.infusionoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* Any first-day treatment record: source-availability flag */
trt_any AS (
    SELECT
        c.patientunitstayid,
        CASE WHEN COUNT(t.treatmentid) > 0 THEN 1 ELSE 0 END::integer
            AS has_any_treatment_record_firstday
    FROM cohort c
    LEFT JOIN eicu_crd.treatment t
      ON t.patientunitstayid = c.patientunitstayid
     AND t.treatmentoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* Structured treatment pathways */
trt AS (
    SELECT
        c.patientunitstayid,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|norepinephrine%'
            OR LOWER(t.treatmentstring) LIKE '%|inotropic agent|norepinephrine%'
            THEN 1 ELSE 0 END)::integer AS norepinephrine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|epinephrine%'
            OR LOWER(t.treatmentstring) LIKE '%|inotropic agent|epinephrine%'
            THEN 1 ELSE 0 END)::integer AS epinephrine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|dopamine%'
            OR LOWER(t.treatmentstring) LIKE '%|inotropic agent|dopamine%'
            THEN 1 ELSE 0 END)::integer AS dopamine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|phenylephrine%'
            THEN 1 ELSE 0 END)::integer AS phenylephrine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|vasopressin%'
            THEN 1 ELSE 0 END)::integer AS vasopressin_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|inotropic agent|dobutamine%'
            THEN 1 ELSE 0 END)::integer AS dobutamine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|inotropic agent|milrinone%'
            THEN 1 ELSE 0 END)::integer AS milrinone_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors%'
            THEN 1 ELSE 0 END)::integer AS any_vasopressor_treatment_path

    FROM cohort c
    LEFT JOIN eicu_crd.treatment t
      ON t.patientunitstayid = c.patientunitstayid
     AND t.treatmentoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* APACHE IV/IVa descriptive severity scores; not primary covariates */
apr AS (
    SELECT
        c.patientunitstayid,
        MAX(NULLIF(r.apachescore, -1))
            FILTER (WHERE UPPER(BTRIM(r.apacheversion::text)) = 'IVA')
            AS apache_iva_score,
        MAX(NULLIF(r.acutephysiologyscore, -1))
            FILTER (WHERE UPPER(BTRIM(r.apacheversion::text)) = 'IVA')
            AS apache_iva_aps
    FROM cohort c
    LEFT JOIN eicu_crd.apachepatientresult r
      ON r.patientunitstayid = c.patientunitstayid
    GROUP BY c.patientunitstayid
)

SELECT
    c.patientunitstayid,

    a.gcs_total,

    /* Primary eICU IMV construct */
    p.oobintubday1::integer
        AS imv_oobintubday1,

    /* Sensitivity/fallback fields, not primary */
    a.aps_intubated,
    p.oobintubday1::integer AS imv_day1_fallback,

    COALESCE(p.oobventday1, p.ventday1, a.aps_vent)::integer
        AS any_mechanical_assist_day1,

    /* Primary vasopressor source-specific indicators */
    GREATEST(
        COALESCE(i.norepinephrine_infusion,0),
        COALESCE(i.epinephrine_infusion,0),
        COALESCE(i.dopamine_infusion,0),
        COALESCE(i.phenylephrine_infusion,0),
        COALESCE(i.vasopressin_infusion,0)
    )::integer AS vasopressor_infusion,

    GREATEST(
        COALESCE(t.norepinephrine_treatment,0),
        COALESCE(t.epinephrine_treatment,0),
        COALESCE(t.dopamine_treatment,0),
        COALESCE(t.phenylephrine_treatment,0),
        COALESCE(t.vasopressin_treatment,0)
    )::integer AS vasopressor_treatment,

    GREATEST(
        COALESCE(i.norepinephrine_infusion,0),
        COALESCE(i.epinephrine_infusion,0),
        COALESCE(i.dopamine_infusion,0),
        COALESCE(i.phenylephrine_infusion,0),
        COALESCE(i.vasopressin_infusion,0),
        COALESCE(t.norepinephrine_treatment,0),
        COALESCE(t.epinephrine_treatment,0),
        COALESCE(t.dopamine_treatment,0),
        COALESCE(t.phenylephrine_treatment,0),
        COALESCE(t.vasopressin_treatment,0)
    )::integer AS vasopressor_recorded_any,

    COALESCE(i.norepinephrine_infusion,0)::integer
        AS norepinephrine_infusion,
    COALESCE(i.epinephrine_infusion,0)::integer
        AS epinephrine_infusion,
    COALESCE(i.dopamine_infusion,0)::integer
        AS dopamine_infusion,
    COALESCE(i.phenylephrine_infusion,0)::integer
        AS phenylephrine_infusion,
    COALESCE(i.vasopressin_infusion,0)::integer
        AS vasopressin_infusion,

    GREATEST(
        COALESCE(i.dobutamine_infusion,0),
        COALESCE(t.dobutamine_treatment,0)
    )::integer AS dobutamine_any,

    GREATEST(
        COALESCE(i.milrinone_infusion,0),
        COALESCE(t.milrinone_treatment,0)
    )::integer AS milrinone_any,

    GREATEST(
        COALESCE(i.dobutamine_infusion,0),
        COALESCE(t.dobutamine_treatment,0),
        COALESCE(i.milrinone_infusion,0),
        COALESCE(t.milrinone_treatment,0)
    )::integer AS any_inotrope,

    COALESCE(ia.has_any_infusiondrug_record_firstday,0)::integer
        AS has_any_infusiondrug_record_firstday,

    COALESCE(ta.has_any_treatment_record_firstday,0)::integer
        AS has_any_treatment_record_firstday,

    ap.apache_iva_score,
    ap.apache_iva_aps

FROM cohort c
LEFT JOIN aps a
  ON a.patientunitstayid = c.patientunitstayid
LEFT JOIN pred p
  ON p.patientunitstayid = c.patientunitstayid
LEFT JOIN resp r
  ON r.patientunitstayid = c.patientunitstayid
LEFT JOIN inf_any ia
  ON ia.patientunitstayid = c.patientunitstayid
LEFT JOIN inf i
  ON i.patientunitstayid = c.patientunitstayid
LEFT JOIN trt_any ta
  ON ta.patientunitstayid = c.patientunitstayid
LEFT JOIN trt t
  ON t.patientunitstayid = c.patientunitstayid
LEFT JOIN apr ap
  ON ap.patientunitstayid = c.patientunitstayid
;

CREATE UNIQUE INDEX eicu_42_severity_candidates_v1_pk
    ON frailty_work.eicu_42_severity_candidates_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_42_severity_candidates_v1;

SELECT
    COUNT(*) AS n_rows,
    COUNT(gcs_total) AS n_with_gcs,
    COUNT(imv_oobintubday1) AS n_with_primary_imv,
    COUNT(*) FILTER (WHERE imv_oobintubday1=1) AS n_primary_imv,
    COUNT(*) FILTER (WHERE vasopressor_recorded_any=1) AS n_primary_vasopressor
FROM frailty_work.eicu_42_severity_candidates_v1;

/* ================================================================
   END 42_SEVERITY_SUPPORT
   ================================================================ */


/* ================================================================
   BEGIN 44_MULTISOURCE_CCI
   ================================================================ */

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

/* ================================================================
   END 44_MULTISOURCE_CCI
   ================================================================ */


/* ================================================================
   BEGIN 47_FINAL_ANALYSIS_BASE
   ================================================================ */

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

/* ================================================================
   END 47_FINAL_ANALYSIS_BASE
   ================================================================ */


/* ================================================================
   BEGIN 48_49_50_AND_COUNT_QC
   ================================================================ */

/*
=====================================================================
eICU S4 FINAL — 48 / 49 / 50 + FINAL QC

This stage materializes the three canonical analytic datasets from the
already-built eICU_47 tables.

No raw-table scan occurs here.

Canonical expected results:
  eICU_48 analysis base:
    n = 2807
    hospital deaths = 261

  eICU_49 primary FI cohort:
    n = 2091
    hospital deaths = 205

  eICU_50 primary model complete-case:
    n = 2015
    hospital deaths = 197
    invasive ventilation positives = 314
    vasopressor positives = 115
=====================================================================
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;


/* ---------------------------------------------------------------
   48 — all analysis-base patients
   --------------------------------------------------------------- */

DROP TABLE IF EXISTS frailty_work.eicu_48_analysis_base_all;

CREATE UNLOGGED TABLE frailty_work.eicu_48_analysis_base_all AS
SELECT *
FROM frailty_work.eicu_47_analysis_base_v1
;

CREATE UNIQUE INDEX eicu_48_analysis_base_all_pk
ON frailty_work.eicu_48_analysis_base_all(patientunitstayid);

CREATE UNIQUE INDEX eicu_48_analysis_base_all_pid
ON frailty_work.eicu_48_analysis_base_all(uniquepid);

ANALYZE frailty_work.eicu_48_analysis_base_all;


/* ---------------------------------------------------------------
   49 — primary FI-Lab-valid cohort
   --------------------------------------------------------------- */

DROP TABLE IF EXISTS frailty_work.eicu_49_primary_fi_analysis_cohort;

CREATE UNLOGGED TABLE frailty_work.eicu_49_primary_fi_analysis_cohort AS
SELECT *
FROM frailty_work.eicu_47_primary_fi_cohort_v1
;

CREATE UNIQUE INDEX eicu_49_primary_fi_analysis_cohort_pk
ON frailty_work.eicu_49_primary_fi_analysis_cohort(patientunitstayid);

CREATE UNIQUE INDEX eicu_49_primary_fi_analysis_cohort_pid
ON frailty_work.eicu_49_primary_fi_analysis_cohort(uniquepid);

ANALYZE frailty_work.eicu_49_primary_fi_analysis_cohort;


/* ---------------------------------------------------------------
   50 — primary complete-case model cohort
   --------------------------------------------------------------- */

DROP TABLE IF EXISTS frailty_work.eicu_50_primary_model_completecase;

CREATE UNLOGGED TABLE frailty_work.eicu_50_primary_model_completecase AS
SELECT *
FROM frailty_work.eicu_47_primary_model_completecase_v1
;

CREATE UNIQUE INDEX eicu_50_primary_model_completecase_pk
ON frailty_work.eicu_50_primary_model_completecase(patientunitstayid);

CREATE UNIQUE INDEX eicu_50_primary_model_completecase_pid
ON frailty_work.eicu_50_primary_model_completecase(uniquepid);

ANALYZE frailty_work.eicu_50_primary_model_completecase;


/* ---------------------------------------------------------------
   Compact final reproducibility QC
   --------------------------------------------------------------- */

DROP TABLE IF EXISTS frailty_work.eicu_s4_final_qc;

CREATE UNLOGGED TABLE frailty_work.eicu_s4_final_qc AS
WITH observed AS (
    SELECT
        (SELECT COUNT(*)
         FROM frailty_work.eicu_15_main_ais_candidate_v1)::integer
            AS eicu15_candidate_n,

        (SELECT COUNT(*)
         FROM frailty_work.eicu_25_primary_ais_cohort_v1)::integer
            AS eicu25_primary_n,

        (SELECT SUM(
            CASE
              WHEN LOWER(BTRIM(COALESCE(hospitaldischargestatus::text,'')))
                   = 'expired'
              THEN 1 ELSE 0
            END
         )
         FROM frailty_work.eicu_25_primary_ais_cohort_v1)::integer
            AS eicu25_deaths,

        (SELECT COUNT(*)
         FROM frailty_work.eicu_25_primary_ais_cohort_v1
         WHERE unitvisitnumber > 1)::integer
            AS eicu25_unitvisit_gt1,

        (SELECT COUNT(*)
         FROM frailty_work.eicu_48_analysis_base_all)::integer
            AS eicu48_n,

        (SELECT SUM(hospital_mortality)
         FROM frailty_work.eicu_48_analysis_base_all)::integer
            AS eicu48_deaths,

        (SELECT COUNT(*)
         FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
            AS eicu49_n,

        (SELECT SUM(hospital_mortality)
         FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
            AS eicu49_deaths,

        (SELECT COUNT(*)
         FROM frailty_work.eicu_50_primary_model_completecase)::integer
            AS eicu50_n,

        (SELECT SUM(hospital_mortality)
         FROM frailty_work.eicu_50_primary_model_completecase)::integer
            AS eicu50_deaths,

        (SELECT SUM(invasive_ventilation_day1)
         FROM frailty_work.eicu_50_primary_model_completecase)::integer
            AS eicu50_imv_positive,

        (SELECT SUM(vasopressor_use_firstday)
         FROM frailty_work.eicu_50_primary_model_completecase)::integer
            AS eicu50_vasopressor_positive
)
SELECT
    o.*,

    2855::integer AS expected_eicu15_candidate_n,
    2807::integer AS expected_eicu25_primary_n,
    261::integer  AS expected_eicu25_deaths,
    193::integer  AS expected_eicu25_unitvisit_gt1,

    2807::integer AS expected_eicu48_n,
    261::integer  AS expected_eicu48_deaths,

    2091::integer AS expected_eicu49_n,
    205::integer  AS expected_eicu49_deaths,

    2015::integer AS expected_eicu50_n,
    197::integer  AS expected_eicu50_deaths,
    314::integer  AS expected_eicu50_imv_positive,
    115::integer  AS expected_eicu50_vasopressor_positive,

    CASE WHEN
        o.eicu15_candidate_n = 2855
        AND o.eicu25_primary_n = 2807
        AND o.eicu25_deaths = 261
        AND o.eicu25_unitvisit_gt1 = 193
        AND o.eicu48_n = 2807
        AND o.eicu48_deaths = 261
        AND o.eicu49_n = 2091
        AND o.eicu49_deaths = 205
        AND o.eicu50_n = 2015
        AND o.eicu50_deaths = 197
        AND o.eicu50_imv_positive = 314
        AND o.eicu50_vasopressor_positive = 115
    THEN 1 ELSE 0 END::integer AS all_locked_counts_pass

FROM observed o
;

ANALYZE frailty_work.eicu_s4_final_qc;


/* ---------------------------------------------------------------
   Human-readable metric-by-metric QC
   --------------------------------------------------------------- */

DROP TABLE IF EXISTS frailty_work.eicu_s4_final_qc_long;

CREATE UNLOGGED TABLE frailty_work.eicu_s4_final_qc_long AS
SELECT * FROM (
    SELECT 'eICU_15 candidate n'::text AS metric,
           eicu15_candidate_n::integer AS observed,
           2855::integer AS expected
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_25 primary n', eicu25_primary_n, 2807
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_25 hospital deaths', eicu25_deaths, 261
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_25 unitVisitNumber > 1', eicu25_unitvisit_gt1, 193
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_48 n', eicu48_n, 2807
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_48 hospital deaths', eicu48_deaths, 261
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_49 n', eicu49_n, 2091
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_49 hospital deaths', eicu49_deaths, 205
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_50 n', eicu50_n, 2015
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_50 hospital deaths', eicu50_deaths, 197
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_50 invasive ventilation positive',
           eicu50_imv_positive, 314
    FROM frailty_work.eicu_s4_final_qc

    UNION ALL
    SELECT 'eICU_50 vasopressor positive',
           eicu50_vasopressor_positive, 115
    FROM frailty_work.eicu_s4_final_qc
) z
;

ALTER TABLE frailty_work.eicu_s4_final_qc_long
ADD COLUMN pass integer;

UPDATE frailty_work.eicu_s4_final_qc_long
SET pass = CASE WHEN observed = expected THEN 1 ELSE 0 END
;

ANALYZE frailty_work.eicu_s4_final_qc_long;


/* FINAL DISPLAY */
SELECT *
FROM frailty_work.eicu_s4_final_qc
;

SELECT *
FROM frailty_work.eicu_s4_final_qc_long
ORDER BY metric
;

/*
SUCCESS CONDITION:
all_locked_counts_pass = 1

Do not change cohort / FI-Lab / CCI / GCS / IMV / vasopressor definitions
to force a pass. If any count differs, export eicu_s4_final_qc_long and stop.
*/

/* ================================================================
   END 48_49_50_AND_COUNT_QC
   ================================================================ */


/* ================================================================
   BEGIN FIELD_ALIGNMENT_QC
   ================================================================ */

/*
=====================================================================
eICU FROZEN FIELD-ALIGNMENT QC
Run AFTER eICU_42 -> 47 -> 48/49/50 have been rebuilt.
=====================================================================
*/

DROP TABLE IF EXISTS frailty_work.eicu_s4_field_alignment_qc;

CREATE UNLOGGED TABLE frailty_work.eicu_s4_field_alignment_qc AS

SELECT
    /* 48 */
    (SELECT SUM(vasopressor_use_firstday)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_vaso_primary_sum,

    (SELECT COUNT(imv_day1_fallback)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_imv_fallback_nonnull,

    (SELECT SUM(imv_day1_fallback)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_imv_fallback_sum,

    (SELECT SUM(vasopressor_treatment)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_vaso_treatment_sum,

    (SELECT SUM(epinephrine_infusion)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_epinephrine_sum,

    (SELECT COUNT(apache_iva_score)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_apache_score_nonnull,

    (SELECT SUM(apache_iva_score)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_apache_score_sum,

    (SELECT COUNT(apache_iva_aps)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_apache_aps_nonnull,

    (SELECT SUM(apache_iva_aps)
     FROM frailty_work.eicu_48_analysis_base_all)::integer
        AS e48_apache_aps_sum,

    /* 49 */
    (SELECT SUM(vasopressor_use_firstday)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_vaso_primary_sum,

    (SELECT COUNT(imv_day1_fallback)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_imv_fallback_nonnull,

    (SELECT SUM(imv_day1_fallback)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_imv_fallback_sum,

    (SELECT SUM(vasopressor_treatment)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_vaso_treatment_sum,

    (SELECT SUM(epinephrine_infusion)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_epinephrine_sum,

    (SELECT COUNT(apache_iva_score)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_apache_score_nonnull,

    (SELECT SUM(apache_iva_score)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_apache_score_sum,

    (SELECT COUNT(apache_iva_aps)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_apache_aps_nonnull,

    (SELECT SUM(apache_iva_aps)
     FROM frailty_work.eicu_49_primary_fi_analysis_cohort)::integer
        AS e49_apache_aps_sum,

    /* 50 */
    (SELECT SUM(vasopressor_use_firstday)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_vaso_primary_sum,

    (SELECT COUNT(imv_day1_fallback)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_imv_fallback_nonnull,

    (SELECT SUM(imv_day1_fallback)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_imv_fallback_sum,

    (SELECT SUM(vasopressor_treatment)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_vaso_treatment_sum,

    (SELECT SUM(epinephrine_infusion)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_epinephrine_sum,

    (SELECT COUNT(apache_iva_score)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_apache_score_nonnull,

    (SELECT SUM(apache_iva_score)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_apache_score_sum,

    (SELECT COUNT(apache_iva_aps)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_apache_aps_nonnull,

    (SELECT SUM(apache_iva_aps)
     FROM frailty_work.eicu_50_primary_model_completecase)::integer
        AS e50_apache_aps_sum
;

ALTER TABLE frailty_work.eicu_s4_field_alignment_qc
ADD COLUMN all_field_proxy_checks_pass integer;

UPDATE frailty_work.eicu_s4_field_alignment_qc
SET all_field_proxy_checks_pass =
CASE WHEN
       e48_vaso_primary_sum = 149
   AND e48_imv_fallback_nonnull = 2752
   AND e48_imv_fallback_sum = 408
   AND e48_vaso_treatment_sum = 82
   AND e48_epinephrine_sum = 44
   AND e48_apache_score_nonnull = 2481
   AND e48_apache_score_sum = 123230
   AND e48_apache_aps_nonnull = 2481
   AND e48_apache_aps_sum = 89110

   AND e49_vaso_primary_sum = 118
   AND e49_imv_fallback_nonnull = 2060
   AND e49_imv_fallback_sum = 328
   AND e49_vaso_treatment_sum = 62
   AND e49_epinephrine_sum = 40
   AND e49_apache_score_nonnull = 1854
   AND e49_apache_score_sum = 93952
   AND e49_apache_aps_nonnull = 1854
   AND e49_apache_aps_sum = 68092

   AND e50_vaso_primary_sum = 115
   AND e50_imv_fallback_nonnull = 2015
   AND e50_imv_fallback_sum = 314
   AND e50_vaso_treatment_sum = 60
   AND e50_epinephrine_sum = 38
   AND e50_apache_score_nonnull = 1842
   AND e50_apache_score_sum = 93320
   AND e50_apache_aps_nonnull = 1842
   AND e50_apache_aps_sum = 67679
THEN 1 ELSE 0 END
;

ANALYZE frailty_work.eicu_s4_field_alignment_qc;

SELECT *
FROM frailty_work.eicu_s4_field_alignment_qc;

/* ================================================================
   END FIELD_ALIGNMENT_QC
   ================================================================ */
