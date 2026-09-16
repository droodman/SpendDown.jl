### A Pluto.jl notebook ###
# v0.20.20

#> [frontmatter]

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 70785342-7c94-4073-9572-8698f1ef9ac2
begin
	# pushfirst!(LOAD_PATH,"..")  # This notebook sits in /src while the SpendDown package definition sits in the parent dir
	using Pkg
    Pkg.activate("SpendDownSharedEnvironment", shared=true)
    Pkg.add(url="https://github.com/droodman/SpendDown.jl")
    Pkg.add.(split("""
        PlutoUI
        ChainRulesCore
        Optim
        CairoMakie
        NLSolversBase
        DataFrames
        AxisKeys
        Distributions
        LinearAlgebra
        Dates
        StatsBase
        LogExpFunctions
    """))
	using SpendDown, ChainRulesCore, PlutoUI, Random, Optim, Statistics, StatsBase, CairoMakie, LogExpFunctions, DataFrames, AxisKeys, Distributions, LinearAlgebra, Dates, NLSolversBase

	# print a KeyedArray as a syntactically correct constructor of itself
	Base.show(io::IO, o::KeyedArray{T}) where {T} = print(io, 
              "KeyedArray($(AxisKeys.keyless(o)), $(axiskeys(o)))")

	# combo number boxes for distribution metaparameters
	# adapted from https://featured.plutojl.org/basic/plutoui.jl#8c51343f-cb35-4ff9-9fd8-642ffab57e22
	function MetaparameterInput(names, range, defaults)
		PlutoUI.combine(
			Child -> begin
				inputs = [md""" $(name): $(Child(name, PlutoUI.NumberField(range; default)))"""
					      for (name,default) ∈ zip(names,defaults)]
				md"""$(inputs)"""
			end
		)
	end

	# generate code for pull-down menu for distribution type
	macro getdisttype(type, default)
		:(begin
			update_to_loaded_params

			@bind $type Select([:Certain=>"Certain", :TwoPieceUniform=>"Two-piece uniform", :Bitriangular=>"Bitriangular"], default=$default)
		end)
	end
		
	# generate code for (meta)parameter entry combo boxes
	macro control(type, metaparam, metaparamdefault, range, xform=identity)
		:($type==:Certain ?
			(@bind $metaparam MetaparameterInput(["Value"], $range, $xform.($metaparamdefault[][$type]))) :
			(@bind $metaparam MetaparameterInput(["Low","Median","High"], $range, $xform.($metaparamdefault[][$type]))))
	end

	# generate code to extract results from (meta)parameter entry
	macro assign(type, metaparam, xform=identity)
		:(($type==:Certain ? $xform($metaparam[1]) : eval($type)($xform.([$metaparam[1], $metaparam[2], $metaparam[3]]))))
	end

	# "Ref" = C's "&"; use here as a hack to allow editing of vars after loading parameter files from disk, without triggering Pluto error about multiple definitions of a var

	NewModeldefault = Ref(true)
	Mdefault = Ref(10_000)
	Sdefault = Ref(Float32)
	lnA₀typedefault = Ref(:Certain); lnA₀metaparamsdefault = Ref(Dict(:TwoPieceUniform=>log.([500,1000,3000]),:Bitriangular=>log.([500,1000,3000]), :Certain=>[log(1000)]))
	lnA₀default = Ref(3000)
	T₁default = Ref(10); T₂default = Ref(40)
	t₁default = Ref(2025)
	ηtypedefault = Ref(:Bitriangular); ηmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[.25,.5,.99],:Bitriangular=>[.25,.5,.99], :Certain=>[.5]))
	Lₘₐₓtypedefault = Ref(:Certain); Lₘₐₓmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[3.5,1.42,1.15], :Bitriangular=>[3.5,1.42,1.15], :Certain=>[1]))
	ctypedefault = Ref(:Bitriangular); cmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[.1,.3,.6], :Bitriangular=>[.1,.3,.6], :Certain=>[.3]))
	ϕtypedefault = Ref(:Certain); ϕmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[.5,.75,1], :Bitriangular=>[.5,.75,1], :Certain=>[1]))
	δₗtypedefault = Ref(:Bitriangular); δₗmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[0,.05,.1], :Bitriangular=>[0,.05,.1], :Certain=>[.05]))
	rtypedefault = Ref(:Bitriangular); rmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[.11,.061,.035], :Bitriangular=>[.11,.061,.035], :Certain=>[.061]))
	simrdefault = Ref(true)
	r_geodefault = Ref(true)
	r_sddefault = Ref(1.)
	∂CEtypedefault = Ref(:Bitriangular); ∂CEmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[.025,.0475,.0725], :Bitriangular=>[.025,.0475,.0725], :Certain=>[.0475]))
	vtypedefault = Ref(:Bitriangular); vmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[-.0035,.0035,.02], :Bitriangular=>[-.0035,.0035,.02], :Certain=>[.0035]))
	Xtypedefault = Ref(:Bitriangular); Xmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[.01,.06,.16666], :Bitriangular=>[.01,.06,.16666], :Certain=>[.06]))
	etypedefault = Ref(:Certain); emetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[.001,.002,.003], :Bitriangular=>[.001,.002,.003], :Certain=>[.002]))
	ftypedefault = Ref(:Bitriangular); fmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[0,.01,.03], :Bitriangular=>[0,.01,.03], :Certain=>[0]))
	δftypedefault = Ref(:Certain); δfmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[0,.01,.03], :Bitriangular=>[0,.01,.03], :Certain=>[.01]))
	ddefault = Ref(0.)
	z₁default = Ref(10.)
	gtypedefault = Ref(:Bitriangular); gmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[0,.05,.1], :Bitriangular=>[0,.05,.1], :Certain=>[.05]))
	C₁typedefault = Ref(:Bitriangular); C₁metaparamsdefault = Ref(Dict(:TwoPieceUniform=>[0,.5,2], :Bitriangular=>[0,.5,2], :Certain=>[.5]))
	∂Ctypedefault = Ref(:Certain); ∂Cmetaparamsdefault = Ref(Dict(:TwoPieceUniform=>[0,.5,1], :Bitriangular=>[0,.5,1], :Certain=>[.5]))

	md"_Initialization code hidden here_"
end

# ╔═╡ c75bd415-6a7f-4a2f-9d0e-85fd25c5a185
TableOfContents(depth=4)

# ╔═╡ 66c691d0-7839-442e-9440-107e8acf3f14
md"""
# Overview

## Usage
If you see "Run notebook code" in the upper right, click it to activate this notbeook. When you do so, especially if it's the first time, there will be a delay as code is loaded and compiled.

This is a Pluto notebook, so it works like a spreadsheet: when you change one cell, dependent cells automatically update.

If your browser window is wide enough, you should see the clickable Table of Contents on the right. Otherwise, click the icon at right to open the the TOC. It's handy for navigating.

The bulk of the notebook is an interface onto the model's parameters and meta-parameters (the ones governing priors for uncertain parameters). When you change an input, the optimal spending path---a series of yearly spending rates---is reestimated, in order to maximize simulated EV. Various graphs and tables are then updated.

You may want to open two windows onto this notebook, one for parameter adjustment, one for results. To do so, just copy and past the address from the browser bar above into a new browser window. Warning: when you open another window, it resets all parameters to their defaults.

Using buttons at the bottom, you can save parameter sets into your downloads folder, and reload them.

## What's new
This notebook allows you to vary the parameters and meta-parameters in the spend-down model and immediately see optimal spending paths. You can run both versions of the model: [version 1](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.iqx8j6aq4tu7) spearheaded by Peter Favaloro circa 2022 and a version built in 2024.

Major changes in version 2:
* Version 1 casts the decision problem as having one control variable: what percentage of available assets to spend each year in the initial phase (say, 10 years). Spending of the remaining assets in the "back 40" years is dictated by a textbook result on how to allocate spending over time to maximize utility. Applying that result requires assuming that at the end of phase 1, OP learns the exact value of all model parameters, such as future stock market returns. It also requires most model components to be expressible as discount rates.

    The revised model largely discards the two-phase framework. It casts the decision problem as picking 49 spending rates, expressed as % of remaining assets. (Assuming the time frame is 50 years). The rate in the last year is always 100%. The EV of the plan is then computed through simulation. This approach can eliminate version 1's unrealistic kinks in optimal spending paths at year 10. It also greatly increases modeling flexibility because it doesn't require that all factors be expressible as discount rates. It allows simulation not only of uncertain parameters, but of deterministic or random _events_, such as market returns and the end of philanthropy because of extinction or cornucopia.

    While dropping the two-phase structure, most other features are retained, including growth of crowding-in during the first phase, and exogenous growth in others' giving.

    The new decision problem is still artificial. No organization is going to adopt a 50-year plan for the % of assets to spend each year and stick to it regardless of actual market returns and other major developments. The purpose is merely to support short-term decision-making in a context of long-term thinking.

    ` `
* Optimization is automated. Because the implementations of version 1 were slow, users just ran it for a few initial spending rates and tabulated the results. The new implementation in Julia can find the optimal version 1 spending rate instantaneously. It can optimize version 2, in 49-dimensional space, in about a second. When optimizing EV under either model, the code runs an iterative search for the optimal spending rate(s). At each step in this iterative search, it runs a full simulation, with, say, 10,000 replications. Run time depends mostly on the ratio of the number of replications to the number of "performance" cores on your CPU. 

    ` `
* Version 2 incorporates learning by doing. More generally, it can represent any channel by which grantmaking today affects cost effectiveness tomorrow. These include field-building, and any investment we make in OP as an organization---staff, systems, reputation---assuming such investments are reasonably proxied by contemporary grant volume. Of course, once the math of endogenous learning is worked out, the challenge remains to form priors for the new parameters. How much does our cost-effectiveness rise for each doubling of cumulative grantmaking? (And is the relationship even monotonic, with constant elasticity, as currently assumed?)

    Version 2 also preserves version 1's representation of _exogenous_ learning in the first phase, i.e., learning that occurs as a function of time, not experience. That seems somewhat superfluous now. To turn it off, set the ``L_{max}`` multiplier to 1.

   ` `
* A discount factor for pure rate of time preference has been added.
"""
# (![](http://localhost:1234/share-outline.50164ded.svg)) 

