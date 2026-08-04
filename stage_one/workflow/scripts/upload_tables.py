#######
# Script purpose: to upload PID mapping and survey periods data tables to BigQuery
# Inputs: CSV files containing PID mapping and survey periods data
# Methods: uploads tables to BigQuery using the BigQuery client library
# Outputs: none
#######

### Dependencies
from google.cloud import bigquery
import pandas as pd

### Load CSV files
pid_mapping = pd.read_csv(snakemake.input[0])
periods = pd.read_csv(snakemake.input[1])

### Initialise BigQuery client
client = bigquery.Client()

### Upload tables to BigQuery
# PID mappings
pid_mapping.to_gbq(
    destination_table = '[REDACTED]', 
    project_id = '[REDACTED]', 
    if_exists = 'fail'
)

# Survey periods
periods.to_gbq(
    destination_table = '[REDACTED]',
    project_id = '[REDACTED]',
    if_exists = 'fail'
)