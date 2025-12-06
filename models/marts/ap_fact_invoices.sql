{{
  config(
    materialized='table',
    tags=['marts', 'invoices', '3way_match']
  )
}}

/*
    Mart Model: AP Invoice Fact Table with 3-Way Match
    
    Purpose: Create a comprehensive fact table for AP invoice analytics by performing
            a 3-way match between Purchase Orders, Goods Receipts, and Invoices
    
    Business Logic - 3-Way Match:
    1. Start with Purchase Order Items (what was ordered)
    2. Left join to Goods Receipts (what was physically received)
    3. Left join to Invoice Receipts from history (what was invoiced in EKBE)
    4. Left join to Accounting Documents (actual invoice postings)
    5. Calculate variances between PO value and invoice amount
    6. Classify match status based on document presence and variance
    
    Match Status Classification:
    - COMPLETE_MATCH: All three documents present AND variance <= 1%
    - MATCHED_WITH_VARIANCE: All three present BUT variance > 1%
    - PARTIAL_MATCH: Missing one document (either GR or invoice)
    - UNMATCHED: Missing multiple documents
    
    Key Metrics:
    - Amount variance (invoice vs PO)
    - Variance percentage
    - Cycle times (PO to GR, GR to invoice)
*/

WITH po_items AS (
    SELECT * FROM {{ ref('stg_sap_po_items') }}
),

gr_ir_history AS (
    SELECT * FROM {{ ref('stg_sap_gr_ir_history') }}
),

accounting_docs AS (
    SELECT * FROM {{ ref('stg_sap_accounting_docs') }}
),

-- Aggregate Goods Receipts by PO Item
goods_receipts AS (
    SELECT
        po_item_key,
        SUM(quantity) AS total_gr_quantity,
        SUM(amount_local_currency) AS total_gr_amount,
        MIN(posting_date) AS first_gr_date,
        MAX(posting_date) AS latest_gr_date
    FROM gr_ir_history
    WHERE transaction_type = 'GOODS_RECEIPT'
    GROUP BY po_item_key
),

-- Aggregate Invoice Receipts by PO Item (from EKBE history)
invoice_receipts AS (
    SELECT
        po_item_key,
        SUM(quantity) AS total_ir_quantity,
        SUM(amount_local_currency) AS total_ir_amount,
        MIN(posting_date) AS first_ir_date,
        MAX(posting_date) AS latest_ir_date
    FROM gr_ir_history
    WHERE transaction_type = 'INVOICE_RECEIPT'
    GROUP BY po_item_key
),

-- Get earliest PO creation date (using GR date as proxy if available)
po_dates AS (
    SELECT
        po.po_item_key,
        COALESCE(gr.first_gr_date, CURRENT_DATE()) AS po_reference_date
    FROM po_items po
    LEFT JOIN goods_receipts gr ON po.po_item_key = gr.po_item_key
),