# ╔═╡ cf97b742-65c1-431e-b4ec-abd49c6c16c7
md"""
## Mathematical statement
The impact of giving in year ``t`` is

```math
u_t\\(y_t\\) = σ \frac{S_t^\eta}{\eta} \frac{y_t^{1-\eta}}{1-\eta}
```

``y_t`` is dollar spending in year ``t``. ``S_t`` is our _selection power_, our ability to find opportunities at any given cost-effectiveness level. ``\sigma`` is a scaling factor, which can be assumed to be 1 since it doesn't affect the relative utility of different spending paths. With ``0<\eta<1``, the ``y_t^{1-\eta}`` term captures diminishing returns to spending within any given year. The utility function has the following sensible property: if ``S_t`` doubles, meaning that we can find twice the funding opportunities at each cost-effectiveness level, and if spending, ``y_t``, doubles too, then total impact also doubles.

The model allows for _endogenous learning_, which really means any other channel by which past spending influences current effectiveness, such as field-building. But the learning from each year's spending can decay over time, with staff turnover or changes in the world that make some of our knowledge obsolete. The formula is:

```math
L_t = \lambda \sum_{s=T_0}^{t-1} \\(1-\delta_l\\)^{t-s} y_s^\phi
```

where ``\delta_l`` is a depreciation rate, and ``\lambda`` is another scaling factor. If ``\phi<1``, there are diminishing learning returns with respect to each year's spending. The year ``T_0`` can be before the present; ``T_0=2011`` makes sense since we have grantmaking data going back that far. Stopping the sum at ``t-1`` means that the current year's learning does not kick in until next year.

Learning determines our selection power, according to

```math
S_t = L_t^c
```

``c`` is the _learning rate_. If ``c=0``, there is no endogenous learning.

Version 2 models "interference" from other donors---funding things that we would otherwise fund---the same way that version 1 does. That includes [endogenous giving](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.5pdbkjuv325k), which we crowd in by our example, and [exogenous giving](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.bdv8v7lie0hh), ``z_t``, which happens regardless of us. So the formula for the net present value of our lifetime impact is much as before:

```math
U = \sum_t \Delta_t\Bigl[u_t\\(y_t\\(1+C_t\\)+z_t\\) - u_t\\(z_t\\)\Bigr]
```

where ``\Delta_t`` is the cumulative discount multiplier for period ``t``.  ``\Delta_t`` incorporates discount factors such as the rate of return on assets and a shrinking opportunity set because of falling global poverty. ``\Delta_1=1.`` Notice one oddity in the formula: it is assumed that any giving that "interferes" with our philanthropy has the same productivity level as ours, ``S_t``. Whenever we learn, or build a field, that completely spills over to other donors. Or, to interpret the model another way, ``z_t'' includes only the funding from other donors that goes to the narrow set of causes and projects that we would otherwise have funded.
"""

# ╔═╡ 8c9aa9bd-87fc-4d62-b26a-2a4c2d89fe00
md"""
# Parameters
"""

# ╔═╡ d603cef6-5db4-4ae6-8ced-deb3746df9a0
md"""
Many of the parameter entry cells below will let you choose between representing a parameter as certain, as distributed according to a two-piece uniform distribution, or as distributed according to a bitriangular/double-triangle distribution. In the first case, you will then enter the exact value for the certain parameter. For the the two uncertain distributions, you instead enter the 0th, 50th, and 100th percentiles of the distribution.

The plot below shows the two distributions when those three numbers are **0, 0.1, and 0.25**.
"""

# ╔═╡ 9964440e-a931-49c3-934b-9fe717ce61d9
begin
	distfig = Figure()
	Axis(distfig[1,1], xticks=0:.05:0.25, ylabel="Density")
	qplot = -.04999:.0001:.3
	lines!(distfig[1,1], qplot, pdf.(TwoPieceUniform([0,.1,.25]), qplot), label="Two-piece uniform")
	lines!(distfig[1,1], qplot, pdf.(Bitriangular([0,.1,.25]), qplot), label="Bitriangular")
	axislegend(position=:lt, framevisible = false)
	distfig
end

# ╔═╡ 9b77c635-7fc6-4813-99ec-0b09d2f94c13
md"""
## Simulation
"""

# ╔═╡ 92bab01e-4c08-4f3e-8190-138a5c9181f4
md"""
## Boundary conditions
"""

# ╔═╡ a8e4ca99-8d9b-42b1-b628-0eac915514f9
md"""
### Start year (``t_1``)

``t_1`` = $(@bind t₁ NumberField(2020:2100, default=t₁default[]))

Calendar year in which spending starts. This matters only for interpreting the X-risk timeline below.
"""

# ╔═╡ 1151d56b-7771-4d6c-8076-2340b0a8c483
md"""
## Learning
"""

# ╔═╡ 55f6ab36-7511-4ea1-b4c1-d09fa1bc7442
md"""
### Endogenous learning
"""

# ╔═╡ 6cc88f19-e9fe-42c7-abd4-2ba7e0f13527
md"""
#### Spending pre-history

Arguably, OP has been learning by doing for >10 years. The block of code below creates a table of spending levels for 2011--24, inflation-adjusted to $ of 2024. Included are OP's GHW grants committed and [Good Ventures 2011--14 spending on GiveWell](https://files.givewell.org/files/metrics/GiveWell_Metrics_Report_2014.pdf#page=2), which is not in our Salesforce data. Tabulation [here](https://docs.google.com/spreadsheets/d/1BlCpcJmaolPFkTNB4fz8tAhVtD2LAc5K2z5Wtm39CBw/edit?gid=0#gid=0).
"""

# ╔═╡ fdf68695-2217-45ad-b56b-4b7e75b5c13f
yhist = [2011  1.53775
	     2012  2.738676
	     2013  12.549013
	     2014  57.978152
	     2015  45.126544
	     2016  298.377962
	     2017  216.060149
	     2018  244.227109
	     2019  265.018214
	     2020  216.817577
	     2021  423.728273
	     2022  563.436754
	     2023  432.340644
	     2024  341.2204228];
# comment out the above with command/ctrl-/ to make X-risk constant
# hit shift-return or click the little ▶ button just below to effect changes

# ╔═╡ 3e34cbba-ac5a-426a-a1df-64a22fe9d7ce
md"""
## Time discounts
"""

# ╔═╡ e3836f7c-e60a-4382-b559-5bfda82e6cbe
md"""
### Rate of return on assets (``r``)
"""

# ╔═╡ fce075f4-cd42-4169-9f4c-c0c298cf687c
begin
CAGR = [md"Australia"	6.7
md"Austria"	0.9
md"Belgium"	2.7
md"Canada"	5.7
md"Denmark"	5.7
md"Finland"	5.4
md"France"	3.4
md"Germany"	3.1
md"Ireland"	4.2
md"Italy"	2.1
md"Japan"	4.2
md"Netherlands"	5
md"New Zealand"	6.1
md"Norway"	4.4
md"Portugal"	3.7
md"South Africa"	7
md"Spain"	3.4
md"Sweden"	5.9
md"Switzerland"	4.53
md"UK"	5.3
md"US"	6.38
md"Europe"	4.1
md"World, ex-US"	4.3
md"World"	5
md"Developed"	5.1
md"Emerging"	3.8]
DataFrame([CAGR[1:13,:] CAGR[14:26,:]], ["Place", "CAGR, 1900-2022 (%)", "Place ", "CAGR, 1900-2022 (%) "])
end

# ╔═╡ 48e29a4a-fd3a-47a4-9c8f-e5f4ae235b9a
md"""
#### Apply prior to geometric or arithmetic average of returns?
Specify geometric average? $(@bind r_geo CheckBox(default=r_geodefault[]))

"Average" market returns can be defined in two ways: as the compound annual growth rate (CAGR) discussed above (geometric mean), or as the average return achieved in each of a series of years (arithmetic mean). Holding the arithmetic mean fixed, increased volatility lowers the CAGR.

This option controls whether the prior for ``r`` refers to the geometric or arithmetic mean.
"""

