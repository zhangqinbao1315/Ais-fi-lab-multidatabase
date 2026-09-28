/*
SICdb - 42
Build final case-level transportability analysis base.

Important:
- available_charlson_domain_count3 is a partial chronic-domain proxy, NOT CCI.
- raw GCS unavailable at this stage.
- saps3 is exported as a severity sensitivity variable.
*/

DROP TABLE IF EXISTS frailty_work.sicdb_42_analysis_base_all_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_42_analysis_base_all_v1 AS
SELECT
    c."CaseID",
    c."PatientID",
    c."AdmissionYear",
    c."AgeOnAdmission" AS age,
    CASE
        WHEN c."Sex"=736 THEN 1
        WHEN c."Sex"=735 THEN 0
        ELSE NULL
    END AS female,

    c."saps3",
    c."ICUOffset",
    c."TimeOfStay",
    c."HospitalStayDays",
    c."ICD10Main",
    c."ICD10MainText",

    CASE
        WHEN c."HospitalDischargeType"=3130 THEN 1
        WHEN c."HospitalDischargeType" IN (3129,3131) THEN 0
        ELSE NULL
    END AS hospital_mortality,

    cp.precondition_diabetes,
    cp.precondition_hypertension,
    cp.precondition_lung_disease,
    cp.precondition_renal_dysfunction,
    cp.available_charlson_domain_count3,
    cp.available_precondition_count4,

    fs.invasive_airway_firstday,
    fs.any_respirator_setting_firstday,
    fs.vasopressor_firstday,
    fs.norepinephrine_firstday,
    fs.phenylephrine_firstday,
    fs.vasopressor_nonsingledose_firstday,
    fs.dobutamine_firstday,

    fi.n_measured AS filab18_n_measured,
    fi.n_evaluable AS filab18_n_evaluable,
    fi.n_deficits AS filab18_n_deficits,
    fi.filab18,
    fi.filab18_per_0_1,

    sens.n_measured AS filab18_fallback_n_measured,
    sens.filab18 AS filab18_fallback,
    sens.filab18_per_0_1 AS filab18_fallback_per_0_1,

    fi.wbc,
    fi.hemoglobin,
    fi.hematocrit,
    fi.platelet,
    fi.rbc,
    fi.mcv,
    fi.sodium,
    fi.potassium,
    fi.chloride,
    fi.bicarbonate,
    fi.bun,
    fi.creatinine,
    fi.glucose,
    fi.calcium,
    fi.magnesium,
    fi.phosphate,
    fi.inr,
    fi.aptt

FROM frailty_work.sicdb_20_primary_ais_cohort_v1 c

LEFT JOIN frailty_work.sicdb_40_chronic_proxy_v1 cp
  ON cp."CaseID"=c."CaseID"

LEFT JOIN frailty_work.sicdb_41_firstday_support_v1 fs
  ON fs."CaseID"=c."CaseID"

LEFT JOIN frailty_work.sicdb_30_filab18_variants_v1 fi
  ON fi."CaseID"=c."CaseID"
 AND fi.mapping_variant='preferred_strict'

LEFT JOIN frailty_work.sicdb_30_filab18_variants_v1 sens
  ON sens."CaseID"=c."CaseID"
 AND sens.mapping_variant='central_plus_BGA_fallback'
;

CREATE UNIQUE INDEX sicdb_42_analysis_base_all_v1_pk
    ON frailty_work.sicdb_42_analysis_base_all_v1 ("CaseID");

ANALYZE frailty_work.sicdb_42_analysis_base_all_v1;


/* Primary valid-FI cohort */
DROP TABLE IF EXISTS frailty_work.sicdb_42_primary_fi_cohort_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_42_primary_fi_cohort_v1 AS
SELECT *
FROM frailty_work.sicdb_42_analysis_base_all_v1
WHERE filab18 IS NOT NULL
;

CREATE UNIQUE INDEX sicdb_42_primary_fi_cohort_v1_pk
    ON frailty_work.sicdb_42_primary_fi_cohort_v1 ("CaseID");


/* Complete for variables that are actually available in SICdb */
DROP TABLE IF EXISTS frailty_work.sicdb_42_available_covariate_completecase_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_42_available_covariate_completecase_v1 AS
SELECT *
FROM frailty_work.sicdb_42_primary_fi_cohort_v1
WHERE hospital_mortality IS NOT NULL
  AND age IS NOT NULL
  AND female IS NOT NULL
  AND available_charlson_domain_count3 IS NOT NULL
  AND saps3 IS NOT NULL
  AND invasive_airway_firstday IS NOT NULL
  AND vasopressor_firstday IS NOT NULL
;

CREATE UNIQUE INDEX sicdb_42_available_covariate_completecase_v1_pk
    ON frailty_work.sicdb_42_available_covariate_completecase_v1 ("CaseID");

ANALYZE frailty_work.sicdb_42_primary_fi_cohort_v1;
ANALYZE frailty_work.sicdb_42_available_covariate_completecase_v1;
