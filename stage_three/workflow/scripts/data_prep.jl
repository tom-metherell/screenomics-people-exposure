#######
# Script purpose: to prepare an analysis dataset by joining object detection summary statistics to survey data
# Inputs: CSV object detection summary statistics and survey data (adolescent and parent datasets)
# Methods: creates a new dataframe by pivoting relevant survey variables to long format, then joins with object detection summary statistics in both "mental health before" and "mental health after" formats
# Outputs: CSV initial analysis datasets for "mental health before" and "mental health after" formats
#######

### Dependencies
using Pkg; Pkg.activate(".")
using CategoricalArrays, CSV, DataFrames, JLD2, Statistics

### Import data
bout_statistics = CSV.read(snakemake.input[1], DataFrame)
sens_wd_bout_statistics = CSV.read(snakemake.input[2], DataFrame)
sens_we_bout_statistics = CSV.read(snakemake.input[3], DataFrame) # Weekday- and weekend-only bout statistics for sensitivity analyses
sens_conf_bout_statistics = CSV.read(snakemake.input[4], DataFrame) # Bout statistics without requirement for >0.7 confidence in people detection
adol_data = CSV.read(snakemake.input[5], DataFrame)
parent_data = CSV.read(snakemake.input[6], DataFrame)
missings_summary = CSV.read(snakemake.input[7], DataFrame)

### Define dictionaries mapping variables to their dynamic column name patterns
## Adolescent data
ad_column_patterns = Dict(
    # Mental health variables
    :ccdis08 => i -> string("ccdis08", lpad(string(i), 2, "0")),
    :ccdisavg_re75 => i -> string("ccdisavg", lpad(string(i), 2, "0"), "_re75"),
    :canxiavg_re75 => i -> string("canxiavg", lpad(string(i), 2, "0"), "_re75"),
    :cposafavg_re75 => i -> string("cposafavg", lpad(string(i), 2, "0"), "_re75"),
    :cstrsavg_re75 => i -> string("cstrsavg", lpad(string(i), 2, "0"), "_re75"),
    :cwgtconavg_re75 => i -> string("cwgtconavg", lpad(string(i), 2, "0"), "_re75"),

    # Time-invariant covariates
    :cageyrs01 => i -> "cageyrs01", # Age
    :cgenderfirst => i -> "cgenderfirst", # Gender
    [Symbol("crace", j, "first") => i -> string("crace", j, "first") for j in vcat(1:6, 99)]..., # Ethnicity
    :csbnum01 => i -> "csbnum01", # Number of siblings

    # Time-varying covariates
    [Symbol("cp", j, "warmavg_re75") => i -> string("cp", j, "warmavg", lpad(string(i), 2, "0"), "_re75") for j in 1:4]..., # Parental warmth
    [Symbol("cp", j, "conf", k) => i -> string("cp", j, "conf", k, lpad(string(i), 2, "0")) for k in 1:9 for j in 1:4]..., # Parental conflicts
    [Symbol("cadd", j) => i -> string("cadd", j, lpad(string(i), 2, "0")) for j in ["sm", "ph"]]..., # Perceived addiction to social media/smartphone
    :chealth => i -> string("chealth", lpad(string(i), 2, "0")), # General health
    [Symbol("ccovbeh", j) => i -> string("ccovbeh", j, lpad(string(i), 2, "0")) for j in 2:5]..., # Physical distancing observance
    [Symbol("ccovtest", j) => i -> string("ccovtest", j, lpad(string(i), 2, "0")) for j in ["", "db", "r"]]..., # COVID-19 testing history
    :ccvmdef01 => i -> string("ccvmdef01", lpad(string(i), 2, "0")), # Fear related to COVID-19 in media
    :cpsqiscore => i -> string("cpsqiscore", lpad(string(i), 2, "0")), # Sleep quality
    :cmodexe => i -> string("cmodexe", lpad(string(i), 2, "0")), # Physical exercise
    [Symbol("ccyb", j, "wk") => i -> string("ccyb", j, "wk", lpad(string(i), 2, "0")) for j in [2, 4]]..., # Cyberbullying victimisation
    [Symbol("csubs", j, "wk", k) => i -> string("csubs", j, "wk", k, lpad(string(i), 2, "0")) for k in 1:6 for j in [2, 4]]..., # Drinking/smoking/substance use
    [Symbol("csch", j) => i -> string("csch", j, lpad(string(i), 2, "0")) for j in ["ftf", "onli"]]... # School attendance
)