# ╔═╡ acf6cb7d-0d6b-41f2-91b8-4dce0c8d4545
begin
md"""
#### Simulate market returns?
Simulate market returns? $(@bind simr CheckBox(default=simrdefault[]))

Check this box for returns to be simulated as random not only across rollouts (assuming the distribution of ``r`` above is not specified as certain) but also over time, within each rollout. For example, if in a particular rollout, ``r`` is 6.1% and "Specify geometric average?" is also checked, then the history of the S&P will be rescaled to have a CAGR of 6.1%/year. The rescaled history will then be randomly sampled, with replacement, to get the simulated return in each year.

The actual history, adjusted for inflation, is plotted below. The CAGR has been 7.03%, and the average annual return, 8.56%. 

If this box is not checked then ``r`` will be constant over time within each simulation run, even if it varies across simulation runs.

Note: when "specify geometric average?" is checked, simluating returns affects the optimal path in a surprising way, because it introduces volatility. The greater the volatility, the more that the arithmetic average must exceed the geometric average. So if the latter does not change, the former must rise. That increases the reward for spending a bit less in any given year and investing more for the next.

$(lines(1871:1870+length(SpendDown.rhist), 100*SpendDown.rhist .-100, axis=(;ylabel="Annual real return, S&P 500 (%)")))
"""
end

# ╔═╡ 193a0195-93ef-4da0-8d10-698bdca822cb
md"""
#### Adjust volatility of returns?
Multiplier on historical S&P 500 volatility? $(@bind r_sd NumberField(.1:.1:10, default=r_sddefault[]))

Use this setting to lower or raise the volatility of simulated returns. Leave it at 1 for no change. If "Specify geometric average?" is not checked, then this adjusts the historical S&P 500 series by lowering returns in below-average years and raising them in above-average years. When "Specify geometric average?" is checked, the adjustment is instead applied to the historical logarithmic returns (``\ln(1+r)`` where ``r`` is a return rate).
"""

# ╔═╡ a59c4fcf-44d0-49e3-bae5-61d90f333880
md"""
### Exogenous decline in cost-effectiveness (``∂CE``)
"""

# ╔═╡ fbe051c5-ba18-49f6-b443-692b20a292aa
begin
	md"""
	#### X-risk timeline
	The parameter above sets the total X-risk through 2100. To allow the year-by-year risk to vary during the century, we define a timeline like the one below. This timeline consists of a series of estimates of the chance that artificial general intelligence (AGI) will have been developed by various years. Though not obvious, the implied probability that AGI will arrive in any given year, if it hasn't already, tends to rise, from 3%/year now to 5%/year at century's end.

	This AGI timeline foresees a 97% chance of AGI by 2100. This is far higher than the existential risk rates contemplated just above. The model therefore takes the provided timeline and rescales it in each simulation rollout so that the final probability matches whatever is specified by the ``X`` parameter above. If annual risk changes over time in the original timeline, this remains the case in the rescaled timeline.

	Spending during lower-risk periods will be modeled as generating more flow-through.
	"""
end

# ╔═╡ d10a63ba-6670-4c36-a322-6bd45587ce05
# probability of artificial general intelligence (AGI) being developed by various dates, as starting point for time-varying X-risk timeline
timeline = [2020 0
            2025 0.05
            2030 0.19
            2035 0.32
            2040 0.44
            2045 0.55
            2050 0.64
            2055 0.71
            2060 0.77
            2065 0.82
            2070 0.86
            2100 0.97];
# comment out the above with command/ctrl-/ to make X-risk constant
# hit shift-return or click the little ▶ button just below to effect changes

# ╔═╡ 574c0bcc-05ae-4222-a76d-09df6bff411e
md"""
## Other donors
"""

# ╔═╡ 7c6dc66d-a893-485b-8057-e04f668e12ef
md"""
## Correlations among uncertain parameters
The code below constructs a matrix of correlations among the uncertain parameters, called ``τ``. To avoid bugs, the rows and columns are labeled by parameter, using a special type of matrix, the `KeyedArray`. As a result, if some of the parameters in the `uncertain_params` list are in fact set elsewhere in this notebook as certain, this will be handled gracefully.

Only the contents of the upper triangle (not even the diagonal) matter.

Most of the cross-correlations come from [this Peter Favaloro spreadsheet](https://docs.google.com/spreadsheets/d/1SudGy_BOwCKAKknniMV-kATdlkwL71HI3ieYZbJ-ThU/edit?gid=0#gid=0).

``τ`` can also be assigned to a single number, such as 0.4, to indicate that all cross-correlations are the same.
"""

# ╔═╡ cdf22b2d-271c-47e9-8bf6-daea461fb4e5
# non-surfaced parameters
begin
	ẋ = 300   # reference level of GW giving; for calibrating version 1 model
    ḅ = 300   # CE at that level; ditto
	calibrate_b₁ = false  # whether to calibrate b₁ using the above (version 2 only)
	
	GPD = false  # add (μ-σ/η)yₜ term to utility? Per Generalized Pareto RFMF dist
	μ = 0
	σ = 1
	λ = 1  # scale factor on learning term
end;
# hit shift-return or click the little ▶ button just below to effect changes

# ╔═╡ bc2c8b47-a844-40b4-bd5f-85afdfb4ee2c
# begin 
# 	mmed = SimModel{S}(Xoshiro(); yhist=Vector{S}(@view yhist[:,2]), [first(p)=>last(p) isa Real ? last(p) : median(last(p)) for p ∈ kwargs]...)


# end

# ╔═╡ 64f154c2-91c2-452f-a9ba-922a76a173a0
md"""
# Results
"""

# ╔═╡ e6b5c24a-7133-4305-a2a3-7f242b3b0c12
md"""
_Notes: The top graph shows the direct result of the optimization. The second and third are derived from it, on the assumption that initial assets start at the median of their distribution, and return on assets is constant over time, at its median. The bottom plot shows the simulated average impact by year._

_If the optimal path spends down essentially all the available assets before the end of the simulation period, then, with pennies at stake, the top graph can jump around in the final years because of numerical imprecision. This looks weird but doesn't matter._
"""

# ╔═╡ 2f9494b8-2706-4d7a-9a15-c09ae0bc715b
md"""
## EV loss vs. initial spending
This plot gives a sense of how peaked or flat the utility surface is near the optimum. It shows how much utility is lost if spending in the first few years is constrained to some level away from the optimum.

Number of initial years to constrain the spending rate $(@bind l NumberField(1:10, default=3))
"""

# ╔═╡ bade4869-d9b0-45f5-9edb-4e2234e91b4a
md"""
_Note: the vertical line shows the average % spending in the initial years along the optimal path. But the optimal % spending rate normally changes from year to year. And in the scenarios simulated to make the plot, % spending is always constant in the initial years. Since none of these scenarios will quite match the optimum, the vertical line may not quite hit the peak of the curve._
"""

# ╔═╡ 45cee101-4bcd-4a6c-8fbc-22b5183cbfc4
md"""
## EV histogram at optimum
"""

# ╔═╡ 582c04d7-bde3-486b-9af7-d1d1c5ead14c
md"""
# Save & load
"""

# ╔═╡ 2dc51672-466b-4ba4-8a20-abbd12f9cbe2
md"""
## Load
$(@bind just_loaded_params FilePicker())

_Doesn't currently restore the correlation matrix, the spending prehistory, and the X-risk timeline._

_Warning: this function loads and executes the chosen file as Julia code, which in principle is a security risk._
"""

# ╔═╡ cf3e479c-74f0-4692-908b-773eb939e653
begin
	loaded_params = Dict()
	try		
		# file contents are ephemeral, maybe for security; append space to immediately duplicate
		global loaded_params = eval(Meta.parse(String(just_loaded_params["data"]) * " "))

		# extract parameter selection UI defaults from parameter value (constant or some distribution)
		function UIdefaults!(type, metaparams, dist)
			if dist isa UnivariateDistribution
				type[] = dist isa PiecewiseUniform ? :TwoPieceUniform : :Bitriangular
				metaparams[][type[]] = dist.x
			else
				type[] = :Certain
				metaparams[][type[]] = [dist]
			end
		end
		
		Mdefault[] = loaded_params[:M]
		Sdefault[] = loaded_params[:S]
		NewModeldefault[] = loaded_params[:Version2]
		UIdefaults!(lnA₀typedefault, lnA₀metaparamsdefault, loaded_params[:lnA₀])
		t₁default[] = loaded_params[:t₁]
		T₁default[] = loaded_params[:T₁]
		T₂default[] = loaded_params[:T₂]
		UIdefaults!(ηtypedefault, ηmetaparamsdefault, loaded_params[:η])
		UIdefaults!(Lₘₐₓtypedefault, Lₘₐₓmetaparamsdefault, loaded_params[:Lₘₐₓ])
		UIdefaults!(ctypedefault, cmetaparamsdefault, loaded_params[:c])
		UIdefaults!(δₗtypedefault, δₗmetaparamsdefault, loaded_params[:δₗ])
		UIdefaults!(rtypedefault, rmetaparamsdefault, loaded_params[:r])
		UIdefaults!(∂CEtypedefault, ∂CEmetaparamsdefault, loaded_params[:∂CE])
		UIdefaults!(vtypedefault, vmetaparamsdefault, loaded_params[:v])
		UIdefaults!(Xtypedefault, Xmetaparamsdefault, loaded_params[:X])
		UIdefaults!(etypedefault, emetaparamsdefault, loaded_params[:e])
		UIdefaults!(ftypedefault, fmetaparamsdefault, loaded_params[:f])
		UIdefaults!(∂_ftypedefault, ∂_fmetaparamsdefault, loaded_params[:∂_f])
		ddefault[] = loaded_params[:d]
		z₁default[] = loaded_params[:z₁]
		UIdefaults!(gtypedefault, gmetaparamsdefault, loaded_params[:g])
		UIdefaults!(C₁typedefault, C₁metaparamsdefault, loaded_params[:C₁])
		UIdefaults!(∂Ctypedefault, ∂Cmetaparamsdefault, loaded_params[:∂C])
	catch
	end

	update_to_loaded_params = rand()  # trigger updates of parameter entry cells
