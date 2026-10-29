#######
# Script purpose: to retrieve survey timestamps data from BigQuery
# Inputs: none
# Methods: runs SQL query
# Outputs: timestamps data in CSV format
#######

### Dependencies
from google.cloud import bigquery
import pandas as pd

### Run SQL query
# Initialise BigQuery client
client = bigquery.Client()

# Query timestamps data
timestamps = client.query(f"""SELECT * FROM `[REDACTED]`;""").to_dataframe()

### Export to CSV
timestamps.to_csv(snakemake.output[0], index = False)