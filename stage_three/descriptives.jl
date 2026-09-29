### A Pluto.jl notebook ###
# v1.0.0

#> [frontmatter]
#> language = "en-GB"
#> title = "Descriptives"
#> date = "2026-05-27"
#> description = "Descriptive statistics"
#> 
#>     [[frontmatter.author]]
#>     name = "Thomas E. Metherell"
#>     url = "https://tommetherell.com/"

using Markdown
using InteractiveUtils

# ╔═╡ c613630c-5922-11f1-9876-4b733dd2b566
# ╠═╡ show_logs = false
using Pkg; Pkg.activate(".");

# ╔═╡ 2cfe67e0-7ec0-461c-9e51-73a92a2216b0
using CSV, CategoricalArrays, DataFrames, Distributions, JLD2, Plots, PlutoUI, StatsBase

# ╔═╡ c976f4ef-0eed-4be8-93c6-b4ce9005fe8c
md"# Descriptives"

# ╔═╡ 1902cd41-23f1-479b-bc47-cc85843d778a
begin
	survey_data = CSV.read("resources/PII_Clean_Teen_Surveys_2023-03-21.csv", DataFrame)
	bout_statistics = CSV.read("resources/tm_bout_statistics.csv", DataFrame)
	missings_summary = CSV.read("resources/tm_missings_summary.csv", DataFrame)
	@load "resources/data_premh.jld2"
	@load "resources/data_postmh.jld2"
end;

# ╔═╡ a37b80a9-53a3-4dd4-aa18-7b024d2d5025
md"## Demographics"

# ╔═╡ bc0d4db0-b7d8-4cff-bb4f-b11a11b0a26c
demographicstable = unique(data_premh[:, [:participant_id, :cageyrs01, :cgenderfirst, :dv_race, :dv_phhinc, :dv_psnap]]);

# ╔═╡ c58502e7-c4fb-4dfa-9482-78994e5ad4e5
function freqtable(
	data::DataFrame,
	col::Symbol,
	label::String;
	keys::Union{Dict, Nothing} = nothing,
	sort::Bool = true,
	combinekeys::Union{Dict, Nothing} = nothing
	)

	ft = combine(groupby(data, col), nrow => :Freq)

	if !isnothing(combinekeys)
		for i in combinekeys
			push!(ft, (i[2], sum(ft[.!ismissing.(ft[!, col]) .&& ft[!, col] .∈ Ref(i[1]), :Freq])))
			
			filter!(x -> ismissing(x[col]) || x[col] ∉ i[1], ft)
		end
	end

	if !sort
		sort!(ft, col)
	end

	if !isnothing(keys)
		ft[!, col] = replace(ft[!, col], keys...)
		ft[!, col] = string.(ft[!, col])
	end

	if sort
		sort!(ft, col)
	end
	
	rename!(ft, col => label)

	toosmall = ft.Freq .< 10
	
	if any(toosmall)
		freqs = ft.Freq
		ft.Freq = string.(freqs)
		ft.Freq[toosmall] .= "<10"
		
		if sum(freqs[toosmall]) < 10
			minallowedidx = findfirst(freqs .== minimum(freqs[.!toosmall]))
			sacrificedval = sum(freqs) - sum(freqs[setdiff(findall(.!toosmall), minallowedidx)]) - 10
			ft.Freq[minallowedidx] = string(">", sacrificedval)
		end
	end

	return ft
end;

# ╔═╡ 650180ad-a7da-4455-b2c3-1c010d9eb410
md"### Initial age"

# ╔═╡ 86668f81-a9f0-468a-8bd4-e0df3d5ff581
md"Please note that this is a histogram and not a bar chart – the bins are 12.5–13.5, 13.5–14.5, ...  up to 17.5–18.5 years."

# ╔═╡ 879d1885-bc38-4a60-9978-5f80112e0c1e
histogram(demographicstable.cageyrs01, bins = 12.5:1.0:18.5, xlabel = "Initial age (years)", ylabel = "Frequency", legend = false)

