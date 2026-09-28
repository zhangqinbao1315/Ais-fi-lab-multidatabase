/* Save result grid as: sicdb_47_dictionary_final_audit.csv */
WITH refs AS (
        SELECT
            CASE
                WHEN CONCAT_WS(
                    ' ',
                    "ReferenceValue",
                    "ReferenceName",
                    "ReferenceDescription"
                ) ~* '(glasgow|gcs|coma|vigil|bewusst|conscious|rass|ramsay|sedat|neurolog|pupil|eye.?open|verbal.?response|motor.?response)'
                THEN 'NEURO_GCS_SEDATION'

                WHEN CONCAT_WS(
                    ' ',
                    "ReferenceValue",
                    "ReferenceName",
                    "ReferenceDescription"
                ) ~* '(precondition|chronic|comorbid|history|anamnes)'
                THEN 'CHRONIC_HISTORY'

                WHEN CONCAT_WS(
                    ' ',
                    "ReferenceValue",
                    "ReferenceName",
                    "ReferenceDescription"
                ) ~* '(norepine|noradren|phenyleph|epineph|adrenalin|dopamin|vasopressin|dobutamin|milrinon)'
                THEN 'VASO_INOTROPE'

                ELSE NULL
            END AS audit_group,

            "ReferenceGlobalID" AS reference_id,
            "ReferenceValue",
            "ReferenceName",
            "ReferenceDescription",
            "ReferenceUnit"

        FROM public.d_references
    )
    SELECT *
    FROM refs
    WHERE audit_group IS NOT NULL
    ORDER BY
        audit_group,
        "ReferenceName",
        "ReferenceValue",
        reference_id;
