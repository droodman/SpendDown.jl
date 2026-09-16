### A Pluto.jl notebook ###
# v0.20.28

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
	pushfirst!(LOAD_PATH,"..")  # This notebook sits in /src while the SpendDown package definition sits in the parent dir
	
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

# ╔═╡ a8e4ca99-8d9b-42b1-b628-0eac915514f9
md"""
### Start year (``t_1``)

``t_1`` = $(@bind t₁ NumberField(2020:2100, default=t₁default[]))

Calendar year in which spending starts. This matters only for interpreting the X-risk timeline below.
"""

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

# ╔═╡ 1151d56b-7771-4d6c-8076-2340b0a8c483
md"""
## Learning
"""

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

# ╔═╡ 55f6ab36-7511-4ea1-b4c1-d09fa1bc7442
md"""
### Endogenous learning
"""

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
# probability of artificial generalized intelligence (AGI) being developed by various dates, as starting point for time-varying X-risk timeline
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

# ╔═╡ 574c0bcc-05ae-4222-a76d-09df6bff411e
md"""
## Other donors
"""

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

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
AxisKeys = "94b1ba4f-4ee9-5380-92f1-94cde586c3c5"
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
LogExpFunctions = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
NLSolversBase = "d41bc354-129a-5804-8e4c-c37616107c6c"
Optim = "429524aa-4258-5aef-a3af-852621145aeb"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"

[compat]
AxisKeys = "~0.2.17"
CairoMakie = "~0.15.14"
ChainRulesCore = "~1.26.1"
DataFrames = "~1.8.2"
Distributions = "~0.25.131"
LogExpFunctions = "~1.0.1"
NLSolversBase = "~8.0.1"
Optim = "~2.3.2"
PlutoUI = "~0.7.63"
StatsBase = "~0.34.13"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.13.0"
manifest_format = "2.1"
project_hash = "f456a07a86335c031c1561a0b737d06009fdd3c1"

[[deps.ADTypes]]
deps = ["PrecompileTools"]
git-tree-sha1 = "629de23e1c16911b439dabd2303c08af9575b226"
registries = "General"
uuid = "47edcb42-4c32-4615-8424-f2b9edc5f35b"
version = "1.24.0"

    [deps.ADTypes.extensions]
    ADTypesChainRulesCoreExt = "ChainRulesCore"
    ADTypesConstructionBaseExt = "ConstructionBase"
    ADTypesEnzymeCoreExt = "EnzymeCore"

    [deps.ADTypes.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ConstructionBase = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
    EnzymeCore = "f151be2c-9106-41f4-ab19-57ee4f262869"

[[deps.AbstractFFTs]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "d92ad398961a3ed262d8bf04a1a2b8340f915fef"
registries = "General"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.5.0"
weakdeps = ["ChainRulesCore", "Test"]

    [deps.AbstractFFTs.extensions]
    AbstractFFTsChainRulesCoreExt = "ChainRulesCore"
    AbstractFFTsTestExt = "Test"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "6e1d2a35f2f90a4bc7c2ed98079b2ba09c35b83a"
registries = "General"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.3.2"

[[deps.AbstractTrees]]
git-tree-sha1 = "2d9c9a55f9c93e8887ad391fbae72f8ef55e1177"
registries = "General"
uuid = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
version = "0.4.5"

[[deps.Accessors]]
deps = ["CompositionsBase", "ConstructionBase", "Dates", "InverseFunctions", "MacroTools"]
git-tree-sha1 = "7063ad1083578215c7c4bf410368150abe8d5524"
registries = "General"
uuid = "7d9f7c33-5ae7-4f3b-8dc6-eff91059b697"
version = "0.1.45"
weakdeps = ["AxisKeys", "IntervalSets", "LinearAlgebra", "StaticArrays", "StructArrays", "Test", "Unitful"]

    [deps.Accessors.extensions]
    AxisKeysExt = "AxisKeys"
    IntervalSetsExt = "IntervalSets"
    LinearAlgebraExt = "LinearAlgebra"
    StaticArraysExt = "StaticArrays"
    StructArraysExt = "StructArrays"
    TestExt = "Test"
    UnitfulExt = "Unitful"

[[deps.Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "7c2c19b5a26e601634bf718490b89d59685f122e"
registries = "General"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "4.7.1"
weakdeps = ["SparseArrays", "StaticArrays"]

    [deps.Adapt.extensions]
    AdaptSparseArraysExt = "SparseArrays"
    AdaptStaticArraysExt = "StaticArrays"

[[deps.AdaptivePredicates]]
git-tree-sha1 = "7e651ea8d262d2d74ce75fdf47c4d63c07dba7a6"
registries = "General"
uuid = "35492f91-a3bd-45ad-95db-fcad7dcfedb7"
version = "1.2.0"

[[deps.AliasTables]]
deps = ["PtrArrays", "Random"]
git-tree-sha1 = "9876e1e164b144ca45e9e3198d0b689cadfed9ff"
registries = "General"
uuid = "66dad0bd-aa9a-41b7-9441-69ab47430ed8"
version = "1.1.3"

[[deps.Animations]]
deps = ["Colors"]
git-tree-sha1 = "e092fa223bf66a3c41f9c022bd074d916dc303e7"
registries = "General"
uuid = "27a7e980-b3e6-11e9-2bcd-0b925532e340"
version = "0.4.2"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.ArrayInterface]]
deps = ["Adapt", "LinearAlgebra"]
git-tree-sha1 = "1aec1ff0dcaa83a484e7f72097562fa3102c6722"
registries = "General"
uuid = "4fba245c-0d91-5ea0-9b3e-6abc04ee57a9"
version = "7.30.2"

    [deps.ArrayInterface.extensions]
    ArrayInterfaceAMDGPUExt = "AMDGPU"
    ArrayInterfaceBandedMatricesExt = "BandedMatrices"
    ArrayInterfaceBlockBandedMatricesExt = "BlockBandedMatrices"
    ArrayInterfaceCUDAExt = "CUDA"
    ArrayInterfaceCUDSSExt = ["CUDSS", "CUDA"]
    ArrayInterfaceChainRulesCoreExt = "ChainRulesCore"
    ArrayInterfaceChainRulesExt = "ChainRules"
    ArrayInterfaceFillArraysExt = "FillArrays"
    ArrayInterfaceGPUArraysCoreExt = "GPUArraysCore"
    ArrayInterfaceGPUArraysCoreTrackerExt = ["GPUArraysCore", "Tracker"]
    ArrayInterfaceMetalExt = "Metal"
    ArrayInterfaceReverseDiffExt = "ReverseDiff"
    ArrayInterfaceSparseArraysExt = "SparseArrays"
    ArrayInterfaceStaticArraysCoreExt = "StaticArraysCore"
    ArrayInterfaceTrackerExt = "Tracker"

    [deps.ArrayInterface.weakdeps]
    AMDGPU = "21141c5a-9bdb-4563-92ae-f87d6854732e"
    BandedMatrices = "aae01518-5342-5314-be14-df237901396f"
    BlockBandedMatrices = "ffab5731-97b5-5995-9138-79e8c1846df0"
    CUDA = "052768ef-5323-5732-b1bb-66c8b64840ba"
    CUDSS = "45b445bb-4962-46a0-9369-b4df9d0f772e"
    ChainRules = "082447d4-558c-5d27-93f4-14fc19e9eca2"
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    FillArrays = "1a297f60-69ca-5386-bcde-b61e274b549b"
    GPUArraysCore = "46192b85-c4d5-4398-a991-12ede77f4527"
    Metal = "dde4c033-4e86-420c-a63e-0dd931031962"
    ReverseDiff = "37e2e3b7-166d-5795-8a7a-e32c996b4267"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
    StaticArraysCore = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
    Tracker = "9f7883ad-71c0-57eb-9f7f-b5c9e6d3789c"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Automa]]
deps = ["PrecompileTools", "TranscodingStreams"]
git-tree-sha1 = "94eab0b3ccdcac361188cc661daf69d4433c1818"
registries = "General"
uuid = "67c07d97-cdcb-5c2c-af73-a7f9c32a568b"
version = "1.2.0"

[[deps.AxisAlgorithms]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "WoodburyMatrices"]
git-tree-sha1 = "01b8ccb13d68535d73d2b0c23e39bd23155fb712"
registries = "General"
uuid = "13072b0f-2c55-5437-9ae7-d433b7a33950"
version = "1.1.0"

[[deps.AxisArrays]]
deps = ["Dates", "IntervalSets", "IterTools", "RangeArrays"]
git-tree-sha1 = "4126b08903b777c88edf1754288144a0492c05ad"
registries = "General"
uuid = "39de3d68-74b9-583c-8d2d-e117c070f3a9"
version = "0.4.8"

