{{
  config(
    materialized='view',
    tags=['staging', 'purchase_orders']
  )
}}

WITH source AS (
    SELECT * FROM {{ source('ap_sap', 'raw_ekpo') }}
),

cleaned AS (
    SELECT
        TRIM(ebeln) || '-' || TRIM(ebelp) AS po_item_key,
        TRIM(ebeln) AS po_number,
        TRIM(ebelp) AS po_item_number,
        TRIM(mandt) AS client,
        TRIM(matnr) AS material_number,
        TRIM(txz01) AS material_description,
        menge AS po_quantity,
        TRIM(meins) AS unit_of_measure,
        netpr AS net_price,
        peinh AS price_unit,
        netwr AS po_net_value,
        TRIM(werks) AS plant,
        TRIM(lifnr) AS vendor_number,
        TRIM(bstyp) AS document_category,
        TRIM(loekz) AS deletion_indicator,
        TRIM(elikz) AS delivery_completed_flag,
        CURRENT_TIMESTAMP() AS loaded_at
    FROM source
    WHERE COALESCE(TRIM(loekz), '') = ''
        AND TRIM(bstyp) = 'F'
)

SELECT * FROM cleaned