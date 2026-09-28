/*
Revision-stage MIMIC H94 + OASIS sensitivity export.
Export the final SELECT result grid as:
  mimic_H94_OASIS_sensitivity_input.csv
*/
SELECT
    h.subject_id, h.hadm_id, h.stay_id, h.hospital_expire_flag,
    h.cci_chronic_burden_no_age, h.filab18_per_0_1,
    h.age, h.female, h.gcs_min,
    h.any_invasive_vent_m6p24, h.any_vasopressor_m6p24,
    o.oasis
FROM frailty_work.mimic_s4_h94_primary_completecase h
LEFT JOIN mimiciv_derived.oasis o
  ON o.stay_id = h.stay_id
ORDER BY h.subject_id, h.hadm_id, h.stay_id;
