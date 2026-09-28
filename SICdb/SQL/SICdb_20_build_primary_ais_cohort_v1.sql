CREATE SCHEMA IF NOT EXISTS frailty_work;

/*
SICdb - 20
Build the primary acute ischemic stroke cohort.

Operational definition used for the frozen analysis:
- age >=18 years;
- principal ICD10Main begins with I63;
- among qualifying admissions for each PatientID, retain the earliest
  OffsetAfterFirstAdmission;
- CaseID is the deterministic tie-breaker.

This exact rule was independently reconstructed from raw SICdb v1.0.8
and matched the frozen historical SICdb_20 table row-for-row (33/33).
*/

DROP TABLE IF EXISTS frailty_work.sicdb_20_primary_ais_cohort_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_20_primary_ais_cohort_v1 AS
WITH qualifying AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c."PatientID"
            ORDER BY
                c."OffsetAfterFirstAdmission" ASC NULLS LAST,
                c."CaseID" ASC
        ) AS rn_qualifying_ais
    FROM public.cases c
    WHERE c."AgeOnAdmission" >= 18
      AND UPPER(BTRIM(c."ICD10Main")) LIKE 'I63%'
)
SELECT *
FROM qualifying
WHERE rn_qualifying_ais = 1
;

CREATE UNIQUE INDEX sicdb_20_primary_ais_cohort_v1_pk
    ON frailty_work.sicdb_20_primary_ais_cohort_v1 ("CaseID");

ANALYZE frailty_work.sicdb_20_primary_ais_cohort_v1;
