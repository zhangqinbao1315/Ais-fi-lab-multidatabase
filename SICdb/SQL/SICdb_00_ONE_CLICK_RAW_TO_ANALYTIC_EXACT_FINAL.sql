/*
=====================================================================
S4 SICdb RAW -> ANALYTIC — AUTHORITATIVE EXACT FINAL
=====================================================================

This file supersedes earlier SICdb reconstruction/discovery/patch scripts.

Pipeline:
  public.cases
      -> SICdb_20 primary AIS cohort
  public.laboratory
      -> SICdb_30 Core-18 FI-Lab variants
  public.data_ref
      -> SICdb_40 partial chronic-condition proxy
  public.data_range / data_float_h / medication
      -> SICdb_41 first-day support variables
      -> SICdb_42 final transportability analysis bases
      -> SICdb_48 locked aggregate QC

Primary frozen checkpoints:
  all cohort n=33, hospital deaths=9
  FI-valid n=30, hospital deaths=8
  available-covariate complete-case n=30

Independent local exact-validation against preserved historical frozen tables:
  SICdb_20: 33/33 exact, 0 row mismatches
  SICdb_30: 66/66 exact, 0 row mismatches
  SICdb_40: 33/33 exact, 0 row mismatches
  SICdb_41: 33/33 exact, 0 row mismatches
  SICdb_42 all: 33/33 exact, 0 row mismatches
  SICdb_42 FI-valid: 30/30 exact, 0 row mismatches
  SICdb_42 complete-case: 30/30 exact, 0 row mismatches

Important interpretation:
- available_charlson_domain_count3 is a partial chronic-domain proxy,
  NOT a harmonized Charlson Comorbidity Index.
- raw reconstructable GCS is unavailable in this SICdb workflow.
- SICdb is used for exploratory FI-Lab transportability, not full third-database
  replication of the complete MIMIC/eICU multivariable model.

The final statement returns only SICdb_48 locked QC.
=====================================================================
*/

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

/*
SICdb - 30
Build the two Core-18 FI-Lab mapping variants used in the frozen analysis.

Primary variant:
  preferred_strict

Sensitivity variant:
  central_plus_BGA_fallback

Time window:
  earliest numeric laboratory value from ICUOffset -6 h through ICUOffset +24 h,
  inclusive; ties are resolved by raw laboratory row id.

Recovered exact LaboratoryID mapping:
  WBC          301
  Hemoglobin   289      fallback 658
  Hematocrit   217      fallback 682
  Platelet     314
  RBC          599
  MCV          286
  Sodium       469
  Potassium    463      fallback 685
  Chloride     450      fallback 683
  Bicarbonate  666
  Urea/BUN     355
  Creatinine   367
  Glucose      348      fallback 656
  Calcium      457
  Magnesium    468
  Phosphate    471
  INR         3128
  aPTT         597

Unit harmonization used in the frozen extraction:
  BUN       = urea * 0.467
  Calcium   = mmol/L * 4.0078
  Magnesium = mmol/L * 2.4305
  Phosphate = mmol/L * 3.0969

The fallback variant uses BGA only when the preferred central value is
missing, and only for Hb/Hct/K/Cl/glucose. Sodium BGA is not used.

FI-Lab:
  abnormal=1; normal=0; missing excluded from denominator;
  score computed only with >=15 evaluable Core-18 items.

For exact frozen numeric reproduction, filab18_per_0_1 is calculated as:
  (n_deficits * 10.0) / n_evaluable

The raw reconstruction matched the preserved frozen SICdb_30 table exactly:
66/66 rows, zero full-row mismatches.
*/

