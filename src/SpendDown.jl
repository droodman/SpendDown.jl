module SpendDown

export SimModel, sim, SimModelOld, simOld, TwoPieceUniform, PiecewiseUniform, Bitriangular, rhist

using Random, Distributions, Statistics, StatsBase, DataFrames, LogExpFunctions, AxisKeys, LinearAlgebra, QuasiMonteCarlo

include("PriorDistributions.jl")
include("SpendDownv1.jl")

const rhist = [  # real January-January S&P returns, 1871-2024, computed from Shiller's ie_data.xls, https://shillerdata.com, Data tab, col. J
                1.139054
                1.087812
                1.020343
                1.125008
                1.118239
                .8508357
                1.16973
                1.296151
                1.237992
                1.343652
                .9280663
                1.055872
                1.023113
                .9769446
                1.345351
                1.1194
                .9485406
                1.082091
                1.124178
                .9155279
                1.26603
                .9848112
                .9360916
                1.080576
                1.034593
                1.062553
                1.16934
                1.275203
                .8869051
                1.239383
                1.165856
                .9876848
                .8672481
                1.291338
                1.213055
                .9636775
                .7748301
                1.349742
                1.050159
                1.035938
                1.045985
                .9989551
                .9335702
                .9359415
                1.274338
                .9620822
                .6807896
                1.001763
                1.022728
                .8738108
                1.237614
                1.298967
                1.024094
                1.271165
                1.216535
                1.141147
                1.387451
                1.493477
                .9057304
                .8310481
                .6197212
                1.040196
                1.53104
                .8928934
                1.527107
                1.298932
                .6743933
                1.189489
                1.037984
                .8982856
                .816631
                1.129713
                1.200692
                1.170023
                1.363003
                .7446544
                .9310727
                1.081985
                1.201119
                1.245138
                1.168263
                1.142581
                1.01877
                1.479252
                1.28459
                1.037795
                .909051
                1.384396
                1.065454
                1.047578
                1.183028
                .9613806
                1.192707
                1.148862
                1.095167
                .9046839
                1.120357
                1.059684
                .8613061
                1.021365
                1.103888
                1.137212
                .7654108
                .7060925
                1.304365
                1.057316
                .8518286
                1.064013
                1.028628
                1.127335
                .8562267
                1.254772
                1.155428
                1.042575
                1.216778
                1.295222
                .938263
                1.126999
                1.169278
                .9386744
                1.286117
                1.043425
                1.089592
                .9840294
                1.317358
                1.236169
                1.259379
                1.29354
                1.124977
                .9137595
                .8554946
                .7785234
                1.261541
                1.030013
                1.059203
                1.110891
                .9453019
                .6435044
                1.298481
                1.145187
                1.004691
                1.144014
                1.236562
                1.135805
                .9525033
                1.181588
                1.224586
                .9379719
                1.250409
                1.162379
                1.13709
                .8269003
                1.198307
                1.206372   ]

const rhist_arithnormed = rhist .- mean(rhist)   # returns history normalized to arithmetic mean = 0
const rhist_geonormed = rhist ./ geomean(rhist)  # returns history normalized to geometric mean = 1

const cachebuff = 32  # how much to extend some array dimensions to prevent false sharing (https://juliafolds2.github.io/OhMyThreads.jl/stable/literate/falsesharing/falsesharing); Mac cache lines are 128B