[[deps.AxisKeys]]
deps = ["IntervalSets", "LinearAlgebra", "NamedDims", "Tables"]
git-tree-sha1 = "74f4672d77b0a98c808880a556768fe2ccf99b13"
registries = "General"
uuid = "94b1ba4f-4ee9-5380-92f1-94cde586c3c5"
version = "0.2.17"

    [deps.AxisKeys.extensions]
    AbstractFFTsExt = "AbstractFFTs"
    ChainRulesCoreExt = "ChainRulesCore"
    CovarianceEstimationExt = "CovarianceEstimation"
    InterpolationsExt = "Interpolations"
    InvertedIndicesExt = "InvertedIndices"
    LazyStackExt = "LazyStack"
    OffsetArraysExt = "OffsetArrays"
    StatisticsExt = "Statistics"
    StatsBaseExt = "StatsBase"

    [deps.AxisKeys.weakdeps]
    AbstractFFTs = "621f4979-c628-5d54-868e-fcf4e3e8185c"
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    CovarianceEstimation = "587fd27a-f159-11e8-2dae-1979310e6154"
    Interpolations = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
    InvertedIndices = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
    LazyStack = "1fad7336-0346-5a1a-a56f-a06ba010965b"
    OffsetArrays = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
    Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
    StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.BaseDirs]]
git-tree-sha1 = "8c290a1b223deaeea9aea44b235d24546da8eb98"
registries = "General"
uuid = "18cc8868-cbac-4acf-b575-c8ff214dc66f"
version = "1.4.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1b96ea4a01afe0ea4090c5c8039690672dd13f2e"
registries = "General"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.9+0"

[[deps.CEnum]]
git-tree-sha1 = "389ad5c84de1ae7cf0e28e381131c98ea87d54fc"
registries = "General"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.5.0"

[[deps.CRC32c]]
uuid = "8bf52ea8-c179-5cab-976a-9e18b702a9bc"
version = "1.11.0"

[[deps.CRlibm]]
deps = ["CRlibm_jll"]
git-tree-sha1 = "66188d9d103b92b6cd705214242e27f5737a1e5e"
registries = "General"
uuid = "96374032-68de-5a5b-8d9e-752f78720389"
version = "1.0.2"

