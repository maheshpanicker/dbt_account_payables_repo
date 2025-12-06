# AP Analytics - Accounts Payable Data Model

A complete, production-ready dbt project for Accounts Payable analytics with 3-way match logic using Snowflake and SAP source data.

## 📋 Project Overview

This project implements a modern data stack solution for AP analytics, transforming raw SAP ERP data into actionable insights through a medallion architecture (Silver → Gold layers).

### Key Features

- **3-Way Match Logic**: Automated matching of Purchase Orders, Goods Receipts, and Invoices
- **Variance Analysis**: Calculate and classify invoice variances against PO values
- **Cycle Time Metrics**: Track processing times from PO to invoice posting
- **Data Quality Tests**: Comprehensive testing framework with dbt
- **Modular Design**: Separate staging and mart layers for maintainability

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     RAW LAYER (SAP)                         │
│  RAW_BKPF │ RAW_BSEG │ RAW_EKPO │ RAW_EKBE                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              SILVER LAYER (SLV_DATA)                        │
│  stg_sap_po_items  │  stg_sap_gr_ir_history  │             │
│  stg_sap_accounting_docs                                    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│               GOLD LAYER (GLD_DATA)                         │
│             ap_fact_invoices                                │
│         (3-Way Match + Analytics)                           │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
ap_analytics/
├── models/
│   ├── staging/
│   │   ├── schema.yml              # Source definitions & staging tests
│   │   ├── stg_sap_po_items.sql    # Purchase Order items
│   │   ├── stg_sap_gr_ir_history.sql  # Goods/Invoice receipts
│   │   └── stg_sap_accounting_docs.sql # Accounting documents
│   └── marts/
│       ├── schema.yml              # Mart model documentation & tests
│       └── ap_fact_invoices.sql    # Final fact table with 3-way match
├── dbt_project.yml                 # Project configuration
├── packages.yml                    # dbt package dependencies
└── profiles.yml                    # Snowflake connection (not in repo)
```

## 🚀 Getting Started

### Prerequisites

- Snowflake account with appropriate permissions
- Python 3.8+
- dbt-core and dbt-snowflake installed

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd ap_analytics
   ```

2. **Install dbt dependencies**
   ```bash
   pip install dbt-core dbt-snowflake
   dbt deps
   ```

3. **Set up Snowflake connection**
   
   Create `~/.dbt/profiles.yml` with your Snowflake credentials (see `profiles.yml` template)
   
   Or set environment variables:
   ```bash
   export SNOWFLAKE_ACCOUNT=xy12345.us-east-1
   export SNOWFLAKE_USER=your_username
   export SNOWFLAKE_PASSWORD=your_password
   export SNOWFLAKE_WAREHOUSE=COMPUTE_WH
   export SNOWFLAKE_DATABASE=AP_ANALYTICS
   ```

4. **Initialize Snowflake schemas and load sample data**
   
   Run the provided Snowflake DDL/DML script:
   ```sql
   -- Execute in Snowflake worksheet
   -- See: snowflake_setup.sql
   ```

5. **Run dbt models**
   ```bash
   # Run all models
   dbt run
   
   # Run with tests
   dbt build
   ```

## 🧪 Testing & Validation

Run data quality tests:

```bash
# Run all tests
dbt test

# Run tests for specific model
dbt test --select ap_fact_invoices

# Run tests for staging layer
dbt test --select staging
```

## 📊 Data Model Details

### Source Tables (SAP)

| Table | Description | Key Fields |
|-------|-------------|------------|
| **RAW_BKPF** | Accounting Document Header | BELNR, GJAHR, BUKRS |
| **RAW_BSEG** | Accounting Document Segments | BELNR, GJAHR, BUZEI, EBELN |
| **RAW_EKPO** | Purchase Order Items | EBELN, EBELP, MATNR |
| **RAW_EKBE** | PO History (GR/IR) | EBELN, EBELP, VGABE |

### Staging Models (Silver Layer - Views)