# ╔═╡ fd02d984-8595-40cf-bb0f-fa73bffca703
md"""
Mean initial age: $(round(mean(skipmissing(demographicstable.cageyrs01)), digits = 1)) years

Standard deviation: $(round(std(skipmissing(demographicstable.cageyrs01)), digits = 1)) years

Maximum initial age: $(maximum(skipmissing(demographicstable.cageyrs01))) years

Minimum initial age: $(minimum(skipmissing(demographicstable.cageyrs01))) years
"""

# ╔═╡ 19fb5e37-30d5-4fff-bef3-654e00e85059
md"### Gender"

# ╔═╡ 6e7e4feb-6f39-4e40-8677-6964d1c36d1a
freqtable(demographicstable, :cgenderfirst, "Gender", keys = Dict(1 => "Male", 2 => "Female", 3 => "Other"))

# ╔═╡ 583fe458-d70d-44b4-bf2f-84b6fe870116
md"### Ethnicity"

# ╔═╡ 6bf69074-acdf-45ad-9344-aa11470bcf97
freqtable(demographicstable, :dv_race, "Ethnicity", combinekeys = Dict(
	["American Indian or Alaskan Native", "Asian", "Black or African American", "Hispanic or Latino", "Multiple"] => "One or more ethnic minority classifications"))

# ╔═╡ 459e4797-924c-43a6-b710-dbab105d4d4c
md"### Household income"

# ╔═╡ 57397af4-8b10-4f58-b7fe-38774a839f06
freqtable(demographicstable, :dv_phhinc, "Household income (USD)", keys = Dict(
	-1 => "< 35,000",
	0 => "35,000 – 74,999",
	6 => "75,000 – 149,999",
	9 => "≥ 150,000"
), sort = false, combinekeys = Dict(
	[1, 2, 3] => -1,
	[4, 5] => 0,
	[7, 8] => 9
))

# ╔═╡ 80caacdb-975a-4f76-bfe5-1fdffc576eea
md"### SNAP receipt"

# ╔═╡ 541cc0ac-b6ab-42fb-954d-6a97347797ad
freqtable(demographicstable, :dv_psnap, "SNAP receipt", keys = Dict(0 => "No", 1 => "Yes"))

# ╔═╡ 08ba8342-faee-4dba-b6f3-9b487e5199d2
md"## Mental health variables"

# ╔═╡ ef1d6508-36e8-4e0b-a899-724689b82c2a
md"### Distributions of all responses"

# ╔═╡ 3b8a6a22-84b3-45c7-8348-69f182d2eb04
mh_vars = ["ccdis08", "ccdisavg_re75", "canxiavg_re75", "cposafavg_re75", "cstrsavg_re75", "cwgtconavg_re75"];

# ╔═╡ f2f54803-a72e-40f5-b70a-b20f7dbe7b1d
mh_titles = ["Loneliness" "Depressive symptoms" "Anxiety symptoms" "Positive affect" "Psychological stress" "Body image"];

# ╔═╡ e3f9431b-49e5-45dc-b09d-b90d521bf973
begin
	mh_plots = []
	for mh_var in mh_vars
		freq = countmap(disallowmissing(data_premh[.!ismissing.(data_premh[!, mh_var]), mh_var]))
	
		p = bar(
			collect(keys(freq)),
			collect(values(freq)),
			ylabel = "Frequency",
			labelfontsize = 8
		)
	
		push!(mh_plots, p)
	end
end

# ╔═╡ 0fe0759b-2e13-4800-b667-4f5d352558dd
Plots.plot(
	mh_plots...,
	layout = (3, 2),
	legend = false,
	title = mh_titles
)

# ╔═╡ 54e6eec3-6676-4bae-86c9-dd15d934edc2
begin
	mhstats = DataFrame(Variable = String[], Mean = Float64[], Variance = Float64[])
	for idx in eachindex(mh_vars)
		i = mh_vars[idx]
		push!(mhstats, [mh_titles[idx] mean(skipmissing(data_premh[!, i])) var(skipmissing(data_premh[!, i]))])
	end
end;

