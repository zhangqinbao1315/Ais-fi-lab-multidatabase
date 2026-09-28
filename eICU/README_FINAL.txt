S4 eICU RAW -> ANALYTIC — EXACT FINAL
=====================================

USE THIS PACKAGE ONLY.
Earlier eICU repair / lock / patch packages are execution history and should
not be placed in the final Supporting Information.

PRIMARY RUN
-----------
Run in Navicat:

eICU_00_ONE_CLICK_RAW_TO_ANALYTIC_EXACT_FINAL.sql

This reconstructs the complete eICU analytic chain and ends with both QC
tables.

SUCCESS
-------
Both must equal 1:

frailty_work.eicu_s4_final_qc.all_locked_counts_pass

frailty_work.eicu_s4_field_alignment_qc.all_field_proxy_checks_pass


EXPECTED FINAL DATASETS
-----------------------
eICU_48:
n = 2807
hospital deaths = 261

eICU_49:
n = 2091
hospital deaths = 205

eICU_50:
n = 2015
hospital deaths = 197
IMV positives = 314
vasopressor positives = 115


EXPORT
------
Use:

eICU_FINAL_EXPORT_QUERIES.sql

No PostgreSQL COPY TO C:\temp is used.


FINAL VALIDATION
----------------
The final locally rerun datasets were compared with the authoritative frozen
analytic file.

eICU_48:
2807 x 105
0 semantic cell mismatches.

eICU_49 and eICU_50:
exact ID subsets and 0 semantic cell mismatches across all 105 columns.


IMPORTANT METHODS WORDING
-------------------------
For eICU, do not write simply "unitVisitNumber=1".

Accurate reproducible wording:

"Within each eICU hospital stay, we selected the first available ICU unit
record (minimum unitVisitNumber, with patientUnitStayID as a deterministic
tie-breaker), then applied the prespecified AIS eligibility criteria."

The resulting first-available unit can have unitVisitNumber >1 when earlier
unit numbers are absent from the available database extract.

Revision-stage addition: eICU_51_export_expanded_IPW_inputs.sql exports the frozen eICU_48/eICU_50 inputs used for the expanded FI-validity IPW and hospital-overlap sensitivity.