[[deps.CRlibm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e329286945d0cfc04456972ea732551869af1cfc"
registries = "General"
uuid = "4e9b3aee-d8a1-5a3d-ad8b-7d824db253f0"
version = "1.0.1+0"

[[deps.Cairo]]
deps = ["Cairo_jll", "Colors", "Glib_jll", "Graphics", "Libdl", "Pango_jll"]
git-tree-sha1 = "71aa551c5c33f1a4415867fe06b7844faadb0ae9"
registries = "General"
uuid = "159f3aea-2a34-519c-b102-8c37f9878175"
version = "1.1.1"

[[deps.CairoMakie]]
deps = ["CRC32c", "Cairo", "Cairo_jll", "Colors", "FileIO", "FreeType", "GeometryBasics", "LinearAlgebra", "Makie", "PrecompileTools"]
git-tree-sha1 = "3495bfc164949714579501b825b8e5e2cce7c56f"
registries = "General"
uuid = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
version = "0.15.14"

[[deps.Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "Libdl", "Pixman_jll", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "1fa950ebc3e37eccd51c6a8fe1f92f7d86263522"
registries = "General"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.18.7+0"

[[deps.ChainRulesCore]]
deps = ["Compat", "LinearAlgebra"]
git-tree-sha1 = "12177ad6b3cad7fd50c8b3825ce24a99ad61c18f"
registries = "General"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.26.1"
weakdeps = ["SparseArrays"]

    [deps.ChainRulesCore.extensions]
    ChainRulesCoreSparseArraysExt = "SparseArrays"

[[deps.CodecZstd]]
deps = ["TranscodingStreams", "Zstd_jll"]
git-tree-sha1 = "da54a6cd93c54950c15adf1d336cfd7d71f51a56"
registries = "General"
uuid = "6b39b394-51ab-5f42-8807-6242bab2b4c2"
version = "0.8.7"

[[deps.ColorBrewer]]
deps = ["Colors", "JSON"]
git-tree-sha1 = "07da79661b919001e6863b81fc572497daa58349"
registries = "General"
uuid = "a2cac450-b92f-5266-8821-25eda20663c8"
version = "0.4.2"

[[deps.ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "PrecompileTools", "Random"]
git-tree-sha1 = "b0fd3f56fa442f81e0a47815c92245acfaaa4e34"
registries = "General"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.31.0"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "b10d0b65641d57b8b4d5e234446582de5047050d"
registries = "General"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.5"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "Requires", "Statistics", "TensorCore"]
git-tree-sha1 = "a1f44953f2382ebb937d60dafbe2deea4bd23249"
registries = "General"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.10.0"
weakdeps = ["SpecialFunctions"]

    [deps.ColorVectorSpace.extensions]
    SpecialFunctionsExt = "SpecialFunctions"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "37ea44092930b1811e666c3bc38065d7d87fcc74"
registries = "General"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.13.1"

[[deps.CommonSolve]]
deps = ["PrecompileTools"]
git-tree-sha1 = "6c389fa857f6ca5a95474b52a52023fd77f24cb7"
registries = "General"
uuid = "38540f10-b2f7-11e9-35d8-d573e4eb0ff2"
version = "0.2.14"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "9d8a54ce4b17aa5bdce0ea5c34bc5e7c340d16ad"
registries = "General"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.18.1"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.5.5+2"

[[deps.CompositionsBase]]
git-tree-sha1 = "802bb88cd69dfd1509f6670416bd4434015693ad"
registries = "General"
uuid = "a33af91c-f02d-484b-be07-31d278c5ca2b"
version = "0.1.2"
weakdeps = ["InverseFunctions"]

    [deps.CompositionsBase.extensions]
    CompositionsBaseInverseFunctionsExt = "InverseFunctions"

[[deps.ComputePipeline]]
deps = ["Observables", "Preferences"]
git-tree-sha1 = "7bc84b769c1d384315e7b5c4ac03a6c303e6cf35"
registries = "General"
uuid = "95dc2771-c249-4cd0-9c9f-1f3b4330693c"
version = "0.1.8"

[[deps.ConstructionBase]]
git-tree-sha1 = "b4b092499347b18a015186eae3042f72267106cb"
registries = "General"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.6.0"
weakdeps = ["IntervalSets", "LinearAlgebra", "StaticArrays"]

    [deps.ConstructionBase.extensions]
    ConstructionBaseIntervalSetsExt = "IntervalSets"
    ConstructionBaseLinearAlgebraExt = "LinearAlgebra"
    ConstructionBaseStaticArraysExt = "StaticArrays"

[[deps.Contour]]
git-tree-sha1 = "439e35b0b36e2e5881738abc8857bd92ad6ff9a8"
registries = "General"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.6.3"

[[deps.CoreMath]]
deps = ["CoreMath_jll"]
git-tree-sha1 = "8c0480f92b1b1796239156a1b9b1bfb1b39499b4"
registries = "General"
uuid = "b7a15901-be09-4a0e-87d2-2e66b0e09b5a"
version = "0.1.0"

[[deps.CoreMath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "a692a4c1dc59a4b8bc0b6403876eb3250fde2bc3"
registries = "General"
uuid = "a38c48d9-6df1-5ac9-9223-b6ada3b5572b"
version = "0.1.0+0"

[[deps.Crayons]]
git-tree-sha1 = "54b76cbb40d9a0f5368c880725b2f141da77c94f"
registries = "General"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.2.0"

[[deps.DataAPI]]
git-tree-sha1 = "abe83f3a2f1b857aac70ef8b269080af17764bbe"
registries = "General"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.16.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "DataStructures", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrecompileTools", "PrettyTables", "Printf", "Random", "Reexport", "SentinelArrays", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "5fab31e2e01e70ad66e3e24c968c264d1cf166d6"
registries = "General"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.8.2"

[[deps.DataStructures]]
deps = ["OrderedCollections"]
git-tree-sha1 = "b0bc6d2cad1fed8b7fd59a1551a991cb3d2809e6"
registries = "General"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.19.6"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
registries = "General"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.DelaunayTriangulation]]
deps = ["AdaptivePredicates", "EnumX", "ExactPredicates", "Random"]
git-tree-sha1 = "4ac548adcad90c1d5d677af13568a748af4c952b"
registries = "General"
uuid = "927a84f5-c5f4-47a5-9785-b46e178433df"
version = "1.6.7"

[[deps.DifferentiationInterface]]
deps = ["ADTypes", "LinearAlgebra"]
git-tree-sha1 = "0693d8b0a4608ff289d228ab4c598df5894845cd"
registries = "General"
uuid = "a0c0ee7d-e4b9-4e03-894e-1c5f64a51d63"
version = "0.7.21"

    [deps.DifferentiationInterface.extensions]
    DifferentiationInterfaceChainRulesCoreExt = "ChainRulesCore"
    DifferentiationInterfaceDiffractorExt = "Diffractor"
    DifferentiationInterfaceEnzymeExt = ["EnzymeCore", "Enzyme"]
    DifferentiationInterfaceFastDifferentiationExt = "FastDifferentiation"
    DifferentiationInterfaceFiniteDiffExt = "FiniteDiff"
    DifferentiationInterfaceFiniteDifferencesExt = "FiniteDifferences"
    DifferentiationInterfaceForwardDiffExt = ["ForwardDiff", "DiffResults"]
    DifferentiationInterfaceGPUArraysCoreExt = ["GPUArraysCore", "Adapt"]
    DifferentiationInterfaceGTPSAExt = "GTPSA"
    DifferentiationInterfaceHyperHessiansExt = "HyperHessians"
    DifferentiationInterfaceMooncakeExt = "Mooncake"
    DifferentiationInterfacePolyesterForwardDiffExt = ["PolyesterForwardDiff", "ForwardDiff", "DiffResults"]
    DifferentiationInterfaceReverseDiffExt = ["ReverseDiff", "DiffResults"]
    DifferentiationInterfaceSparseArraysExt = "SparseArrays"
    DifferentiationInterfaceSparseConnectivityTracerExt = "SparseConnectivityTracer"
    DifferentiationInterfaceSparseMatrixColoringsExt = "SparseMatrixColorings"
    DifferentiationInterfaceStaticArraysExt = "StaticArrays"
    DifferentiationInterfaceSymbolicsExt = "Symbolics"
    DifferentiationInterfaceTrackerExt = "Tracker"
    DifferentiationInterfaceZygoteExt = ["Zygote", "ForwardDiff"]

    [deps.DifferentiationInterface.weakdeps]
    Adapt = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    DiffResults = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
    Diffractor = "9f5e2b26-1114-432f-b630-d3fe2085c51c"
    Enzyme = "7da242da-08ed-463a-9acd-ee780be4f1d9"
    EnzymeCore = "f151be2c-9106-41f4-ab19-57ee4f262869"
    FastDifferentiation = "eb9bf01b-bf85-4b60-bf87-ee5de06c00be"
    FiniteDiff = "6a86dc24-6348-571c-b903-95158fe2bd41"
    FiniteDifferences = "26cc04aa-876d-5657-8c51-4c34ba976000"
    ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210"
    GPUArraysCore = "46192b85-c4d5-4398-a991-12ede77f4527"
    GTPSA = "b27dd330-f138-47c5-815b-40db9dd9b6e8"
    HyperHessians = "06b494a0-c8e0-40cc-ad32-d99506a00a6c"
    Mooncake = "da2b9cff-9c12-43a0-ae48-6db2b0edb7d6"
    PolyesterForwardDiff = "98d1487c-24ca-40b6-b7ab-df2af84e126b"
    ReverseDiff = "37e2e3b7-166d-5795-8a7a-e32c996b4267"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
    SparseConnectivityTracer = "9f842d2f-2579-4b1d-911e-f412cf18a3f5"
    SparseMatrixColorings = "0a514795-09f3-496d-8182-132a7b665d35"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"
    Symbolics = "0c5d862f-8b57-4792-8d23-62f2024744c7"
    Tracker = "9f7883ad-71c0-57eb-9f7f-b5c9e6d3789c"
    Zygote = "e88e6eb3-aa80-5325-afca-941959d7151f"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"
version = "1.11.0"

[[deps.Distributions]]
deps = ["AliasTables", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "Roots", "SpecialFunctions", "Statistics", "StatsAPI", "StatsBase", "StatsFuns"]
git-tree-sha1 = "a958ab3a40c755563f5e1405c0846cb0446bf19d"
registries = "General"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.131"

    [deps.Distributions.extensions]
    DistributionsChainRulesCoreExt = "ChainRulesCore"
    DistributionsDensityInterfaceExt = "DensityInterface"
    DistributionsSparseConnectivityTracerExt = "SparseConnectivityTracer"
    DistributionsTestExt = "Test"

    [deps.Distributions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    DensityInterface = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
    SparseConnectivityTracer = "9f842d2f-2579-4b1d-911e-f412cf18a3f5"
    Test = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.DocStringExtensions]]
git-tree-sha1 = "7442a5dfe1ebb773c29cc2962a8980f47221d76c"
registries = "General"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.5"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.7.0"

[[deps.EarCut_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e3290f2d49e661fbd94046d7e3726ffcb2d41053"
registries = "General"
uuid = "5ae413db-bbd1-5e63-b57d-d24a61df00f5"
version = "2.2.4+0"

[[deps.EnumX]]
git-tree-sha1 = "c49898e8438c828577f04b92fc9368c388ac783c"
registries = "General"
uuid = "4e289a0a-7415-4d19-859d-a7e5c4648b56"
version = "1.0.7"

[[deps.ExactPredicates]]
deps = ["IntervalArithmetic", "Random", "StaticArrays"]
git-tree-sha1 = "83231673ea4d3d6008ac74dc5079e77ab2209d8f"
registries = "General"
uuid = "429591f6-91af-11e9-00e2-59fbe8cec110"
version = "2.2.9"

[[deps.Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "2bfb1e047e2ad0a5ca94365340bde8005d637568"
registries = "General"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.8.4+0"

[[deps.FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "PCRE2_jll", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libva_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "7a58e45171b63ed4782f2d36fdee8713a469e6e0"
registries = "General"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "8.1.2+0"

[[deps.FFTA]]
deps = ["AbstractFFTs", "DocStringExtensions", "LinearAlgebra", "MuladdMacro", "Primes", "Random", "Reexport"]
git-tree-sha1 = "65e55303b72f4a567a51b174dd2c47496efeb95a"
registries = "General"
uuid = "b86e33f2-c0db-4aa1-a6e0-ab43e668529e"
version = "0.3.1"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "6621fef488e496356c9c9625d0562c12a6070819"
registries = "General"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.20.0"

    [deps.FileIO.extensions]
    HTTPExt = "HTTP"

    [deps.FileIO.weakdeps]
    HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"

[[deps.FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport"]
git-tree-sha1 = "a1b2fbfe98503f15b665ed45b3d149e5d8895e4c"
registries = "General"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.9.0"

    [deps.FilePaths.extensions]
    FilePathsGlobExt = "Glob"
    FilePathsURIParserExt = "URIParser"
    FilePathsURIsExt = "URIs"

    [deps.FilePaths.weakdeps]
    Glob = "c27321d9-0574-5035-807b-f59d2c89b15c"
    URIParser = "30578b45-9adc-5946-b283-645ec420af67"
    URIs = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"

[[deps.FilePathsBase]]
deps = ["Compat", "Dates"]
git-tree-sha1 = "3bab2c5aa25e7840a4b065805c0cdfc01f3068d2"
registries = "General"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.24"
weakdeps = ["Mmap", "Test"]

    [deps.FilePathsBase.extensions]
    FilePathsBaseMmapExt = "Mmap"
    FilePathsBaseTestExt = "Test"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FillArrays]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "5bad39456d9f0166184fce2248783dd9862645c1"
registries = "General"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "1.17.0"
weakdeps = ["PDMats", "SparseArrays", "StaticArrays", "Statistics"]

    [deps.FillArrays.extensions]
    FillArraysPDMatsExt = "PDMats"
    FillArraysSparseArraysExt = "SparseArrays"
    FillArraysStaticArraysExt = "StaticArrays"
    FillArraysStatisticsExt = "Statistics"

[[deps.FiniteDiff]]
deps = ["ArrayInterface", "LinearAlgebra", "Setfield"]
git-tree-sha1 = "5031f23e040bf17082e5b52422d77b5e844eefb1"
registries = "General"
uuid = "6a86dc24-6348-571c-b903-95158fe2bd41"
version = "2.33.0"

    [deps.FiniteDiff.extensions]
    FiniteDiffBandedMatricesExt = "BandedMatrices"
    FiniteDiffBlockBandedMatricesExt = "BlockBandedMatrices"
    FiniteDiffSparseArraysExt = "SparseArrays"
    FiniteDiffStaticArraysExt = "StaticArrays"

    [deps.FiniteDiff.weakdeps]
    BandedMatrices = "aae01518-5342-5314-be14-df237901396f"
    BlockBandedMatrices = "ffab5731-97b5-5995-9138-79e8c1846df0"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.FixedPointNumbers]]
deps = ["Random", "Statistics"]
git-tree-sha1 = "59af96b98217c6ef4ae0dfe065ac7c20831d1a84"
registries = "General"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.6"

[[deps.Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Zlib_jll"]
git-tree-sha1 = "f85dac9a96a01087df6e3a749840015a0ca3817d"
registries = "General"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.17.1+0"

[[deps.Format]]
git-tree-sha1 = "9c68794ef81b08086aeb32eeaf33531668d5f5fc"
registries = "General"
uuid = "1fa38f19-a742-5d3f-a2b9-30dd87b9d5f8"
version = "1.3.7"

[[deps.FreeType]]
deps = ["CEnum", "FreeType2_jll"]
git-tree-sha1 = "907369da0f8e80728ab49c1c7e09327bf0d6d999"
registries = "General"
uuid = "b38be410-82b0-50bf-ab77-7b57e271db43"
version = "4.1.1"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "70329abc09b886fd2c5d94ad2d9527639c421e3e"
registries = "General"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.14.3+1"

[[deps.FreeTypeAbstraction]]
deps = ["BaseDirs", "ColorVectorSpace", "Colors", "FreeType", "GeometryBasics", "Mmap"]
git-tree-sha1 = "4ebb930ef4a43817991ba35db6317a05e59abd11"
registries = "General"
uuid = "663a7486-cb36-511b-a19d-713bb74d65c9"
version = "0.10.8"

[[deps.FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "7a214fdac5ed5f59a22c2d9a885a16da1c74bbc7"
registries = "General"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.17+0"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"
version = "1.11.0"

[[deps.Gamma]]
deps = ["LogExpFunctions"]
git-tree-sha1 = "becc397f7cfb06e343496ae6ffb04818a851da51"
registries = "General"
uuid = "a0844989-3bd2-4988-8bea-c9407ab0941b"
version = "1.2.0"

[[deps.GeometryBasics]]
deps = ["EarCut_jll", "LinearAlgebra", "PrecompileTools", "Random", "StaticArrays"]
git-tree-sha1 = "592cfb5ed8b02804f6a9c04091571c393081f73a"
registries = "General"
uuid = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
version = "0.5.12"

    [deps.GeometryBasics.extensions]
    ExtentsExt = "Extents"
    GeometryBasicsGeoInterfaceExt = "GeoInterface"
    IntervalSetsExt = "IntervalSets"

    [deps.GeometryBasics.weakdeps]
    Extents = "411431e0-e8b7-467b-b5e0-f676ba4f2910"
    GeoInterface = "cf35fbd7-0cd7-5166-be24-54bfbe79505f"
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"

[[deps.GettextRuntime_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll"]
git-tree-sha1 = "45288942190db7c5f760f59c04495064eedf9340"
registries = "General"
uuid = "b0724c58-0f36-5564-988d-3bb0596ebc4a"
version = "0.22.4+0"

[[deps.Giflib_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6570366d757b50fabae9f4315ad74d2e40c0560a"
registries = "General"
uuid = "59f7168a-df46-5410-90c8-f2779963d0ec"
version = "5.2.3+0"

[[deps.Glib_jll]]
deps = ["Artifacts", "GettextRuntime_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE2_jll", "Zlib_jll"]
git-tree-sha1 = "090526e65de8f69648ac156daae153de8b56df62"
registries = "General"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.88.3+0"

[[deps.Graphics]]
deps = ["Colors", "LinearAlgebra", "NaNMath"]
git-tree-sha1 = "a641238db938fff9b2f60d08ed9030387daf428c"
registries = "General"
uuid = "a2bd30eb-e257-5431-a919-1863eab51364"
version = "1.1.3"

[[deps.Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "69ffb934a5c5b7e086a0b4fee3427db2556fba6e"
registries = "General"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.16+0"

[[deps.GridLayoutBase]]
deps = ["GeometryBasics", "InteractiveUtils", "Observables"]
git-tree-sha1 = "ef70da5e123a06a29e2d6ddff0f09985bc226491"
registries = "General"
uuid = "3955a311-db13-416c-9275-1d80ed98e5e9"
version = "0.11.3"

[[deps.HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll"]
git-tree-sha1 = "9d9531a9cb63a9edc33836414e82a07e81710de2"
registries = "General"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "100.14004.0+0"

[[deps.HypergeometricFunctions]]
deps = ["Gamma", "LinearAlgebra"]
git-tree-sha1 = "31bb6c92405c084617facc1d7ed9eb6c402d061e"
registries = "General"
uuid = "34004b35-14d8-5ef3-9330-4cdb6864b03a"
version = "0.3.30"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
registries = "General"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "7134810b1afce04bbc1045ca1985fbe81ce17653"
registries = "General"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.5"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "b6d6bfdd7ce25b0f9b2f6b3dd56b2673a66c8770"
registries = "General"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.5"

[[deps.ImageAxes]]
deps = ["AxisArrays", "ImageBase", "ImageCore", "Reexport", "SimpleTraits"]
git-tree-sha1 = "e12629406c6c4442539436581041d372d69c55ba"
registries = "General"
uuid = "2803e5a7-5153-5ecf-9a86-9b4c37f5f5ac"
version = "0.6.12"

[[deps.ImageBase]]
deps = ["ImageCore", "Reexport"]
git-tree-sha1 = "eb49b82c172811fd2c86759fa0553a2221feb909"
registries = "General"
uuid = "c817782e-172a-44cc-b673-b171935fbb9e"
version = "0.1.7"

[[deps.ImageCore]]
deps = ["ColorVectorSpace", "Colors", "FixedPointNumbers", "MappedArrays", "MosaicViews", "OffsetArrays", "PaddedViews", "PrecompileTools", "Reexport"]
git-tree-sha1 = "8c193230235bbcee22c8066b0374f63b5683c2d3"
registries = "General"
uuid = "a09fc81d-aa75-5fe9-8630-4744c3626534"
version = "0.10.5"

[[deps.ImageIO]]
deps = ["FileIO", "IndirectArrays", "JpegTurbo", "LazyModules", "Netpbm", "OpenEXR", "PNGFiles", "QOI", "Sixel", "TiffImages", "UUIDs", "WebP"]
git-tree-sha1 = "f0f005f997dfb8c5fe23920d99458a9619873893"
registries = "General"
uuid = "82e4d734-157c-48bb-816b-45c225c6df19"
version = "0.6.10"

[[deps.ImageMetadata]]
deps = ["AxisArrays", "ImageAxes", "ImageBase", "ImageCore"]
git-tree-sha1 = "2a81c3897be6fbcde0802a0ebe6796d0562f63ec"
registries = "General"
uuid = "bc367c6b-8a6b-528e-b4bd-a4b897500b49"
version = "0.9.10"

[[deps.Imath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "dcc8d0cd653e55213df9b75ebc6fe4a8d3254c65"
registries = "General"
uuid = "905a6f67-0a94-5f89-b386-d35d92009cd1"
version = "3.2.2+0"

[[deps.IndirectArrays]]
git-tree-sha1 = "012e604e1c7458645cb8b436f8fba789a51b257f"
registries = "General"
uuid = "9b13fd28-a010-5f03-acff-a1bbcff69959"
version = "1.0.0"

[[deps.Inflate]]
git-tree-sha1 = "d1b1b796e47d94588b3757fe84fbf65a5ec4a80d"
registries = "General"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.5"

[[deps.InlineStrings]]
git-tree-sha1 = "06b65886c7577a3784d616e29f1302c2e36e389d"
registries = "General"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.6"

    [deps.InlineStrings.extensions]
    ArrowTypesExt = "ArrowTypes"
    ParsersExt = "Parsers"

    [deps.InlineStrings.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"
    Parsers = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"

[[deps.IntegerMathUtils]]
git-tree-sha1 = "c72458f1962faeb003bf23cbdb75164fe6280906"
registries = "General"
uuid = "18e54dd8-cb9d-406c-a71d-865a43cbb235"
version = "0.1.4"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.Interpolations]]
deps = ["Adapt", "AxisAlgorithms", "ChainRulesCore", "LinearAlgebra", "OffsetArrays", "Random", "Ratios", "Requires", "SharedArrays", "SparseArrays", "StaticArrays", "WoodburyMatrices"]
git-tree-sha1 = "c6c24bc9db44d9ad66af947398380233900e2bcd"
registries = "General"
uuid = "a98d9a8b-a2ab-59e6-89dd-64a1c18fca59"
version = "0.15.2"
weakdeps = ["Unitful"]

    [deps.Interpolations.extensions]
    InterpolationsUnitfulExt = "Unitful"

[[deps.IntervalArithmetic]]
deps = ["CRlibm", "CoreMath", "MacroTools", "OpenBLASConsistentFPCSR_jll", "Printf", "Random", "RoundingEmulator"]
git-tree-sha1 = "1c531bf0f8a5c60a340926e058fd3f209b5eef5d"
registries = "General"
uuid = "d1acc4aa-44c8-5952-acd4-ba5d80a2a253"
version = "1.0.12"

    [deps.IntervalArithmetic.extensions]
    IntervalArithmeticArblibExt = "Arblib"
    IntervalArithmeticDiffRulesExt = "DiffRules"
    IntervalArithmeticForwardDiffExt = "ForwardDiff"
    IntervalArithmeticIntervalSetsExt = "IntervalSets"
    IntervalArithmeticIrrationalConstantsExt = "IrrationalConstants"
    IntervalArithmeticLinearAlgebraExt = "LinearAlgebra"
    IntervalArithmeticMakieExt = "Makie"
    IntervalArithmeticRecipesBaseExt = "RecipesBase"
    IntervalArithmeticSparseArraysExt = "SparseArrays"

    [deps.IntervalArithmetic.weakdeps]
    Arblib = "fb37089c-8514-4489-9461-98f9c8763369"
    DiffRules = "b552c78f-8df3-52c6-915a-8e097449b14b"
    ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210"
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    IrrationalConstants = "92d709cd-6900-40b7-9082-c6be49f344b6"
    LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
    Makie = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
    RecipesBase = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.IntervalSets]]
git-tree-sha1 = "79d6bd28c8d9bccc2229784f1bd637689b256377"
registries = "General"
uuid = "8197267c-284f-5f27-9208-e0e47529a953"
version = "0.7.14"

    [deps.IntervalSets.extensions]
    IntervalSetsRandomExt = "Random"
    IntervalSetsRecipesBaseExt = "RecipesBase"
    IntervalSetsStatisticsExt = "Statistics"

    [deps.IntervalSets.weakdeps]
    Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
    RecipesBase = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
    Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.InverseFunctions]]
git-tree-sha1 = "a779299d77cd080bf77b97535acecd73e1c5e5cb"
registries = "General"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.17"
weakdeps = ["Dates", "Test"]

    [deps.InverseFunctions.extensions]
    InverseFunctionsDatesExt = "Dates"
    InverseFunctionsTestExt = "Test"

[[deps.InvertedIndices]]
git-tree-sha1 = "6da3c4316095de0f5ee2ebd875df8721e7e0bdbe"
registries = "General"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.3.1"

[[deps.IrrationalConstants]]
git-tree-sha1 = "b2d91fe939cae05960e760110b328288867b5758"
registries = "General"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.6"

[[deps.Isoband]]
deps = ["isoband_jll"]
git-tree-sha1 = "f9b6d97355599074dc867318950adaa6f9946137"
registries = "General"
uuid = "f1662d9f-8043-43de-a69a-05efc1cc6ff4"
version = "0.1.1"

[[deps.IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
registries = "General"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
registries = "General"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7204148362dafe5fe6a273f855b8ccbe4df8173e"
registries = "General"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.8.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
registries = "General"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JpegTurbo]]
deps = ["CEnum", "FileIO", "ImageCore", "JpegTurbo_jll", "TOML"]
git-tree-sha1 = "9496de8fb52c224a2e3f9ff403947674517317d9"
registries = "General"
uuid = "b835a17e-a41a-41e7-81f0-2f016b05efe0"
version = "0.1.6"

[[deps.JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "037babc10853eeb8e585418922246cb97b8e5b74"
registries = "General"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "3.2.0+1"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

[[deps.KernelDensity]]
deps = ["Distributions", "DocStringExtensions", "FFTA", "Interpolations", "StatsBase"]
git-tree-sha1 = "9eda8292dd3268b3b7ec9df21bbfac24e177ec52"
registries = "General"
uuid = "5ab0869b-81aa-558d-bb23-cbf5423bbe9b"
version = "0.6.12"

[[deps.LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "059aabebaa7c82ccb853dd4a0ee9d17796f7e1bc"
registries = "General"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.3+0"

[[deps.LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "39bca05343661c347aae0bca57a5994a0bf4f08d"
registries = "General"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "4.2.0+0"

[[deps.LLVMOpenMP_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e5b100780d4d30d63b4618d7930d48af409c1772"
registries = "General"
uuid = "1d63c593-3942-5779-bab2-d838dc0a180e"
version = "23.1.1+0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "f88f3ccef05a6a72a0cf0ed417c8fd68530f4ab2"
registries = "General"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.4.1"

[[deps.LazyModules]]
git-tree-sha1 = "a560dd966b386ac9ae60bdd3a3d3a326062d3c3e"
registries = "General"
uuid = "8cdb02fc-e678-4876-92c5-9defec4f444e"
version = "0.3.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "1.0.0"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "LibSSH2_jll", "Libdl", "OpenSSL_jll", "Zlib_jll", "Zstd_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.18.0+1"

[[deps.LibGit2]]
deps = ["LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"
version = "1.11.0"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "LibSSH2_jll", "Libdl", "OpenSSL_jll", "PCRE2_jll", "Zlib_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.9.1+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl", "OpenSSL_jll", "Zlib_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.103+0"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "c8da7e6a91781c41a863611c7e966098d783c57a"
registries = "General"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.4.7+0"

[[deps.Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "d36c21b9e7c172a44a10484125024495e2625ac0"
registries = "General"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.7.1+1"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "be484f5c92fad0bd8acfef35fe017900b0b73809"
registries = "General"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.18.0+0"

[[deps.Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "cc3ad4faf30015a3e8094c9b5b7f19e85bdf2386"
registries = "General"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.42.0+0"

[[deps.Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "XZ_jll", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "aebd334d06cee9f24cea70bd19a39749daf73881"
registries = "General"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.7.3+0"

[[deps.Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "d620582b1f0cbe2c72dd1d5bd195a9ce73370ab1"
registries = "General"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.42.0+0"

[[deps.LineSearches]]
deps = ["LinearAlgebra", "NLSolversBase", "NaNMath", "Printf"]
git-tree-sha1 = "a09a85e94e681def2446752cddaf9401a4d82b6d"
registries = "General"
uuid = "d3d80556-e9d4-5f37-9878-2ab0fcc64255"
version = "7.8.2"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.13.0"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "bba2d9aa057d8f126415de240573e86a8f39d2a1"
registries = "General"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "1.0.1"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.MIMEs]]
git-tree-sha1 = "c64d943587f7187e751162b3b84445bbbd79f691"
registries = "General"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "1.1.0"

[[deps.MacroTools]]
git-tree-sha1 = "1e0228a030642014fe5cfe68c2c0a818f9e3f522"
registries = "General"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.16"

[[deps.Makie]]
deps = ["Animations", "Base64", "CRC32c", "ColorBrewer", "ColorSchemes", "ColorTypes", "Colors", "ComputePipeline", "Contour", "Dates", "DelaunayTriangulation", "Distributions", "DocStringExtensions", "Downloads", "FFMPEG_jll", "FileIO", "FilePaths", "FixedPointNumbers", "Format", "FreeType", "FreeTypeAbstraction", "GeometryBasics", "GridLayoutBase", "ImageBase", "ImageIO", "InteractiveUtils", "Interpolations", "IntervalSets", "InverseFunctions", "Isoband", "KernelDensity", "LaTeXStrings", "LinearAlgebra", "MacroTools", "Markdown", "MathTeXEngine", "Observables", "OffsetArrays", "PNGFiles", "Packing", "Pkg", "PlotUtils", "PolygonOps", "PrecompileTools", "Printf", "REPL", "Random", "RelocatableFolders", "Scratch", "ShaderAbstractions", "SignedDistanceFields", "SparseArrays", "Statistics", "StatsBase", "StatsFuns", "StructArrays", "TriplotBase", "UnicodeFun", "Unitful"]
git-tree-sha1 = "37b10d17f74f54dc5fa7d3c6c20fd75613c71d80"
registries = "General"
uuid = "ee78f7c6-11fb-53f2-987a-cfe4a2b5a57a"
version = "0.24.14"

    [deps.Makie.extensions]
    MakieDynamicQuantitiesExt = "DynamicQuantities"

    [deps.Makie.weakdeps]
    DynamicQuantities = "06fc5a27-2a28-4c7c-a15d-362465fb6821"

[[deps.MappedArrays]]
git-tree-sha1 = "0ee4497a4e80dbd29c058fcee6493f5219556f40"
registries = "General"
uuid = "dbb5928d-eab1-5f90-85c2-b9b0edb7c900"
version = "0.4.3"

[[deps.Markdown]]
deps = ["Base64", "JuliaSyntaxHighlighting", "StyledStrings"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MathTeXEngine]]
deps = ["AbstractTrees", "Automa", "DataStructures", "FreeTypeAbstraction", "GeometryBasics", "LaTeXStrings", "REPL", "RelocatableFolders", "UnicodeFun"]
git-tree-sha1 = "aa1078778be5a8e5259ff04fbc3d258b3e78d464"
registries = "General"
uuid = "0a4f8689-d25c-4efe-a92b-7142dfc1aa53"
version = "0.6.9"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "ec4f7fbeab05d7747bdf98eb74d130a2a2ed298d"
registries = "General"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.2.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MosaicViews]]
deps = ["MappedArrays", "OffsetArrays", "PaddedViews", "StackViews"]
git-tree-sha1 = "7b86a5d4d70a9f5cdf2dacb3cbe6d251d1a61dbe"
registries = "General"
uuid = "e94cdb99-869f-56ef-bcf0-1ae2bcbe0389"
version = "0.3.4"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2026.8.13"

[[deps.MuladdMacro]]
deps = ["PrecompileTools"]
git-tree-sha1 = "283bf85d4a767481dd924dff0eee1735e95f449e"
registries = "General"
uuid = "46d2c3a1-f734-5fdb-9937-b9b9aeba4221"
version = "0.2.7"

[[deps.NLSolversBase]]
deps = ["ADTypes", "DifferentiationInterface", "FiniteDiff", "LinearAlgebra"]
git-tree-sha1 = "f96d38936d92d610318dec4d3b5ef37b0373c20f"
registries = "General"
uuid = "d41bc354-129a-5804-8e4c-c37616107c6c"
version = "8.0.1"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "dbd2e8cd2c1c27f0b584f6661b4309609c5a685e"
registries = "General"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.1.4"

[[deps.NamedDims]]
deps = ["LinearAlgebra", "Statistics"]
git-tree-sha1 = "f9e4a49ecd1ea2eccfb749a506fa882c094152b4"
registries = "General"
uuid = "356022a1-0364-5f58-8944-0da4b18d706f"
version = "1.2.3"

    [deps.NamedDims.extensions]
    AbstractFFTsExt = "AbstractFFTs"
    ChainRulesCoreExt = "ChainRulesCore"
    CovarianceEstimationExt = "CovarianceEstimation"
    TrackerExt = "Tracker"

    [deps.NamedDims.weakdeps]
    AbstractFFTs = "621f4979-c628-5d54-868e-fcf4e3e8185c"
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    CovarianceEstimation = "587fd27a-f159-11e8-2dae-1979310e6154"
    Requires = "ae029012-a4dd-5104-9daa-d747884805df"
    Tracker = "9f7883ad-71c0-57eb-9f7f-b5c9e6d3789c"

[[deps.Netpbm]]
deps = ["FileIO", "ImageCore", "ImageMetadata"]
git-tree-sha1 = "d92b107dbb887293622df7697a2223f9f8176fcd"
registries = "General"
uuid = "f09324ee-3d7c-5217-9330-fc30815ba969"
version = "1.1.1"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.3.0"

[[deps.Observables]]
git-tree-sha1 = "7438a59546cf62428fc9d1bc94729146d37a7225"
registries = "General"
uuid = "510215fc-4207-5dde-b226-833fc4488ee2"
version = "0.5.5"

[[deps.OffsetArrays]]
git-tree-sha1 = "117432e406b5c023f665fa73dc26e79ec3630151"
registries = "General"
uuid = "6fe1bfb0-de20-5000-8ca7-80f57d26f881"
version = "1.17.0"
weakdeps = ["Adapt"]

    [deps.OffsetArrays.extensions]
    OffsetArraysAdaptExt = "Adapt"

[[deps.Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "b6aa4566bb7ae78498a5e68943863fa8b5231b59"
registries = "General"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.6+0"

[[deps.OpenBLASConsistentFPCSR_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "38a93f17e431141c6470bb67a88952a7c4f0e928"
registries = "General"
uuid = "6cdc7f73-28fd-5e50-80fb-958a8875b1af"
version = "0.3.34+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.30+0"

[[deps.OpenEXR]]
deps = ["Colors", "FileIO", "OpenEXR_jll"]
git-tree-sha1 = "97db9e07fe2091882c765380ef58ec553074e9c7"
registries = "General"
uuid = "52e1d378-f018-4a11-a4be-720524705ac7"
version = "0.3.3"

[[deps.OpenEXR_jll]]
deps = ["Artifacts", "Imath_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "1bcebd887dd33f1108210b3954049b1bb8af0e7a"
registries = "General"
uuid = "18a262bb-aa17-5467-a713-aee519bc75cb"
version = "3.4.15+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.7+0"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.5.6+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1346c9208249809840c91b26703912dff463d335"
registries = "General"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.6+0"

[[deps.Optim]]
deps = ["ADTypes", "EnumX", "FillArrays", "LineSearches", "LinearAlgebra", "NLSolversBase", "NaNMath", "PositiveFactorizations", "Printf", "SparseArrays", "Statistics"]
git-tree-sha1 = "81f338ad984b25bc82471db4d235e7b8bf21b8d6"
registries = "General"
uuid = "429524aa-4258-5aef-a3af-852621145aeb"
version = "2.3.2"

    [deps.Optim.extensions]
    OptimMOIExt = "MathOptInterface"

    [deps.Optim.weakdeps]
    MathOptInterface = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"

[[deps.Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e2bb57a313a74b8104064b7efd01406c0a50d2ff"
registries = "General"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.6.1+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "05f45c2e0de6259db764adbfd2f1dc6d3f8de13c"
registries = "General"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "2.0.1"

[[deps.PCRE2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "efcefdf7-47ab-520b-bdef-62a2eaa19f15"
version = "10.46.0+0"

[[deps.PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "123266c25174ef6c8d4718920abc206452cf8de6"
registries = "General"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.41"
weakdeps = ["StatsBase"]

    [deps.PDMats.extensions]
    StatsBaseExt = "StatsBase"

[[deps.PNGFiles]]
deps = ["Base64", "CEnum", "ImageCore", "IndirectArrays", "OffsetArrays", "libpng_jll"]
git-tree-sha1 = "32b657a0d57c310a1a172bfc8c8cf68c5e674323"
registries = "General"
uuid = "f57f5aa1-a3ce-4bc8-8ab9-96f992907883"
version = "0.4.5"

[[deps.Packing]]
deps = ["GeometryBasics"]
git-tree-sha1 = "bc5bf2ea3d5351edf285a06b0016788a121ce92c"
registries = "General"
uuid = "19eb6ba3-879d-56ad-ad62-d5c202156566"
version = "0.5.1"

[[deps.PaddedViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "0fac6313486baae819364c52b4f483450a9d793f"
registries = "General"
uuid = "5432bcbf-9aad-5242-b902-cca2824c8663"
version = "0.5.12"

[[deps.Pango_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "FriBidi_jll", "Glib_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1912a9f1b9ca55005b03ba075f8e19993583e237"
registries = "General"
uuid = "36c8627f-9965-5494-a995-c6b170f724f3"
version = "1.58.2+0"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "ba0dc8a8a67cacac4842631f960c046e4e563675"
registries = "General"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.8"

[[deps.Pixman_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "LLVMOpenMP_jll", "Libdl"]
git-tree-sha1 = "e4a6721aa89e62e5d4217c0b21bd714263779dda"
registries = "General"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.46.4+0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "Random", "SHA", "TOML", "Tar", "UUIDs", "Zstd_jll", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.13.0"
weakdeps = ["REPL"]

    [deps.Pkg.extensions]
    REPLExt = "REPL"

[[deps.PkgVersion]]
deps = ["Pkg"]
git-tree-sha1 = "f9501cc0430a26bc3d156ae1b5b0c1b47af4d6da"
registries = "General"
uuid = "eebad327-c553-4316-9ea0-9fa01ccd7688"
version = "0.3.3"

[[deps.PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "PrecompileTools", "Printf", "Random", "Reexport", "StableRNGs", "Statistics"]
git-tree-sha1 = "26ca162858917496748aad52bb5d3be4d26a228a"
registries = "General"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.4.4"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "3876f0ab0390136ae0b5e3f064a109b87fa1e56e"
registries = "General"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.63"

[[deps.PolygonOps]]
git-tree-sha1 = "77b3d3605fc1cd0b42d95eba87dfcd2bf67d5ff6"
registries = "General"
uuid = "647866c9-e3ac-4575-94e7-e3d426903924"
version = "0.1.2"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "36d8b4b899628fb92c2749eb488d884a926614d3"
registries = "General"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.3"

[[deps.PositiveFactorizations]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "17275485f373e6673f7e7f97051f703ed5b15b20"
registries = "General"
uuid = "85a6dd25-e78a-55b7-8502-1745935b8125"
version = "0.2.4"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "edbeefc7a4889f528644251bdb5fc9ab5348bc2c"
registries = "General"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.3.4"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "5005266de4bfe50e53ff44a5cb5c540b6e47a254"
registries = "General"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.6.0"

[[deps.PrettyTables]]
deps = ["Crayons", "LaTeXStrings", "Markdown", "PrecompileTools", "Printf", "REPL", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "1b8aa19f229b1cea7fc93874a52e49db6a854450"
registries = "General"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "3.4.8"

    [deps.PrettyTables.extensions]
    PrettyTablesExcelExt = "XLSX"
    PrettyTablesTypstryExt = "Typstry"

    [deps.PrettyTables.weakdeps]
    Typstry = "f0ed7684-a786-439e-b1e3-3b82803b501e"
    XLSX = "fdbf4ff8-1666-58a4-91e7-1b58723a45e0"

[[deps.Primes]]
deps = ["IntegerMathUtils"]
git-tree-sha1 = "25cdd1d20cd005b52fc12cb6be3f75faaf59bb9b"
registries = "General"
uuid = "27ebfcd6-29c5-5fa9-bf4b-fb8fc14df3ae"
version = "0.5.7"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "fbb92c6c56b34e1a2c4c36058f68f332bec840e7"
registries = "General"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.11.0"

[[deps.PtrArrays]]
git-tree-sha1 = "4fbbafbc6251b883f4d2705356f3641f3652a7fe"
registries = "General"
uuid = "43287f4e-b6f4-7ad1-bb20-aadabca52c3d"
version = "1.4.0"

[[deps.QOI]]
deps = ["ColorTypes", "FileIO", "FixedPointNumbers"]
git-tree-sha1 = "472daaa816895cb7aee81658d4e7aec901fa1106"
registries = "General"
uuid = "4b34888f-f399-49d4-9bb3-47ed5cae4e65"
version = "1.0.2"

[[deps.QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "5e8e8b0ab68215d7a2b14b9921a946fee794749e"
registries = "General"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.11.3"

    [deps.QuadGK.extensions]
    QuadGKEnzymeExt = "Enzyme"

    [deps.QuadGK.weakdeps]
    Enzyme = "7da242da-08ed-463a-9acd-ee780be4f1d9"

[[deps.REPL]]
deps = ["Base64", "Dates", "FileWatching", "InteractiveUtils", "JuliaSyntaxHighlighting", "Markdown", "Sockets", "StyledStrings", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.RangeArrays]]
git-tree-sha1 = "b9039e93773ddcfc828f12aadf7115b4b4d225f5"
registries = "General"
uuid = "b3c3ace0-ae52-54e7-9d0b-2c1406fd6b9d"
version = "0.3.2"

[[deps.Ratios]]
deps = ["Requires"]
git-tree-sha1 = "1342a47bf3260ee108163042310d26f2be5ec90b"
registries = "General"
uuid = "c84ed2f1-dad5-54f0-aa8e-dbefe2724439"
version = "0.4.5"
weakdeps = ["FixedPointNumbers"]

    [deps.Ratios.extensions]
    RatiosFixedPointNumbersExt = "FixedPointNumbers"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
registries = "General"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "ffdaf70d81cf6ff22c2b6e733c900c3321cab864"
registries = "General"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "1.0.1"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "62389eeff14780bfe55195b7204c0d8738436d64"
registries = "General"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.1"

[[deps.Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "5b3d50eb374cea306873b371d3f8d3915a018f0b"
registries = "General"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.9.0"

[[deps.Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6d40b2fe70437b01397d2a4d5b020008da4e7019"
registries = "General"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.5.2+0"

[[deps.Roots]]
deps = ["Accessors", "CommonSolve", "Printf"]
git-tree-sha1 = "4db094d5e079abbda658acfe1c4d098430417717"
registries = "General"
uuid = "f2b01f46-fcfa-551c-844a-d8ac1e96c665"
version = "3.0.8"

    [deps.Roots.extensions]
    RootsChainRulesCoreExt = "ChainRulesCore"
    RootsForwardDiffExt = "ForwardDiff"
    RootsIntervalRootFindingExt = "IntervalRootFinding"
    RootsSymPyExt = "SymPy"
    RootsSymPyPythonCallExt = "SymPyPythonCall"
    RootsUnitfulExt = "Unitful"

    [deps.Roots.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210"
    IntervalRootFinding = "d2bf35a9-74e0-55ec-b149-d360ff49b807"
    SymPy = "24249f21-da20-56a4-8eb1-6a02cf4ae2e6"
    SymPyPythonCall = "bc8888f7-b21e-4b7c-a06a-5d9c9496438c"
    Unitful = "1986cc42-f94f-5a68-af5c-568840ba703d"

[[deps.RoundingEmulator]]
git-tree-sha1 = "40b9edad2e5287e05bd413a38f61a8ff55b9557b"
registries = "General"
uuid = "5eaf0fd0-dfba-4ccb-bf02-d820a40db705"
version = "0.2.1"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "1.0.0"

[[deps.SIMD]]
deps = ["PrecompileTools"]
git-tree-sha1 = "e24dc23107d426a096d3eae6c165b921e74c18e4"
registries = "General"
uuid = "fdea26ae-647d-5447-a871-4b548cad5224"
version = "3.7.2"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "9b81b8393e50b7d4e6d0a9f14e192294d3b7c109"
registries = "General"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.3.0"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "084c47c7c5ce5cfecefa0a98dff69eb3646b5a80"
registries = "General"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.4.10"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "StaticArraysCore"]
git-tree-sha1 = "c5391c6ace3bc430ca630251d02ea9687169ca68"
registries = "General"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "1.1.2"

[[deps.ShaderAbstractions]]
deps = ["ColorTypes", "FixedPointNumbers", "GeometryBasics", "LinearAlgebra", "Observables", "StaticArrays"]
git-tree-sha1 = "818554664a2e01fc3784becb2eb3a82326a604b6"
registries = "General"
uuid = "65257c39-d410-5151-9873-9b3e5be5013e"
version = "0.5.0"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"
version = "1.11.0"

[[deps.SignedDistanceFields]]
deps = ["Statistics"]
git-tree-sha1 = "3949ad92e1c9d2ff0cd4a1317d5ecbba682f4b92"
registries = "General"
uuid = "73760f76-fbc4-59ce-8f25-708e95d2df96"
version = "0.4.1"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "7ddb0b49c109481b046972c0e4ab02b2127d6a75"
registries = "General"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.6"

[[deps.Sixel]]
deps = ["Dates", "FileIO", "ImageCore", "IndirectArrays", "OffsetArrays", "REPL", "libsixel_jll"]
git-tree-sha1 = "0494aed9501e7fb65daba895fb7fd57cc38bc743"
registries = "General"
uuid = "45858cf5-a6b0-47a3-bbea-62219f50df47"
version = "0.1.5"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"
version = "1.11.0"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "13cd91cc9be159e3f4d95b857fa2aa383b53772a"
registries = "General"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.3"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.13.0"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "429071b23f4c9a13fb6582f807cc2ef454082408"
registries = "General"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.9.0"
weakdeps = ["ChainRulesCore"]

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

[[deps.StableRNGs]]
deps = ["Random"]
git-tree-sha1 = "4f96c596b8c8258cc7d3b19797854d368f243ddc"
registries = "General"
uuid = "860ef19b-820b-49d6-a774-d7a799459cd3"
version = "1.0.4"

[[deps.StackViews]]
deps = ["OffsetArrays"]
git-tree-sha1 = "be1cf4eb0ac528d96f5115b4ed80c26a8d8ae621"
registries = "General"
uuid = "cae243ae-269e-4f55-b966-ac2d0dc13c15"
version = "0.1.2"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "PrecompileTools", "Random", "StaticArraysCore"]
git-tree-sha1 = "e206cf4850fd7ac4255ffd2b98922f563e18ac53"
registries = "General"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.9.20"
weakdeps = ["ChainRulesCore", "Statistics"]

    [deps.StaticArrays.extensions]
    StaticArraysChainRulesCoreExt = "ChainRulesCore"
    StaticArraysStatisticsExt = "Statistics"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6ab403037779dae8c514bad259f32a447262455a"
registries = "General"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.4"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "e2b53ce13a53367e96601081e33d34746b571bad"
registries = "General"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.5"
weakdeps = ["SparseArrays"]

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "178ed29fd5b2a2cfc3bd31c13375ae925623ff36"
registries = "General"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.8.0"

[[deps.StatsBase]]
deps = ["AliasTables", "DataAPI", "DataStructures", "IrrationalConstants", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "adb9da019510162e67a4493fc235c23203d8b09e"
registries = "General"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.34.13"

[[deps.StatsFuns]]
deps = ["HypergeometricFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "91a5737baed20ee31f3faea0e51f57461f6a689e"
registries = "General"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "2.2.1"
weakdeps = ["ChainRulesCore", "InverseFunctions"]

    [deps.StatsFuns.extensions]
    StatsFunsChainRulesCoreExt = "ChainRulesCore"
    StatsFunsInverseFunctionsExt = "InverseFunctions"

[[deps.StringManipulation]]
deps = ["PrecompileTools"]
git-tree-sha1 = "773065c6e0e903924a9d838259be74338422aef2"
registries = "General"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.5.0"

[[deps.StructArrays]]
deps = ["ConstructionBase", "DataAPI", "Tables"]
git-tree-sha1 = "ad8002667372439f2e3611cfd14097e03fa4bccd"
registries = "General"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.7.3"

    [deps.StructArrays.extensions]
    StructArraysAdaptExt = "Adapt"
    StructArraysGPUArraysCoreExt = ["GPUArraysCore", "KernelAbstractions"]
    StructArraysLinearAlgebraExt = "LinearAlgebra"
    StructArraysSparseArraysExt = "SparseArrays"
    StructArraysStaticArraysExt = "StaticArrays"

    [deps.StructArrays.weakdeps]
    Adapt = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
    GPUArraysCore = "46192b85-c4d5-4398-a991-12ede77f4527"
    KernelAbstractions = "63c18a36-062a-441e-b654-da1e3ab1ce7c"
    LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.10.1+0"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
registries = "General"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "OrderedCollections", "TableTraits"]
git-tree-sha1 = "a94d9bdda1b7bed0046cea645639ab3f62196fac"
registries = "General"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.14.0"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
registries = "General"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.TiffImages]]
deps = ["CodecZstd", "ColorTypes", "DataStructures", "DocStringExtensions", "FileIO", "FixedPointNumbers", "IndirectArrays", "Inflate", "Mmap", "OffsetArrays", "PkgVersion", "PrecompileTools", "ProgressMeter", "SIMD", "UUIDs"]
git-tree-sha1 = "9ca5f1f2d42f80df4b8c9f6ab5a64f438bbd9976"
registries = "General"
uuid = "731e570b-9d59-4bfa-96dc-6df516fadf69"
version = "0.11.9"

[[deps.TranscodingStreams]]
git-tree-sha1 = "0c45878dcfdcfa8480052b6ab162cdd138781742"
registries = "General"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.11.3"

[[deps.Tricks]]
git-tree-sha1 = "311349fd1c93a31f783f977a71e8b062a57d4101"
registries = "General"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.13"

[[deps.TriplotBase]]
git-tree-sha1 = "4d4ed7f294cda19382ff7de4c137d24d16adc89b"
registries = "General"
uuid = "981d1d27-644d-49a2-9326-4793e63143c3"
version = "0.1.0"

[[deps.URIs]]
git-tree-sha1 = "908fec9df6c5de98548ead82a468c95ccf6cd263"
registries = "General"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.7.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
registries = "General"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[deps.Unitful]]
deps = ["Dates", "LinearAlgebra", "Random"]
git-tree-sha1 = "1f0f9f401753701a7e4113b5056ca38d33875b55"
registries = "General"
uuid = "1986cc42-f94f-5a68-af5c-568840ba703d"
version = "1.29.0"

    [deps.Unitful.extensions]
    ConstructionBaseUnitfulExt = "ConstructionBase"
    ForwardDiffExt = "ForwardDiff"
    InverseFunctionsUnitfulExt = "InverseFunctions"
    LatexifyExt = ["Latexify", "LaTeXStrings"]
    NaNMathExt = "NaNMath"
    PrintfExt = "Printf"

    [deps.Unitful.weakdeps]
    ConstructionBase = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
    ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"
    LaTeXStrings = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
    Latexify = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
    NaNMath = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
    Printf = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.WebP]]
deps = ["CEnum", "ColorTypes", "FileIO", "FixedPointNumbers", "ImageCore", "libwebp_jll"]
git-tree-sha1 = "aa1ca3c47f119fbdae8770c29820e5e6119b83f2"
registries = "General"
uuid = "e3aaa7dc-3e4b-44e0-be63-ffb868ccd7c1"
version = "0.1.3"

[[deps.WoodburyMatrices]]
deps = ["LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "248a7031b3da79a127f14e5dc5f417e26f9f6db7"
registries = "General"
uuid = "efce3f68-66dc-5838-9240-27a6d6f5f9b6"
version = "1.1.0"

[[deps.XZ_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e52eca002a11c30a858185efdfb15311e1c7a6bf"
registries = "General"
uuid = "ffd25f8a-64ca-5728-b0f7-c24cf3aae800"
version = "5.8.4+0"

[[deps.Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "808090ede1d41644447dd5cbafced4731c56bd2f"
registries = "General"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.8.13+0"

[[deps.Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "aa1261ebbac3ccc8d16558ae6799524c450ed16b"
registries = "General"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.13+0"

[[deps.Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "52858d64353db33a56e13c341d7bf44cd0d7b309"
registries = "General"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.6+0"

[[deps.Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libX11_jll"]
git-tree-sha1 = "1a4a26870bf1e5d26cd585e38038d399d7e65706"
registries = "General"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.8+0"

[[deps.Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libX11_jll"]
git-tree-sha1 = "75e00946e43621e09d431d9b95818ee751e6b2ef"
registries = "General"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "6.0.2+0"

[[deps.Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libX11_jll"]
git-tree-sha1 = "7ed9347888fac59a618302ee38216dd0379c480d"
registries = "General"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.12+0"

[[deps.Xorg_libpciaccess_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "58972370b81423fc546c56a60ed1a009450177c3"
registries = "General"
uuid = "a65dc6b1-eb27-53a1-bb3e-dea574b5389e"
version = "0.19.0+0"

[[deps.Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libXau_jll", "Xorg_libXdmcp_jll"]
git-tree-sha1 = "bfcaf7ec088eaba362093393fe11aa141fa15422"
registries = "General"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.17.1+0"

[[deps.Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "a63799ff68005991f9d9491b6e95bd3478d783cb"
registries = "General"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.6.0+0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.3.1+2"

[[deps.Zstd_jll]]
deps = ["CompilerSupportLibraries_jll", "Libdl"]
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.7+1"

[[deps.isoband_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51b5eeb3f98367157a7a12a1fb0aa5328946c03c"
registries = "General"
uuid = "9a68df92-36a6-505f-a73e-abb412b6bfb4"
version = "0.2.3+0"

[[deps.libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "ef17c47d22224aaecc76e597ab21a072e025cf7b"
registries = "General"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.14.1+0"

[[deps.libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "cb007192783c56d8249db4cf0e3495001edfe414"
registries = "General"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.17.5+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.15.0+0"

[[deps.libdrm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libpciaccess_jll"]
git-tree-sha1 = "28e57478e8a160d346a19c28b3fffb9273bcc9c2"
registries = "General"
uuid = "8e53e030-5e6c-5a89-a30b-be5b7263a166"
version = "2.4.134+0"

[[deps.libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "646634dd19587a56ee2f1199563ec056c5f228df"
registries = "General"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.4+0"

[[deps.libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "e51150d5ab85cee6fc36726850f0e627ad2e4aba"
registries = "General"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.58+0"

[[deps.libsixel_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "Libdl", "libpng_jll"]
git-tree-sha1 = "c1733e347283df07689d71d61e14be986e49e47a"
registries = "General"
uuid = "075b6546-f08a-558a-be8f-8157d0f608a5"
version = "1.10.5+0"

[[deps.libva_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Xorg_libX11_jll", "Xorg_libXext_jll", "Xorg_libXfixes_jll", "libdrm_jll"]
git-tree-sha1 = "7dbf96baae3310fe2fa0df0ccbb3c6288d5816c9"
registries = "General"
uuid = "9a156e7d-b971-5f62-b2c9-67348b8fb97c"
version = "2.23.0+0"

[[deps.libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll"]
git-tree-sha1 = "11e1772e7f3cc987e9d3de991dd4f6b2602663a5"
registries = "General"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.8+0"

[[deps.libwebp_jll]]
deps = ["Artifacts", "Giflib_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libglvnd_jll", "Libtiff_jll", "libpng_jll"]
git-tree-sha1 = "4e4282c4d846e11dce56d74fa8040130b7a95cb3"
registries = "General"
uuid = "c5f90fcd-3b7e-5836-afba-fc50a0988cb2"
version = "1.6.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.67.1+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.8.2+0"

[[deps.x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "14cc7083fc6dff3cc44f2bc435ee96d06ed79aa7"
registries = "General"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "10164.0.1+0"

[[deps.x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "e7b67590c14d487e734dcb925924c5dc43ec85f3"
registries = "General"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "4.1.0+0"

[registries.General]
url = "https://github.com/JuliaRegistries/General.git"
uuid = "23338594-aafe-5451-b93e-139f81909106"
"""

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
# ╟─c9643bd7-0125-4a9a-8b70-b966bbccf2fa
# ╟─2dc51672-466b-4ba4-8a20-abbd12f9cbe2
# ╟─cf3e479c-74f0-4692-908b-773eb939e653
# ╟─70785342-7c94-4073-9572-8698f1ef9ac2
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