# ╔═╡ 12c8aa84-09b3-4422-819c-69e68fe9ffa5
mhstats

# ╔═╡ 0560ab4c-b5f0-446a-8641-ff5b3f1f66f2
md"### Mean levels across timepoints"

# ╔═╡ dff6dd29-19de-439b-bb42-b56310cc8645
begin
	mh_long_plots = []
	for mh_var in ["ccdis08", "ccdisavg", "canxiavg", "cposafavg", "cstrsavg"]
		push!(mh_long_plots, Plots.plot(
			1:13,
			[mean(skipmissing(Matrix(survey_data[:, Cols(Regex("^$mh_var$(lpad(string(i), 2, '0'))"))]))) for i in 1:13],
			ribbon = quantile(Normal(), 0.975) .* [sem(skipmissing(Matrix(survey_data[:, Cols(Regex("^$mh_var$(lpad(string(i), 2, '0'))"))]))) for i in 1:13],
			xticks = 1:13,
			xlabel = "Timepoint",
			ylabel = "Mean value",
			labelfontsize = 8,
			xlims = (0.7, 13.3),
			ylims = mh_var ∈ ["ccdis08", "ccdisavg"] ? (0, 2) : (1, 5),
			linecolour = :black,
			fillcolour = :grey
		))
	end

	push!(mh_long_plots, Plots.plot(
		[1; 2:2:12],
		[mean(skipmissing(Matrix(survey_data[:, Cols(Regex("^cwgtconavg$(lpad(string(i), 2, '0'))"))]))) for i in [1; 2:2:12]],
		ribbon = quantile(Normal(), 0.975) .* [sem(skipmissing(Matrix(survey_data[:, Cols(Regex("^cwgtconavg$(lpad(string(i), 2, '0'))"))]))) for i in [1; 2:2:12]],
		xticks = [1; 2:2:12],
		xlabel = "Timepoint",
		ylabel = "Mean value",
		labelfontsize = 8,
		xlims = (0.7, 13.3),
		ylims = (1, 3),
		linecolour = :black,
		fillcolour = :grey
	))
end;

# ╔═╡ a9274c6d-bc68-4b56-8e68-d93c1766da84
Plots.plot(
	mh_long_plots...,
	layout = (3, 2),
	legend = false,
	title = mh_titles,
	size = (800, 600)
)

# ╔═╡ 9623384e-a462-4bf8-91d7-e6ca634d4d94
savefig("figures/mhsectrends.svg");

# ╔═╡ 4ccf58d1-b072-4192-a446-e538b0c3c0a2
md"## People detection summary statistics"

# ╔═╡ 1574236c-752f-413f-a11c-e6908a0cf0a8
md"### Overall numbers of screenshots"

# ╔═╡ 2f1bb721-2e16-412d-a0ef-2412803754fb
md"Mean number of screenshots per two-week period: $(round(mean(vcat(bout_statistics.n_screenshots, repeat([0], 163 * 12 - length(bout_statistics.n_screenshots)))), digits = 1))"

# ╔═╡ 82ff975a-2ac0-4b85-b4b3-31b90961da56
md"Mean number of screenshots per two-week period excluding missing periods: $(round(mean(bout_statistics.n_screenshots), digits = 1))"

# ╔═╡ 48f9c7c4-8918-4d98-aad9-14a949f91774
md"### Distributions of all statistics"

# ╔═╡ 0f9416e6-7975-4125-9c47-2fcd8e7b537f
screen_vars = ["prop_screens_with_person", "n_bouts", "mean_bout_duration_seconds", "sd_bout_duration_seconds", "mean_time_between_bouts_seconds", "sd_time_between_bouts_seconds", "median_bout_mean_person_area_pct"];

# ╔═╡ 07b80ad1-a76b-434a-becf-4cf66f5045b9
screen_titles_1 = ["Proportion of screenshots containing at least one person (%)" "Number of bouts of people on-screen (log₁₀)" "Mean bout duration (log₁₀) (s)" "Standard deviation of bout duration (log₁₀) (s)" "Mean time between bouts (log₁₀) (s)" "Standard deviation of time between bouts (log₁₀) (s)" "Median of bout-level mean percentages\nof screen area occupied by people (%)"];

