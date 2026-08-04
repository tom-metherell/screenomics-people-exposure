#######
# Script purpose: to identify hours of screenshot data to be included based on derived missingness across survey periods and return these as tables with the relevant UTC offsets
# Inputs: CSV-format survey timestamps, timezone information, participant ID mapping and raw missingness data for each participant
# Methods: joins timezone information to survey timestamps, then iterates through each participant and survey period to identify hours with at least 4 days with at least 15 minutes of non-missing data in that survey period for that participant, marking these hours as non-missing in the output tables
# Outputs: CSV-format period-wise summary and hour-wise details of derived screenshot missingness with timezone information
#######

### Dependencies
using CSV, DataFrames, Dates

### Import data
timestamps = CSV.read(snakemake.input[1], DataFrame)
timezones = CSV.read(snakemake.input[2], DataFrame)
pid_mapping = CSV.read(snakemake.input[3], DataFrame)

### Temporarily remove screenshot PIDs to avoid duplication of computationally intensive missingness derivation for these participants; also remove unneeded California-time timestamps
missings_summary = select(timestamps, Not(:recordid0101, :family_id, :pid, r"_timestamp$"))
missings_summary = unique(missings_summary)

### Join timezone information to survey timestamps
## Join datasets
missings_summary = leftjoin(missings_summary, timezones, on = :participant_id)
missings_summary = select(missings_summary, Not(:redcap_id))

## Map timezones to their respective UTC offsets for winter and summer
timezone_mapping = (
    ("America/Chicago", 6, 5),
    ("America/Los_Angeles", 8, 7),
    ("America/New_York", 5, 4),
    ("America/Indiana/Indianapolis", 5, 4),
    ("America/Denver", 7, 6),
    ("America/Detroit", 5, 4),
    ("America/Boise", 7, 6),
    ("America/Phoenix", 7, 7) # Note lack of DST!
)
missings_summary.winter_offset = Vector{Int}(undef, nrow(missings_summary))
missings_summary.summer_offset = Vector{Int}(undef, nrow(missings_summary))
for i in 1:nrow(missings_summary)
    missings_summary.winter_offset[i] = timezone_mapping[findfirst(x -> x[1] == missings_summary.TimeZone[i], timezone_mapping)][2]
    missings_summary.summer_offset[i] = timezone_mapping[findfirst(x -> x[1] == missings_summary.TimeZone[i], timezone_mapping)][3]
end

### Convert date/time strings to DateTime objects
for i in names(missings_summary[!, Not(:participant_id, :TimeZone, :winter_offset, :summer_offset)])
    missings_summary[!, i] = passmissing(DateTime).(missings_summary[!, i], dateformat"yyyy-mm-dd HH:MM:SS")
end

### Rename baseline survey timestamp for easier iteration in missingness derivation
rename!(missings_summary, :baseline_survey_part_2_timestamp_local => :survey_0_wk_0_timestamp_local)

### Derive missingness for each hour of each survey period for each participant, marking, in separate tables:
### - hours with at least 4 days with at least 15 minutes of non-missing data in that survey period for that participant as non-missing
### - individual hours with at least 15 minutes of non-missing data for that participant as non-missing
## In missingness summary: initialize columns to be filled with missingness information
for j in 1:12
    for k in 0:23
        missings_summary[!, Symbol("ismissing_$(j)_$(lpad(string(k), 2, '0'))")] = Vector{Union{Bool, Missing}}(undef, nrow(missings_summary))
    end
    missings_summary[!, Symbol("ismissing_period_$(j)")] = Vector{Union{Bool, Missing}}(undef, nrow(missings_summary))
end

## Initialise new table for detailed per-hour missingness information
missings_detail = DataFrame(participant_id = Int[], period = Int[], hour = Int[], start_time_local = DateTime[], end_time_local = DateTime[], ismissing = Bool[])

## Initialise new table for table of missing intervals listed sequentially for each participant
missing_intervals = DataFrame(status_session = Int[], start_time_gmt = DateTime[], end_time_gmt = DateTime[], start_time_local = DateTime[], end_time_local = DateTime[], start_time_local_cleaned = DateTime[], end_time_local_cleaned = DateTime[], label = String[], missing_reason = String[], duration_status_session_cleaned = Int[], pid = Int[], start_time_utc_cleaned = DateTime[], end_time_utc_cleaned = DateTime[])

