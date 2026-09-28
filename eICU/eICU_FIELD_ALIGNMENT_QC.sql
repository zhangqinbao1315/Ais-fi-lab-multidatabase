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
