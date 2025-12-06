{{
  config(
    materialized='view',
    tags=['staging', 'goods_receipts', 'invoice_receipts']
  )
}}

WITH source AS (
    SELECT * FROM {{ source('ap_sap', 'raw_ekbe') }}
),

cleaned AS (
    SELECT
        TRIM(ebeln) || '-' || TRIM(ebelp) || '-' || TRIM(vgabe) || '-' || 
        TRIM(gjahr) || '-' || TRIM(belnr) || '-' || TRIM(buzei) AS gr_ir_key,
        TRIM(ebeln) || '-' || TRIM(ebelp) AS po_item_key,
        CASE TRIM(vgabe)
            WHEN '1' THEN 'GOODS_RECEIPT'
            WHEN '2' THEN 'INVOICE_RECEIPT'
            ELSE 'OTHER'
        END AS transaction_type,
        TRIM(vgabe) AS transaction_code,
        TRIM(bewtp) AS po_history_category,
        TRIM(ebeln) AS po_number,
        TRIM(ebelp) AS po_item_number,
        TRIM(belnr) AS document_number,
        TRIM(buzei) AS document_line_item,
        TRIM(gjahr) AS fiscal_year,
        TRIM(zekkn) AS account_assignment_sequence,
        budat AS posting_date,
        menge AS quantity,
        dmbtr AS amount_local_currency,
        wrbtr AS amount_document_currency,
        TRIM(waers) AS currency_key,
        TRIM(shkzg) AS debit_credit_indicator,
        TRIM(lfbnr) AS reference_document_number,
        TRIM(lfpos) AS reference_document_item,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source
    WHERE TRIM(vgabe) IN ('1', '2')
        AND TRIM(shkzg) = 'S'
)

SELECT * FROM cleaned