@kwdef struct SimModel{S}
  rng = TaskLocalRNG()  # random number generator, for replicability

  # these fields not assigned for uncertain parameters; realizations stored in V instead
  lnA₀        ::S = 0  # log initial assets
  ẋ           ::S = 0  # initial GW cost effectiveness
  ḅ           ::S = 0  # initial GW spending
  η           ::S = 0  # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
  r           ::S = 0  # rate of return on assets
  r_geo       ::Bool = true  # interpret r as geometric rather than arithmetic mean
  r_sd        ::S = 1  # multiplier on annual std. dev. of historical returns, if simr=true
  ∂CE         ::Union{S,Vector{S}} = S(0)  # annual decline in cost effectiveness because world is getting better
  z₁          ::S = 0  # initial exogenous spending
  g           ::S = 0  # growth rate of exogenous spending
  C₁          ::S = 0  # initial crowd-in rate
  ∂C          ::S = 0  # per-decade multiplier for crowd-in decay/growth (e.g., .5)
  d           ::S = 0  # pure rate of time preference
  f           ::S = 0  # flow-through rate
  δf          ::S = 0  # annual decay in flow-through
  X           ::S = 0  # total risk of extinction, end of scarcity through ~2100
  e           ::S = 0  # annual risk of expropriation
  v           ::S = 0  # annual loss from values drift
  Lₘₐₓ        ::S = 0  # exogenouslearning cap
  c           ::S = 0  # learning rate: elasticity of effectiveness to cumulative disbursement
  λ           ::S = 1  # scale factor on stock of endogenous learning when calibrate=false
  ϕ           ::S = 1  # elasticity of learning to spending within each year
  σ           ::S = 1
  μ           ::S = 100
  GPD         ::Bool = false
  δₗ           ::S = 0  # annual knowledge depreciation rate
  yhist       ::Vector{S} = S[]  # disbursement history before year 1, which affects subsequent learning levels
  T₁          ::Int        # initial learning period (e.g., 10 years)
  T₂          ::Int        # spend-down deadline (e.g., 40 years)
  T           ::Int = T₁ + T₂
  M           ::Int        # number of simulations
  simr        ::Bool     = false # simulate returns by sampling historical real S&P 500 returns?
  calibrate_b₁::Bool = false  # use ḅ and ẋ to calibrate b₁ and normalize learning=1 at t=1?
  timeline::Matrix{S} = S[;;]  # timeline for cumulative risk of end of philanthropy; will be scaled to average draws from X from now to 2100

  # internal
  nt              ::Int  # number of threads
  batches         ::Vector{UnitRange{Int}}  # indexes of simultations assigned to each thread

  V::Matrix{S}        # ~10xM matrix of uncertain parameter draws
  Tsim::Matrix{Int}   # 1xM. stopping times when simulating X-risk
  Esim::Matrix{S}     # 1xM. ultimate "extinction," which may come after end of spending and affect only flow-through; floating-point type in order to allow Inf
  Asim::Matrix{S}     # T x M matrix of all draws from historical returns, normalized to (geo)mean=1, then scaled by r
  L₁::Vector{S}       # year-1 learning level, depends on fixed spending prehistory
  Δ::Matrix{S}        # exogenous multipliers on the utility term in each year and simulation rollout, incorporating discounts, flow-through, etc.
  u_z::Matrix{S}      # impact of exogenous giving in each year and rollout
  C::Matrix{S}        # crowding-in effect in each year and rollout
  z::Matrix{S}        # exogenous spending in each year and rollout
  param_indices::NamedTuple{(:η, :δₗ, :c, :λ, :ϕ), Tuple{Union{Int,Nothing}, Union{Int,Nothing}, Union{Int,Nothing}, Union{Int,Nothing}, Union{Int,Nothing}}}

  dist::Vector{S}     = Vector{S}(undef,M)  # total utility by simulation: leave behind for histograms, etc.
  u::Vector{S}        = Vector{S}(undef,T)  # can hold EV by year, if requested
  uᵢ::Matrix{S}       = Matrix{S}(undef,T,nt)
  x::Vector{S}        = Vector{S}(undef,T-1)  # trial values of % spending rates by year
  y::Vector{S}        = Vector{S}(undef,T)  # chunks of initial assets to be set aside & invested for each future year; same in all parameter draws
  yr::Matrix{S}       = Matrix{S}(undef,T,nt)  # actual spending levels; vary by draw
  yϕ::Matrix{S}       = Matrix{S}(undef,T,nt)  # y^ϕ
  EV::Vector{S}       = Vector{S}(undef, nt)  # thread-wise accumulators of EV
  y∂u∂y::Matrix{S}    = Matrix{S}(undef, T, nt)  # cross-simualation accumulator for ∂uₜ/∂yₜ × yₜ
  y²∂²u∂y²::Matrix{S} = Matrix{S}(undef, T, nt)  # cross-simualation accumulator for ∂²uₜ/∂yₜ² × yₜ²
  Σy∂u∂y::Vector{S}   = Vector{S}(undef,T)
  Σy²∂²u∂y²::Vector{S} = Vector{S}(undef,T)
  _G::Vector{S}       = Vector{S}(undef,T-1)  # once-allocated scratchpad
  λonemδₗnegty::Matrix{S} = Matrix{S}(undef,T+cachebuff,nt)
  ∂u∂L::Matrix{S}     = Matrix{S}(undef,T+cachebuff,nt)
  Gₗ::Matrix{S}        = Matrix{S}(undef,T-1,nt)
  ϕGₗ::Matrix{S}       = Matrix{S}(undef,T-1,nt)
  Hₗ::Array{S,3}       = Array{S,3}(undef,T-1,T-1,nt)
  ∂L∂logitx::Array{S,3} = Array{S,3}(undef,T,T-1+cachebuff,nt)
  y∂²u∂y∂L::Array{S,3} = Array{S,3}(undef,T,T+cachebuff,nt)
  y∂²u∂y∂L_diag::Matrix{S} = Matrix{S}(undef,T+cachebuff,nt)
  ∂²u∂logitx∂L::Array{S,3} = Array{S,3}(undef,T,T+cachebuff,nt)
  Σ₂::Matrix{S}     = Matrix{S}(undef,T-1+cachebuff,nt)
  ΣGₗ::Vector{S}     = Vector{S}(undef,T-1)
  ΣϕGₗ::Vector{S}    = Vector{S}(undef,T-1)
  Hₗdiag::Matrix{S}  = Matrix{S}(undef,T-1,nt)  # to hold extra term in Hessian diagonal when ϕ≠1
  ΣHₗdiag::Vector{S} = Vector{S}(undef,T-1)
