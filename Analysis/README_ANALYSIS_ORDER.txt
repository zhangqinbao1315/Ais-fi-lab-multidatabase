FINAL ANALYSIS EXECUTION ORDER
==============================

After exporting the analytic CSVs from the three database pipelines:

1. 01_MIMIC_PRIMARY_ASSOCIATION_INCREMENTAL_FINAL.R
   Primary MIMIC association, multiplicative/additive interaction,
   and incremental FI-Lab value.

2. 02_FUNCTIONAL_FORM_FINAL.R
   Restricted-cubic-spline / flexible-main-effect checks in MIMIC and eICU.

3. 03_BROADER_AIS_SENSITIVITY_FINAL.R
   Broader MIMIC AIS case-definition sensitivity.

4. 04_STRICT_24H_LANDMARK_FINAL.R
   AUTHORITATIVE secondary 24-h prediction model.
   This model intentionally excludes hospitalization-level CCI and the
   CCI×FI-Lab interaction.

5. 05_eICU_ASSOCIATION_SENSITIVITIES_FINAL.R
   Hospital-cluster robust refit, diagnosis-only CCI, evaluable-item
   thresholds, valid/invalid comparison, and IPW.

6. 06_SICdb_TRANSPORTABILITY_FINAL.R
   Exploratory logistf Firth analysis.

7. 07_REDUCED_RED_CELL_SAME_SAMPLE_FINAL.py
   AUTHORITATIVE Core17/Core16 sensitivity on the identical frozen H94 sample.

Important:
The former V5 single-file runner is deliberately NOT included in this merged
candidate because its archived landmark module contained hospitalization-level
CCI and its optional reduced-FI module used a stricter post-deletion
computability rule. The scripts above are the authoritative final analyses.


8. 08_eICU_EXPANDED_IPW_OVERLAP_FINAL.R
   Revision-stage FI-Lab-validity IPW expanded to GCS, invasive ventilation,
   vasopressor exposure, and hospital fixed effects, with full-hospital and
   within-hospital-overlap sensitivities.

9. 09_MIMIC_OASIS_SEVERITY_FINAL.R
   Alternative MIMIC H94 acute-severity adjustment replacing age/GCS/IMV
   with OASIS while retaining sex and vasopressor exposure.

10. 10_eICU_IPW_BALANCE_DIAGNOSTICS_FINAL.py
    Aggregate standardized-mean-difference balance diagnostics for the
    expanded eICU FI-validity weighting; no patient-level output is written.
