/*
SICdb - 48
Locked aggregate QC for the authoritative raw-to-analytic pipeline.

This QC does not require frozen patient-level files.
It verifies the aggregate checkpoints used in the manuscript/supporting files.
*/

DROP TABLE IF EXISTS frailty_work.sicdb_s4_final_qc;

CREATE UNLOGGED TABLE frailty_work.sicdb_s4_final_qc AS
SELECT
    (SELECT COUNT(*)
     FROM frailty_work.sicdb_20_primary_ais_cohort_v1)
        AS cohort_n,

    (SELECT COUNT(*)
     FROM frailty_work.sicdb_30_filab18_variants_v1)
        AS filab_variant_rows,

    (SELECT COUNT(*)
     FROM frailty_work.sicdb_42_analysis_base_all_v1
     WHERE hospital_mortality=1)
        AS cohort_hospital_deaths,

    (SELECT COUNT(*)
     FROM frailty_work.sicdb_42_primary_fi_cohort_v1)
        AS primary_fi_n,

    (SELECT COUNT(*)
     FROM frailty_work.sicdb_42_primary_fi_cohort_v1
     WHERE hospital_mortality=1)
        AS primary_fi_hospital_deaths,

    (SELECT COUNT(*)
     FROM frailty_work.sicdb_42_available_covariate_completecase_v1)
        AS available_completecase_n,

    33::bigint AS expected_cohort_n,
    66::bigint AS expected_filab_variant_rows,
    9::bigint  AS expected_cohort_hospital_deaths,
    30::bigint AS expected_primary_fi_n,
    8::bigint  AS expected_primary_fi_hospital_deaths,
    30::bigint AS expected_available_completecase_n,

    CASE
        WHEN
            (SELECT COUNT(*) FROM frailty_work.sicdb_20_primary_ais_cohort_v1)=33
        AND
            (SELECT COUNT(*) FROM frailty_work.sicdb_30_filab18_variants_v1)=66
        AND
            (SELECT COUNT(*)
             FROM frailty_work.sicdb_42_analysis_base_all_v1
             WHERE hospital_mortality=1)=9
        AND
            (SELECT COUNT(*) FROM frailty_work.sicdb_42_primary_fi_cohort_v1)=30
        AND
            (SELECT COUNT(*)
             FROM frailty_work.sicdb_42_primary_fi_cohort_v1
             WHERE hospital_mortality=1)=8
        AND
            (SELECT COUNT(*)
             FROM frailty_work.sicdb_42_available_covariate_completecase_v1)=30
        THEN 1 ELSE 0
    END AS all_locked_counts_pass
;

ANALYZE frailty_work.sicdb_s4_final_qc;


/* Final one-click result grid */
SELECT *
FROM frailty_work.sicdb_s4_final_qc;