## Parent data
pa_column_patterns = Dict(
    # Time-invariant covariates (in all cases asked until answered)
    [Symbol("p", j, "educ") => i -> string("p", j, "educ", lpad(string(i), 2, "0")) for j in ["", "s"]]..., # Parental education
    :phhinc => i -> string("phhinc", lpad(string(i), 2, "0")), # Household income
    :psnap => i -> string("psnap", lpad(string(i), 2, "0")), # Use of SNAP/EBT etc.

    # Time-varying covariates
    [Symbol("p", j) => i -> string("p", j, lpad(string(i), 2, "0")) for j in ["empl", "sempl", "essent", "sessent"]]..., # Parental employment
    [Symbol("padd", j) => i -> string("padd", j, lpad(string(i), 2, "0")) for j in ["ph", "sm"]]..., # Perceived parental addiction to social media/smartphone
    :psaddph => i -> string("psaddph", lpad(string(i), 2, "0")), # Perceived spousal addiction to smartphone
    :phealth => i -> string("phealth", lpad(string(i), 2, "0")), # General health
    [Symbol("pcovtest", j) => i -> string("pcovtest", j, lpad(string(i), 2, "0")) for j in ["", "db", "r"]]..., # COVID-19 testing history
    :pcvmdef01 => i -> string("pcvmdef01", lpad(string(i), 2, "0")), # Fear related to COVID-19 in media
    :pcesd09 => i -> string("pcesd09", lpad(string(i), 2, "0")), # Loneliness
    :pcesdavg_re75 => i -> string("pcesdavg", lpad(string(i), 2, "0"), "_re75"), # Depression
    :panxiavg_re75 => i -> string("panxiavg", lpad(string(i), 2, "0"), "_re75"), # Anxiety
    [Symbol("pposaf", j) => i -> string("pposaf", j, lpad(string(i), 2, "0")) for j in string.(lpad.(1:11, 2, "0"))]..., # Perceived social support
    [Symbol("pstrs", j) => i -> string("pstrs", j, lpad(string(i), 2, "0")) for j in 1:4]..., # Perceived stress
    [Symbol("psubs", j) => i -> string("psubs", j, lpad(string(i), 2, "0")) for j in 1:3]... # Drinking/smoking/substance use
)

### Create pivoted dataset
## Initialise the DataFrame for the pivoted data
adol_data_pivot = DataFrame(
    participant_id = repeat(adol_data.participant_id, inner = 13),
    family_id = repeat(adol_data.family_id, inner = 13),
    timepoint = repeat(1:13, outer = nrow(adol_data))
)

## Populate the pivoted DataFrame dynamically based on the column patterns
for (measure, pattern_func) in ad_column_patterns
    avail_col = pattern_func(findfirst(col_name -> col_name ∈ names(adol_data), [pattern_func(i) for i in 1:13]))
    adol_data_pivot[!, measure] = Vector{Union{Missing, eltype(adol_data[!, avail_col])}}(undef, nrow(adol_data_pivot))
    for i in 1:13
        col_name = pattern_func(i)
        if col_name ∈ names(adol_data)
            # Check for and resolve type incompatibility between float and integer
            if nonmissingtype(eltype(adol_data[!, col_name])) <: Float64 && nonmissingtype(eltype(adol_data_pivot[!, measure])) <: Int
                adol_data_pivot[!, measure] = convert.(Union{Missing, Float64}, adol_data_pivot[!, measure])
            end
            adol_data_pivot[adol_data_pivot.timepoint .== i, measure] = adol_data[!, col_name]
        else
            adol_data_pivot[adol_data_pivot.timepoint .== i, measure] .= missing
        end
    end
