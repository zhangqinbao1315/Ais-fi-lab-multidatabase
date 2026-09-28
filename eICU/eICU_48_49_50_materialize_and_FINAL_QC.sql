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