-- Perform 3-Way Match Join
three_way_match AS (
    SELECT
        -- Generate Surrogate Key
        MD5(CONCAT(po.po_item_key, '-', COALESCE(ad.accounting_doc_key, 'NULL'))) AS invoice_fact_key,
        
        -- Purchase Order Dimensions
        po.po_item_key,
        po.po_number,
        po.po_item_number,
        po.vendor_number,
        po.material_number,
        po.material_description,
        po.plant,
        
        -- Purchase Order Metrics
        po.po_quantity,
        po.unit_of_measure,
        po.po_net_value,
        
        -- Goods Receipt Metrics
        gr.total_gr_quantity AS gr_quantity,
        gr.total_gr_amount AS gr_amount,
        gr.first_gr_date AS gr_posting_date,
        
        -- Invoice Receipt Metrics (from history table)
        ir.total_ir_quantity AS ir_quantity,
        ir.total_ir_amount AS ir_amount,
        ir.first_ir_date AS ir_posting_date,
        
        -- Accounting Document Metrics (actual invoice)
        ad.invoice_amount_local AS invoice_amount,
        ad.accounting_doc_number AS invoice_document_number,
        ad.document_date AS invoice_date,
        ad.posting_date AS invoice_posting_date,
        ad.reference_document AS reference_invoice_number,
        ad.cost_center,
        ad.tax_code,
        
        -- Calculate Variance
        COALESCE(ad.invoice_amount_local, 0) - po.po_net_value AS amount_variance,
        
        CASE 
            WHEN po.po_net_value = 0 THEN 0
            ELSE ROUND(
                ((COALESCE(ad.invoice_amount_local, 0) - po.po_net_value) / NULLIF(po.po_net_value, 0)) * 100, 
                2
            )
        END AS variance_percentage,
        
        -- Match Status Flags
        CASE WHEN gr.po_item_key IS NOT NULL THEN TRUE ELSE FALSE END AS has_goods_receipt,
        CASE WHEN ir.po_item_key IS NOT NULL THEN TRUE ELSE FALSE END AS has_invoice_receipt,
        CASE WHEN ad.po_item_key IS NOT NULL THEN TRUE ELSE FALSE END AS has_accounting_invoice,
        
        -- Calculate Cycle Times
        CASE 
            WHEN pd.po_reference_date IS NOT NULL AND gr.first_gr_date IS NOT NULL
            THEN DATEDIFF(day, pd.po_reference_date, gr.first_gr_date)
            ELSE NULL
        END AS days_po_to_gr,
        
        CASE 
            WHEN gr.first_gr_date IS NOT NULL AND ad.posting_date IS NOT NULL
            THEN DATEDIFF(day, gr.first_gr_date, ad.posting_date)
            ELSE NULL
        END AS days_gr_to_invoice,
        
        CASE 
            WHEN pd.po_reference_date IS NOT NULL AND ad.posting_date IS NOT NULL
            THEN DATEDIFF(day, pd.po_reference_date, ad.posting_date)
            ELSE NULL
        END AS days_po_to_invoice,
        
        -- Metadata
        CURRENT_TIMESTAMP() AS loaded_at
        
    FROM po_items po
    LEFT JOIN goods_receipts gr 
        ON po.po_item_key = gr.po_item_key
    LEFT JOIN invoice_receipts ir 
        ON po.po_item_key = ir.po_item_key
    LEFT JOIN accounting_docs ad 
        ON po.po_item_key = ad.po_item_key
    LEFT JOIN po_dates pd
        ON po.po_item_key = pd.po_item_key
    
    -- Only include PO items with at least an invoice
    WHERE ad.po_item_key IS NOT NULL
),

-- Classify Match Status
final AS (
    SELECT
        *,
        
        -- 3-Way Match Status Classification
        CASE
            -- Complete match: All documents present and variance within tolerance (1%)
            WHEN has_goods_receipt 
                AND has_invoice_receipt 
                AND has_accounting_invoice
                AND ABS(variance_percentage) <= 1
            THEN 'COMPLETE_MATCH'
            
            -- Matched with variance: All documents present but significant variance
            WHEN has_goods_receipt 
                AND has_invoice_receipt 
                AND has_accounting_invoice
                AND ABS(variance_percentage) > 1
            THEN 'MATCHED_WITH_VARIANCE'
            
            -- Partial match: Missing one document
            WHEN (has_goods_receipt AND has_accounting_invoice AND NOT has_invoice_receipt)
                OR (has_invoice_receipt AND has_accounting_invoice AND NOT has_goods_receipt)
                OR (has_goods_receipt AND has_invoice_receipt AND NOT has_accounting_invoice)
            THEN 'PARTIAL_MATCH'
            
            -- Unmatched: Missing multiple documents
            ELSE 'UNMATCHED'
        END AS match_status
        
    FROM three_way_match
)

SELECT * FROM final