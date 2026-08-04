#######
# Script purpose: to clean timestamps data and convert times to UTC
# Inputs: CSV timestamps data
# Methods: strips leading/trailing whitespaces, creates new columns with UTC times and exports new dataset
# Outputs: Cleaned timestamps data in JLD2 format
#######

### Dependencies
using CSV, DataFrames, Dates, JLD2

### Import data
timestamps = CSV.read(snakemake.input[1], DataFrame)

### Remove leading/trailing whitespaces
# Remove leading/trailing spaces from column names
rename!(timestamps, names(timestamps) .=> strip.(names(timestamps)))

# Remove leading/trailing spaces from string variables (currently including timestamps themselves)
for i in names(timestamps)
    if eltype(timestamps[!, i]) ∈ [String, Union{Missing, String}]
        timestamps[!, i] = passmissing(strip).(timestamps[!, i])
    end
end

### Drop rows without matched participant ID (=> no screenshots available)
timestamps = timestamps[.!ismissing.(timestamps.pid), :]

### Converting times to UTC
#######
# Function: convertToUTC
# Inputs: a date/time as a string
# Methods: parses string to DateTime format and adds 8 hours (non-DST) or 7 hours (DST) to convert from California time, or returns missing if not possible
# Outputs: UTC-converted date/time in DateTime format
#######
function convertToUTC(datetime)
    try
        dt = DateTime(datetime, dateformat"Y-m-d H:M:S+00:00")
        if (dt > DateTime("2021-11-07T02:00:00") && dt < DateTime("2022-03-13T02:00:00")) || dt > DateTime("2022-11-06T02:00:00")
            dt_utc = dt + Hour(8)
        else
            dt_utc = dt + Hour(7)
        end
        return dt_utc
    catch
        return missing
    end
end

# Add new columns for UTC timestamps for baseline surveys parts 1 & 2
for i in 1:2
    col = Symbol("baseline_survey_part_$(i)_timestamp")
    utcCol = Symbol("baseline_survey_part_$(i)_timestamp_utc")
    timestamps[!, utcCol] = convertToUTC.(timestamps[!, col])
end

# Add new columns for UTC timestamps for follow-up surveys 1–12
for i in 1:12
    col = Symbol("survey_$(i)_wk_$(2*i)_timestamp")
    utcCol = Symbol("survey_$(i)_wk_$(2*i)_timestamp_utc")
    timestamps[!, utcCol] = convertToUTC.(timestamps[!, col])
end

### Export data in JLD2 format
save_object(snakemake.output[1], timestamps)