S4 CODE — MERGED AUTHORITATIVE CANDIDATE
========================================

Purpose
-------
This package replaces the incomplete third-draft S4 code archive.

It closes the database-to-analytic chain for all three databases, with the MIMIC component beginning from source tables plus pre-existing derived concept tables:

MIMIC-IV v3.1
  source + mimiciv_derived concepts -> H92/H93/H94 + broader AIS sensitivity

eICU-CRD v2.0
  raw -> eICU_48/eICU_49/eICU_50
  exact frozen validation completed: 0 semantic cell mismatches

SICdb v1.0.8
  raw -> primary AIS cohort -> Core-18 variants -> support/chronic proxy
      -> analysis base / FI-valid / available-complete-case
  exact frozen validation completed at every stage


Authoritative analysis
----------------------
See:
  Analysis/README_ANALYSIS_ORDER.txt
  Documentation/RESULTS_TO_SCRIPT_MANIFEST.tsv

The archived third-draft V5 single-file runner is NOT carried forward as the
authoritative final runner, because its old 24-h module contained
hospitalization-level CCI and its optional reduced-FI block used a different
computability rule.

The final 24-h model is:
  hospital mortality ~ FI-Lab + age + sex + GCS
                       + invasive ventilation + vasopressor

No CCI and no CCI×FI-Lab interaction are included in the final landmark model.


Data access
-----------
No source patient-level data are included.
Researchers must obtain database access under the original MIMIC-IV,
eICU-CRD, and SICdb access/data-use requirements.


Portability
-----------
The final MIMIC/eICU/SICdb export queries use ordinary SELECT result grids.
No final database pipeline requires a PostgreSQL server-side COPY TO C:\temp.


Validation status
-----------------
MIMIC locked counts:
  H92 1741/189
  H93 1666/183
  H94 1665/183

eICU exact final:
  eICU_48 2807/261
  eICU_49 2091/205
  eICU_50 2015/197
  complete frozen row/cell alignment passed

SICdb exact final:
  all cohort 33/9
  FI-valid 30/8
  every validated raw-to-analytic stage exact full-row pass

Strict 24-h final:
  MIMIC n=1496, deaths=162, AUC=0.837986, Brier=0.082761
  eICU n=1638, deaths=168, AUC=0.780049, Brier=0.091954
  calibration intercept=-0.467829; slope=0.628547
  final landmark model excludes hospitalization-level CCI and CCI×FI-Lab.


Revision-stage statistical lock
-------------------------------
Two additional sensitivity analyses were completed after the fourth-draft
pre-submission review without changing any frozen cohort or exposure:

1. Expanded eICU FI-validity IPW:
   age + sex + modified CCI + GCS + invasive ventilation + vasopressor
   + hospital indicators, with a separate restriction to hospitals containing
   both FI-valid and FI-invalid patients to address hospital-level positivity.

2. MIMIC OASIS alternative severity adjustment:
   frozen H94 sample; age/GCS/IMV replaced by OASIS, with sex and vasopressor
   retained.

The expanded eICU analysis also archives propensity/weight diagnostics and
aggregate SMD balance diagnostics. These analyses are sensitivity analyses,
not replacements for the frozen primary models.

SICdb Firth code correction after final pre-submission audit
----------------------------------------------------------
The authoritative SICdb transportability script now directly uses logistf::logistf(..., firth=TRUE, pl=TRUE) and outputs the reported profile-likelihood confidence intervals for the frozen FI-Lab-only and FI-Lab+age models. The previously archived ordinary-GLM copy was an outdated script and has been replaced without changing the frozen manuscript results.

Final executed SICdb verification
---------------------------------
The corrected logistf script was executed on the frozen SICdb inputs using
R 4.6.0 and logistf 1.26.1. It reproduced FI-Lab OR 1.897992
(profile-likelihood 95% CI 1.094603-3.783797; p=0.021328) and the
age-adjusted FI-Lab OR 2.284600 (1.173258-6.056660; p=0.012484).
A non-statistical CSV row-duplication issue in the first corrected script
was subsequently fixed by writing scalar method labels; estimates were unchanged.
