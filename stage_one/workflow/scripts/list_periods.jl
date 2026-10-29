#######
# Script purpose: to create a list of periods between surveys for all participants
# Inputs: timestamps data in JLD2 format
# Methods: creates new long-format dataset with one row per participant and inter-survey period, detailing the start and end timestamps
# Outputs: long-format inter-survey periods dataset in JLD2 format
#######

### Dependencies
using CSV, DataFrames, Dates, JLD2

### Load timestamps data
timestamps = load_object(snakemake.input[1])

### Was needed for CSV format input: strip leading/trailing whitespaces
#=
rename!(timestamps, names(timestamps) .=> strip.(names(timestamps)))
for i in names(timestamps)
    if eltype(timestamps[!, i]) <: AbstractString || eltype(timestamps[!, i]) <: Union{Missing, AbstractString}
        timestamps[!, i] = passmissing(strip).(timestamps[!, i])
        timestamps[!, i] = replace(timestamps[!, i], "" => missing)
    end
end
=#

### Initialise new (empty) dataset
periods = DataFrame(participant_id = repeat(unique(timestamps.participant_id), inner = 12),
                    pids = Vector{Vector{String}}(undef, 12 * length(unique(timestamps.participant_id))),
                    period_id = repeat(1:12, outer = length(unique(timestamps.participant_id))),
                    period_start = Vector{Union{Missing, DateTime}}(undef, 12 * length(unique(timestamps.participant_id))),
                    period_end = Vector{Union{Missing, DateTime}}(undef, 12 * length(unique(timestamps.participant_id))))

### Pass all matched app PIDs for each participant into a single vector for each row
periods.pids = [Vector{String}(timestamps.pid[timestamps.participant_id .== i]) for i in periods.participant_id]

### Identify start/end survey timepoints for each inter-survey period
# Starts for period 1 (from baseline survey part 2 to survey 1)
periods.period_start[periods.period_id .== 1] = passmissing(DateTime).([timestamps[findfirst(timestamps.participant_id .== i), :baseline_survey_part_2_timestamp_utc] for i in periods[periods.period_id .== 1, :participant_id]])
# Starts for periods 2–12
periods.period_start[periods.period_id .!= 1] = passmissing(DateTime).([timestamps[findfirst(timestamps.participant_id .== i), Symbol("survey_$(j)_wk_$(2*j)_timestamp_utc")] for i in unique(periods.participant_id) for j in 1:11])
# Ends for all periods
periods.period_end = passmissing(DateTime).([timestamps[findfirst(timestamps.participant_id .== i), Symbol("survey_$(j)_wk_$(2*j)_timestamp_utc")] for i in unique(periods.participant_id) for j in 1:12])

### Put dataset in useful formats
# Mapping table between survey IDs and app IDs
pid_mapping = unique(periods[:, [:participant_id, :pids]])
pid_mapping = flatten(pid_mapping, :pids)
rename!(pid_mapping, :pids => :pid)

# Period start/end times with survey IDs (only one per participant)
periods_canonical = periods[:, [:participant_id, :period_id, :period_start, :period_end]]

### Export datasets in CSV format
CSV.write(snakemake.output[1], pid_mapping)
CSV.write(snakemake.output[2], periods_canonical)