# ╔═╡ e0a04f67-3e9f-44f1-afd9-e567e88f5d0e
screen_titles_2 = ["Proportion of screenshots containing at least one person (%)" "Number of bouts of people on-screen" "Mean bout duration (s)" "Standard deviation of bout duration (s)" "Mean time between bouts (s)" "Standard deviation of time between bouts (s)" "Median of bout-level mean percentages\nof screen area occupied by people (%)"];

# ╔═╡ 716b46bd-4902-4db5-a0db-f3fa44363c70
histogram(
	[screen_var ∈ ["n_bouts", "mean_bout_duration_seconds", "sd_bout_duration_seconds", "mean_time_between_bouts_seconds", "sd_time_between_bouts_seconds"] ? log10.(data_premh[!, screen_var]) : data_premh[!, screen_var] for screen_var in screen_vars],
	layout = @layout([a b; c d; e f; g _]),
	legend = false,
	title = screen_titles_1,
	titlefontsize = 6,
	tickfontsize = 5
)

# ╔═╡ def396de-3a44-4cb3-bff7-ad81202b2060
data_premh.sd_bout_duration_seconds[coalesce.(data_premh.sd_bout_duration_seconds .== 0, false)] .= minimum(data_premh.sd_bout_duration_seconds[coalesce.(data_premh.sd_bout_duration_seconds .≠ 0, false)]);

# ╔═╡ 209fd0dc-7315-47aa-9011-21044a96d9b8
begin
	screenstats = DataFrame("Variable" => String[], "Mean" => Float64[], "Variance" => Float64[], "Standard deviation" => Float64[], "Variance of log-variable" => Float64[], "Skewness" => Float64[], "Skewness of log-variable" => Float64[])
	for idx in eachindex(screen_vars)
		i = screen_vars[idx]
		variable = data_premh[!, i]
		variance = var(skipmissing(variable))
		push!(screenstats, [replace(screen_titles_2[idx], "\n" => " ") mean(skipmissing(variable)) variance sqrt(variance) var(skipmissing(log.(variable))) skewness(collect(skipmissing(variable))) skewness(log.(collect(skipmissing(variable))))])
	end
end;

# ╔═╡ 01e49e46-6cea-4891-a732-b3a1e554e2c9
md"Note that the proportion of screenshots containing at least one person has true zero values. Recording bout duration standard deviations of zero have been raised to half the next-lowest value to approximate the limit of detection."

# ╔═╡ 6d293bfb-d7ba-4767-b807-68a7e6eca8e6
screenstats

# ╔═╡ f730f9f7-9458-4bf4-a331-6c18fd71ea7e
md"### Mean levels across timepoints"

# ╔═╡ ef1b8e5e-7352-4258-854f-cdad7eac9421
begin
	screen_long_plots = []
	for screen_var in screen_vars
		values = [mean(skipmissing(bout_statistics[bout_statistics.period_id .== i, screen_var])) .* if screen_var == "prop_screens_with_person"; 100; else; 1; end for i in unique(bout_statistics.period_id)]
		cis = quantile(Normal(), 0.975) .* [sem(skipmissing(bout_statistics[bout_statistics.period_id .== i, screen_var])) .* if screen_var == "prop_screens_with_person"; 100; else; 1; end for i in unique(bout_statistics.period_id)]
		
		push!(screen_long_plots, Plots.plot(
			unique(bout_statistics.period_id),
			values,
			ribbon = (min.(values, cis), cis),
			xticks = 1:12,
			xlims = (0.5, 12.5),
			xlabel = "Period",
			ylabel = "Mean value",
			labelfontsize = 8,
			linecolour = :black,
			fillcolour = :grey
		))
	end
end

# ╔═╡ 96afeff2-f265-4fb3-a9ee-36f160a49552
Plots.plot(
	screen_long_plots...,
	layout = (4, 2),
	title = screen_titles_2,
	legend = false,
	size = (800, 800),
	titlefontsize = 9
)