end;

# ╔═╡ ee95926c-6ea1-4b47-8e58-c5a271aa8b0a
begin 
	update_to_loaded_params
	md"""
	### Model version
	Use version 2 of the model? $(@bind Version2 CheckBox(default=true))
	"""
end

# ╔═╡ 7832130e-4bcb-4188-b2ef-3476d0fd0f5a
begin

# static parameter lists, equivalent to collect(keys(paramdict)) but avoiding reset of menu to :none when a parameter changes

paramvec = Version2 ?
   [:r, :lnA₀, :η, :Lₘₐₓ, :c, :δₗ, :∂CE, :v, :e, :f, :d, :z₁, :g, :C₁, :∂C, :ẋ, :ḅ] :
   [:r, :lnA₀, :η, :Lₘₐₓ,          :∂CE, :v, :e, :f,     :z₁, :g, :C₁, :∂C, :ẋ, :ḅ]

md"""
## Sensitivity test: optimal year-1 spending vs parameter value
Parameter: $(@bind sym Select([:none; paramvec]))
Multiplier range: $(@bind rangesenstext TextField(default="0.5 : 0.1 : 1.5"))

A multiplier range such as 0.5 : 0.1 : 1.5 means multiplying the chosen parameter value or distribution by 0.5, 0.6, ..., 1.5 and plotting the first year's spending on the optimal path.
"""
end

# ╔═╡ 09be9aa7-dcf4-4078-a232-8e7a46bec617
md"""
 $(try (global rangesens=eval(Meta.parse(rangesenstext))) isa StepRangeLen || throw(ArgumentError); ""; catch e1 "Not a valid number range. Valid example: 0.5 : 0.1 : 1.5" end)
"""

# ╔═╡ 5c184343-e6b7-4b10-8157-607b667c507c
begin
	update_to_loaded_params
	
	md"""
	### Number of simulations (``M``)
	10,000 usually works well.
	
	Every time any model inputs in this notebook are changed, a full simulation will be run ~10 times as the computer iteratively searches for the spending path that maximizes simulated EV. Each simulation will itself include ``M`` replications, which will vary uncertain parameters and simulate random events such as the end of philanthropy (which see).
	
	``M= `` $(@bind M NumberField(1:1e6, default=Mdefault[]))
	"""
end

# ╔═╡ b2b2448e-a6f1-4795-b029-3cf88ed9e305
begin
	update_to_loaded_params
	md"""
	### Precision
	Computing in 32-bit precision is faster and usually fine. Switching to 64-bit might help if the results get glitchy.
	
	Precision: $(@bind S Select([Float32=>"32-bit", Float64=>"64-bit"]; default=Float32))
	"""
end

# ╔═╡ 529b4f14-b60b-4400-aac7-50d8a5ea974e
begin
	uncertain_params = [:lnA₀,:r,:∂CE,:v,:Lₘₐₓ,:X,:η,:C₁,:f,:z₁,:g,:δₗ,:c,:ϕ]
	τ  = KeyedArray(Symmetric(
			S[ 1  0  0   0  0   0   0   0   0  0   0    0 0 0   
			   0  1 -0.3 0  0   0.1 0  -0.5 0  0  -0.5  0 0 0  
			   0  0  1   0  0  -0.1 0   0.3 0  0   0.3  0 0 0  
			   0  0  0   1  0   0   0   0   0  0   0    0 0 0
			   0  0  0   0  1   0   0   0.2 0  0   0    0 0 0
			   0  0  0   0  0   1   0  -0.1 0  0  -0.1  0 0 0
			   0  0  0   0  0   0   1   0   0  0   0    0 0 0
			   0  0  0   0  0   0   0   1   0  0   0.65 0 0 0
			   0  0  0   0  0   0   0   0   1  0   0    0 0 0 
			   0  0  0   0  0   0   0   0   0  1   0    0 0 0  
			   0  0  0   0  0   0   0   0   0  0   1    0 0 0  
			   0  0  0   0  0   0   0   0   0  0   0    1 0 0  
			   0  0  0   0  0   0   0   0   0  0   0    0 1 0  
			   0  0  0   0  0   0   0   0   0  0   0    0 0 1]), 
			row = uncertain_params, col = uncertain_params)  # label the rows and cols
	# τ = 0.4  # uncomment this to override matrix and make all correlations same
end;
# hit shift-return or click the little ▶ button just below to effect changes

# ╔═╡ 72dd2e82-fa0d-4500-bb67-6ee615398b62
md"""
### Initial assets (``A_0``)

Distribution type: $(@getdisttype(lnA₀type, lnA₀typedefault[]))
"""

# ╔═╡ 817d5e1f-9d9c-4c74-8d81-0c5aff46415b
@control(lnA₀type, lnA₀metaparams, lnA₀metaparamsdefault, 1:100_000, xform=exp)

# ╔═╡ 224446c2-6a8e-46b9-9780-7b9dc5c9b21d
begin
	lnA₀ = @assign(lnA₀type, lnA₀metaparams, xform=log)
	md"""Values are in million $.
	     
	Note: Distributions are here interpreted as applying to the _log_ of initial assets.
	"""
end

# ╔═╡ aacaa244-c6d3-47ec-a6fd-68278f108303
begin
	update_to_loaded_params
	md"""
	### Period lengths (``T_1`` and ``T_2``)
	
	Version 1 of the spenddown model splits the ~50-year timeframe into an initial ~10 years and a subsequent ~40 years. The two periods differ in several ways:
	1. In the first phase, spending occurrs at a fixed % of remaining assets each year. Then in the second, it moves along an optimal, full-information path.
	2. Learning occurrs exogenously in the first phase, at a fixed growth rate. Learning stops in the second phase.
	3. Similarly, the crowding-in multiplier grows in the first phase only, at a fixed rate.
	
	Version 2 of the model removes the first item. It retains the second for continuity, but makes it somewhat superflous since learning is now endogenized. And it retains the third.
	
	Version 2 imposes the restriction that in the last year of the 2ⁿᵈ phase, 100% of remaining assets are spent.
	
	Here, you can change the lengths of the periods. Either can be 0.
	
	``T_1`` (years) = $(@bind T₁ NumberField(0:100, default=T₁default[]))
	``T_2`` (years) = $(@bind T₂ NumberField(0:100, default=T₂default[]))
	"""
end

# ╔═╡ d9029735-fd6a-4032-8480-44b2624501a9
md"""
## Diminishing returns within a year (``η``)
Distribution type: $(@getdisttype(ηtype, ηtypedefault[]))
"""

# ╔═╡ c35e5119-a9c4-4575-b199-68c21ac48c54
@control(ηtype, ηmetaparams, ηmetaparamsdefault, 0:.01:1)

# ╔═╡ f1a7bbba-91d1-4a2b-b907-723df653de3c
begin
	η = @assign(ηtype, ηmetaparams)
		
	md"""
	``1 – \eta`` is the elasticity of philanthropic good to philanthropy: each 1% increase in giving increases total impact ``(1 – \eta)``%. ``\eta = 0`` makes the relationship linear. ``\eta = 1`` makes it sort of logarithmic.[^1] Assuming ``\eta>0``, total impact grows more slowly than total giving.
	
	Taking the difference between ``1`` and ``1-\eta``, average impact per dollar falls by ``\eta``% for each ``1``% increase in giving. It works out that our _marginal_ impact, which ideally is our bar, falls at the same rate.
	
	The defaults are copied from this [fall 2023 spreadsheet](https://docs.google.com/spreadsheets/d/1K-j1C8_-oxh2nXfHgmKm_hxSvgYNhHl3zBeQ9AMMM00/edit?gid=935943732#gid=935943732).
	
	Peter Favaloro [estimated](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.1snwsiiw44hu) _η_ = 0.37 from data on GiveWell charities assembled by Alex Cohen.
	
	In Feb 2023, Martin Gould [estimated](https://docs.google.com/document/d/1SJnUSj8Dp5VQpuKQXSA6PP4g9hSwvx1O5OA8Q3HkOjo/edit?tab=t.0) _η_ = 0.3–0.7 for FAW going forward.

	[^1]: Footnote: the relevant term of the utility function is ``y_t^{1-\eta}/(1-\eta)``. If it were ``(y_t^{1-\eta}-1)/(1-\eta)`` then it would [converge to logarithmic](https://en.wikipedia.org/wiki/Isoelastic_utility) as ``\eta\rightarrow1``.
	"""
end

# ╔═╡ f75fa40c-5af7-4eb7-ab86-3b3f9acb0dce
md"""
### Total exogenous learning (``L_{max}``)
Distribution type: $(@getdisttype(Lₘₐₓtype, Lₘₐₓtypedefault[]))
"""

# ╔═╡ 62a746fc-5455-4789-b5db-4cfb737762dd
@control(Lₘₐₓtype, Lₘₐₓmetaparams, Lₘₐₓmetaparamsdefault, 0:.01:10)

# ╔═╡ 9bc51dce-4d25-4900-9c27-4ca1b2b351a0
begin
	Lₘₐₓ = @assign(Lₘₐₓtype, Lₘₐₓmetaparams)

	md"""
	``L_{max}`` is a multiplier that sets total exogenous learning in the first phase, as [defined in version1 of the model](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.l3qhcyjigysm). The _endogenous_ learning in version 2 of the model---learning driven by past grantmaking experience rather than the pure passage of time---tends to make this parameter obsolete. Since it is a multiplier, setting it to 1 turns off exogenous learning.
	"""