end


# convert something like PieceWiseUniform{Float64} to PieceWiseUniform{S}
convertdist(S, d::UnivariateDistribution) = typeof(d).name.wrapper(map(x->S.(x), params(d))...)


# model constructor
# Accepts one arg not in the struct def: τ::Union{S, KeyedArray{S}}, which is the Kendall correlations as a scalar or labeled matrix
#
# Sole positional argument is a lxM matrix of draws from unit interval for simulating uncertain params,
#   where l = # of uncertain params and M = # of simulations
# Suggested usage for quasi-Monte Carlo draws: quantile.(𝒩, QuasiMonteCarlo.sample(M, zeros(S,l), ones(S,l), SobolSample()))

function SimModel{S}(seqs::AbstractMatrix{S}; rng=TaskLocalRNG(), M, T₁, T₂, τ, simr::Bool=false, r_geo::Bool=true, r_sd=one(S), GPD::Bool=false, calibrate_b₁::Bool=false, yhist::Vector=S[], timeline=S[;;], t₁=2025, kwargs...) where {S}
  M  = min(M, size(seqs,2))
  nt = min(M, Threads.nthreads())
  batches = [floor(Int,M/nt*(t-1))+1:floor(Int,M/nt*t) for t ∈ 1:nt]  # indexes to split simulations by CPU thread
  T = T₁ + T₂

  uncertain_params = [first(p)=>convertdist(S, last(p)) for p ∈ kwargs if   last(p) isa UnivariateDistribution ]
    certain_params = [first(p)=>            S.(last(p)) for p ∈ kwargs if !(last(p) isa UnivariateDistribution)]
  l = length(uncertain_params)

  uncertain_param_syms = first.(uncertain_params)
  Σ = τ isa KeyedArray ? S.(τ(uncertain_param_syms,uncertain_param_syms)) : fill(S(τ),l,l)  # if a (labeled) correlation matrix, align it with order of entries in uncertain_params
  Σ .= sinpi.(Σ ./ 2)  # Convert Kendall's τ to regular correlation https://math.stackexchange.com/questions/3058888/kendalls-tau-of-bivariate-normal
  Σ[diagind(Σ)] .= 1

  # all uncertain parameter draws; avoid Copulas package because it generates annoying error messages when loaded, as with:
  #   V = rand(rng, SklarDist(GaussianCopula(Σ), Tuple(last.(uncertain_params))), M)
  dists = last.(uncertain_params)
  𝒩 = Normal(zero(S),one(S)) 
  V = cholesky(Σ, NoPivot()).L * quantile.(𝒩, seqs)  # map to multivariate normal with covariance Σ
  V = quantile.(dists, cdf.(𝒩, V))  # map to desired distributions via cdfs. ".=" instead of "=" causes intermittent crash

  realizations(s::Symbol) = findfirst(==(s), uncertain_param_syms) |> t -> isnothing(t) ? kwargs[s] : view(V,t:t,:)  # get scalar or 1xM matrix of realizations for a param

  randGeometric(p   ) = p < eps(S) ?      S(Inf)      : one(S)  + rand(rng, Geometric(p))  # draw from geometric distribution with mean 1/p
  randGeometric(p, M) = p < eps(S) ? fill(S(Inf),1,M) : one(S) .+ rand(rng, Geometric(p),1,M)  # M draws from geometric distribution with mean 1/p

  # simulate X-risk realizations, whether the risk is constant or time-varying (with base timeline supplied)
  X = realizations(:X)
  if isempty(timeline)  # X-risk constant?
    X = @. 1  - (1 - X)^(1/(2100 - t₁))  # convert from through-2100 risk to annual risk
    Esim = X isa Number ? randGeometric(S(X),M) : randGeometric.(X)  # Esim holds simulated end-of-time in all simulations
  else
    timeline_end = Int(timeline[end,1])

    # log annual survival rate in each block of timeline, as fraction of log cumulative survival at timeline end
    log_s = [S((log((1-timeline[y,2])/(1-timeline[y-1,2]))) / 
               (       timeline[y,1] -   timeline[y-1,1]) / log1p(-timeline[end,2]))
             for y ∈ Iterators.drop(axes(timeline,1),1)]
    log_s = log_s[findlast.(.≤(t₁:timeline_end), Ref(timeline[1:end-1,1]))]  # explode to one row per year
    timeline_end -= t₁ - 1

    Esim = Matrix{S}(undef,1,M)  # Esim holds simulated end-of-time in all simulations
    X isa Number && (logS₂₁₀₀ = log1p(-X))  # log cumulative survival probablility from compounding fixed-rate X over timeline duration: use to scale time-varying timeline to same cumulative survival
    @inbounds for m∈1:M
      X isa Number || (logS₂₁₀₀ = log1p(-X[m]))
      Esimₘ = timeline_end+1
      for t ∈ 2:timeline_end  # sequence of Bernoulli processes to simulate end of philanthropy during time-varying hazard
        if rand(rng) ≥ exp(log_s[t] * logS₂₁₀₀)
          Esimₘ = t-1  # extinction/cornucopia at time t in simulation m
          break
        end
      end
      Esim[m] = Esimₘ ≤ timeline_end ? Esimₘ : timeline_end + randGeometric(-expm1(log_s[end] * logS₂₁₀₀))  # if survive to end of timeline period, simulate later extinction for flow-through, assuming risk constant at final rate in timeline
    end
  end
  Tsim = Int.(min.(T, Esim))  # stopping time for spending as distinct from flow-through

  # simulated assets at each time in each simulation if no spending ever
  if r_geo
    Asim = simr ? rand(rng, rhist_geonormed, T, M) : ones(S,T,M)  # whether constant or sampled from normalized history, expected geomean of this = 1
    Asim .= Asim .^ r_sd .* (1 .+ realizations(:r)) # scale to geomean=1+r
  else
    Asim = simr ? rand(rng, rhist_arithnormed, T, M) : ones(S,T,M)  # whether constant or sampled from normalized history, expected mean of this = 1
    Asim .= Asim .* r_sd .+ (1 .+ realizations(:r)) # scale to arithmetic mean=1+r
  end
  Asim[1,:] .= 1  # no returns compounding at t=1
  cumprod!(Asim, Asim, dims=1)  # compound the returns
  Asim .*= exp.(realizations(:lnA₀))  # scale by initial assets

  # compute exogenous components, which differ accross simulation rollouts, but not across _simulations_ during optimization because they do not depend on spending
  Δ = Matrix{S}(undef,T,M)
  u_z = Matrix{S}(undef,T,M)
  L₁ = Vector{S}(undef,M)
  C = Matrix{S}(undef,T,M)
  z = Matrix{S}(undef,T,M)
  Threads.@threads for i ∈ 1:nt
    @fastmath @inbounds for j ∈ batches[i]  # iterate over this thread's simulations
      p = deepcopy(Dict(certain_params))
      for (k,u) ∈ enumerate(uncertain_params)  # put uncertain params' current values in the param dict
        p[first(u)] = V[k,j]  # some computational cost in using a Dict, but handles uncertain parameters gracefully, by name
      end
      zₜ, η, onemδₗ, g, λ, ϕ, ∂CE, e, f₀, v, d, X, Lₘₐₓ, ẋ, ḅ, δf, Cₜ, ∂C, c =
         p[:z₁], p[:η], 1-p[:δₗ], p[:g], p[:λ], p[:ϕ], p[:∂CE], p[:e], p[:f], p[:v], p[:d], p[:X], p[:Lₘₐₓ], p[:ẋ], p[:ḅ], p[:δf], p[:C₁], p[:∂C], p[:c]
      λ *= ϕ  # To simplify derivatives, the code is written with y_s^ϕ/ϕ instead of y_s^ϕ in the learning equation. This line mathematically undoes that.

      δf += d  # add pure rate of time preference to flow-through decay rate (flow-through math is in continuous time for simplicity)
      doflowthrough = !iszero(δf)  # account for flow-through unless it doesn't decay
      f₀divδf = f₀ / δf

      onemη = 1 - η
      zₜto1mη = zₜ^onemη
      g_z = 1 + g  # growth multiplier for exogenous spending, zₜ
      g_zto1mη = g_z^onemη  # growth multiplier for zₜ^(1-η) (cute speed-up)
      g_C = ∂C ^ (one(S)/T₁)  # growth rate in first period of crowding-in effect

      L = zero(S); for y ∈ yhist L += isone(ϕ) ? y : y^ϕ/ϕ; L *= onemδₗ end; L₁[j] = λ * L  # initial learning level from y prehistory

      δ2 = (1-v) * (1-d) * (1-e); ∂CE isa Number && (δ2 *= 1 - ∂CE)  # phase 2 discount rate      
      δ1 = δ2 * Lₘₐₓ^(one(S)/T₁)  # phase 1 discount rate

      δc = calibrate_b₁ ? ḅ * (ẋ/L₁[j]^c)^η / η : 1/η  # if calibrating with ḅ * ẋ^η, also rescale learning multiplier to 1, dividing by (λL₁)^η 

      # simulation rollout of exogenous factors
      for t ∈ 1:Tsim[j]
        scale = δc
        doflowthrough && (scale /= exp(f₀divδf * expm1(δf * (t - Esim[j]))))  # flow-through-scale impact, exp⁡(f_0/δ ̃_f  [1-e^(-δ ̃_f (T-t) ) ])
        Δ[t,j] = scale  # exogenous multiplier on own spending impact
        u_z[t,j] = scale * zₜto1mη; zₜto1mη *= g_zto1mη  # impact of exogenous others' spending

        z[t,j] = zₜ; zₜ *= g_z  # update exog spending
        δc *= t ≤ T₁ ? δ1 : δ2; !(∂CE isa Number) && (δc *= 1 - ∂CE[t])  # update cumulative discount
        C[t,j] = 1 + Cₜ; t ≤ T₁ && (Cₜ *= g_C)
      end
    end
  end

  param_indices = (
    η = findfirst(p -> first(p) == :η, uncertain_params),
    δₗ = findfirst(p -> first(p) == :δₗ, uncertain_params),
    c = findfirst(p -> first(p) == :c, uncertain_params),
    λ = findfirst(p -> first(p) == :λ, uncertain_params),
    ϕ = findfirst(p -> first(p) == :ϕ, uncertain_params)
  )

  SimModel{S}(; rng, M, T₁, T₂, certain_params..., simr, GPD, yhist=S.(yhist), V, Tsim, Esim, Asim, L₁, Δ, u_z, C, z, nt, batches, calibrate_b₁, param_indices)
