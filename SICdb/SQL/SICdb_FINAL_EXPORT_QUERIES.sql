/* SICdb final UI-export queries. Run each SELECT and export the result grid in Navicat. */

/* Save result grid as: sicdb_43_analysis_base_all.csv */
SELECT *
FROM frailty_work.sicdb_42_analysis_base_all_v1
ORDER BY "CaseID";

/* Save result grid as: sicdb_44_primary_FI_analysis_cohort.csv */
SELECT *
FROM frailty_work.sicdb_42_primary_fi_cohort_v1
ORDER BY "CaseID";

/* Save result grid as: sicdb_45_available_covariate_completecase.csv */
SELECT *
FROM frailty_work.sicdb_42_available_covariate_completecase_v1
ORDER BY "CaseID";

/* Save result grid as: sicdb_46_transportability_qc.csv */
WITH a AS (
        SELECT *
        FROM frailty_work.sicdb_42_analysis_base_all_v1
    ),
    f AS (
        SELECT *
        FROM frailty_work.sicdb_42_primary_fi_cohort_v1
    ),
    metrics AS (
        SELECT 'Q01_all_n' AS metric,
               COUNT(*)::numeric AS value FROM a

        UNION ALL
        SELECT 'Q02_hospital_deaths_all',
               SUM(hospital_mortality)::numeric FROM a

        UNION ALL
        SELECT 'Q03_hospital_mortality_pct_all',
               100.0*AVG(hospital_mortality)::numeric FROM a

        UNION ALL
        SELECT 'Q04_valid_FI_n',
               COUNT(filab18)::numeric FROM a

        UNION ALL
        SELECT 'Q05_valid_FI_pct',
               100.0*COUNT(filab18)/NULLIF(COUNT(*),0) FROM a

        UNION ALL
        SELECT 'Q06_deaths_valid_FI',
               SUM(hospital_mortality)::numeric FROM f

        UNION ALL
        SELECT 'Q07_mortality_pct_valid_FI',
               100.0*AVG(hospital_mortality)::numeric FROM f

        UNION ALL
        SELECT 'Q08_mean_FI_valid',
               AVG(filab18)::numeric FROM f

        UNION ALL
        SELECT 'Q09_median_FI_valid',
               percentile_cont(0.5)
               WITHIN GROUP (ORDER BY filab18)::numeric FROM f

        UNION ALL
        SELECT 'Q10_mean_available_charlson_domain_count3',
               AVG(available_charlson_domain_count3)::numeric FROM a

        UNION ALL
        SELECT 'Q11_count3_ge1_n',
               COUNT(*) FILTER (
                   WHERE available_charlson_domain_count3>=1
               )::numeric FROM a

        UNION ALL
        SELECT 'Q12_mean_available_precondition_count4',
               AVG(available_precondition_count4)::numeric FROM a

        UNION ALL
        SELECT 'Q13_diabetes_n',
               SUM(precondition_diabetes)::numeric FROM a

        UNION ALL
        SELECT 'Q14_hypertension_n',
               SUM(precondition_hypertension)::numeric FROM a

        UNION ALL
        SELECT 'Q15_lung_disease_n',
               SUM(precondition_lung_disease)::numeric FROM a

        UNION ALL
        SELECT 'Q16_renal_dysfunction_n',
               SUM(precondition_renal_dysfunction)::numeric FROM a

        UNION ALL
        SELECT 'Q17_invasive_airway_firstday_n',
               SUM(invasive_airway_firstday)::numeric FROM a

        UNION ALL
        SELECT 'Q18_any_respirator_setting_firstday_n',
               SUM(any_respirator_setting_firstday)::numeric FROM a

        UNION ALL
        SELECT 'Q19_vasopressor_firstday_n',
               SUM(vasopressor_firstday)::numeric FROM a

        UNION ALL
        SELECT 'Q20_norepinephrine_firstday_n',
               SUM(norepinephrine_firstday)::numeric FROM a

        UNION ALL
        SELECT 'Q21_phenylephrine_firstday_n',
               SUM(phenylephrine_firstday)::numeric FROM a

        UNION ALL
        SELECT 'Q22_vasopressor_nonsingledose_firstday_n',
               SUM(vasopressor_nonsingledose_firstday)::numeric FROM a

        UNION ALL
        SELECT 'Q23_dobutamine_firstday_n',
               SUM(dobutamine_firstday)::numeric FROM a

        UNION ALL
        SELECT 'Q24_mean_saps3',
               AVG(saps3)::numeric FROM a

        UNION ALL
        SELECT 'Q25_saps3_missing_n',
               COUNT(*) FILTER (WHERE saps3 IS NULL)::numeric FROM a

        UNION ALL
        SELECT 'Q26_available_completecase_n',
               COUNT(*)::numeric
        FROM frailty_work.sicdb_42_available_covariate_completecase_v1

        UNION ALL
        SELECT 'Q27_FI_missing_deaths',
               SUM(hospital_mortality)::numeric
        FROM a
        WHERE filab18 IS NULL

        UNION ALL
        SELECT 'Q28_FI_missing_n',
               COUNT(*)::numeric
        FROM a
        WHERE filab18 IS NULL
    )
    SELECT metric,value
    FROM metrics
    ORDER BY metric;

/* Save result grid as: sicdb_47_dictionary_final_audit.csv */
WITH refs AS (
        SELECT
            CASE
                WHEN CONCAT_WS(
                    ' ',
                    "ReferenceValue",
                    "ReferenceName",
                    "ReferenceDescription"
                ) ~* '(glasgow|gcs|coma|vigil|bewusst|conscious|rass|ramsay|sedat|neurolog|pupil|eye.?open|verbal.?response|motor.?response)'
                THEN 'NEURO_GCS_SEDATION'

                WHEN CONCAT_WS(
                    ' ',
                    "ReferenceValue",
                    "ReferenceName",
                    "ReferenceDescription"
                ) ~* '(precondition|chronic|comorbid|history|anamnes)'
                THEN 'CHRONIC_HISTORY'

                WHEN CONCAT_WS(
                    ' ',
                    "ReferenceValue",
                    "ReferenceName",
                    "ReferenceDescription"
                ) ~* '(norepine|noradren|phenyleph|epineph|adrenalin|dopamin|vasopressin|dobutamin|milrinon)'
                THEN 'VASO_INOTROPE'

                ELSE NULL
            END AS audit_group,

            "ReferenceGlobalID" AS reference_id,
            "ReferenceValue",
            "ReferenceName",
            "ReferenceDescription",
            "ReferenceUnit"

        FROM public.d_references
    )
    SELECT *
    FROM refs
    WHERE audit_group IS NOT NULL
    ORDER BY
        audit_group,
        "ReferenceName",
        "ReferenceValue",
        reference_id;

/* Save result grid as: SICdb_S4_FINAL_QC.csv */
SELECT *
FROM frailty_work.sicdb_s4_final_qc;
