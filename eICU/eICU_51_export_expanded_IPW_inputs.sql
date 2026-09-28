/*
Revision-stage eICU expanded FI-validity IPW export.
Export the two SELECT result grids as:
  eicu_IPW_expanded_selection_input.csv
  eicu_IPW_expanded_outcome_input.csv
*/
SELECT
    patientunitstayid, hospitalid, hospital_mortality,
    filab18_n_evaluable, filab18_n_deficits, filab18, filab18_per_0_1,
    age_numeric, sex_female, cci_chronic_burden_no_age, gcs,
    invasive_ventilation_day1, vasopressor_use_firstday
FROM frailty_work.eicu_48_analysis_base_all
ORDER BY patientunitstayid;

SELECT
    patientunitstayid, hospitalid, hospital_mortality,
    cci_chronic_burden_no_age, filab18_per_0_1, age_numeric, sex_female, gcs,
    invasive_ventilation_day1, vasopressor_use_firstday
FROM frailty_work.eicu_50_primary_model_completecase
ORDER BY patientunitstayid;