## Iterate through each participant and survey period to derive missingness
for i in unique(missings_summary.participant_id)
    # Iterate through surveys to fill in missing timestamps as precisely (survey number * 2) weeks after baseline survey part 1 (or if missing the week 2 survey)
    if ismissing(only(missings_summary[missings_summary.participant_id .== i, Symbol("baseline_survey_part_1_timestamp_local")]))
        missings_summary[missings_summary.participant_id .== i, :baseline_survey_part_1_timestamp_local] .= only(missings_summary[missings_summary.participant_id .== i, :survey_1_wk_2_timestamp_local]) - Week(2)
    end

    for j in 0:12
        if ismissing(only(missings_summary[missings_summary.participant_id .== i, Symbol("survey_$(j)_wk_$(2*j)_timestamp_local")])) 
            if !ismissing(only(missings_summary[missings_summary.participant_id .== i, :baseline_survey_part_1_timestamp_local]))
                missings_summary[missings_summary.participant_id .== i, Symbol("survey_$(j)_wk_$(2*j)_timestamp_local")] .= only(missings_summary[missings_summary.participant_id .== i, :baseline_survey_part_1_timestamp_local]) + Week(2*j)
            end
        end        
    end

    # Load missingness data; for participants where these are not available, mark all hours as missing and skip to the next participant
    # missingness_file_idx = findfirst(x -> occursin("missing_categories_$(i).csv", x), snakemake.input)
    missingness_file_idx = findfirst(x -> occursin("missing_categories_$(i).csv", x), readdir("resources/missingness"))
    if isnothing(missingness_file_idx)
        for j in 1:12
            for k in 0:23
                missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_$(j)_$(lpad(string(k), 2, '0'))")] .= true
            end
            missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_period_$(j)")] .= true
        end
        continue
    end
    # missingness = CSV.read(snakemake.input[missingness_file_idx], DataFrame)
    missingness = CSV.read("resources/missingness/$(readdir("resources/missingness")[missingness_file_idx])", DataFrame)

    # Convert date/time strings to DateTime objects
    for j in [:start_time_gmt, :end_time_gmt, :start_time_local, :end_time_local, :start_time_local_cleaned, :end_time_local_cleaned]
        missingness[!, j] = DateTime.(missingness[!, j], dateformat"yyyy-mm-dd HH:MM:SS")
    end

    # Create UTC version of cleaned times
    missingness.start_time_utc_cleaned = missingness.start_time_local_cleaned .+ (missingness.start_time_gmt .- missingness.start_time_local)
    missingness.end_time_utc_cleaned = missingness.end_time_local_cleaned .+ (missingness.end_time_gmt .- missingness.end_time_local)

    # Append missing intervals to the table of missing intervals
    append!(missing_intervals, missingness[missingness.label .== "Missing", :])

    # Iterate through each survey period for the participant to derive missingness for each hour of that survey period
    for j in 1:12
        # Identify start and end of survey period
        period_start = only(missings_summary[missings_summary.participant_id .== i, Symbol("survey_$(j-1)_wk_$(2*(j-1))_timestamp_local")])
        period_end = only(missings_summary[missings_summary.participant_id .== i, Symbol("survey_$(j)_wk_$(2*j)_timestamp_local")])

        # If survey dates are still missing, it means there are none available for that participant at all, therefore mark all hours missing and continue
        if ismissing(period_start) || ismissing(period_end)
            for k in 0:23
                missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_$(j)_$(lpad(string(k), 2, '0'))")] .= true
            end
            missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_period_$(j)")] .= true
            continue
        end

        # Subset missingness data to the survey period; if no missingness data are available for that survey period, mark all hours as missing and skip to the next survey period
        period_missingness = missingness[(missingness.end_time_local_cleaned .≥ period_start) .&& (missingness.start_time_local_cleaned .< period_end), :]
        if nrow(period_missingness) == 0
            for k in 0:23
                missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_$(j)_$(lpad(string(k), 2, '0'))")] .= true
            end
            missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_period_$(j)")] .= true
            continue
        end

        # Initialise temporary DataFrame to store missingness information for each hour of the survey period
        missing_hours = DataFrame(date = Date[], hour = Int[], ismissing = Bool[])
        date = Date(period_start)
        hour = Dates.hour(period_start)

        # Iterate through each hour of the survey period to identify hours with at least 4 days with at least 15 minutes of non-missing data in that survey period for that participant, marking these hours as non-missing in the temporary DataFrame
        while DateTime(date, Time(hour)) ≤ period_end
            current_dt = DateTime(date, Time(hour))

            # Subset missingness data to the current hour
            hour_missingness = period_missingness[(period_missingness.end_time_local_cleaned .≥ current_dt) .&& (period_missingness.start_time_local_cleaned .< current_dt + Hour(1)), :]
            
            # Initialise counter of non-missing seconds in the current hour; if there are any missingness data for the current hour, iterate through these to calculate the number of non-missing seconds in the current hour
            nonmissing_secs = Dates.Second(0)
            if nrow(hour_missingness) > 0
                for row in eachrow(hour_missingness)
                    if row.label != "Missing"
                        nonmissing_secs += Dates.Second(minimum([row.end_time_local_cleaned, current_dt + Hour(1), period_end]) - maximum([row.start_time_local_cleaned, current_dt, period_start]))
                    end
                end
            end

            # If there are at least 15 minutes (900 seconds) of non-missing data in the current hour, mark this hour as non-missing in the temporary DataFrame; otherwise, mark it as missing
            if nonmissing_secs ≥ Dates.Second(900) 
                push!(missing_hours, (date, hour, false))
                push!(missings_detail, (i, j, hour, maximum([current_dt, period_start]), minimum([current_dt + Hour(1), period_end]), false))
            else
                push!(missing_hours, (date, hour, true))
                push!(missings_detail, (i, j, hour, maximum([current_dt, period_start]), minimum([current_dt + Hour(1), period_end]), true))
            end
            if hour == 23
                date += Day(1)
                hour = 0
            else
                hour += 1
            end
        end

        # Iterate through each hour of the day to identify hours with at least 4 days with at least 15 minutes of non-missing data in that survey period for that participant, marking these hours as non-missing in the output table
        for k in 0:23
            missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_$(j)_$(lpad(string(k), 2, '0'))")] .= sum(.!missing_hours[missing_hours.hour .== k, :ismissing]) < 4
        end

        # Mark periods as missing if there are fewer than 6 (25%) hours not treated as missing
        if sum(Matrix(missings_summary[missings_summary.participant_id .== i, Regex("ismissing_$(j)_")])) > 18
            missings_summary[missings_summary.participant_id .== i, "ismissing_period_$(j)"] .= true
        else
            missings_summary[missings_summary.participant_id .== i, "ismissing_period_$(j)"] .= false
        end
    end
