#######
# Script purpose: to perform multiple imputation on the two longitudinal datasets, one with "mental health before" and one with "mental health after"
# Inputs: CSV-format prepared datasets with missing data
# Methods: performs multiple imputation using R's mice package and saves both sets of results in JLD2 (Julia data) format
# Outputs: imputed datasets in JLD2 format
#######

### Julia dependencies
using Pkg; Pkg.activate(".")
using CategoricalArrays, DataFrames, JLD2, Mice, RCall, StatsBase

### Import data
data_premh = load(snakemake.input[1], "data_premh")
data_postmh = load(snakemake.input[2], "data_postmh")

### Removal/simplification of some variables to reduce complexity and allow imputation convergence
for i in [data_premh, data_postmh]
    i[!, "dv_psubs1_re"] = maximum.(eachrow(i[:, ["dv_psubs1_re", "dv_psubs3_re"]])) # Merge tobacco and other substance use
    # Remove the following variables:
    select!(i, Not(
        "median_bout_sd_person_area_pct", # Variance too low
        "dv_pempl", "dv_pessent", # Both too multicollinear with other socioeconomic variables
        "dv_psubs3_re" # Redundant following merger above
    ))
end

### Export prepared datasets to R for imputation using R's mice package
@rput data_premh
@rput data_postmh

### Using RCall.jl to run R code
R"
### Dependencies
library(mice)
library(parallel)

### Convert gender and race variables to factor
data_premh$cgenderfirst <- factor(data_premh$cgenderfirst)
data_premh$dv_race <- factor(data_premh$dv_race)
data_postmh$cgenderfirst <- factor(data_postmh$cgenderfirst)
data_postmh$dv_race <- factor(data_postmh$dv_race)

### Prepare imputation parameters
# Imputation method: PMM for all variables that are to be imputed
methods <- make.method(data_premh)
methods[] <- 'pmm'
methods[c('participant_id', 'family_id')] <- ''

# As before, exclude participant_id and family_id as predictors
predictormatrix = make.predictorMatrix(data_premh)
predictormatrix[, c('participant_id', 'family_id')] <- 0

### Set random seed for reproducibility
set.seed(9107)

### Run multiple imputation using R's mice package
results <- mclapply(list(data_premh, data_postmh), function(x){
    mice(x, m = 50, maxit = 60, method = methods, predictorMatrix = predictormatrix, printFlag = FALSE)
}, mc.cores = 2)

R_imputed_data_premh <- results[[1]]
R_imputed_data_postmh <- results[[2]]
"

### Retrieve imputed datasets from R
@rget R_imputed_data_premh
@rget R_imputed_data_postmh

### Save R-imputed datasets
@save snakemake.output[1] R_imputed_data_premh
@save snakemake.output[2] R_imputed_data_postmh