DROP TABLE IF EXISTS frailty_work.sicdb_30_filab18_variants_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_30_filab18_variants_v1 AS
WITH cohort AS (
    SELECT
        "CaseID",
        "PatientID",
        "Sex",
        "AgeOnAdmission",
        "saps3",
        "HospitalDischargeType",
        "DischargeState",
        "ICUOffset"
    FROM frailty_work.sicdb_20_primary_ais_cohort_v1
),
raw_window AS (
    SELECT
        c."CaseID",
        l."id" AS raw_row_id,
        l."LaboratoryID",
        l."Offset",
        l."LaboratoryValue",
        ROW_NUMBER() OVER (
            PARTITION BY c."CaseID", l."LaboratoryID"
            ORDER BY l."Offset" ASC, l."id" ASC
        ) AS rn
    FROM cohort c
    INNER JOIN public.laboratory l
      ON l."CaseID"=c."CaseID"
     AND l."LaboratoryID" IN (
          217,286,289,301,314,348,355,367,450,457,463,468,469,471,597,599,
          656,658,666,682,683,685,3128
     )
     AND l."LaboratoryValue" IS NOT NULL
     AND l."Offset" >= c."ICUOffset" - 21600
     AND l."Offset" <= c."ICUOffset" + 86400
),
first_value AS (
    SELECT
        "CaseID",
        "LaboratoryID",
        "LaboratoryValue"
    FROM raw_window
    WHERE rn=1
),
wide AS (
    SELECT
        c."CaseID",
        c."PatientID",
        c."Sex",
        c."AgeOnAdmission",
        c."saps3",
        c."HospitalDischargeType",
        c."DischargeState",

        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=301) AS wbc_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=289) AS hemoglobin_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=217) AS hematocrit_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=314) AS platelet_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=599) AS rbc_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=286) AS mcv_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=469) AS sodium_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=463) AS potassium_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=450) AS chloride_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=666) AS bicarbonate_bga,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=355) AS urea_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=367) AS creatinine_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=348) AS glucose_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=457) AS calcium_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=468) AS magnesium_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=471) AS phosphate_zl,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=3128) AS inr_raw,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=597) AS aptt_zl,

        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=658) AS hemoglobin_bga,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=682) AS hematocrit_bga,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=685) AS potassium_bga,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=683) AS chloride_bga,
        MAX(f."LaboratoryValue") FILTER (WHERE f."LaboratoryID"=656) AS glucose_bga

    FROM cohort c
    LEFT JOIN first_value f
      ON f."CaseID"=c."CaseID"
    GROUP BY
        c."CaseID",
        c."PatientID",
        c."Sex",
        c."AgeOnAdmission",
        c."saps3",
        c."HospitalDischargeType",
        c."DischargeState"
),
variants AS (
    SELECT
        'preferred_strict'::text AS mapping_variant,
        w."CaseID",
        w."PatientID",
        w."Sex",
        w."AgeOnAdmission",
        w."saps3",
        w."HospitalDischargeType",
        w."DischargeState",

        w.wbc_zl AS wbc,
        w.hemoglobin_zl AS hemoglobin,
        w.hematocrit_zl AS hematocrit,
        w.platelet_zl AS platelet,
        w.rbc_zl AS rbc,
        w.mcv_zl AS mcv,
        w.sodium_zl AS sodium,
        w.potassium_zl AS potassium,
        w.chloride_zl AS chloride,
        w.bicarbonate_bga AS bicarbonate,
        w.urea_zl * 0.467::double precision AS bun,
        w.creatinine_zl AS creatinine,
        w.glucose_zl AS glucose,
        w.calcium_zl * 4.0078::double precision AS calcium,
        w.magnesium_zl * 2.4305::double precision AS magnesium,
        w.phosphate_zl * 3.0969::double precision AS phosphate,
        w.inr_raw AS inr,
        w.aptt_zl AS aptt
    FROM wide w

    UNION ALL

    SELECT
        'central_plus_BGA_fallback'::text AS mapping_variant,
        w."CaseID",
        w."PatientID",
        w."Sex",
        w."AgeOnAdmission",
        w."saps3",
        w."HospitalDischargeType",
        w."DischargeState",

        w.wbc_zl AS wbc,
        COALESCE(w.hemoglobin_zl,w.hemoglobin_bga) AS hemoglobin,
        COALESCE(w.hematocrit_zl,w.hematocrit_bga) AS hematocrit,
        w.platelet_zl AS platelet,
        w.rbc_zl AS rbc,
        w.mcv_zl AS mcv,
        w.sodium_zl AS sodium,
        COALESCE(w.potassium_zl,w.potassium_bga) AS potassium,
        COALESCE(w.chloride_zl,w.chloride_bga) AS chloride,
        w.bicarbonate_bga AS bicarbonate,
        w.urea_zl * 0.467::double precision AS bun,
        w.creatinine_zl AS creatinine,
        COALESCE(w.glucose_zl,w.glucose_bga) AS glucose,
        w.calcium_zl * 4.0078::double precision AS calcium,
        w.magnesium_zl * 2.4305::double precision AS magnesium,
        w.phosphate_zl * 3.0969::double precision AS phosphate,
        w.inr_raw AS inr,
        w.aptt_zl AS aptt
    FROM wide w
),
deficits AS (
    SELECT
        v.*,

        CASE WHEN wbc IS NULL THEN NULL
             WHEN wbc < 4.0 OR wbc > 10.0 THEN 1 ELSE 0 END AS d_wbc,

        CASE WHEN hemoglobin IS NULL THEN NULL
             WHEN "Sex"=736 AND (hemoglobin < 11.2 OR hemoglobin > 15.7) THEN 1
             WHEN "Sex"=736 THEN 0
             WHEN "Sex"=735 AND (hemoglobin < 13.7 OR hemoglobin > 17.5) THEN 1
             WHEN "Sex"=735 THEN 0
             ELSE NULL END AS d_hemoglobin,

        CASE WHEN hematocrit IS NULL THEN NULL
             WHEN "Sex"=736 AND (hematocrit < 34 OR hematocrit > 45) THEN 1
             WHEN "Sex"=736 THEN 0
             WHEN "Sex"=735 AND (hematocrit < 40 OR hematocrit > 51) THEN 1
             WHEN "Sex"=735 THEN 0
             ELSE NULL END AS d_hematocrit,

        CASE WHEN platelet IS NULL THEN NULL
             WHEN platelet < 150 OR platelet > 400 THEN 1 ELSE 0 END AS d_platelet,

        CASE WHEN rbc IS NULL THEN NULL
             WHEN "Sex"=736 AND (rbc < 3.9 OR rbc > 5.2) THEN 1
             WHEN "Sex"=736 THEN 0
             WHEN "Sex"=735 AND (rbc < 4.6 OR rbc > 6.1) THEN 1
             WHEN "Sex"=735 THEN 0
             ELSE NULL END AS d_rbc,

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

        CASE WHEN creatinine IS NULL THEN NULL
             WHEN "Sex"=736 AND (creatinine < 0.4 OR creatinine > 1.1) THEN 1
             WHEN "Sex"=736 THEN 0
             WHEN "Sex"=735 AND (creatinine < 0.5 OR creatinine > 1.2) THEN 1
             WHEN "Sex"=735 THEN 0
             ELSE NULL END AS d_creatinine,

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

    FROM variants v
),
counts AS (
    SELECT
        d.*,

        (
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
          (aptt IS NOT NULL)::int
        ) AS n_measured,

        (
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
          (d_aptt IS NOT NULL)::int
        ) AS n_evaluable,

        (
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
          COALESCE(d_aptt,0)
        ) AS n_deficits

    FROM deficits d
)
SELECT
    mapping_variant,
    "CaseID",
    "PatientID",
    "Sex",
    "AgeOnAdmission",
    "saps3",
    "HospitalDischargeType",
    "DischargeState",

    wbc,
    hemoglobin,
    hematocrit,
    platelet,
    rbc,
    mcv,
    sodium,
    potassium,
    chloride,
    bicarbonate,
    bun,
    creatinine,
    glucose,
    calcium,
    magnesium,
    phosphate,
    inr,
    aptt,

    d_wbc,
    d_hemoglobin,
    d_hematocrit,
    d_platelet,
    d_rbc,
    d_mcv,
    d_sodium,
    d_potassium,
    d_chloride,
    d_bicarbonate,
    d_bun,
    d_creatinine,
    d_glucose,
    d_calcium,
    d_magnesium,
    d_phosphate,
    d_inr,
    d_aptt,

    n_measured,
    n_evaluable,
    n_deficits,

    CASE
        WHEN n_evaluable >= 15
        THEN n_deficits::double precision / n_evaluable::double precision
        ELSE NULL
    END AS filab18,

    CASE
        WHEN n_evaluable >= 15
        THEN (n_deficits::double precision * 10.0) / n_evaluable::double precision
        ELSE NULL
    END AS filab18_per_0_1