- **stg_sap_po_items**: Cleaned and standardized PO line items
- **stg_sap_gr_ir_history**: Classified GR/IR transactions with event types
- **stg_sap_accounting_docs**: Combined header and line item invoice data

### Mart Models (Gold Layer - Tables)

- **ap_fact_invoices**: Comprehensive invoice fact table with:
  - 3-way match logic (PO ↔ GR ↔ Invoice)
  - Amount variance calculations
  - Match status classification
  - Cycle time metrics
  - Complete dimensional attributes

## 🎯 Business Logic: 3-Way Match

The `ap_fact_invoices` model implements the following matching logic:

### Match Status Classifications

| Status | Criteria |
|--------|----------|
| **COMPLETE_MATCH** | PO + GR + IR all present, variance ≤ 1% |
| **MATCHED_WITH_VARIANCE** | All documents present, variance > 1% |
| **PARTIAL_MATCH** | Missing one document (GR or IR) |
| **UNMATCHED** | Missing multiple documents |

### Key Metrics

- **amount_variance**: Invoice amount minus PO net value
- **variance_percentage**: Variance as % of PO value
- **days_po_to_gr**: Cycle time from PO to goods receipt
- **days_gr_to_invoice**: Cycle time from GR to invoice posting
- **days_po_to_invoice**: Total cycle time

## 📈 Sample Queries

### Find invoices with significant variances
```sql
SELECT 
    po_number,
    vendor_number,
    material_description,
    po_net_value,
    invoice_amount,
    amount_variance,
    variance_percentage,
    match_status
FROM gld_data.ap_fact_invoices
WHERE ABS(variance_percentage) > 5
ORDER BY ABS(variance_percentage) DESC;
```

### Analyze cycle times by vendor
```sql
SELECT 
    vendor_number,
    COUNT(*) as invoice_count,
    AVG(days_po_to_invoice) as avg_total_cycle_days,
    AVG(days_po_to_gr) as avg_po_to_gr_days,
    AVG(days_gr_to_invoice) as avg_gr_to_invoice_days
FROM gld_data.ap_fact_invoices
WHERE match_status = 'COMPLETE_MATCH'
GROUP BY vendor_number
ORDER BY avg_total_cycle_days DESC;
```

### Match status summary
```sql
SELECT 
    match_status,
    COUNT(*) as invoice_count,
    SUM(invoice_amount) as total_amount,
    AVG(variance_percentage) as avg_variance_pct
FROM gld_data.ap_fact_invoices
GROUP BY match_status
ORDER BY invoice_count DESC;
```

## 🔄 Incremental Updates

To implement incremental loading for production:

1. Modify staging models to filter by date range
2. Update `ap_fact_invoices` materialization to `incremental`
3. Add incremental logic based on `posting_date`

Example:
```sql
{{
  config(
    materialized='incremental',
    unique_key='invoice_fact_key'
  )
}}

...

{% if is_incremental() %}
WHERE ad.posting_date >= (SELECT MAX(invoice_posting_date) FROM {{ this }})
{% endif %}
```

## 🛠️ Customization

### Adjusting Variance Tolerance

Edit the variance threshold in `ap_fact_invoices.sql`:

```sql
-- Change from 1% to your desired tolerance
AND ABS(variance_percentage) <= 5  -- 5% tolerance
```

### Adding Custom Fields

1. Add fields to staging models
2. Update schema.yml with new field documentation
3. Include in final mart model joins

## 📝 Best Practices

1. **Run tests before deploying**: Always run `dbt test` before production deployments
2. **Monitor match rates**: Track the distribution of match_status values
3. **Investigate variances**: Set up alerts for invoices with variance > threshold
4. **Document changes**: Update schema.yml when adding new fields
5. **Version control**: Use Git for all dbt code changes

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Run tests: `dbt test`
4. Submit a pull request with clear description

## 📄 License

[Your License Here]

## 🆘 Support

For questions or issues:
- Create an issue in the repository
- Contact the data engineering team
- Review dbt documentation: https://docs.getdbt.com

---

**Built with ❤️ using dbt and Snowflake**