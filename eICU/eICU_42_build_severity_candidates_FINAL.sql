/*
=====================================================================
FINAL APACHE SENTINEL PATCH
=====================================================================

Full file-level comparison against the authoritative frozen eICU_48 file
showed that all remaining differences were confined to:

  apache_iva_score
  apache_iva_aps

Every remaining mismatch was:
  rebuilt = -1
  frozen  = NULL

Counts:
  eICU_48: 24 rows
  eICU_49: 20 rows
  eICU_50: 17 rows

Therefore -1 is treated as a missing-value sentinel for these two APACHE IVa
descriptive fields.

This patch applies NULLIF(value, -1) before aggregation.

No cohort, outcome, FI-Lab, CCI, GCS, invasive-ventilation, vasopressor,
or primary-model definition is changed.
=====================================================================
*/

/*
=====================================================================
FIELD-ALIGNMENT PATCH — FINAL
=====================================================================

This script supersedes the prior eICU_42 stage for exact reproduction of
the authoritative frozen analytic files.

File-level comparison after the R4 cohort lock showed that:
- all 2,807 eICU_48 IDs were exact;
- all 105 columns existed in identical order;
- 99/105 columns were already exact;
- only six auxiliary/support fields differed:
    vasopressor_use_firstday      1 row
    imv_day1_fallback           235 rows
    vasopressor_treatment         8 rows
    epinephrine_infusion         44 rows
    apache_iva_score           2481 rows
    apache_iva_aps             2481 rows

Primary eICU_50 model variables were already 100% row-wise identical.

This patch reproduces the historical frozen field definitions:
1. APACHE IVa rows use apacheVersion='IVa' (case-normalized).
2. Historical epinephrine substring matching is retained for exact frozen
   reproduction; this duplicates norepinephrine-positive rows in the
   epinephrine component but does not alter the union vasopressor indicator.
3. Historical imv_day1_fallback equals oOBIntubDay1, including missingness.
4. The primary treatment-derived vasopressor indicator uses only named
   vasopressor agents; the generic parent treatment pathway is not counted.

No cohort, FI-Lab, CCI, GCS, primary IMV, or outcome definition is changed.
=====================================================================
*/

/*
FIX v1.3
--------
eICU local schema stores apacheversion as character varying.
All apacheversion comparisons in this script are now cast to text explicitly
(e.g., BTRIM(apacheversion::text) = '4'), preventing varchar = integer errors.
*/

/*
eICU S4 FINAL - 42
Build the frozen first-day severity/support covariates.

Primary constructs (as reported in S1 Appendix)
------------------------------------------------
GCS:
  APACHE APS eyes + motor + verbal.
  Medication-coded/unscorable observations are excluded.

Invasive ventilation:
  apachePredVar oOBIntubDay1.
  This is the PRIMARY eICU IMV variable.

Vasopressor:
  first-day (-6 h/+24 h) union of infusionDrug and treatment evidence for:
  norepinephrine, epinephrine, dopamine, phenylephrine, vasopressin.

Dobutamine and milrinone are retained only as inotrope sensitivity fields,
not counted in the primary vasopressor indicator.

No outcome fields are used to define these covariates.
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_42_severity_candidates_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_42_severity_candidates_v1 AS
WITH cohort AS (
    SELECT patientunitstayid
    FROM frailty_work.eicu_25_primary_ais_cohort_v1
),

/* APACHE APS: worst GCS components in the APACHE day */
aps AS (
    SELECT DISTINCT ON (a.patientunitstayid)
        a.patientunitstayid,
        a.apacheapsvarid,
        a.intubated AS aps_intubated,
        a.vent AS aps_vent,
        a.meds AS aps_meds,
        a.eyes AS aps_eyes,
        a.motor AS aps_motor,
        a.verbal AS aps_verbal,

        CASE
            WHEN COALESCE(a.meds,0) <> 1
             AND a.eyes BETWEEN 1 AND 4
             AND a.motor BETWEEN 1 AND 6
             AND a.verbal BETWEEN 1 AND 5
            THEN a.eyes + a.motor + a.verbal
            ELSE NULL
        END::integer AS gcs_total

    FROM cohort c
    JOIN eicu_crd.apacheapsvar a
      ON a.patientunitstayid = c.patientunitstayid
    ORDER BY a.patientunitstayid, a.apacheapsvarid
),

/* APACHE day-1 ventilation/intubation variables */
pred AS (
    SELECT DISTINCT ON (p.patientunitstayid)
        p.patientunitstayid,
        p.apachepredvarid,
        p.oobintubday1,
        p.oobventday1,
        p.ventday1
    FROM cohort c
    JOIN eicu_crd.apachepredvar p
      ON p.patientunitstayid = c.patientunitstayid
    ORDER BY p.patientunitstayid, p.apachepredvarid
),

