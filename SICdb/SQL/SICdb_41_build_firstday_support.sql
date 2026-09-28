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
