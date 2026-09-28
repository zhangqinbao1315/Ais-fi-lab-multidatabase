/*
eICU - 27
Build earliest Core-18 values in the frozen primary unique-patient cohort.

Uses existing small table:
  frailty_work.eicu_20_lab_window_v1

Primary mapping is deliberately strict:
- serum/central-lab glucose only
- bicarbonate only
- excludes bedside glucose, Total CO2, HCO3
*/

DROP TABLE IF EXISTS frailty_work.eicu_27_core18_earliest_long_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_27_core18_earliest_long_v1 AS
WITH mapped AS (
    SELECT
        l.patientunitstayid,
        l.labid,
        l.labresultoffset,
        l.labname,
        l.labresult::double precision AS value,

        CASE
            WHEN l.labname = 'WBC x 1000' THEN 'WBC'
            WHEN l.labname = 'Hgb' THEN 'Hemoglobin'
            WHEN l.labname = 'Hct' THEN 'Hematocrit'
            WHEN l.labname = 'platelets x 1000' THEN 'Platelet'
            WHEN l.labname = 'RBC' THEN 'RBC'
            WHEN l.labname = 'MCV' THEN 'MCV'
            WHEN l.labname = 'sodium' THEN 'Sodium'
            WHEN l.labname = 'potassium' THEN 'Potassium'
            WHEN l.labname = 'chloride' THEN 'Chloride'
            WHEN l.labname = 'bicarbonate' THEN 'Bicarbonate'
            WHEN l.labname = 'BUN' THEN 'BUN'
            WHEN l.labname = 'creatinine' THEN 'Creatinine'
            WHEN l.labname = 'glucose' THEN 'Glucose'
            WHEN l.labname = 'calcium' THEN 'Calcium'
            WHEN l.labname = 'magnesium' THEN 'Magnesium'
            WHEN l.labname = 'phosphate' THEN 'Phosphate'
            WHEN l.labname = 'PT - INR' THEN 'INR'
            WHEN l.labname = 'PTT' THEN 'aPTT'
            ELSE NULL
        END AS core18_item

    FROM frailty_work.eicu_20_lab_window_v1 l
    JOIN frailty_work.eicu_25_primary_ais_cohort_v1 c
      ON c.patientunitstayid = l.patientunitstayid

    WHERE l.labresultoffset BETWEEN -360 AND 1440
      AND l.labresult IS NOT NULL
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY patientunitstayid, core18_item
            ORDER BY labresultoffset ASC, labid ASC
        ) AS rn
    FROM mapped
    WHERE core18_item IS NOT NULL
)
SELECT
    patientunitstayid,
    core18_item,
    labname,
    value,
    labresultoffset,
    labid
FROM ranked
WHERE rn = 1
;

CREATE UNIQUE INDEX eicu_27_core18_earliest_long_v1_pk
    ON frailty_work.eicu_27_core18_earliest_long_v1
       (patientunitstayid, core18_item);


DROP TABLE IF EXISTS frailty_work.eicu_27_core18_earliest_wide_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_27_core18_earliest_wide_v1 AS
SELECT
    c.patientunitstayid,

    MAX(v.value) FILTER (WHERE v.core18_item='WBC') AS wbc,
    MAX(v.value) FILTER (WHERE v.core18_item='Hemoglobin') AS hemoglobin,
    MAX(v.value) FILTER (WHERE v.core18_item='Hematocrit') AS hematocrit,
    MAX(v.value) FILTER (WHERE v.core18_item='Platelet') AS platelet,
    MAX(v.value) FILTER (WHERE v.core18_item='RBC') AS rbc,
    MAX(v.value) FILTER (WHERE v.core18_item='MCV') AS mcv,
    MAX(v.value) FILTER (WHERE v.core18_item='Sodium') AS sodium,
    MAX(v.value) FILTER (WHERE v.core18_item='Potassium') AS potassium,
    MAX(v.value) FILTER (WHERE v.core18_item='Chloride') AS chloride,
    MAX(v.value) FILTER (WHERE v.core18_item='Bicarbonate') AS bicarbonate,
    MAX(v.value) FILTER (WHERE v.core18_item='BUN') AS bun,
    MAX(v.value) FILTER (WHERE v.core18_item='Creatinine') AS creatinine,
    MAX(v.value) FILTER (WHERE v.core18_item='Glucose') AS glucose,
    MAX(v.value) FILTER (WHERE v.core18_item='Calcium') AS calcium,
    MAX(v.value) FILTER (WHERE v.core18_item='Magnesium') AS magnesium,
    MAX(v.value) FILTER (WHERE v.core18_item='Phosphate') AS phosphate,
    MAX(v.value) FILTER (WHERE v.core18_item='INR') AS inr,
    MAX(v.value) FILTER (WHERE v.core18_item='aPTT') AS aptt

FROM frailty_work.eicu_25_primary_ais_cohort_v1 c
LEFT JOIN frailty_work.eicu_27_core18_earliest_long_v1 v
  ON v.patientunitstayid = c.patientunitstayid
GROUP BY c.patientunitstayid
;

CREATE UNIQUE INDEX eicu_27_core18_earliest_wide_v1_pk
    ON frailty_work.eicu_27_core18_earliest_wide_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_27_core18_earliest_long_v1;
ANALYZE frailty_work.eicu_27_core18_earliest_wide_v1;

SELECT
    COUNT(*) AS n_primary_rows,
    COUNT(*) FILTER (
        WHERE
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
          (aptt IS NOT NULL)::int >= 15
    ) AS n_with_at_least_15_of_18
FROM frailty_work.eicu_27_core18_earliest_wide_v1;
