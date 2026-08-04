# On-screen people exposure derived from screen captures and internalising symptoms in adolescents

This repository contains the supplementary data for the paper "On-screen people exposure derived from screen captures and internalising symptoms in adolescents" (preprint available at LINK TBC).

Please review the licensing information at [LICENCE](https://github.com/tom-metherell/screenomics-people-exposure/blob/main/LICENCE) before reusing any software in this repository.

## Data source

The data used in this study are controlled by Stanford University and are not publicly available.

## Data analysis

Because of technical limitations, the data analysis for this study is divided into three stages:

* Stage one – cleaning of survey timestamps and derivation of inter-survey periods per participant.

* Stage two – identification of survey periods to be treated as missing for each participant and querying of on-screen people exposure summary statistics.

* Stage three – multiple imputation and formal analysis.

Most data analysis is conducted in Julia version 1.12.2. Scripts to query from and upload to BigQuery in stage one were executed in Python version 3.13.3, and backup multiple imputation in stage three was executed in R version 4.6.0 (called from Julia using [RCall.jl](https://github.com/JuliaInterop/RCall.jl)). There is a separate Snakemake pipeline for each stage.

## Supplementary information

In the stage three folder there are three HTML files containing supplementary information. To view these, you should download both the `.html` file and the associated `_files` subdirectory to ensure that graphics are rendered correctly. In the case of `models.html`, you should host a local server by running the following in a terminal in the directory where the HTML file is located:

```python
python -m http.server 8000
```

and then access the file by visiting `localhost:8000/models.html` in your web browser.

The files are as follows:

* Descriptives (`descriptives.html`, [view online](https://tom-metherell.github.io/screenomics-people-exposure/descriptives.html))

* Multiple imputation plots (`multiple_imputation.html`, [view online](https://tom-metherell.github.io/screenomics-people-exposure/multiple_imputation.html))

* Modelling including results dashboard (`models.html`, [view online](https://tom-metherell.github.io/screenomics-people-exposure/models.html))
