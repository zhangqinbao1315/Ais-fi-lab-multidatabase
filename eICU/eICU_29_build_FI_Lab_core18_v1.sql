/*
FIX v1.2
--------
Replaced w.* with an explicit list of the 18 laboratory columns.
This prevents duplicate patientunitstayid in CREATE TABLE AS because
eicu_27_core18_earliest_wide_v1 already contains patientunitstayid while
the cohort keys are selected explicitly from c.
*/

/*
eICU - 29
Build Core-18 FI-Lab using MIMIC-frozen v1 thresholds.

Primary FI requires:
- gender Male/Female because Hb/Hct/RBC/creatinine use sex-specific thresholds
- >=15 measured Core-18 items

Missing labs are NULL and are NOT counted as normal.
*/

DROP TABLE IF EXISTS frailty_work.eicu_29_filab18_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_29_filab18_v1 AS
WITH x AS (
    SELECT
        c.patientunitstayid,
        c.patienthealthsystemstayid,
        c.uniquepid,
        c.gender,
        c.age_numeric,
        c.hospitaldischargestatus,

        CASE
            WHEN LOWER(BTRIM(COALESCE(c.hospitaldischargestatus,'')))='expired'
                THEN 1
            WHEN LOWER(BTRIM(COALESCE(c.hospitaldischargestatus,'')))='alive'
                THEN 0
            ELSE NULL
        END AS hospital_mortality,

        w.wbc,
        w.hemoglobin,
        w.hematocrit,
        w.platelet,
        w.rbc,
        w.mcv,
        w.sodium,
        w.potassium,
        w.chloride,
        w.bicarbonate,
        w.bun,
        w.creatinine,
        w.glucose,
        w.calcium,
        w.magnesium,
        w.phosphate,
        w.inr,
        w.aptt,

        (w.wbc IS NOT NULL)::int +
        (w.hemoglobin IS NOT NULL)::int +
        (w.hematocrit IS NOT NULL)::int +
        (w.platelet IS NOT NULL)::int +
        (w.rbc IS NOT NULL)::int +
        (w.mcv IS NOT NULL)::int +
        (w.sodium IS NOT NULL)::int +
        (w.potassium IS NOT NULL)::int +
        (w.chloride IS NOT NULL)::int +
        (w.bicarbonate IS NOT NULL)::int +
        (w.bun IS NOT NULL)::int +
        (w.creatinine IS NOT NULL)::int +
        (w.glucose IS NOT NULL)::int +
        (w.calcium IS NOT NULL)::int +
        (w.magnesium IS NOT NULL)::int +
        (w.phosphate IS NOT NULL)::int +
        (w.inr IS NOT NULL)::int +
        (w.aptt IS NOT NULL)::int AS n_measured

    FROM frailty_work.eicu_25_primary_ais_cohort_v1 c
    JOIN frailty_work.eicu_27_core18_earliest_wide_v1 w
      ON w.patientunitstayid = c.patientunitstayid
),
d AS (
    SELECT
        x.*,

        CASE WHEN wbc IS NULL THEN NULL
             WHEN wbc < 4.0 OR wbc > 10.0 THEN 1 ELSE 0 END AS d_wbc,

        CASE
            WHEN hemoglobin IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN hemoglobin < 11.2 OR hemoglobin > 15.7 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN hemoglobin < 13.7 OR hemoglobin > 17.5 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_hemoglobin,

        CASE
            WHEN hematocrit IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN hematocrit < 34 OR hematocrit > 45 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN hematocrit < 40 OR hematocrit > 51 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_hematocrit,

        CASE WHEN platelet IS NULL THEN NULL
             WHEN platelet < 150 OR platelet > 400 THEN 1 ELSE 0 END AS d_platelet,

        CASE
            WHEN rbc IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN rbc < 3.9 OR rbc > 5.2 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN rbc < 4.6 OR rbc > 6.1 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_rbc,

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

        CASE
            WHEN creatinine IS NULL THEN NULL
            WHEN LOWER(BTRIM(gender))='female'
                 THEN CASE WHEN creatinine < 0.4 OR creatinine > 1.1 THEN 1 ELSE 0 END
            WHEN LOWER(BTRIM(gender))='male'
                 THEN CASE WHEN creatinine < 0.5 OR creatinine > 1.2 THEN 1 ELSE 0 END
            ELSE NULL
        END AS d_creatinine,

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

    FROM x
),
s AS (
    SELECT
        d.*,

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
        COALESCE(d_aptt,0) AS n_deficits,

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
        (d_aptt IS NOT NULL)::int AS n_evaluable

    FROM d
)
SELECT
    s.*,

    CASE
        WHEN LOWER(BTRIM(COALESCE(gender,''))) IN ('female','male')
         AND n_measured >= 15
         AND n_evaluable >= 15
        THEN n_deficits::double precision / NULLIF(n_evaluable,0)
        ELSE NULL
    END AS filab18,

    CASE
        WHEN LOWER(BTRIM(COALESCE(gender,''))) IN ('female','male')
         AND n_measured >= 15
         AND n_evaluable >= 15
        THEN 10.0 * n_deficits::double precision / NULLIF(n_evaluable,0)
        ELSE NULL
    END AS filab18_per_0_1

FROM s
;

CREATE UNIQUE INDEX eicu_29_filab18_v1_pk
    ON frailty_work.eicu_29_filab18_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_29_filab18_v1;

SELECT
    COUNT(*) AS n_total,
    COUNT(filab18) AS n_valid_filab18
FROM frailty_work.eicu_29_filab18_v1;
