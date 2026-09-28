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