end

## Repeat the same process for the parent data
parent_data_pivot = DataFrame(
    participant_id = repeat(parent_data.participant_id, inner = 13),
    family_id = repeat(parent_data.family_id, inner = 13),
    timepoint = repeat(1:13, outer = nrow(parent_data))
)

for (measure, pattern_func) in pa_column_patterns
    avail_col = pattern_func(findfirst(col_name -> col_name ∈ names(parent_data), [pattern_func(i) for i in 1:13]))
    parent_data_pivot[!, measure] = Vector{Union{Missing, eltype(parent_data[!, avail_col])}}(undef, nrow(parent_data_pivot))
    for i in 1:13
        col_name = pattern_func(i)
        if col_name ∈ names(parent_data)
            parent_data_pivot[parent_data_pivot.timepoint .== i, measure] = parent_data[!, col_name]
        else
            parent_data_pivot[parent_data_pivot.timepoint .== i, measure] .= missing
        end
    end
end

## Recode values indicating refusals/don't know to missing
replace!(parent_data_pivot.phhinc, 88 => missing, 99 => missing)

### Merge adolescent variables
## Standard operations
ad_merge_table = (
    (:dv_cpwarm, [Symbol("cp", j, "warmavg_re75") for j in 1:4], i -> all(ismissing.(Vector(i))) ? missing : mean(skipmissing(i))), # Parental warmth: average across parents
    (:dv_cpconf5, [Symbol("cp", j, "conf5") for j in 1:4], i -> all(ismissing.(Vector(i))) ? missing : mean(skipmissing(i))), # Parental conflict about devices: average across parents
    (
        :dv_cpconf,
        [Symbol("cp", j, "conf", k) for k in vcat(1:4, 6:9) for j in 1:4],
        i -> all(ismissing.(Vector(i))) ? missing : mean(skipmissing([all(ismissing.(Vector(i[j:4:end]))) ? missing : mean(skipmissing(i[j:4:end])) for j in 1:4]))
    ), # Parental conflict (excl. about devices): average across conflict items within parent, then across parents
    (:dv_covbeh, [Symbol("ccovbeh", j) for j in 2:5], i -> all(ismissing.(Vector(i))) ? missing : mean(skipmissing(i))), # Physical distancing observance: average across behaviours
)

for entry in ad_merge_table
    measure, cols, merge_func = entry
    adol_data_pivot[!, measure] = map(eachrow(adol_data_pivot)) do row
        merge_func(row[cols])
    end
    select!(adol_data_pivot, Not(cols))
end

## More complex logic
# Loneliness: make binary
adol_data_pivot.ccdis08 = map(eachrow(adol_data_pivot)) do row
    if coalesce(row.ccdis08 == 2, false)
        1
    else 
        row.ccdis08
    end
end

# Gender: make categorical
adol_data_pivot.cgenderfirst = categorical(adol_data_pivot.cgenderfirst, ordered = false)

# Race variables
race_map = [
    (:crace1first, "American Indian or Alaskan Native"),
    (:crace2first, "Asian"),
    (:crace3first, "Black or African American"),
    (:crace4first, "Hispanic or Latino"),
    (:crace5first, "Native Hawaiian or Pacific Islander"),
    (:crace6first, "White"),
    (:crace99first, "Other")
]

adol_data_pivot[!, :dv_race] = map(eachrow(adol_data_pivot)) do row
    race_count = sum(skipmissing((row[col] for (col, _) in race_map)); init = 0)
    if race_count > 1
        "Multiple"
    else
        idx = findfirst(t -> coalesce(row[t[1]] == 1, false), race_map)
        isnothing(idx) ? missing : race_map[idx][2]
    end
end

# COVID-19 caseness
adol_data_pivot[!, :dv_covcase] = map(eachrow(adol_data_pivot)) do row
    if coalesce(row[:ccovtestr] == 1, false) && coalesce(row[:ccovtestdb] ≤ 14, false) && coalesce(row[:ccovtestdb] > -1, true) # Reject negative "days before" values (outside a margin of error) as clearly wrong
        1
    elseif !ismissing(row[:ccovtest]) && coalesce(row[:ccovtestdb] > -1, true)
        0
    else
        missing
    end