end

# wrapper for constructor, which takes rng rather than matrix of uniform draws as a sole positional argument
# if QMC=true, generates Sobol' rather than pseudo-random sequences, and just passes the rng to SimModel() to simulate stochastic events
function SimModel{S}(rng::AbstractRNG; M, QMC=false, kwargs...) where {S}
  l = sum(last(p) isa UnivariateDistribution for p ∈ kwargs)  # number of uncertain params
  SimModel{S}(QMC ? QuasiMonteCarlo.sample(M, zeros(S,l), ones(S,l), SobolSample(R=QuasiMonteCarlo.Shift(rng))) : 
                    rand(rng,S,l,M);
              rng, M, kwargs...)
end

# reverse cumulative sum
function rev_cumsum!(x::AbstractVector{S}) where {S}
  cumsum = zero(S)
  @inbounds for i ∈ lastindex(x):-1:firstindex(x)
    cumsum += x[i]
    x[i] = cumsum
  end
  x
end

# simulation function to be called from optimizing routine. Returns total utility along with gradient and Hessian if requested.
# If byyear==true, will also save EV by year in m.u
# After optimization, m.x will hold the optimal spending rates, not in logits
function sim(m::SimModel, _nothing, G, H, logitx::Vector{S}; byyear=false) where {S}
  dogradient = !isnothing(G)
  dohessian  = !isnothing(H)

  fill!(m.EV, 0)
  byyear && fill!(m.uᵢ,0)
  if dogradient || dohessian
    fill!(m.y∂u∂y, 0)  # cross-simualation accumulator for ∂uₜ/∂yₜ × yₜ
    fill!(m.Gₗ, 0)
    if dohessian
      fill!(m.ϕGₗ, 0)
      fill!(m.y²∂²u∂y², 0)  # cross-simualation accumulator for ∂²uₜ/∂yₜ² × yₜ²
      fill!(m.Hₗ, 0)
      fill!(m.Hₗdiag, 0)
    end
  end
   
  m.x .= logistic.(logitx)
  m.y[1] = 1; m.y[2:end] .= 1 .- m.x
  cumprod!(m.y, m.y)  # assets at start of each period, as fractions of A₀, not factoring in future investment returns; same in all simulations
  @inbounds for k∈1:m.T-1 m.y[k] *= m.x[k] end  # fraction of initial assets to be set aside and invested in year 1 for eventual use in each year

  Threads.@threads for i ∈ 1:m.nt
    @fastmath @inbounds for j ∈ m.batches[i]  # iterate over this thread's simulations
      η = isnothing(m.param_indices.η) ? m.η : m.V[m.param_indices.η,j]
      c = isnothing(m.param_indices.c) ? m.c : m.V[m.param_indices.c,j]
      λ = isnothing(m.param_indices.λ) ? m.λ : m.V[m.param_indices.λ,j]
      onemδₗ = isnothing(m.param_indices.δₗ) ? 1-m.δₗ : 1-m.V[m.param_indices.δₗ,j]
      ϕ = isnothing(m.param_indices.ϕ) ? m.ϕ : m.V[m.param_indices.ϕ,j]
      λ *= ϕ  # To simplify derivatives, the code below is written with y_s^ϕ/ϕ instead of y_s^ϕ in the learning equation. This line mathematically undoes that.
      onemϕ = 1 - ϕ
      onemη = 1 - η
      cη = c*η
      U = zero(S)  # total utility
      onemδₗnegt = one(S)  # accumulator for (1+δₗ)^-t
      Lₜ = m.L₁[j]  # initial learning level from y prehistory
      T = m.Tsim[j]  # stopping time for spending
      m.GPD && (μ̂  = m.μ - m.σ / η)  # for GP distribution only

      for t ∈ 1:T
        m.yr[t,i] = m.y[t] * m.Asim[t,j]  # $ spending in year t
        m.yϕ[t,i] = isone(ϕ) ? m.yr[t,i] : m.yr[t,i] ^ ϕ
        _y = m.yr[t,i] * m.C[t,j]
        ỹₜ = _y + m.z[t,j]  # $ spending, all sources
        Lₜcη  = Lₜ^cη
        uₜ = m.Δ[t,j] * Lₜcη * ỹₜ ^ onemη  # utility thereof, sans 1/(1-η) multiplier
        Uₜ = (uₜ - Lₜcη * m.u_z[t,j]) / onemη
        m.GPD && (Uₜ += μ̂y = μ̂ * _y * m.Δ[t,j])  # second utility term, associated with Generalized Pareto
        U += Uₜ; byyear && (m.uᵢ[t,i] += Uₜ)

        if dogradient || dohessian
          ydivỹ = _y / ỹₜ
          m.y∂u∂y[t,i] += y∂u∂yₜ = uₜ * ydivỹ  # yₜ × sans-learning derivative: ḅ^(1+η) * δc * Lₜ^(c*η)/η * ỹₜ^onemη / ỹₜ * m.y[t] * rp1t * (1+Cₜ)
          m.GPD && (m.y∂u∂y[t,i] += μ̂y)  # derivative of extra GPD term just a constant

          onemδₗnegt /= onemδₗ
          onemδₗnegtLₜ = iszero(Lₜ) ? onemδₗnegt : onemδₗnegt * Lₜ

          t<m.T && (m.λonemδₗnegty[t,i] = λ * onemδₗnegt * m.yϕ[t,i])
          m.∂u∂L[t,i] = Uₜ * cη / onemδₗnegtLₜ  # (1-δₗ)^t × ∂uₜ/∂Lₜ

          if dohessian
            m.y²∂²u∂y²[t,i] -= y∂u∂yₜ * η * ydivỹ

            ∂²u∂y∂L = λ * (cη-1) / onemδₗnegtLₜ * m.∂u∂L[t,i]
            for q ∈ 1:t-1
              ∂²u∂y∂L /= onemδₗ
              m.y∂²u∂y∂L[q,t,i] = m.yϕ[q,i] * ∂²u∂y∂L
            end
            
            m.y∂²u∂y∂L_diag[t,i] = m.y∂²u∂y∂L[t,t,i] = y∂u∂yₜ * cη / onemδₗnegtLₜ
            Σy∂²u∂y∂L = t==m.T ? m.y∂²u∂y∂L_diag[t,i] : zero(S)
            for p ∈ min(t,m.T-1):-1:1
              Σy∂²u∂y∂L += (tmp = m.y∂²u∂y∂L[p,t,i])
              m.∂²u∂logitx∂L[t,p,i] = tmp - m.x[p] * Σy∂²u∂y∂L  # (1-δₗ)^t × m.∂²u∂logitx∂L
            end
          end
        end
        
        Lₜ += λ * (isone(ϕ) ? m.yr[t,i] : m.yϕ[t,i]/ϕ); Lₜ *= onemδₗ  # update endogenous learning stock
      end
      
      # derivatives through endogenous learning, except component that is x × gradient wrt learning done later
      if dogradient || dohessian
        _T = min(T,m.T-1)  # last year with spending decision: year of simulated end of philanthropy if any, otherwise penultimate year
        for s ∈ 1:_T
          Σλonemδₗnegty = λonemδₗnegtyₛᵢ = m.λonemδₗnegty[s,i]
          xₛ = m.x[s]
          for t ∈ s+1:T
            m.Gₗ[s,i] += tmp = m.∂u∂L[t,i] * (m.∂L∂logitx[t,s,i] = λonemδₗnegtyₛᵢ - xₛ * Σλonemδₗnegty)
            dohessian && (m.ϕGₗ[s,i] += ϕ * tmp)
            Σλonemδₗnegty += m.λonemδₗnegty[t,i]
          end
        end

        if dohessian
          if !isone(ϕ)  # additional in Hessian diagonal when ϕ≠1. (1-x_s )(1-ϕ)λ (y_s^ϕ)/(1-δ_l )^s  ∑_(t=s+1)^T▒〖(1-δ_l )^t  (∂u_t)/(∂L_t )〗
            rev_cumsum!(@view m.∂u∂L[2:T,i])
            for s ∈ 1:_T
              m.Hₗdiag[s,i] += onemϕ * m.λonemδₗnegty[s,i] * m.∂u∂L[s+1,i]
            end
          end
  
          # Hessian component: derivative of non-learning *gradient* terms via learning
          # (∂^2 u_s)/(∂y_s ∂L_s ) y_s  (∂L_s)/(∂ logit⁡〖x_p 〗) - x_s ∑_(r=s)^T▒〖(∂^2 u_r)/(∂y_r ∂L_r ) y_r  (∂L_r)/(∂ logit⁡〖x_p 〗 )〗

          # s = _T iteration of s loop below
          A = m.y∂²u∂y∂L_diag[_T,i]
          if _T < T  # no premature end of philanthropy
            xₛ = m.x[_T]
            for p ∈ 1:_T-1
              Σ₁        = m.∂L∂logitx[T,_T,i] * m.∂²u∂logitx∂L[T,p,i]
              m.Σ₂[p,i] = m.∂L∂logitx[T, p,i] * m.y∂²u∂y∂L_diag[T,i]
              m.Hₗ[p,_T,i] += Σ₁ - xₛ * m.Σ₂[p,i] + A * m.∂L∂logitx[_T,p,i]
            end
            # p = _T iteration of p loop above
            Σ₁         = m.∂L∂logitx[T,_T,i] * m.∂²u∂logitx∂L[T,_T,i]
            m.Σ₂[_T,i] = m.∂L∂logitx[T,_T,i] * m.y∂²u∂y∂L_diag[T,i]
            m.Hₗ[_T,_T,i] += Σ₁ - xₛ * m.Σ₂[_T,i]
          else  # _T=T
            for p ∈ 1:_T-1
              m.Σ₂[p,i] = 0
              m.Hₗ[p,_T,i] += A * m.∂L∂logitx[_T,p,i]
            end
            m.Σ₂[_T,i] = 0
          end

          for s ∈ _T-1:-1:1
            xₛ = m.x[s]
            A = (1 - xₛ) * m.y∂²u∂y∂L_diag[s,i]
            for p ∈ 1:s-1
              Σ₁ = zero(S)
              @simd for t ∈ s+1:T
                Σ₁ += m.∂L∂logitx[t,s,i] * m.∂²u∂logitx∂L[t,p,i]
              end
              m.Σ₂[p,i] += m.∂L∂logitx[s+1,p,i] * m.y∂²u∂y∂L_diag[s+1,i]  # Σ₂ = sum_(t ∈ s+1:T) of m.∂L∂logitx[t,p ,i] * m.y∂²u∂y∂L_diag[t,i]
              m.Hₗ[p,s,i] += Σ₁ - xₛ * m.Σ₂[p,i] + A * m.∂L∂logitx[s,p,i]
            end
            
            # p = _T iteration of p loop above
            Σ₁ = zero(S)
            for t ∈ s+1:T
              Σ₁ += m.∂L∂logitx[t,s,i] * m.∂²u∂logitx∂L[t,s,i]
            end
            m.Σ₂[_T,i] += m.∂L∂logitx[s+1,s,i] * m.y∂²u∂y∂L_diag[s+1,i]
            m.Hₗ[s,s,i] += Σ₁ - xₛ * m.Σ₂[_T,i]
          end
        end
      end

      m.EV[i] += (m.dist[j] = U)
    end
  end
  
  # sum results across thread-specific batches of simulations
  if dogradient || dohessian
    sum!(m.Σy∂u∂y, m.y∂u∂y)  # sum over CPU cores
    sum!(m.ΣGₗ, m.Gₗ)

    !dogradient && (G = m._G)
    ΣΣy∂u∂y = m.Σy∂u∂y[end]
    @inbounds @fastmath for s ∈ m.T-1:-1:1
      ΣΣy∂u∂y += m.Σy∂u∂y[s]
      G[s] = m.Σy∂u∂y[s] - m.x[s] * ΣΣy∂u∂y  # ∂U/∂logit xₛ = ∂uₛ/∂yₛ × yₛ - xₛ × Σ_(t=s)^T ∂uₜ/∂yₜ × yₜ
    end

    if dohessian
      sum!(m.Σy²∂²u∂y², m.y²∂²u∂y²)  # sum over CPU cores
      sum!(m.ΣHₗdiag, m.Hₗdiag)
      sum!(m.ΣϕGₗ, m.ϕGₗ)
      ΣΣy²∂²u∂y² = m.Σy²∂²u∂y²[end]
      @inbounds @fastmath for s ∈ m.T-1:-1:1
        ΣΣy²∂²u∂y² += m.Σy²∂²u∂y²[s]
        m.Σy²∂²u∂y²[s] += G[s]  # optimization hack since these two added together in two places
        tₛ = m.x[s] * ΣΣy²∂²u∂y² - m.Σy²∂²u∂y²[s] - m.ΣϕGₗ[s]
        for r ∈ 1:s
          H[r,s] = m.x[r] * tₛ
        end
        H[s,s] += (1 - m.x[s]) * (m.Σy²∂²u∂y²[s] + m.ΣGₗ[s] - m.ΣHₗdiag[s])
      end

      # add in learning components, except the bits added above through ΣGₗ
      @inbounds for i∈1:m.nt, s∈1:m.T-1, r∈1:s
        H[r,s] += m.Hₗ[r,s,i]
      end
      @inbounds for s∈1:m.T-1, r∈1:s-1
        H[s,r] = H[r,s]
      end
      H ./= -m.M
    end

    @. G = (G + m.ΣGₗ) / -m.M  # mean gradient over simulations; negated because Optim minimizes
  end

  if byyear
    sum!(m.u, m.uᵢ)
    m.u ./= m.M
  end

  sum(m.EV) / -m.M  # mean over simulations; negated because Optim minimizes
end

end