FROM counts
;

CREATE UNIQUE INDEX sicdb_30_filab18_variants_v1_pk
    ON frailty_work.sicdb_30_filab18_variants_v1
       (mapping_variant, "CaseID");

ANALYZE frailty_work.sicdb_30_filab18_variants_v1;

/*
SICdb - 40
Build available chronic-condition indicators.

These are NOT a Charlson index.

data_ref IDs from the local audited dictionary:
  FieldID 3097 PreconditionDiabetes
  FieldID 3098 PreconditionArtHypertension
  FieldID 3103 PreconditionLungDisease
  FieldID 3104 PreconditionRenalDysfunction

RefID:
  738 = No
  740 = Yes
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.sicdb_40_chronic_proxy_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_40_chronic_proxy_v1 AS
WITH p AS (
    SELECT
        c."CaseID",

        MAX(
            CASE
                WHEN dr."FieldID"=3097 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3097 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_diabetes,

        MAX(
            CASE
                WHEN dr."FieldID"=3098 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3098 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_hypertension,

        MAX(
            CASE
                WHEN dr."FieldID"=3103 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3103 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_lung_disease,

        MAX(
            CASE
                WHEN dr."FieldID"=3104 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3104 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_renal_dysfunction

    FROM frailty_work.sicdb_20_primary_ais_cohort_v1 c
    LEFT JOIN public.data_ref dr
      ON dr."CaseID"=c."CaseID"
     AND dr."FieldID" IN (3097,3098,3103,3104)

    GROUP BY c."CaseID"
)
SELECT
    *,

    CASE
        WHEN precondition_diabetes IS NOT NULL
         AND precondition_lung_disease IS NOT NULL
         AND precondition_renal_dysfunction IS NOT NULL
        THEN
            precondition_diabetes +
            precondition_lung_disease +
            precondition_renal_dysfunction
        ELSE NULL
    END AS available_charlson_domain_count3,

    CASE
        WHEN precondition_diabetes IS NOT NULL
         AND precondition_hypertension IS NOT NULL
         AND precondition_lung_disease IS NOT NULL
         AND precondition_renal_dysfunction IS NOT NULL
        THEN
            precondition_diabetes +
            precondition_hypertension +
            precondition_lung_disease +
            precondition_renal_dysfunction
        ELSE NULL
    END AS available_precondition_count4

FROM p
;

CREATE UNIQUE INDEX sicdb_40_chronic_proxy_v1_pk
    ON frailty_work.sicdb_40_chronic_proxy_v1 ("CaseID");

ANALYZE frailty_work.sicdb_40_chronic_proxy_v1;

/*
SICdb - 41
Build first-day invasive-airway, respiratory-support and vasopressor variables.

Window:
  actual ICU admission -6 h to +24 h

Primary IMV proxy:
  data_range DataID 720 = EndotrachealTube, overlapping the window.

Broader respiratory-support sensitivity:
  any RespiratorSetting data_float_h record in the window using observed IDs:
  2278 PEEP
  2282 RespRate
  2283 FIO2
  2284 PressureSupport
  2285 IERatio
  3040 PressureOverPeep

Primary vasopressor:
  medication DrugID 1562 norepinephrine
  medication DrugID 1593 phenylephrine
  any overlap with the same -6/+24 h window.
  Single-dose rows are not excluded, matching the broad any-exposure concept.

Inotrope:
  DrugID 1559 dobutamine, kept separate.
*/