end

# Cyberbullying - because of variable question schedule, widen resolution to 4 weeks
adol_data_pivot[!, :ccyb4wk] = [let
    row = adol_data_pivot[i, :]
    ppt = row.participant_id
    tp = row.timepoint
    prevrow = tp ≠ 1 ? adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp - 1, :] : nothing
    nextrow = tp ≠ 13 ? adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp + 1, :] : nothing

    if !ismissing(row.ccyb4wk)
        row.ccyb4wk
    else
        if coalesce(row.ccyb2wk == 1, false)
            1
        elseif coalesce(row.ccyb2wk == 0, false)
            if !isnothing(prevrow) && coalesce(only(prevrow.ccyb2wk) == 1, false)
                1
            elseif !isnothing(prevrow) && (coalesce(only(prevrow.ccyb2wk) == 0, false) || coalesce(only(prevrow.ccyb4wk) == 0, false))
                0
            else
                missing
            end
        elseif !isnothing(nextrow) && !isnothing(prevrow) && (coalesce(only(prevrow.ccyb4wk) == 0, false) || coalesce(only(prevrow.ccyb2wk) == 0, false)) && coalesce(only(nextrow.ccyb4wk) == 0, false)
            0
        else
            if !isnothing(prevrow) && coalesce(only(prevrow.ccyb2wk) == 1, false)
                1
            else
                missing
            end
        end
    end
end for i in axes(adol_data_pivot, 1)]

# Substance use - divide into 3 variables (alcohol, tobacco, cannabis) and merge 2/4-weekly variables
# Map response options to continuous variable (per YRBS guidelines)
twowk_freq_map = Dict(
    1 => 0,
    2 => 0.75,
    3 => 2,
    4 => 3.75,
    5 => 5.75,
    6 => 7,
    7 => 14,
    8 => missing, # Isolated examples of this undefined value
    missing => missing
)

fourwk_freq_map = Dict(
    [k => 0 for k in 1:3]...,
    4 => 0.75,
    5 => 1,
    6 => 1.875,
    7 => 3.625,
    8 => 6.125,
    9 => 7,
    10 => 14,
    missing => missing
)

[adol_data_pivot[!, Symbol("csubs2wk", k, "_re")] = [twowk_freq_map[x] for x in adol_data_pivot[!, Symbol("csubs2wk", k)]] for k in 1:6]
[adol_data_pivot[!, Symbol("csubs4wk", k, "_re")] = [fourwk_freq_map[x] for x in adol_data_pivot[!, Symbol("csubs4wk", k)]] for k in 1:6]

# Derive variables
adol_data_pivot[!, :dv_calc] = Vector{Union{Missing, Float64}}(undef, nrow(adol_data_pivot))
adol_data_pivot[!, :dv_csmoke] = Vector{Union{Missing, Float64}}(undef, nrow(adol_data_pivot))
adol_data_pivot[!, :dv_ccan] = Vector{Union{Missing, Float64}}(undef, nrow(adol_data_pivot))