# ╔═╡ 79fe0c73-6112-443d-9603-3b21dd220bf2
savefig("figures/screensectrends.svg");

# ╔═╡ 357fbc08-f44d-4645-b844-fcb2168a66e3
md"## Missingness"

# ╔═╡ 788819ef-ee6b-47dc-8065-49bb4409afd4
md"### Mental health variables"

# ╔═╡ 0c90786e-51ab-41b3-a8ea-e123cfaf82e4
begin
	mh_missingness_plots = []
	for mh_var in ["ccdis08", "ccdisavg", "canxiavg", "cposafavg", "cstrsavg"]
		let y = [sum(ismissing.(Matrix(survey_data[:, Cols(Regex("^$mh_var$(lpad(string(i), 2, '0'))"))]))) for i in 1:13]
			push!(mh_missingness_plots, Plots.plot(
				1:13,
				y,
				xticks = 1:13,
				xlabel = "Timepoint",
				ylabel = "Number of missing entries",
				labelfontsize = 8,
				xlims = (0.5, 13.2),
				linecolour = :black,
				annotations = [(i, y[i] + (i ∈ 1:4 ? 5 : -5), string(y[i])) for i in 1:13],
				annotationfontsize = 8,
				annotationcolor = :grey
			))
		end
	end

	let y = [sum(ismissing.(Matrix(survey_data[:, Cols(Regex("^cwgtconavg$(lpad(string(i), 2, '0'))"))]))) for i in [1; 2:2:12]]

		push!(mh_missingness_plots, Plots.plot(
			[1; 2:2:12],
			y,
			xticks = [1; 2:2:12],
			xlabel = "Timepoint",
			ylabel = "Number of missing entries",
			labelfontsize = 8,
			xlims = (0.5, 13.2),
			linecolour = :black,
			annotations = [([1; 2:2:12][i], y[i] + (i ∈ 1:3 ? 5 : -5), string(y[i])) for i in eachindex([1; 2:2:12])],
			annotationfontsize = 8,
			annotationcolor = :grey
		))
	end
end;

# ╔═╡ 6ecdc1c7-a5c3-4cbd-b46e-9fba3a34c2fb
Plots.plot(
	mh_missingness_plots...,
	layout = (3, 2),
	legend = false,
	title = mh_titles,
	size = (800, 600)
)

# ╔═╡ 8a6acb65-0145-4027-ad31-86a51de8302a
md"### People detection summary statistics"

# ╔═╡ 90b7b66a-5645-421a-aaee-598603893192
begin
	ismissingstats = [[
		only(missings_summary[missings_summary.participant_id .== i, "ismissing_period_" * string(j)]) ? true :
				sum(bout_statistics.participant_id .== i .&& bout_statistics.period_id .== j) == 0 ? true :
					ismissing(bout_statistics[bout_statistics.participant_id .== i .&& bout_statistics.period_id .== j, k]) ? true : false
	for i in unique(missings_summary.participant_id), j in 1:12] for k in screen_vars]

	ismissingstats = only(unique(ismissingstats))
end;

# ╔═╡ c6296889-3cd6-48b5-bed8-20f1f032cfda
plot(
	1:12,
	sum.(eachcol(ismissingstats)),
	xticks = 1:12,
	legend = false,
	lc = :black,
	xlabel = "Period",
	ylabel = "Number of missing entries",
	annotations = [(i, sum(ismissingstats[:, i]) + (i == 1 ? 5 : -5), string(sum(ismissingstats[:, i]))) for i in 1:12],
	annotationfontsize = 8,
	annotationcolor = :grey
)

