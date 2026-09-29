#######
# Script purpose: to perform multiple imputation on the two longitudinal datasets, one with "mental health before" and one with "mental health after"
# Inputs: CSV-format prepared datasets with missing data
# Methods: performs multiple imputation using both Mice.jl and R's mice package and saves both sets of results in JLD2 (Julia data) format
# Outputs: imputed datasets in JLD2 format
#######

### Julia dependencies
using Pkg; Pkg.activate(".")
using Base.Threads, CategoricalArrays, DataFrames, JLD2, Mice, Random, RCall, StatsBase

### Import data
data_premh = load(snakemake.input[1], "data_premh")
data_postmh = load(snakemake.input[2], "data_postmh")
sens_wd_data_premh = load(snakemake.input[3], "sens_wd_data_premh")
sens_wd_data_postmh = load(snakemake.input[4], "sens_wd_data_postmh")
sens_we_data_premh = load(snakemake.input[5], "sens_we_data_premh")
sens_we_data_postmh = load(snakemake.input[6], "sens_we_data_postmh")
sens_missingness_data_premh = load(snakemake.input[7], "sens_missingness_data_premh")
sens_missingness_data_postmh = load(snakemake.input[8], "sens_missingness_data_postmh")
sens_conf_data_premh = load(snakemake.input[9], "sens_conf_data_premh")
sens_conf_data_postmh = load(snakemake.input[10], "sens_conf_data_postmh")

data_sens_auxil_premh = copy(data_premh)
data_sens_auxil_postmh = copy(data_postmh)

datasetlist = [data_premh, data_postmh, sens_wd_data_premh, sens_wd_data_postmh, sens_we_data_premh, sens_we_data_postmh, sens_missingness_data_premh, sens_missingness_data_postmh, sens_conf_data_premh, sens_conf_data_postmh]

### Removal/simplification of some variables to reduce complexity and allow imputation convergence
for i in datasetlist
    i[!, "dv_psubs1_re"] = maximum.(eachrow(i[:, ["dv_psubs1_re", "dv_psubs3_re"]])) # Merge tobacco and other substance use
    i[!, "dv_pempl"] = unwrap.(recode(i[!, "dv_pempl"], [k => 0 for k in ["Not working for pay", "Working part-time"]]..., "Working full-time" => 1)) # Simplify employment status to binary
    # Remove the following variables:
    select!(i, Not(
        "median_bout_sd_person_area_pct", # Variance too low
        "dv_psubs3_re" # Redundant following merger above
    ))
end

### Remove potential collider auxiliary variables from main datasets for sensitivity analysis
for i in [data_premh, data_postmh]
    select!(i, Not(
        "n_bouts_overlapping_missing",
        "n_between_bout_gaps_ignored_missing"
    ))
end

### Preparation of imputation predictor matrix: participant_id and family_id should not act as predictors
# Shortened list of predictors for analyses leaving out auxiliary variables
shortpredictormatrix = makepredictormatrix(data_premh)
shortpredictormatrix[:, ["participant_id", "family_id"]] .= 0

fullpredictormatrix = makepredictormatrix(sens_wd_data_premh)
fullpredictormatrix[:, ["participant_id", "family_id"]] .= 0

### Set random seed for reproducibility
Random.seed!(9106)

### Initialise container for imputed datasets
results = Vector{Mids}(undef, length(datasetlist))

### Run multiple imputation using Mice.jl
Threads.@threads for i in eachindex(datasetlist)
    results[i] = mice(
        datasetlist[i], m = 50, iter = 60,
        predictormatrix = i ∈ [1, 2] ? shortpredictormatrix : fullpredictormatrix,
        progressreports = false
    )
end

imputed_data_sens_auxil_premh = results[1]
imputed_data_sens_auxil_postmh = results[2]
imputed_data_sens_wd_premh = results[3]
imputed_data_sens_wd_postmh = results[4]
imputed_data_sens_we_premh = results[5]
imputed_data_sens_we_postmh = results[6]
imputed_data_sens_missingness_premh = results[7]
imputed_data_sens_missingness_postmh = results[8]
imputed_data_sens_conf_premh = results[9]
imputed_data_sens_conf_postmh = results[10]

### Save imputed datasets
@save snakemake.output[1] imputed_data_sens_auxil_premh
@save snakemake.output[2] imputed_data_sens_auxil_postmh
@save snakemake.output[3] imputed_data_sens_wd_premh
@save snakemake.output[4] imputed_data_sens_wd_postmh
@save snakemake.output[5] imputed_data_sens_we_premh
@save snakemake.output[6] imputed_data_sens_we_postmh
@save snakemake.output[7] imputed_data_sens_missingness_premh
@save snakemake.output[8] imputed_data_sens_missingness_postmh
@save snakemake.output[9] imputed_data_sens_conf_premh
@save snakemake.output[10] imputed_data_sens_conf_postmh