for ppt in unique(adol_data_pivot.participant_id)
    adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== 1, :dv_calc] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== 1, :csubs2wk5_re]
    adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== 1, :dv_csmoke] = [
        all(ismissing, values(row)) ? missing : maximum(skipmissing(values(row)))
        for row in eachrow(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== 1, Cols(r"^csubs2wk[1-4]_re")])
    ]
    adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== 1, :dv_ccan] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== 1, :csubs2wk6_re]

    for tp in 2:13
        if !all(ismissing.(Matrix(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, Cols(r"^csubs2wk\d_re")])))
            adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_calc] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :csubs2wk5_re]
            adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_csmoke] .= let row = only(eachrow(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, Cols(r"^csubs2wk[1-4]_re")]))
                all(ismissing, values(row)) ? missing : maximum(skipmissing(values(row)))
            end
            adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_ccan] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :csubs2wk6_re]
        end
        if tp % 2 == 0
            if all(ismissing.(Matrix(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .∈ Ref([tp, tp + 1]), Cols(:dv_calc, :dv_csmoke, :dv_ccan)])))
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .∈ Ref([tp, tp + 1]), :dv_calc] .= adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :csubs4wk5_re]
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .∈ Ref([tp, tp + 1]), :dv_csmoke] .= let row = only(eachrow(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, Cols(r"^csubs4wk[1-4]_re")]))
                    all(ismissing, values(row)) ? missing : maximum(skipmissing(values(row)))
                end
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .∈ Ref([tp, tp + 1]), :dv_ccan] .= adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :csubs4wk6_re]
            elseif all(ismissing.(Matrix(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, Cols(:dv_calc, :dv_csmoke, :dv_ccan)])))
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_calc] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :csubs4wk5_re]
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_csmoke] .= let row = only(eachrow(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, Cols(r"^csubs4wk[1-4]_re")]))
                    all(ismissing, values(row)) ? missing : maximum(skipmissing(values(row)))
                end
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_ccan] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :csubs4wk6_re]
            elseif all(ismissing.(Matrix(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp + 1, Cols(:dv_calc, :dv_csmoke, :dv_ccan)])))
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp + 1, :dv_calc] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_calc]
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp + 1, :dv_csmoke] .= let row = only(eachrow(adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, Cols(r"^csubs4wk[1-4]_re")]))
                    all(ismissing, values(row)) ? missing : maximum(skipmissing(values(row)))
                end
                adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp + 1, :dv_ccan] = adol_data_pivot[adol_data_pivot.participant_id .== ppt .&& adol_data_pivot.timepoint .== tp, :dv_ccan]
            end
        end
    end
end

## Remove unneeded columns
select!(adol_data_pivot, Not(r"^crace\d+first$", :ccyb2wk, r"^ccovtest", r"^csubs"))

