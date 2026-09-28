/*
eICU S4 FINAL - 20
Materialize first-day laboratory rows for the qualifying AIS candidate stays.

Window:
  ICU admission -360 to +1440 minutes.

This intentionally retains raw eICU lab names.
Strict Core-18 mapping occurs in eICU_27.
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.eicu_20_lab_window_v1;

CREATE UNLOGGED TABLE frailty_work.eicu_20_lab_window_v1 AS
SELECT
    l.labid,
    l.patientunitstayid,
    l.labresultoffset,
    l.labtypeid,
    l.labname,
    l.labresult,
    l.labresulttext,
    l.labmeasurenamesystem,
    l.labmeasurenameinterface
FROM eicu_crd.lab l
JOIN frailty_work.eicu_15_main_ais_candidate_v1 c
  ON c.patientunitstayid = l.patientunitstayid
WHERE l.labresultoffset BETWEEN -360 AND 1440
  AND l.labresult IS NOT NULL
;

CREATE INDEX eicu_20_lab_window_v1_stay_item_time
    ON frailty_work.eicu_20_lab_window_v1
       (patientunitstayid, labname, labresultoffset, labid);

ANALYZE frailty_work.eicu_20_lab_window_v1;

SELECT
    COUNT(*) AS n_lab_rows,
    COUNT(DISTINCT patientunitstayid) AS n_stays_with_any_lab,
    COUNT(DISTINCT labname) AS n_distinct_lab_names
FROM frailty_work.eicu_20_lab_window_v1;