DROP TABLE IF EXISTS frailty_work.sicdb_41_firstday_support_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_41_firstday_support_v1 AS
WITH cohort AS (
    SELECT
        "CaseID",
        "ICUOffset"
    FROM frailty_work.sicdb_20_primary_ais_cohort_v1
),
airway AS (
    SELECT
        c."CaseID",
        MAX(
            CASE
                WHEN r."DataID"=720
                 AND r."Offset" <= c."ICUOffset"+86400
                 AND COALESCE(r."OffsetEnd",r."Offset") >= c."ICUOffset"-21600
                THEN 1 ELSE 0
            END
        ) AS endotracheal_tube_firstday

    FROM cohort c
    LEFT JOIN public.data_range r
      ON r."CaseID"=c."CaseID"
     AND r."DataID"=720

    GROUP BY c."CaseID"
),
resp AS (
    SELECT
        c."CaseID",
        MAX(
            CASE
                WHEN d."DataID" IN (2278,2282,2283,2284,2285,3040)
                 AND d."Offset" >= c."ICUOffset"-21600
                 AND d."Offset" <= c."ICUOffset"+86400
                THEN 1 ELSE 0
            END
        ) AS any_respirator_setting_firstday

    FROM cohort c
    LEFT JOIN public.data_float_h d
      ON d."CaseID"=c."CaseID"
     AND d."DataID" IN (2278,2282,2283,2284,2285,3040)

    GROUP BY c."CaseID"
),
med AS (
    SELECT
        c."CaseID",

        MAX(
            CASE
                WHEN m."DrugID" IN (1562,1593)
                 AND m."Offset" <= c."ICUOffset"+86400
                 AND COALESCE(m."OffsetDrugEnd",m."Offset") >= c."ICUOffset"-21600
                THEN 1 ELSE 0
            END
        ) AS vasopressor_firstday,

        MAX(
            CASE
                WHEN m."DrugID"=1562
                 AND m."Offset" <= c."ICUOffset"+86400
                 AND COALESCE(m."OffsetDrugEnd",m."Offset") >= c."ICUOffset"-21600
                THEN 1 ELSE 0
            END
        ) AS norepinephrine_firstday,

        MAX(
            CASE
                WHEN m."DrugID"=1593
                 AND m."Offset" <= c."ICUOffset"+86400
                 AND COALESCE(m."OffsetDrugEnd",m."Offset") >= c."ICUOffset"-21600
                THEN 1 ELSE 0
            END
        ) AS phenylephrine_firstday,

        MAX(
            CASE
                WHEN m."DrugID" IN (1562,1593)
                 AND COALESCE(m."IsSingleDose",0)<>1
                 AND m."Offset" <= c."ICUOffset"+86400
                 AND COALESCE(m."OffsetDrugEnd",m."Offset") >= c."ICUOffset"-21600
                THEN 1 ELSE 0
            END
        ) AS vasopressor_nonsingledose_firstday,

        MAX(
            CASE
                WHEN m."DrugID"=1559
                 AND m."Offset" <= c."ICUOffset"+86400
                 AND COALESCE(m."OffsetDrugEnd",m."Offset") >= c."ICUOffset"-21600
                THEN 1 ELSE 0
            END
        ) AS dobutamine_firstday

    FROM cohort c
    LEFT JOIN public.medication m
      ON m."CaseID"=c."CaseID"
     AND m."DrugID" IN (1559,1562,1593)

    GROUP BY c."CaseID"
)
SELECT
    c."CaseID",
    COALESCE(a.endotracheal_tube_firstday,0) AS invasive_airway_firstday,
    COALESCE(r.any_respirator_setting_firstday,0) AS any_respirator_setting_firstday,
    COALESCE(m.vasopressor_firstday,0) AS vasopressor_firstday,
    COALESCE(m.norepinephrine_firstday,0) AS norepinephrine_firstday,
    COALESCE(m.phenylephrine_firstday,0) AS phenylephrine_firstday,
    COALESCE(m.vasopressor_nonsingledose_firstday,0)
        AS vasopressor_nonsingledose_firstday,
    COALESCE(m.dobutamine_firstday,0) AS dobutamine_firstday
FROM cohort c
LEFT JOIN airway a USING ("CaseID")
LEFT JOIN resp r USING ("CaseID")
LEFT JOIN med m USING ("CaseID")
;

CREATE UNIQUE INDEX sicdb_41_firstday_support_v1_pk
    ON frailty_work.sicdb_41_firstday_support_v1 ("CaseID");

ANALYZE frailty_work.sicdb_41_firstday_support_v1;

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