### Merge parent variables
## Standard operations
pa_merge_table = (
    (:dv_paredu, [Symbol("p", j, "educ") for j in ["", "s"]], i -> all(ismissing.(Matrix(i))) ? missing : maximum(skipmissing(Matrix(i)))), # Parental education: highest across parents
    (:dv_phhinc, :phhinc, i -> all(ismissing.(Vector(i))) || length(unique(skipmissing(Vector(i)))) > 1 ? missing : only(unique(skipmissing(Vector(i))))), # Household income: reject if disagreement
    (:dv_psnap, :psnap, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Use of SNAP/EBT etc.: if any yes then yes
    (:dv_pempl, [Symbol("p", j) for j in ["empl", "sempl"]], i -> all(ismissing.(Matrix(i))) ? missing : minimum(skipmissing(Matrix(i)))), # Parental employment: greatest extent across parents
    (:dv_pessent, [Symbol("p", j) for j in ["essent", "sessent"]], i -> all(ismissing.(Matrix(i))) ? missing : maximum(skipmissing(Matrix(i)))), # Parental essential worker status: if any yes then yes
    (:dv_paddph, [Symbol("p", j) for j in ["addph", "saddph"]], i -> all(ismissing.(Matrix(i))) ? missing : maximum(skipmissing(Matrix(i)))), # Perceived spousal addiction to smartphone: if any yes then yes
    (:dv_paddsm, :paddsm, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Perceived parental addiction to smartphone: if any yes then yes
    (:dv_phealth, :phealth, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # General health: keep worst rating across parents
    (:dv_pcvmdef01, :pcvmdef01, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Fear related to COVID-19 in media: keep greatest fear across parents
    (:dv_pcesd09, :pcesd09, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Loneliness: keep greatest loneliness across parents
    (:dv_pcesdavg_re75, :pcesdavg_re75, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Depression: keep greatest depression across parents
    (:dv_panxiavg_re75, :panxiavg_re75, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Anxiety: keep greatest anxiety across parents
    (:dv_psubs1_re, :psubs1, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Tobacco use: keep maximum frequency across parents
    (:dv_psubs2_re, :psubs2, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Alcohol use: keep maximum frequency across parents
    (:dv_psubs3_re, :psubs3, i -> all(ismissing.(Vector(i))) ? missing : maximum(skipmissing(Vector(i)))), # Other substance use: keep maximum frequency across parents
)

for entry in pa_merge_table
    measure, cols, merge_func = entry
    parent_data_pivot[!, measure] = Vector{Union{Missing, eltype.(eachcol(parent_data_pivot[!, cols]))...}}(undef, nrow(parent_data_pivot))
    for i in unique(parent_data_pivot.family_id)
        for j in unique(parent_data_pivot.timepoint)
            parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, measure] .= merge_func(parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, cols])
        end
    end
    select!(parent_data_pivot, Not(cols))
end

## More complex logic
# Employment: make categorical and ordered
parent_data_pivot[!, :dv_pempl] = categorical(parent_data_pivot.dv_pempl, ordered = true)
parent_data_pivot[!, :dv_pempl] = recode(parent_data_pivot.dv_pempl, 3 => "Not working for pay", 2 => "Working part-time", 1 => "Working full-time")
levels!(parent_data_pivot.dv_pempl, ["Not working for pay", "Working part-time", "Working full-time"])

# COVID-19 caseness
parent_data_pivot[!, :dv_pcovcase] = map(eachrow(parent_data_pivot)) do row
    if coalesce(row[:pcovtestr] == 1, false) && coalesce(row[:pcovtestdb] ≤ 14, false) && coalesce(row[:pcovtestdb] > -1, true) # Reject negative "days before" values (outside a margin of error) as clearly wrong
        1
    elseif !ismissing(row[:pcovtest]) && coalesce(row[:pcovtestdb] > -1, true)
        0
    else
        missing
    end
end

for i in unique(parent_data_pivot.family_id)
    for j in unique(parent_data_pivot.timepoint)
        parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pcovcase] .= all(ismissing.(parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pcovcase])) ? missing : maximum(skipmissing(parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pcovcase]))
    end
end

# Positive affect
parent_data_pivot[!, :dv_pposafavg_re75] = map(eachrow(parent_data_pivot)) do row
    if(sum(ismissing.(Vector(row[r"^pposaf\d{2}$"])))) > 2
        missing
    else
        mean(skipmissing(row[r"^pposaf\d{2}$"]))
    end
end

for i in unique(parent_data_pivot.family_id)
    for j in unique(parent_data_pivot.timepoint)
        parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pposafavg_re75] .= all(ismissing.(parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pposafavg_re75])) ? missing : maximum(skipmissing(parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pposafavg_re75]))
    end
end

# Psychological stress
parent_data_pivot[!, :dv_pstrsavg_re75] = map(eachrow(parent_data_pivot)) do row
    if(sum(ismissing.(Vector(row[r"^pstrs\d{1}$"])))) > 1
        missing
    else
        mean(skipmissing(row[r"^pstrs\d{1}$"]))
    end
end

for i in unique(parent_data_pivot.family_id)
    for j in unique(parent_data_pivot.timepoint)
        parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pstrsavg_re75] .= all(ismissing.(parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pstrsavg_re75])) ? missing : maximum(skipmissing(parent_data_pivot[parent_data_pivot.family_id .== i .&& parent_data_pivot.timepoint .== j, :dv_pstrsavg_re75]))
    end
end

# Substance use - continuous recode (per YRBS guidelines)
pa_freq_map = Dict(
    1 => 0,
    2 => 0.5,
    3 => 1,
    4 => 4,
    5 => 6,
    6 => 7,
    7 => 17.5,
    8 => 31.5,
    missing => missing
)
for k in 1:3
    parent_data_pivot[!, Symbol("dv_psubs", k, "_re")] = Vector{Union{Missing, Float64}}([pa_freq_map[x] for x in parent_data_pivot[!, Symbol("dv_psubs", k, "_re")]])
