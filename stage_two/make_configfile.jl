#######
# Script purpose: to make a list of unique participant IDs for Snakemake
# Inputs: PID mapping CSV file
# Methods: determines unique participant IDs and writes them out in YAML format
# Outputs: YAML-format config file with list of unique participant IDs
#######

using CSV, DataFrames, YAML

pid_mapping = CSV.read("resources/tm_teen_survey_pid_mapping.csv", DataFrame)

YAML.write_file("resources/configfile.yaml", Dict("participant_ids" => unique(pid_mapping.participant_id)))