/* Respiratory-care fallback retained for sensitivity/QC only */
resp AS (
    SELECT
        c.patientunitstayid,

        MAX(CASE
            WHEN rc.airwaytype IN ('Oral ETT','Tracheostomy')
             AND (
                  (
                    rc.ventstartoffset IS NOT NULL
                    AND rc.ventstartoffset <= 1440
                    AND (
                         rc.ventendoffset IS NULL
                         OR rc.ventendoffset >= -360
                    )
                  )
                  OR
                  (
                    rc.priorventstartoffset IS NOT NULL
                    AND rc.priorventstartoffset <= 1440
                    AND (
                         rc.priorventendoffset IS NULL
                         OR rc.priorventendoffset >= -360
                    )
                  )
             )
            THEN 1 ELSE 0 END
        )::integer AS rc_invasive_airway_overlap

    FROM cohort c
    LEFT JOIN eicu_crd.respiratorycare rc
      ON rc.patientunitstayid = c.patientunitstayid
    GROUP BY c.patientunitstayid
),

/* Any first-day infusion record: source-availability flag */
inf_any AS (
    SELECT
        c.patientunitstayid,
        CASE WHEN COUNT(i.infusiondrugid) > 0 THEN 1 ELSE 0 END::integer
            AS has_any_infusiondrug_record_firstday
    FROM cohort c
    LEFT JOIN eicu_crd.infusiondrug i
      ON i.patientunitstayid = c.patientunitstayid
     AND i.infusionoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* Drug-specific infusion evidence */
inf AS (
    SELECT
        c.patientunitstayid,

        MAX(CASE
            WHEN (
                 LOWER(i.drugname) LIKE '%norepinephrine%'
                 OR LOWER(i.drugname) LIKE '%levophed%'
            ) THEN 1 ELSE 0 END)::integer AS norepinephrine_infusion,

        MAX(CASE
            WHEN (
                 LOWER(i.drugname) LIKE '%epinephrine%'
                 OR LOWER(i.drugname) LIKE '%adrenaline%'
            ) THEN 1 ELSE 0 END)::integer AS epinephrine_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%dopamine%'
            THEN 1 ELSE 0 END)::integer AS dopamine_infusion,

        MAX(CASE
            WHEN (
                 LOWER(i.drugname) LIKE '%phenylephrine%'
                 OR LOWER(i.drugname) LIKE '%neo-synephrine%'
                 OR LOWER(i.drugname) LIKE '%neosynephrine%'
            ) THEN 1 ELSE 0 END)::integer AS phenylephrine_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%vasopressin%'
            THEN 1 ELSE 0 END)::integer AS vasopressin_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%dobutamine%'
            THEN 1 ELSE 0 END)::integer AS dobutamine_infusion,

        MAX(CASE
            WHEN LOWER(i.drugname) LIKE '%milrinone%'
            THEN 1 ELSE 0 END)::integer AS milrinone_infusion

    FROM cohort c
    LEFT JOIN eicu_crd.infusiondrug i
      ON i.patientunitstayid = c.patientunitstayid
     AND i.infusionoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* Any first-day treatment record: source-availability flag */
trt_any AS (
    SELECT
        c.patientunitstayid,
        CASE WHEN COUNT(t.treatmentid) > 0 THEN 1 ELSE 0 END::integer
            AS has_any_treatment_record_firstday
    FROM cohort c
    LEFT JOIN eicu_crd.treatment t
      ON t.patientunitstayid = c.patientunitstayid
     AND t.treatmentoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* Structured treatment pathways */
trt AS (
    SELECT
        c.patientunitstayid,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|norepinephrine%'
            OR LOWER(t.treatmentstring) LIKE '%|inotropic agent|norepinephrine%'
            THEN 1 ELSE 0 END)::integer AS norepinephrine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|epinephrine%'
            OR LOWER(t.treatmentstring) LIKE '%|inotropic agent|epinephrine%'
            THEN 1 ELSE 0 END)::integer AS epinephrine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|dopamine%'
            OR LOWER(t.treatmentstring) LIKE '%|inotropic agent|dopamine%'
            THEN 1 ELSE 0 END)::integer AS dopamine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|phenylephrine%'
            THEN 1 ELSE 0 END)::integer AS phenylephrine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors|vasopressin%'
            THEN 1 ELSE 0 END)::integer AS vasopressin_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|inotropic agent|dobutamine%'
            THEN 1 ELSE 0 END)::integer AS dobutamine_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|inotropic agent|milrinone%'
            THEN 1 ELSE 0 END)::integer AS milrinone_treatment,

        MAX(CASE WHEN
            LOWER(t.treatmentstring) LIKE '%|vasopressors%'
            THEN 1 ELSE 0 END)::integer AS any_vasopressor_treatment_path

    FROM cohort c
    LEFT JOIN eicu_crd.treatment t
      ON t.patientunitstayid = c.patientunitstayid
     AND t.treatmentoffset BETWEEN -360 AND 1440
    GROUP BY c.patientunitstayid
),