end

# ╔═╡ bf7a906f-11af-4d4b-8c65-e365d0661cf5
md"""
#### Depreciation of experience (``δ_l``)
Distribution type: $(@getdisttype(δₗtype, δₗtypedefault[]))
"""

# ╔═╡ 3588ce71-0d64-42d0-9610-3b9f669c8c65
@control(δₗtype, δₗmetaparams, δₗmetaparamsdefault, 0:.0001:1)

# ╔═╡ 26a2c19f-e401-4671-81bf-5c24339b1bf4
begin
δₗ = @assign(δₗtype, δₗmetaparams)

md"""
``δ_l`` is the annualized rate at which past experience---or past investments in OP capacity or field-building---loses value, as staff turns over, or a changing world makes our experience and investments less relevant. If ``δ_l = 0``, then the utility function is a classic learning curve in which productivity depends with constant elasticity on cumulative production. Experience never loses value. If ``δ_l > 0``, this would seem to reward building up the organization and, having done so, spending down more aggressively before the accumulated experience effectively depreciates.
"""
end

# ╔═╡ 5087952f-4b1d-497c-9c1b-ed5ebae34c81
md"""
#### Diminishing learning returns from each year's spending (``ϕ``)
Distribution type: $(@getdisttype(ϕtype, ϕtypedefault[]))
"""

# ╔═╡ 8bd60ffd-b287-468c-96f2-6aa0962f4495
@control(ϕtype, ϕmetaparams, ϕmetaparamsdefault, 0:.01:1)

# ╔═╡ 0554c422-b130-4a8e-abe6-2f4ad7ae8956
begin
ϕ = @assign(ϕtype, ϕmetaparams)

md"""
Our capacity to learn through each year's spending might face diminishing returns. Perhaps if we disburse \$1 billion in one year rather than over ten, we will learn less. The model expresses this possibility through the exoponent ``ϕ`` on each year's, spending, ``y_t``. (See the first equation under Mathematical Statement above.) Setting ``\phi=1`` implies no diminishing returns within each year. Setting it between 0 and 1 causes the rate of return to diminish.
"""
end

# ╔═╡ 218b6bc8-453a-44eb-97bc-6e8ac0851422
md"""
#### Learning rate (``c``)
Distribution type: $(@getdisttype(ctype, ctypedefault[]))
"""

# ╔═╡ ebf524ce-55ec-446f-b9fc-84d76e5dad0b
@control(ctype, cmetaparams, cmetaparamsdefault, 0:.01:2)

# ╔═╡ 0952a455-f9e4-4fcf-a285-a16f57f46042
begin
c = @assign(ctype, cmetaparams)

md"""
_c_ is the elasticity of selection power---how much $ funding opportunity that we find at each cost-effectiveness level---to "cumulative production" of grants. It is the rate of endogenous learning...or field-building, or any other spending-correlated investment that boosts future productivity.

This framing of learning-by-doing, with price or productivity related linearly to cumulative production on a log-log plot, is well established. The prices of [lithium batteries](https://ourworldindata.org/battery-price-decline) and [solar cells](https://ourworldindata.org/cheap-renewables-growth) have fallen 20% for each doubling of cumulative global production. Inverting that number, productivity has risen ``1/(1-.2)=125\%`` for each doubling. To convert that to an elasticity like ``c``, divide it by ``\ln 2`` (or multiply by ``1.44``). That gives a learning rate of 0.32: each 1% increase in cumulative production was accompanied by a 32% rise in output per dollar.

In this set-up, if our giving plateaus, learning slows, because each successive doubling of cumulative grantmaking takes longer.

Since learning enters the model through the productivity multiplier ``S_t^\eta = (L_t^c)^\eta = L_t^{c\eta}``, arguably it is the product ``c\eta`` that best corresponds to observed learning rates such as ``0.32``. If we thought ``\eta=0.5``, then we might prefer ``c=0.64``, to arrange that ``c\eta=0.32``.

Learning-by-manufacturing is not obviously a good model for learning-by-grantmaking. Manufacturers benefit from tight feedback loops in a way that we and our grantees [rarely do](https://www.openphilanthropy.org/research/three-key-issues-ive-changed-my-mind-about/#id-3-changing-my-mind-about-general-properties-of-promising-ideas-and-interventions). So maybe we learn less efficiently. On the other hand, our bar, a rough indicator of our marginal and average effectiveness, rose ~20x between 2017 and 2024 while our cumulative grantmaking grew 10x. If we attribute the first solely to the second, then we achieved extraordinarily rapid endogenous learning, with ``c\eta\approx 2``.
"""
end

# ╔═╡ 9fdff29f-0a0a-4bf9-b083-563d35a46b2b
md"""
Distribution type: $(@getdisttype(rtype, rtypedefault[]))
"""

# ╔═╡ 7a1ea043-8743-4943-9ba7-f4afa02e032b
@control(rtype, rmetaparams, rmetaparamsdefault, -100:.001:100)

# ╔═╡ 416f25f2-15f9-4c9d-885a-b2779e195990
begin
	r = @assign(rtype, rmetaparams)
	
	md"""
	``r`` is the anual rate of return on assets. The defaults are [copied from the version 1 model](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.xjnyrwk5etbt).
	
	(If the "low" and "high" values look swapped, that is not a mistake. The models have established the convention that "high" values reward more giving now. The convention matters only for interpretation of cross-parameter correlations.)

	Since 1871, the S&P 500 (or an approximation thereof in the early years) [has returned](https://shillerdata.com) a compound annual growth rate (CAGR) of 6.95%, including dividends and adjusting for inflation. The returns exhibit essentially no year-to-year correlation or long-term trend.

	Past stock market performance is a good baseline for predicting future performance. However, U.S. returns were achieved as America became the greatest economic power in history. And the spectacular gains in recent decades [can](https://www.federalreserve.gov/econres/feds/files/2023041pap.pdf) be [attributed](https://www.gspublishing.com/content/research/en/reports/2024/10/18/29e68989-0d2c-4960-bd4b-010a101f711e.html) to unsustainable factors such as falling interest rates and corporate tax rates. Stocks did less well elsewhere, and could therefore be reasonably predicted to do less well in the U.S. going forward. Here are returns for 1900--2022 from [Credit Suisse](https://www.credit-suisse.com/media/assets/corporate/docs/about-us/research/publications/credit-suisse-global-investment-returns-yearbook-2023-summary-edition.pdf):
	"""
end

# ╔═╡ e4bf8fe4-47a7-4c14-99b9-f39c6c733fed
md"""
Distribution type: $(@getdisttype(∂CEtype, ∂CEtypedefault[]))
"""

# ╔═╡ c050d60d-3409-4c6f-956d-b13dfe1dfcc2
@control(∂CEtype, ∂CEmetaparams, ∂CEmetaparamsdefault, -1:.0001:1)

# ╔═╡ d8682222-b840-4f06-b953-44cd4c6a53a7
begin
∂CE = @assign(∂CEtype, ∂CEmetaparams)

md"""
``∂CE`` is the anual rate of decline (or rise, if ``∂CE < 0``) in our effectiveness for exogenous reasons. It represents the net effect of forces such as declining global poverty and advances in medical technology.

The defaults are copied from the [falll 2023 exercise](https://docs.google.com/spreadsheets/d/1K-j1C8_-oxh2nXfHgmKm_hxSvgYNhHl3zBeQ9AMMM00/edit?gid=935943732#gid=935943732&range=A1). See the version 1 [spenddown write-up](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.mfmlgc8fv17t) for a thoughtful discussion.
"""
end

# ╔═╡ c9b1a39f-881e-4757-a555-f6daf3e26a77
md"""
### Values drift (``v``)
Distribution type: $(@getdisttype(vtype, vtypedefault[]))
"""

# ╔═╡ e2866a95-73a5-4c39-8f7d-403326ef0e37
@control(vtype, vmetaparams, vmetaparamsdefault, -1:.0001:1)

# ╔═╡ c28390d8-b2a0-489f-80a0-c54583fb843c
begin
v = @assign(vtype, vmetaparams)

md"""
``v`` is the anual rate of decline (or rise, if ``v < 0``) in the net present value of our impact owing to mission drift. See [this section](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.iox25644x5fl) of the write-up of the version 1 model.
"""
end

# ╔═╡ e62a679b-6a01-47cc-beaf-9bed178c763a
begin
update_to_loaded_params

md"""
### Flow-through (``f``)

The good we do at can [compound over time](https://blog.givewell.org/2013/05/15/flow-through-effects). Increasing people's income may eventually increase their education, or their children's, and vice versa--and so on, potentially over generations. (See Amartya Sen's [Development as Freedom](https://en.wikipedia.org/wiki/Development_as_Freedom).) In this way, a grant can be seen as trading one form of investment for another: the donor's portfolio shrinks, and so compounds less, while the assets of the rest of society, financial or otherwise, grow and compound faster.

The drafters of the spenddown model are skeptical that flow-through matters much. If the flow-through "multiplier" is about the same regardless of when a grant is made---if $1 in spending ultimately does $2 in good, for example---the effects should largely cancel out influences on the optimal spending path.

For completeness, the model nevertheless includes flow-through. It introduces two wrinkles. To avoid infinities in concept, the rate at which benefits compound can itself decay over time. And to capture the intuition that giving earlier ought to do more good since the compounding begins sooner, existential risk is allowed to vary over time. For example, if we foresee heightened risk of extinction in the middle of this century, then spending just before that period will in expectation have less time to compound than earlier spending. (See Holden Karnofsky's [most important century](https://www.cold-takes.com/most-important-century) series.) 

#### Initial flow-through rate
Distribution type: $(@getdisttype(ftype, ftypedefault[]))
"""
end

