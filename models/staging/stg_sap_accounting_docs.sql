{{
  config(
    materialized='view',
    tags=['staging', 'accounting', 'invoices']
  )
}}

WITH header AS (
    SELECT * FROM {{ source('ap_sap', 'raw_bkpf') }}
),

line_items AS (
    SELECT * FROM {{ source('ap_sap', 'raw_bseg') }}
),

combined AS (
    SELECT
        TRIM(li.belnr) || '-' || TRIM(li.gjahr) || '-' || TRIM(li.buzei) AS accounting_doc_key,
        TRIM(li.belnr) AS accounting_doc_number,
        TRIM(li.gjahr) AS fiscal_year,
        TRIM(li.buzei) AS line_item,
        TRIM(li.bukrs) AS company_code,
        TRIM(li.mandt) AS client,
        CASE 
            WHEN TRIM(li.ebeln) IS NOT NULL AND TRIM(li.ebelp) IS NOT NULL
            THEN TRIM(li.ebeln) || '-' || TRIM(li.ebelp)
            ELSE NULL
        END AS po_item_key,
        TRIM(li.ebeln) AS po_number,
        TRIM(li.ebelp) AS po_item_number,
        TRIM(li.lifnr) AS vendor_number,
        TRIM(hdr.blart) AS document_type,
        hdr.bldat AS document_date,
        hdr.budat AS posting_date,
        TRIM(hdr.waers) AS currency_key,
        TRIM(hdr.xblnr) AS reference_document,
        TRIM(hdr.usnam) AS user_name,
        TRIM(hdr.tcode) AS transaction_code,
        TRIM(li.koart) AS account_type,
        TRIM(li.shkzg) AS debit_credit_indicator,
        li.dmbtr AS invoice_amount_local,
        li.wrbtr AS invoice_amount_document,
        TRIM(li.mwskz) AS tax_code,
        TRIM(li.matnr) AS material_number,
        TRIM(li.werks) AS plant,
        TRIM(li.kostl) AS cost_center,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM line_items li
    LEFT JOIN header hdr
        ON li.belnr = hdr.belnr
        AND li.gjahr = hdr.gjahr
        AND li.bukrs = hdr.bukrs
        AND li.mandt = hdr.mandt
    WHERE TRIM(li.koart) = 'K'
        AND TRIM(li.shkzg) = 'H'
        AND TRIM(hdr.blart) = 'RE'
)

SELECT * FROM combined