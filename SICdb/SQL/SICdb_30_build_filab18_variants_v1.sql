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