# ╔═╡ d5938b8a-03dc-4706-afa8-b018ed13d19d
@control(ftype, fmetaparams, fmetaparamsdefault, -1:.0001:1)

# ╔═╡ 02f745b2-8ce7-4d99-a6ba-0ac2201fe9d7
begin
f = @assign(ftype, fmetaparams)
	
	md"""
Here a value of 0.01 means that initially the good done by a grant compounds at 1%/year. The default values are taken from the [Version 1 write-up](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?pli=1&tab=t.0#heading=h.td08plqwplqx).
"""
end

# ╔═╡ 3aca7360-a8a8-4dfc-b61f-4670f1cd6ac7
md"""

#### Decay of flow-through over time (``\delta_f``)

Annual decay in flow-through rate: $(@getdisttype(δftype, δftypedefault[]))
"""

# ╔═╡ b19ca241-8373-44eb-a572-ccd24c614261
@control(δftype, δfmetaparams, δfmetaparamsdefault, 0:.001:1)

# ╔═╡ 7605db32-345f-4f77-a51b-3eae23359cc4
begin
δf = @assign(δftype, δfmetaparams);
	md"""
	While the good we do might initially compound at the rate or rates specified above, it seems plausible that over the long run they would peter out rather than compounding toward infinity. _Consequences_ might unfurl indefinitely, but whether for good or ill would become increasingly uncertain.

	This parameter describes such decay in benefits. For example if the good done by grantmaking in year 1 compounded by 5% in year 2 (``f = 0.05``), and if ``\delta_f=0.01``, then the compounding between years 2 and 3 would be ``5\% \times (1-0.01) = 4.95\%``. The flow-through rate would continue decaying thereafter.
	
	As long as ``\delta_f>0``, _total_ flow-through will not grow without bound. If ``\delta_f=0``, then flow-through is dropped from the model.
	"""
end

# ╔═╡ 015bceb5-1406-40ff-b2ed-1e9559111ec9
md"""
### X-risk/end-of-scarcity through 2100 (``X``)
Distribution type: $(@getdisttype(Xtype, Xtypedefault[]))
"""

# ╔═╡ 1d3d2829-0bf1-428a-bb21-d11abddbfdcc
@control(Xtype, Xmetaparams, Xmetaparamsdefault, -1:.001:1)

# ╔═╡ 6e0dde3b-91b5-4486-a050-854b8cccb694
begin
X = @assign(Xtype, Xmetaparams)

md"""
``X`` is the risk that philanthropy will end by 2100 because of extinction---or because of its opposite, the end of scarcity. This risk affects not how long spending continues but how long any benefits of any spending "flow through" into the future (see next parameter). See [this section](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.oj8x5fi6sy0) of the version 1 write-up.

The default high value, 0.167, comes from Toby Ord's [estimate](https://theprecipice.com) that there is 1-in-6 chance of human extinction by 2100. The default low and median values come from the Existential Risk Persuasion Tournament (XPT). The XPT [extracted](https://static1.squarespace.com/static/635693acf15a3e2a14a56a4a/t/64f0a7838ccbf43b6b5ee40c/1693493128111/XPT.pdf#page=6) a median estimate of 6% from experts on various existential risks (95% confidence interval [3.41%, 10.00%]) and just 1% ([0.55%, 1.23%]) from non-expert "superforecasters."

In the version 2 model, X-risk is simulated rather than being expressed as discount rate. In each simulation run, an unfair coin is flipped each year. When it comes up heads, the timeline halts, and no more spending or flow-through occurs.
"""
end

# ╔═╡ 8f1f27a3-b256-49c0-887a-377eeebb5745
md"""
### Expropriation risk (``e``)
Distribution type: $(@getdisttype(etype, etypedefault[]))
"""

# ╔═╡ e2febb27-e7c9-4321-8dfa-16b5974274e8
@control(etype, emetaparams, emetaparamsdefault, -1:.0001:1)

# ╔═╡ 37c83e3a-432d-4ec9-8193-9fa23342b838
begin
e = @assign(etype, emetaparams)

md"""
``e`` is the annual risk of that philanthropy will end because of (government) expropriation of the assets. Expropriation might occur suddenly, or over many years through taxation. This risk affects the continuance of spending over time. It does _not_ affect the "flow-through" of any benefits from the spending that does occur (see below).

The default of 0.2%/year comes from [the version 1 write-up](https://docs.google.com/document/d/1HrTRJBMrSxdnskgzfv8sNUKHkRYoOvtS7T1owKUXxJU/edit?tab=t.0#heading=h.oj8x5fi6sy0).
"""
end

# ╔═╡ adda29e5-c8de-4785-badd-edbb495e111a
begin
	update_to_loaded_params
	md"""
	### Pure rate of time preference (``d``)
	
	OP does not usually discount the future simply because it is the future. This is why the default pure rate of time preference is ``0``.
	
	``d = `` $(@bind d NumberField(0:.001:1, default=ddefault[]))
	"""
end

# ╔═╡ b95d201f-c317-471b-a315-6c1acd352880
begin
	update_to_loaded_params
	md"""
	### Initial exogenous spending (``z_1``)
	
	Exogenous spending in year 1 (million $): $(@bind z₁ NumberField(1:1e6, default=z₁default[]))

	Exogenous spending is that which occurs regardless of our actions, yet goes to projects we would otherwise fund. It is modeled as starting at some set level and growing or shrinking at a fixed rate from there.
	
	The value of \$10 million comes from the [fall 2023 exercise](https://docs.google.com/spreadsheets/d/1K-j1C8_-oxh2nXfHgmKm_hxSvgYNhHl3zBeQ9AMMM00/edit?gid=935943732#gid=935943732&range=A1). It is small relative to our giving.
	"""
end

# ╔═╡ f204d544-aa38-474f-95e7-9014edeb019f
md"""
### Growth in exogenous spending (``g``)
Distribution type: $(@getdisttype(gtype, gtypedefault[]))
"""

# ╔═╡ 613c0bd8-e730-40ed-b021-05ad62037c04
@control(gtype, gmetaparams, gmetaparamsdefault, -1:.0001:1)

# ╔═╡ 889773c3-dc87-4ff3-b364-bf60b76de2e1
begin
g = @assign(gtype, gmetaparams)

md"""
``g`` is the anual percentage growth in exogenous spending on our causes, i.e., spending that is not influenced by our decisions. If the growth is positive, it reduces grantmaking opportunities over time, and puts a premium on giving earlier.  The defaults come from [fall 2023](https://docs.google.com/spreadsheets/d/1K-j1C8_-oxh2nXfHgmKm_hxSvgYNhHl3zBeQ9AMMM00/edit?gid=935943732#gid=935943732&range=A1).

The model simulates exogenous spending and calculates our impact using the formula at the end of the mathematical statement above.
"""
end

# ╔═╡ c7d57b24-a644-4a4d-b77b-ec25b329ff42
md"""
### Initial crowding-in rate (``C_1``)
Distribution type: $(@getdisttype(C₁type, C₁typedefault[]))
"""

# ╔═╡ a9459bab-1b78-497a-becb-a735557046f7
@control(C₁type, C₁metaparams, C₁metaparamsdefault, -1:.01:10)

# ╔═╡ 189735c7-9809-4b81-9e57-cab06c9c714b
begin
C₁ = @assign(C₁type, C₁metaparams)

md"""
``C_1`` is initial crowding-in rate of our giving, i.e., the rate of increase in our effective giving caused by other donors copying our funding choices.

It should _not_ be seen as including purposely leveraged funding, since such leveraging is reflected in higher cost-effectiveness. Indeed, use of leverage in LEAF and the regranting challenge is a good example of our learning by doing, which is captured elsewhere in the model.

Here too, the priors are copied from the version 1 model and need to be revisited in a "post-GiveWell" world.
"""
end

# ╔═╡ d5071867-4a64-44f2-89a0-62de047dcd8c
md"""
### Total growth/decline in crowding-in, phase 1 (``∂C``)
Distribution type: $(@getdisttype(∂Ctype, ∂Ctypedefault[]))
"""

# ╔═╡ fc6094b6-1de0-4684-a8a7-013544cf9ef6
@control(∂Ctype, ∂Cmetaparams, ∂Cmetaparamsdefault, -1:.001:1)

# ╔═╡ 76ade393-1507-449c-9f87-4b8062a30cf7
begin
∂C = @assign(∂Ctype, ∂Cmetaparams)

md"""
``∂C`` is a multiplier for cumulative growth or decline in ``C`` during the first period (decade). A value of 1.3 would mean 30% growth in total over phase 1, while 0.7 would mean 30% decline.

Unlike the growth of exogenous spending, the crowding-in multiplier is assumed to change only in phase 1. This structural distinction can be erased by setting ``T_2`` to ``0`` above and setting ``T_1`` to the length of the full simulation period.
"""
end