/* APACHE IV/IVa descriptive severity scores; not primary covariates */
apr AS (
    SELECT
        c.patientunitstayid,
        MAX(NULLIF(r.apachescore, -1))
            FILTER (WHERE UPPER(BTRIM(r.apacheversion::text)) = 'IVA')
            AS apache_iva_score,
        MAX(NULLIF(r.acutephysiologyscore, -1))
            FILTER (WHERE UPPER(BTRIM(r.apacheversion::text)) = 'IVA')
            AS apache_iva_aps
    FROM cohort c
    LEFT JOIN eicu_crd.apachepatientresult r
      ON r.patientunitstayid = c.patientunitstayid
    GROUP BY c.patientunitstayid
)

SELECT
    c.patientunitstayid,

    a.gcs_total,

    /* Primary eICU IMV construct */
    p.oobintubday1::integer
        AS imv_oobintubday1,

    /* Sensitivity/fallback fields, not primary */
    a.aps_intubated,
    p.oobintubday1::integer AS imv_day1_fallback,

    COALESCE(p.oobventday1, p.ventday1, a.aps_vent)::integer
        AS any_mechanical_assist_day1,

    /* Primary vasopressor source-specific indicators */
    GREATEST(
        COALESCE(i.norepinephrine_infusion,0),
        COALESCE(i.epinephrine_infusion,0),
        COALESCE(i.dopamine_infusion,0),
        COALESCE(i.phenylephrine_infusion,0),
        COALESCE(i.vasopressin_infusion,0)
    )::integer AS vasopressor_infusion,

    GREATEST(
        COALESCE(t.norepinephrine_treatment,0),
        COALESCE(t.epinephrine_treatment,0),
        COALESCE(t.dopamine_treatment,0),
        COALESCE(t.phenylephrine_treatment,0),
        COALESCE(t.vasopressin_treatment,0)
    )::integer AS vasopressor_treatment,

    GREATEST(
        COALESCE(i.norepinephrine_infusion,0),
        COALESCE(i.epinephrine_infusion,0),
        COALESCE(i.dopamine_infusion,0),
        COALESCE(i.phenylephrine_infusion,0),
        COALESCE(i.vasopressin_infusion,0),
        COALESCE(t.norepinephrine_treatment,0),
        COALESCE(t.epinephrine_treatment,0),
        COALESCE(t.dopamine_treatment,0),
        COALESCE(t.phenylephrine_treatment,0),
        COALESCE(t.vasopressin_treatment,0)
    )::integer AS vasopressor_recorded_any,

    COALESCE(i.norepinephrine_infusion,0)::integer
        AS norepinephrine_infusion,
    COALESCE(i.epinephrine_infusion,0)::integer
        AS epinephrine_infusion,
    COALESCE(i.dopamine_infusion,0)::integer
        AS dopamine_infusion,
    COALESCE(i.phenylephrine_infusion,0)::integer
        AS phenylephrine_infusion,
    COALESCE(i.vasopressin_infusion,0)::integer
        AS vasopressin_infusion,

    GREATEST(
        COALESCE(i.dobutamine_infusion,0),
        COALESCE(t.dobutamine_treatment,0)
    )::integer AS dobutamine_any,

    GREATEST(
        COALESCE(i.milrinone_infusion,0),
        COALESCE(t.milrinone_treatment,0)
    )::integer AS milrinone_any,

    GREATEST(
        COALESCE(i.dobutamine_infusion,0),
        COALESCE(t.dobutamine_treatment,0),
        COALESCE(i.milrinone_infusion,0),
        COALESCE(t.milrinone_treatment,0)
    )::integer AS any_inotrope,

    COALESCE(ia.has_any_infusiondrug_record_firstday,0)::integer
        AS has_any_infusiondrug_record_firstday,

    COALESCE(ta.has_any_treatment_record_firstday,0)::integer
        AS has_any_treatment_record_firstday,

    ap.apache_iva_score,
    ap.apache_iva_aps

FROM cohort c
LEFT JOIN aps a
  ON a.patientunitstayid = c.patientunitstayid
LEFT JOIN pred p
  ON p.patientunitstayid = c.patientunitstayid
LEFT JOIN resp r
  ON r.patientunitstayid = c.patientunitstayid
LEFT JOIN inf_any ia
  ON ia.patientunitstayid = c.patientunitstayid
LEFT JOIN inf i
  ON i.patientunitstayid = c.patientunitstayid
LEFT JOIN trt_any ta
  ON ta.patientunitstayid = c.patientunitstayid
LEFT JOIN trt t
  ON t.patientunitstayid = c.patientunitstayid
LEFT JOIN apr ap
  ON ap.patientunitstayid = c.patientunitstayid
;

CREATE UNIQUE INDEX eicu_42_severity_candidates_v1_pk
    ON frailty_work.eicu_42_severity_candidates_v1 (patientunitstayid);

ANALYZE frailty_work.eicu_42_severity_candidates_v1;

SELECT
    COUNT(*) AS n_rows,
    COUNT(gcs_total) AS n_with_gcs,
    COUNT(imv_oobintubday1) AS n_with_primary_imv,
    COUNT(*) FILTER (WHERE imv_oobintubday1=1) AS n_primary_imv,
    COUNT(*) FILTER (WHERE vasopressor_recorded_any=1) AS n_primary_vasopressor
FROM frailty_work.eicu_42_severity_candidates_v1;