# ╔═╡ Cell order:
# ╟─c976f4ef-0eed-4be8-93c6-b4ce9005fe8c
# ╟─c613630c-5922-11f1-9876-4b733dd2b566
# ╟─2cfe67e0-7ec0-461c-9e51-73a92a2216b0
# ╟─1902cd41-23f1-479b-bc47-cc85843d778a
# ╟─a37b80a9-53a3-4dd4-aa18-7b024d2d5025
# ╟─bc0d4db0-b7d8-4cff-bb4f-b11a11b0a26c
# ╟─c58502e7-c4fb-4dfa-9482-78994e5ad4e5
# ╟─650180ad-a7da-4455-b2c3-1c010d9eb410
# ╟─86668f81-a9f0-468a-8bd4-e0df3d5ff581
# ╟─879d1885-bc38-4a60-9978-5f80112e0c1e
# ╟─fd02d984-8595-40cf-bb0f-fa73bffca703
# ╟─19fb5e37-30d5-4fff-bef3-654e00e85059
# ╟─6e7e4feb-6f39-4e40-8677-6964d1c36d1a
# ╟─583fe458-d70d-44b4-bf2f-84b6fe870116
# ╟─6bf69074-acdf-45ad-9344-aa11470bcf97
# ╟─459e4797-924c-43a6-b710-dbab105d4d4c
# ╟─57397af4-8b10-4f58-b7fe-38774a839f06
# ╟─80caacdb-975a-4f76-bfe5-1fdffc576eea
# ╟─541cc0ac-b6ab-42fb-954d-6a97347797ad
# ╟─08ba8342-faee-4dba-b6f3-9b487e5199d2
# ╟─ef1d6508-36e8-4e0b-a899-724689b82c2a
# ╟─3b8a6a22-84b3-45c7-8348-69f182d2eb04
# ╟─f2f54803-a72e-40f5-b70a-b20f7dbe7b1d
# ╟─e3f9431b-49e5-45dc-b09d-b90d521bf973
# ╟─0fe0759b-2e13-4800-b667-4f5d352558dd
# ╟─54e6eec3-6676-4bae-86c9-dd15d934edc2
# ╟─12c8aa84-09b3-4422-819c-69e68fe9ffa5
# ╟─0560ab4c-b5f0-446a-8641-ff5b3f1f66f2
# ╟─dff6dd29-19de-439b-bb42-b56310cc8645
# ╟─a9274c6d-bc68-4b56-8e68-d93c1766da84
# ╟─9623384e-a462-4bf8-91d7-e6ca634d4d94
# ╟─4ccf58d1-b072-4192-a446-e538b0c3c0a2
# ╟─1574236c-752f-413f-a11c-e6908a0cf0a8
# ╟─2f1bb721-2e16-412d-a0ef-2412803754fb
# ╟─82ff975a-2ac0-4b85-b4b3-31b90961da56
# ╟─48f9c7c4-8918-4d98-aad9-14a949f91774
# ╟─0f9416e6-7975-4125-9c47-2fcd8e7b537f
# ╟─07b80ad1-a76b-434a-becf-4cf66f5045b9
# ╟─e0a04f67-3e9f-44f1-afd9-e567e88f5d0e
# ╟─716b46bd-4902-4db5-a0db-f3fa44363c70
# ╟─def396de-3a44-4cb3-bff7-ad81202b2060
# ╟─209fd0dc-7315-47aa-9011-21044a96d9b8
# ╟─01e49e46-6cea-4891-a732-b3a1e554e2c9
# ╟─6d293bfb-d7ba-4767-b807-68a7e6eca8e6
# ╟─f730f9f7-9458-4bf4-a331-6c18fd71ea7e
# ╟─ef1b8e5e-7352-4258-854f-cdad7eac9421
# ╟─96afeff2-f265-4fb3-a9ee-36f160a49552
# ╟─79fe0c73-6112-443d-9603-3b21dd220bf2
# ╟─357fbc08-f44d-4645-b844-fcb2168a66e3
# ╟─788819ef-ee6b-47dc-8065-49bb4409afd4
# ╟─0c90786e-51ab-41b3-a8ea-e123cfaf82e4
# ╟─6ecdc1c7-a5c3-4cbd-b46e-9fba3a34c2fb
# ╟─8a6acb65-0145-4027-ad31-86a51de8302a
# ╟─90b7b66a-5645-421a-aaee-598603893192
# ╟─c6296889-3cd6-48b5-bed8-20f1f032cfda