# ╔═╡ 6c0fd4ad-8971-4e2d-946d-d29c236e14e3
begin
	getkwargs(;kwargs...) = kwargs  # function to turn kwarg list into Vector{Pair}
	
	if Version2
		kwargs = getkwargs(; M=round(Int,M), lnA₀, η, Lₘₐₓ, c, ϕ, δₗ, r, ∂CE, v, e, X, f, δf, d, z₁, g, C₁, ∂C, ẋ, ḅ, μ=S(μ), σ=S(σ), λ=S(λ), GPD, τ, simr, r_geo, r_sd, T₁, T₂, calibrate_b₁, timeline=(try timeline catch _ S[;;] end))

		m = SimModel{S}(Xoshiro(102398); yhist=Vector{S}(try @view yhist[:,2] catch _ S[;] end), kwargs...)
	
		start = fill(logit(S(.1)), m.T-1)  # start: spending 10%/year
		objective = (F, G, H, x) -> sim(m, F, G, H, x)
		o = optimize(NLSolversBase.only_fgh!(objective), start, NewtonTrustRegion())		

		# call once more to get EV by year at optimum
		sim(m, nothing, nothing, nothing, Optim.minimizer(o), byyear=true)
	
		rmed = median(kwargs[:r])  # median rate of return on assets
		A₀med = exp(median(kwargs[:lnA₀]))
		
		x = [logistic.(Optim.minimizer(o)); 1]  # optimal spending as % of assets, including 100% in last year
		A = [A₀med; collect(Iterators.accumulate((Aₜ,xₜ) -> Aₜ*(1-xₜ)*(1+rmed), x, init=A₀med))]  # $ assets
		y = x .* A[1:end-1]  # $ spending by year
	else
		kwargs = getkwargs(; M=round(Int,M), A₀=exp(lnA₀), η, Lₘₐₓ, r, ∂CE, v, e = e + 1-(1-X)^(1/(2100-2025)), f, z₁, g, C₁, ∂C, ẋ, ḅ, τ, T₁, T₂)

		m = SimModelOld{S}(Xoshiro(102398); kwargs...)
	
		objective = x₁->-sum(m(x₁))
		o = optimize(objective, S(0), S(1), GoldenSection())
		A, y = m.cs[1].parent.A, m.cs[1].parent.y
		x = y ./ A
		A = [A; 0]
	end
	paramdict = Dict(kwargs)  # mutable copy, for sensitivity tests

	md"_Optimization code hidden here_"
end

# ╔═╡ 9bfcec49-42f9-414f-ad7c-bfb2280dd85d
md"""
## Optimal timeline

$(Optim.converged(o) ? md"" : md"**Optimizer did not declare convergence**")

Maximum plot year = $(@bind maxxplot Scrubbable(1:m.T; default=m.T)) (Click on the number and drag left or right.)
"""

# ╔═╡ 53aade45-274e-43a2-bde9-184c0e2e3e5f
begin
	fig = Figure(size=(900,900))
	
	Axis(fig[1,1], ylabel="Spending as % of assets", ylabelsize = 20, 
                        xminorgridvisible=true, xticklabelsvisible=false,
		                xticksize=10, xminorticks=(IntervalsBetween(10)),
	                    yminorgridvisible=true,
		                yminorticks=(IntervalsBetween(10)),
			            ytickformat="{:.0%}", yticklabelsize=18,
	                    limits=((1,maxxplot),nothing))
	
	Axis(fig[2,1], ylabel="Assets (million \$)", ylabelsize = 20, 
                        xticksize=10, yminorgridvisible=true, xticklabelsvisible=false, yticklabelsize=18,
		                yminorticks=(IntervalsBetween(10)),
	                    xminorgridvisible=true, xminorticks=(IntervalsBetween(10)),
	                    limits=((1,maxxplot),nothing))

	Axis(fig[3,1], ylabel="Spending (million \$)", ylabelsize = 20, 
                        xticksize=10, xminorgridvisible=true, xticklabelsvisible=false,  yticklabelsize=18,
                        xminorticks=(IntervalsBetween(10)),
	                    yminorgridvisible=true, yminorticks=(IntervalsBetween(10)),
	                    limits=((1,maxxplot),nothing))

    lines!(fig[2,1], 1:maxxplot, A[1:maxxplot], linewidth=2)
	
	lines!(fig[3,1], 1:maxxplot, x[1:maxxplot] .* A[1:maxxplot], linewidth=2)
	
	
  	last_t = findfirst(>(.97), x[1:maxxplot])
	isnothing(last_t) && (last_t=maxxplot)
	lines!(fig[1,1], 1:last_t, x[1:last_t], linewidth=2)
	
	if Version2
		Axis(fig[4,1], ylabel="Impact", ylabelsize = 20, 
                        xminorgridvisible=true, xticklabelsize=20,
	                        xminorticks=(IntervalsBetween(10)),
		                    yminorgridvisible=true, yminorticks= 
                            (IntervalsBetween(10)), yticklabelsize=18,
		                    limits=((1,maxxplot),nothing))
		lines!(fig[4,1], 1:maxxplot, m.u[1:maxxplot], linewidth=2)
	end

	fig
end

# ╔═╡ 6249e76e-b8b6-4a13-b883-3386d16f04f6
begin
	df = DataFrame("Spending %"=>x*100, "Assets"=>A[1:end-1], raw"Spending $"=>y)
end

# ╔═╡ 16698d41-0e2e-4699-9686-3681d60d0aea
# EV vs initial spending plot
begin
	mi = Optim.minimizer(o)
	
	if Version2
		_G = Vector{S}(undef,m.T-1); _H = Matrix{S}(undef,m.T-1,m.T-1)
		# objective with first entries of x constrained
		objective₁(x₁::Vector{S}) where {S} = 
		  (F, G, H, x) -> begin
			    l = length(x₁)
			    EV = sim(m, F, isnothing(G) ? nothing : _G, isnothing(H) ? nothing :              _H, [logit.(x₁); x])
			    isnothing(G) || (G .= @view _G[1+l:end])
			    isnothing(H) || (H .= @view _H[1+l:end,1+l:end])
		    EV
		  end

		peakx, startc = mean(logistic.(mi[1:l])), mi[1+l:end]
	  xplot = S(max(.001,peakx-.1)):S(.01):S(peakx+.1)
		peakEV = -Optim.minimum(o)
		
		EVplot = S[]
		for x₁ ∈ xplot
		  global oc = optimize(NLSolversBase.only_fgh!(objective₁(fill(x₁,l))), startc, NewtonTrustRegion())
		  global startc = Optim.minimizer(oc)
		  push!(EVplot, -Optim.minimum(oc))
		end
	else
		peakx, peakEV = mi, -Optim.minimum(o)/M
		xplot = S(max(.001,peakx-.1)):S(.01):S(peakx+.1)
		EVplot = mean.(m.(xplot))  # old-model objects can be functions: initial spending rate -> EV 
	end
	
	EVloss = EVplot./peakEV .- 1
	# xticks = [peakx; Makie.get_tickvalues(Makie.automatic, identity, 0, maximum(xplot)...)]
	xticks = [peakx, extrema(xplot)...]
	
	figEVloss = Figure()
	a = Axis(figEVloss[1,1]; xlabel="Spending rate in first $(Version2 ? l : m.T₁) years", 
               xminorgridvisible=true, xticks, xtickformat="{:.1%}", 						xlabelsize = 15, ylabelsize = 15, xminorticks=(IntervalsBetween(10)),
	           ylabel="EV loss", ytickformat="{:.1%}", 							        yminorgridvisible=true, yminorticks= 
               (IntervalsBetween(10)))
	lines!(figEVloss[1,1], xplot, EVloss)
	vlines!(figEVloss[1,1], peakx)

	figEVloss
end

# ╔═╡ e254d23c-4969-45b3-b47d-c11e35ff68fc
if sym != :none
	yplotsens = S[]
	if Version2
		startsens = Optim.minimizer(o)
		for s ∈ rangesens
			paramdict[sym] = kwargs[sym] * S(s)
			msens = SimModel{S}(Xoshiro(102398); M=round(Int,M), yhist=Vector{S}(yhist[:,2]), τ, 
                                T₁, T₂, paramdict...)
			objectivesens = (F, G, H, x) -> sim(msens, F, G, H, x)
			osens = Optim.optimize(Optim.only_fgh!(objectivesens), startsens, NewtonTrustRegion())
			push!(yplotsens, logistic(Optim.minimizer(osens)[1])*exp(m.lnA₀))
			global startsens = Optim.minimizer(osens)
		end
	else
		for s ∈ rangesens
			paramdict[sym] = kwargs[sym] * S(s)
			msens = SimModelOld{S}(Xoshiro(102398); M=round(Int,M), τ, T₁, T₂, paramdict...)
			
			objectivesens = x₁->-sum(msens(x₁))
			osens = Optim.optimize(objectivesens, S(0), S(1), GoldenSection())
			push!(yplotsens, Optim.minimizer(osens)*exp(m.lnA₀))
		end
	end
	
	if paramdict[:η] isa UnivariateDistribution
		lines(rangesens * median(kwargs[sym]), yplotsens, axis=(xlabel="Median " * string(sym), 
              ylabel="Year 1 spending (million \$)"))
	else
		lines(rangesens * kwargs[sym], yplotsens, axis=(xlabel=string(sym), ylabel="average initial spending/year (million \$)"))
	end
end