end

## Remove unneeded columns
select!(parent_data_pivot, Not(r"^pcovtest", r"^pposaf", r"^pstrs"))

### Collapse parent data to one row per family
select!(parent_data_pivot, Not(:participant_id))
unique!(parent_data_pivot)

### Join adolescent and parent survey data
survey_data_pivot = outerjoin(adol_data_pivot, parent_data_pivot, on = [:family_id, :timepoint])

## Fill gaps in variables asked less frequently
ask_pattern = Dict(
    [k => "odd" for k in [:cschftf, :cschonli, :dv_cpwarm, :dv_cpconf5, :dv_cpconf, :dv_pempl, :dv_pessent]]..., # Asked at every odd timepoint (1, 3, 5, 7, 9, 11, 13)
    :cwgtconavg_re75 => "even", # Asked at baseline + every even timepoint (1, 2, 4, 6, 8, 10, 12)
    [k => "once" for k in [:dv_psnap, :dv_paredu, :dv_phhinc]]... # Asked until answered
)

resolution = Dict(
    :dv_phhinc => "reject",
    [k => "maximum" for k in [:dv_paredu, :dv_psnap]]...
)

for key in keys(ask_pattern)
    for ppt in unique(survey_data_pivot.participant_id)
        if ask_pattern[key] == "odd"
            for tp in 2:2:12
                if ismissing(only(survey_data_pivot[survey_data_pivot.participant_id .== ppt .&& survey_data_pivot.timepoint .== tp, key]))
                    survey_data_pivot[survey_data_pivot.participant_id .== ppt .&& survey_data_pivot.timepoint .== tp, key] = survey_data_pivot[survey_data_pivot.participant_id .== ppt .&& survey_data_pivot.timepoint .== tp - 1, key]
                end
            end
        elseif ask_pattern[key] == "even"
            for tp in 3:2:13
                if ismissing(only(survey_data_pivot[survey_data_pivot.participant_id .== ppt .&& survey_data_pivot.timepoint .== tp, key]))
                    survey_data_pivot[survey_data_pivot.participant_id .== ppt .&& survey_data_pivot.timepoint .== tp, key] = survey_data_pivot[survey_data_pivot.participant_id .== ppt .&& survey_data_pivot.timepoint .== tp - 1, key]
                end
            end
        elseif ask_pattern[key] == "once"
            survey_data_pivot[survey_data_pivot.participant_id .== ppt, key] .= (
                if all(ismissing.(Vector(survey_data_pivot[survey_data_pivot.participant_id .== ppt, key])))
                    missing
                elseif length(unique(skipmissing(survey_data_pivot[survey_data_pivot.participant_id .== ppt, key]))) > 1
                    if resolution[key] == "reject"
                        missing
                    elseif resolution[key] == "maximum"
                        maximum(skipmissing(survey_data_pivot[survey_data_pivot.participant_id .== ppt, key]))
                    end
                else
                    only(unique(skipmissing(survey_data_pivot[survey_data_pivot.participant_id .== ppt, key])))
                end
            )
        end
    end
end

### Across all bout statistics datasets
for dataset in [bout_statistics, sens_wd_bout_statistics, sens_we_bout_statistics, sens_conf_bout_statistics]
    ## Reject periods' data if missingness exceeds thresholds
    allowmissing!(dataset, Not(:participant_id, :period_id))

    for i in unique(missings_summary.participant_id)
        for j in 1:12
            if only(missings_summary[missings_summary.participant_id .== i, Symbol("ismissing_period_", j)])
                dataset[dataset.participant_id .== i .&& dataset.period_id .== j, Not(:participant_id, :period_id)] .= missing
            end
        end
    end

    ## Remove raw number of screenshots containing people, which is a function of the proportion and the total number of screenshots
    select!(dataset, Not(:n_person_screenshots))
end

### Join survey data to object detection summary statistics
## Alter timepoint indicators
# List mental health variables
mh_vars = [:ccdis08, :ccdisavg_re75, :canxiavg_re75, :cposafavg_re75, :cstrsavg_re75, :cwgtconavg_re75]