end

### Disallow missing values in missingness indicators (there should be none)
disallowmissing!(missings_summary[!, Cols(r"ismissing")])

### Join participant ID mapping and timezone offsets to the detailed missingness table
missings_detail = leftjoin(missings_detail, select(missings_summary, Cols(:participant_id, :TimeZone, :winter_offset, :summer_offset)), on = :participant_id)
missings_detail = leftjoin(missings_detail, pid_mapping, on = :participant_id)

### Add UTC start/end times to detailed missingness table
for i in ["start_time", "end_time"]
    missings_detail[!, Symbol("$(i)_utc")] = map(eachrow(missings_detail)) do row
        let dt = row[Symbol("$(i)_local")]
            if (dt > DateTime("2021-11-07T02:00:00") && dt < DateTime("2022-03-13T02:00:00")) || dt > DateTime("2022-11-06T02:00:00")
                dt + Hour(row.winter_offset)
            else
                dt + Hour(row.summer_offset)
            end
        end
    end
end

### Rename pid to participant_id in missing intervals table for consistency
rename!(missing_intervals, :pid => :participant_id)

### Remove unneeded columns from missing intervals table
missing_intervals = select(missing_intervals, Cols(:participant_id, :start_time_utc_cleaned, :end_time_utc_cleaned, :start_time_local_cleaned, :end_time_local_cleaned))

### Write output table with derived missingness information and timezone information to CSV
CSV.write(snakemake.output[1], missings_summary)
CSV.write(snakemake.output[2], missings_detail)
CSV.write(snakemake.output[3], missing_intervals)