# ╔═╡ 50a81f1e-1638-4280-96c3-cbd7aab260fb
# ╠═╡ skip_as_script = true
#=╠═╡
begin
	fighist = Figure()
	Axis(fighist[1,1]; xlabel="Utility", title="Simulated distribution, with mean and median")
	hist!(fighist[1,1], m.dist, normalization=:density, bins=floor(Int,√size(m.dist,1)))
	vlines!(fighist[1,1], [mean(m.dist), median(m.dist)])
	fighist
end
  ╠═╡ =#

# ╔═╡ a85fe9a3-2791-4ab8-9c8e-b7976ad78688
begin
	io = IOBuffer()
	print(io, merge(paramdict, Dict(:M=>M, :S=>S, :Version2=>Version2, :simr=>simr, :r_geo=>r_geo, :t₁=>t₁, :T₁=>T₁, :T₂=>T₂, :τ=>τ)))  # dump parameters
	print(io, "\n\n#=\n", df, "=#")  # dump optimal timelines
	savetxt = String(take!(io))
	
	md"""
	## Save
	Edit file name: $(@bind downloadname TextField((90,1),default=#=Sys.username()*" "*=#string(today())*" [your description here].txt"))
	"""
end

# ╔═╡ c9643bd7-0125-4a9a-8b70-b966bbccf2fa
DownloadButton(savetxt, downloadname)

# ╔═╡ Cell order:
# ╟─c75bd415-6a7f-4a2f-9d0e-85fd25c5a185
# ╟─66c691d0-7839-442e-9440-107e8acf3f14
# ╟─cf97b742-65c1-431e-b4ec-abd49c6c16c7
# ╟─8c9aa9bd-87fc-4d62-b26a-2a4c2d89fe00
# ╟─d603cef6-5db4-4ae6-8ced-deb3746df9a0
# ╟─9964440e-a931-49c3-934b-9fe717ce61d9
# ╟─9b77c635-7fc6-4813-99ec-0b09d2f94c13
# ╟─ee95926c-6ea1-4b47-8e58-c5a271aa8b0a
# ╟─5c184343-e6b7-4b10-8157-607b667c507c
# ╟─b2b2448e-a6f1-4795-b029-3cf88ed9e305
# ╟─92bab01e-4c08-4f3e-8190-138a5c9181f4
# ╟─72dd2e82-fa0d-4500-bb67-6ee615398b62
# ╟─817d5e1f-9d9c-4c74-8d81-0c5aff46415b
# ╟─224446c2-6a8e-46b9-9780-7b9dc5c9b21d
# ╟─a8e4ca99-8d9b-42b1-b628-0eac915514f9
# ╟─aacaa244-c6d3-47ec-a6fd-68278f108303
# ╟─d9029735-fd6a-4032-8480-44b2624501a9
# ╟─c35e5119-a9c4-4575-b199-68c21ac48c54
# ╟─f1a7bbba-91d1-4a2b-b907-723df653de3c
# ╟─1151d56b-7771-4d6c-8076-2340b0a8c483
# ╟─f75fa40c-5af7-4eb7-ab86-3b3f9acb0dce
# ╟─62a746fc-5455-4789-b5db-4cfb737762dd
# ╟─9bc51dce-4d25-4900-9c27-4ca1b2b351a0
# ╟─55f6ab36-7511-4ea1-b4c1-d09fa1bc7442
# ╟─bf7a906f-11af-4d4b-8c65-e365d0661cf5
# ╟─3588ce71-0d64-42d0-9610-3b9f669c8c65
# ╟─26a2c19f-e401-4671-81bf-5c24339b1bf4
# ╟─5087952f-4b1d-497c-9c1b-ed5ebae34c81
# ╟─8bd60ffd-b287-468c-96f2-6aa0962f4495
# ╟─0554c422-b130-4a8e-abe6-2f4ad7ae8956
# ╟─218b6bc8-453a-44eb-97bc-6e8ac0851422
# ╟─ebf524ce-55ec-446f-b9fc-84d76e5dad0b
# ╟─0952a455-f9e4-4fcf-a285-a16f57f46042
# ╟─6cc88f19-e9fe-42c7-abd4-2ba7e0f13527
# ╠═fdf68695-2217-45ad-b56b-4b7e75b5c13f
# ╟─3e34cbba-ac5a-426a-a1df-64a22fe9d7ce
# ╟─e3836f7c-e60a-4382-b559-5bfda82e6cbe
# ╟─9fdff29f-0a0a-4bf9-b083-563d35a46b2b
# ╟─7a1ea043-8743-4943-9ba7-f4afa02e032b
# ╟─416f25f2-15f9-4c9d-885a-b2779e195990
# ╟─fce075f4-cd42-4169-9f4c-c0c298cf687c
# ╟─48e29a4a-fd3a-47a4-9c8f-e5f4ae235b9a
# ╟─acf6cb7d-0d6b-41f2-91b8-4dce0c8d4545
# ╟─193a0195-93ef-4da0-8d10-698bdca822cb
# ╟─a59c4fcf-44d0-49e3-bae5-61d90f333880
# ╟─e4bf8fe4-47a7-4c14-99b9-f39c6c733fed
# ╟─c050d60d-3409-4c6f-956d-b13dfe1dfcc2
# ╟─d8682222-b840-4f06-b953-44cd4c6a53a7
# ╟─c9b1a39f-881e-4757-a555-f6daf3e26a77
# ╟─e2866a95-73a5-4c39-8f7d-403326ef0e37
# ╟─c28390d8-b2a0-489f-80a0-c54583fb843c
# ╟─e62a679b-6a01-47cc-beaf-9bed178c763a
# ╟─d5938b8a-03dc-4706-afa8-b018ed13d19d
# ╟─02f745b2-8ce7-4d99-a6ba-0ac2201fe9d7
# ╟─3aca7360-a8a8-4dfc-b61f-4670f1cd6ac7
# ╟─b19ca241-8373-44eb-a572-ccd24c614261
# ╟─7605db32-345f-4f77-a51b-3eae23359cc4
# ╟─015bceb5-1406-40ff-b2ed-1e9559111ec9
# ╟─1d3d2829-0bf1-428a-bb21-d11abddbfdcc
# ╟─6e0dde3b-91b5-4486-a050-854b8cccb694
# ╟─fbe051c5-ba18-49f6-b443-692b20a292aa
# ╠═d10a63ba-6670-4c36-a322-6bd45587ce05
# ╟─8f1f27a3-b256-49c0-887a-377eeebb5745
# ╟─e2febb27-e7c9-4321-8dfa-16b5974274e8
# ╟─37c83e3a-432d-4ec9-8193-9fa23342b838
# ╟─adda29e5-c8de-4785-badd-edbb495e111a
# ╟─574c0bcc-05ae-4222-a76d-09df6bff411e
# ╟─b95d201f-c317-471b-a315-6c1acd352880
# ╟─f204d544-aa38-474f-95e7-9014edeb019f
# ╟─613c0bd8-e730-40ed-b021-05ad62037c04
# ╟─889773c3-dc87-4ff3-b364-bf60b76de2e1
# ╟─c7d57b24-a644-4a4d-b77b-ec25b329ff42
# ╟─a9459bab-1b78-497a-becb-a735557046f7
# ╟─189735c7-9809-4b81-9e57-cab06c9c714b
# ╟─d5071867-4a64-44f2-89a0-62de047dcd8c
# ╟─fc6094b6-1de0-4684-a8a7-013544cf9ef6
# ╟─76ade393-1507-449c-9f87-4b8062a30cf7
# ╟─7c6dc66d-a893-485b-8057-e04f668e12ef
# ╠═529b4f14-b60b-4400-aac7-50d8a5ea974e
# ╠═cdf22b2d-271c-47e9-8bf6-daea461fb4e5
# ╟─6c0fd4ad-8971-4e2d-946d-d29c236e14e3
# ╟─bc2c8b47-a844-40b4-bd5f-85afdfb4ee2c
# ╟─64f154c2-91c2-452f-a9ba-922a76a173a0
# ╟─9bfcec49-42f9-414f-ad7c-bfb2280dd85d
# ╟─53aade45-274e-43a2-bde9-184c0e2e3e5f
# ╟─e6b5c24a-7133-4305-a2a3-7f242b3b0c12
# ╟─6249e76e-b8b6-4a13-b883-3386d16f04f6
# ╟─2f9494b8-2706-4d7a-9a15-c09ae0bc715b
# ╟─16698d41-0e2e-4699-9686-3681d60d0aea
# ╟─bade4869-d9b0-45f5-9edb-4e2234e91b4a
# ╟─7832130e-4bcb-4188-b2ef-3476d0fd0f5a
# ╟─e254d23c-4969-45b3-b47d-c11e35ff68fc
# ╟─09be9aa7-dcf4-4078-a232-8e7a46bec617
# ╟─45cee101-4bcd-4a6c-8fbc-22b5183cbfc4
# ╟─50a81f1e-1638-4280-96c3-cbd7aab260fb
# ╟─582c04d7-bde3-486b-9af7-d1d1c5ead14c
# ╟─a85fe9a3-2791-4ab8-9c8e-b7976ad78688
# ╠═c9643bd7-0125-4a9a-8b70-b966bbccf2fa
# ╟─2dc51672-466b-4ba4-8a20-abbd12f9cbe2
# ╟─cf3e479c-74f0-4692-908b-773eb939e653
# ╟─70785342-7c94-4073-9572-8698f1ef9ac2
