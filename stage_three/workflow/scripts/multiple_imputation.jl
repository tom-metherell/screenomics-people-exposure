#######
# Script purpose: to perform multiple imputation on the two longitudinal datasets, one with "mental health before" and one with "mental health after"
# Inputs: CSV-format prepared datasets with missing data
# Methods: performs multiple imputation using Mice.jl and saves both sets of results in JLD2 (Julia data) format
# Outputs: imputed datasets in JLD2 format
#######

### Julia dependencies
using Pkg; Pkg.activate(".")
using Base.Threads, CategoricalArrays, DataFrames, JLD2, Mice, Random, StatsBase

### Import data
data_premh = load(snakemake.input[1], "data_premh")
data_postmh = load(snakemake.input[2], "data_postmh")

### Removal/simplification of some variables to reduce complexity and allow imputation convergence
for i in [data_premh, data_postmh]
    i[!, "dv_psubs1_re"] = maximum.(eachrow(i[:, ["dv_psubs1_re", "dv_psubs3_re"]])) # Merge tobacco and other substance use
    i[!, "dv_pempl"] = unwrap.(recode(i[!, "dv_pempl"], [k => 0 for k in ["Not working for pay", "Working part-time"]]..., "Working full-time" => 1)) # Simplify employment status to binary
    # Remove the following variables:
    select!(i, Not(
        "median_bout_sd_person_area_pct", # Variance too low
        "dv_psubs3_re" # Redundant following merger above
    ))
end

### Preparation of imputation predictor matrix: participant_id and family_id should not act as predictors
predictormatrix = makepredictormatrix(data_premh)
predictormatrix[:, ["participant_id", "family_id"]] .= 0

### Set random seed for reproducibility
Random.seed!(9106)

### Initialise container for imputed datasets
results = Vector{Mids}(undef, 2)

### Run multiple imputation using Mice.jl
Threads.@threads for i in eachindex([data_premh, data_postmh])
    results[i] = mice([data_premh, data_postmh][i], m = 50, iter = 60, predictormatrix = predictormatrix, progressreports = false)
end

imputed_data_premh = results[1]
imputed_data_postmh = results[2]

### Save imputed datasets
@save snakemake.output[1] imputed_data_premh
@save snakemake.output[2] imputed_data_postmh