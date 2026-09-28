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
