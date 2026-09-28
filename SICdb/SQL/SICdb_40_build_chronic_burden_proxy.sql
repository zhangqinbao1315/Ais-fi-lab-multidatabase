/*
SICdb - 40
Build available chronic-condition indicators.

These are NOT a Charlson index.

data_ref IDs from the local audited dictionary:
  FieldID 3097 PreconditionDiabetes
  FieldID 3098 PreconditionArtHypertension
  FieldID 3103 PreconditionLungDisease
  FieldID 3104 PreconditionRenalDysfunction

RefID:
  738 = No
  740 = Yes
*/

CREATE SCHEMA IF NOT EXISTS frailty_work;

DROP TABLE IF EXISTS frailty_work.sicdb_40_chronic_proxy_v1;

CREATE UNLOGGED TABLE frailty_work.sicdb_40_chronic_proxy_v1 AS
WITH p AS (
    SELECT
        c."CaseID",

        MAX(
            CASE
                WHEN dr."FieldID"=3097 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3097 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_diabetes,

        MAX(
            CASE
                WHEN dr."FieldID"=3098 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3098 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_hypertension,

        MAX(
            CASE
                WHEN dr."FieldID"=3103 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3103 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_lung_disease,

        MAX(
            CASE
                WHEN dr."FieldID"=3104 AND dr."RefID"=740 THEN 1
                WHEN dr."FieldID"=3104 AND dr."RefID"=738 THEN 0
                ELSE NULL
            END
        ) AS precondition_renal_dysfunction

    FROM frailty_work.sicdb_20_primary_ais_cohort_v1 c
    LEFT JOIN public.data_ref dr
      ON dr."CaseID"=c."CaseID"
     AND dr."FieldID" IN (3097,3098,3103,3104)

    GROUP BY c."CaseID"
)
SELECT
    *,

    CASE
        WHEN precondition_diabetes IS NOT NULL
         AND precondition_lung_disease IS NOT NULL
         AND precondition_renal_dysfunction IS NOT NULL
        THEN
            precondition_diabetes +
            precondition_lung_disease +
            precondition_renal_dysfunction
        ELSE NULL
    END AS available_charlson_domain_count3,

    CASE
        WHEN precondition_diabetes IS NOT NULL
         AND precondition_hypertension IS NOT NULL
         AND precondition_lung_disease IS NOT NULL
         AND precondition_renal_dysfunction IS NOT NULL
        THEN
            precondition_diabetes +
            precondition_hypertension +
            precondition_lung_disease +
            precondition_renal_dysfunction
        ELSE NULL
    END AS available_precondition_count4

FROM p
;

CREATE UNIQUE INDEX sicdb_40_chronic_proxy_v1_pk
    ON frailty_work.sicdb_40_chronic_proxy_v1 ("CaseID");

ANALYZE frailty_work.sicdb_40_chronic_proxy_v1;