# Mental health before screenshot periods, covariates before that
mh_vars_premh = copy(survey_data_pivot[:, [:participant_id, :timepoint, mh_vars...]])
mh_vars_premh.period_id = mh_vars_premh.timepoint
covariates_premh = copy(survey_data_pivot[:, Not(mh_vars)])
covariates_premh.period_id = covariates_premh.timepoint .+ 1
select!(covariates_premh, Not(:timepoint))
survey_data_premh = outerjoin(mh_vars_premh, covariates_premh, on = [:participant_id, :period_id])
filter!(:period_id => x -> x ∉ [1, 13, 14], survey_data_premh)
select!(survey_data_premh, Not(:timepoint))

# Mental health after screenshot periods, covariates before
mh_vars_postmh = copy(survey_data_pivot[:, [:participant_id, :timepoint, mh_vars...]])
mh_vars_postmh.period_id = mh_vars_postmh.timepoint .- 2
covariates_postmh = copy(survey_data_pivot[:, Not(mh_vars)])
covariates_postmh.period_id = covariates_postmh.timepoint
select!(covariates_postmh, Not(:timepoint))
survey_data_postmh = outerjoin(mh_vars_postmh, covariates_postmh, on = [:participant_id, :period_id])
filter!(:period_id => x -> x ∉ [-1, 0, 12, 13], survey_data_postmh)
select!(survey_data_postmh, Not(:timepoint))

## Join tables
data_premh = outerjoin(bout_statistics, survey_data_premh, on = [:participant_id, :period_id])
data_postmh = outerjoin(bout_statistics, survey_data_postmh, on = [:participant_id, :period_id])
sens_wd_data_premh = outerjoin(sens_wd_bout_statistics, survey_data_premh, on = [:participant_id, :period_id])
sens_wd_data_postmh = outerjoin(sens_wd_bout_statistics, survey_data_postmh, on = [:participant_id, :period_id])
sens_we_data_premh = outerjoin(sens_we_bout_statistics, survey_data_premh, on = [:participant_id, :period_id])
sens_we_data_postmh = outerjoin(sens_we_bout_statistics, survey_data_postmh, on = [:participant_id, :period_id])
sens_conf_data_premh = outerjoin(sens_conf_bout_statistics, survey_data_premh, on = [:participant_id, :period_id])
sens_conf_data_postmh = outerjoin(sens_conf_bout_statistics, survey_data_postmh, on = [:participant_id, :period_id])

## Keep only periods where bout statistics, mental health data, and screenshot data are all available
for i in [data_premh, sens_wd_data_premh, sens_we_data_premh, sens_conf_data_premh]
    filter!(:period_id => x -> x ∉ [1, 13, 14], i)
end
for i in [data_postmh, sens_wd_data_postmh, sens_we_data_postmh, sens_conf_data_postmh]
    filter!(:period_id => x -> x ∉ [-1, 0, 12, 13], i)
end

## Create new sensitivity analyses removing participants with <25% non-missing periods
sens_missingness_data_premh = copy(data_premh)
sens_missingness_data_postmh = copy(data_postmh)

for i in [sens_missingness_data_premh, sens_missingness_data_postmh]
    for j in unique(i.participant_id)
        if sum(Matrix(missings_summary[missings_summary.participant_id .== j, Cols(r"^ismissing_period_\d+$")])) > 9
            filter!(:participant_id => x -> x ≠ j, i)
        end
    end
end

### Write outputs
@save snakemake.output[1] data_premh
@save snakemake.output[2] data_postmh
@save snakemake.output[3] sens_wd_data_premh
@save snakemake.output[4] sens_wd_data_postmh
@save snakemake.output[5] sens_we_data_premh
@save snakemake.output[6] sens_we_data_postmh
@save snakemake.output[7] sens_missingness_data_premh
@save snakemake.output[8] sens_missingness_data_postmh
@save snakemake.output[9] sens_conf_data_premh
@save snakemake.output[10] sens_conf_data_postmh