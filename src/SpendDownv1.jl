# spending scenario: evolution of assets, spending, exogenous and crowded-in, over a time frame
# S is a vector type like Vector{Float64}
@kwdef struct Scenario{S}
  T      ::Int             # length of scenario (in years)
  A      ::S = S(undef,T)  # $ assets at start of each year
  y      ::S = S(undef,T)  # $ spending
  z      ::S = S(undef,T)  # $ exogenous spending
  C::S = S(undef,T)  # crowd-in rate
end
Base.show(io::IO, s::Scenario) = print(io, DataFrame("Assets (A)"=>s.A, raw"Spending $ (y)"=>s.y, "Spending % (x)"=>s.y./s.A*100, raw"Exog spend $ (z)"=>s.z, raw"C"=>s.C))

# composite scenario--with potentially multiple phases. Each phase holds partial views onto vectors representing full scenario.
struct CompositeScenario{S}
  parent::Scenario{Vector{S}}  # holds entire timeline
  n::Int                       # number of phases
  parts::Vector{Scenario{SubArray{S, 1, Vector{S}, Tuple{UnitRange{Int64}}, true}}}  # phases based on views onto parent scenario

  function CompositeScenario{S}(args...) where S  # constructor; args should be episode lengths
    T = sum(args)
    s = Scenario{Vector{S}}(;T)
    @views new{S}(s, length(args), [Scenario(T=length(I), A=s.A[I], y=s.y[I], z=s.z[I], C=s.C[I])
                                      for I ∈ Iterators.accumulate((I,i) -> last(I).+(1:i), args, init=0:0)])
  end
end

# utility of a single phase
utility(s::Scenario; η, δ::Real) =
  sum( δ^(t-1) * ((yₜ * (1+Cₜ) + zₜ)^(1-η) - zₜ^(1-η))
        for (t, (yₜ, zₜ, Cₜ)) ∈ enumerate(zip(s.y, s.z, s.C))
      ) / (1-η)

# utility of scenario with multiple phases, allowing different discount rates in each
function utility(cs::CompositeScenario{S}; η, ḅ, ẋ, f, δ::Vector) where {S}
  length(δ) == cs.n || throw(ArgumentError("Received $(length(δ)) δ parameters for a $(cs.n)-part composite scenario."))

  U = zero(S)
  δc = one(S)  # cumulative discount
  @inbounds for (pᵢ,δᵢ) ∈ zip(cs.parts, δ)
    U += utility(pᵢ; η, δ=δᵢ) * δc
    δc *= δᵢ^pᵢ.T
  end
  U * ḅ * ẋ ^η * (1+f)^75
end


# Spending strategies:
#   Functions that take a Scenario as first arg, which will be written into, and parameters as keyword args
#   Return values ignored
#   Any unneeded parameters passed are ignored

# fixed-rate spending path for inital assets A₀, asset return rate r, spending rate x
function fixed_rate!(s; A₀, r, x, kwargs...)
  s.A[1] = Aₜ = A₀
  ρ = (1+r)*(1-x)
  @inbounds for t=2:s.T
    s.A[t] = (Aₜ *= ρ)
  end
  @inbounds @. s.y = s.A * x
end

# optimal spending path according to the spec https://docs.google.com/document/d/136494mE4MrxbbinCU9RliaJ2tkLjFuvsg6c1p2Mt1RI/edit
function optimal_finite_hor_spec!(s::Scenario; A₀, r, Δ, η, kwargs...)
  rp1 = r + 1
  A = A₀
  ρ = (Δ - r*(1-η))/η
  onemρ = 1 - ρ
  ρʸ = onemρ^s.T
  @inbounds for t ∈ 1:s.T
    s.A[t] = A
    s.y[t] = y = A * ρ / (1 - ρʸ)
    A -= y; A *= rp1
    ρʸ /= onemρ
  end
end

# 2-stage scenario: fixed-rate, then optimized, finite-horizon. Δ₂ is the discount rate for *2nd* phase
function two_part!(cs::CompositeScenario, p, x)
  fixed_rate!(cs.parts[1]; A₀=p[:A₀], r=p[:r], x)
  optimal_finite_hor_spec!(cs.parts[2]; r=p[:r], Δ=p[:Δ₂], η=p[:η], A₀=(cs.parts[1].A[end] - cs.parts[1].y[end]) * (1+p[:r]))
end


@kwdef struct SimModelOld{S}
  rng = TaskLocalRNG  # random number generator, for replicability
  A₀                  # initial assets
  ẋ                   # initial GW cost effectiveness
  ḅ                   # initial GW giving
  η                   # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
  r                   # rate of return on assets
  ∂CE                 # annual decline in cost effectiveness because world is getting better
  z₁                  # initial exogenous spending
  g                   # growth rate of exogenous spending
  C₁            # initial crowd-in rate
  ∂C            # per-decade multiplier for crowd-in decay/growth (e.g., .5)
  f                   # flow-through rate
  e                   # annual risk of extinction, expropriation, etc.
  v                   # annual loss from values drift
  Lₘₐₓ                # learning cap
  T₁      ::Int       # initial learning period (e.g., 10 years)
  T₂      ::Int       # spend-down deadline (e.g., 40 years)
  T       ::Int = T₁ + T₂
  M       ::Int       # number of simulations

  # internal
  nt              ::Int
  batches         ::Vector{UnitRange{Int}} = [floor(Int,M/nt*(t-1))+1:floor(Int,M/nt*t) for t ∈ 1:nt]  # indexes to split simulations by CPU thread
  uncertain_params::Vector{Pair{Symbol,<:UnivariateDistribution}}  # alternate-format storage of above parameters, allowing more model-agnostic code
    certain_params::Vector{Pair{Symbol,S}}
            params::Vector{Dict{Symbol,S}}

  V               ::Matrix{S}                                      # ~9xM matrix of parameter draws
  cs              ::Vector{CompositeScenario{S}} = [CompositeScenario{S}(T₁,T₂) for _ in 1:nt]  # spending & asset paths for each CPU thread
  dist            ::Vector{S} = Vector{S}(undef, M)  # holder for simulated distribution of utility

  x::Vector{S} = Vector{S}(undef,T-1)
  y::Vector{S} = Vector{S}(undef,T)
end

# constructor
# accepts one arg not in the struct def: τ::Union{S, KeyedArray{S}}, which is the Kendall correlations as a scalar or labelled matrix
function SimModelOld{S}(rng; M, T₁, T₂, τ, kwargs...) where {S}
  nt = min(M, Threads.nthreads())

  uncertain_params = [first(p)=>  last(p)  for p ∈ kwargs if   last(p) isa UnivariateDistribution ]  # "first(p)=>  last(p)" logically same as p, but more type-stable
    certain_params = [first(p)=>S(last(p)) for p ∈ kwargs if !(last(p) isa UnivariateDistribution)]
  d = Dict(certain_params); params = [deepcopy(d) for _ ∈ 1:nt]
  l = length(uncertain_params)

  p = first.(uncertain_params)
  Σ = τ isa KeyedArray ? Array{S}(τ(p,p)) : fill(sinpi(S(τ)/2),l,l) # if a labeled correlation matrix, align it with order of entries in uncertain_params
  Σ .= sinpi.(Σ ./ 2)  # Convert Kendall's τ to regular correlation https://math.stackexchange.com/questions/3058888/kendalls-tau-of-bivariate-normal
  Σ[diagind(Σ)] .= 1

  # all uncertain parameter draws; avoid Copulas package because it generates annoying error messages
  # V = rand(rng, SklarDist(GaussianCopula(Σ), Tuple(last.(uncertain_params))), M)
  V = Matrix{S}(undef, l, M)
  𝒩 = Normal(); M𝒩 = MvNormal(Σ)
  dists = last.(uncertain_params)
  @inbounds for m∈1:M
    V[:,m] .= quantile.(dists, cdf.(𝒩, rand(rng, M𝒩)))
  end

  SimModelOld{S}(; rng, M, T₁, T₂, kwargs..., V, uncertain_params, certain_params, params, nt)
end

# version of simulation function to replicate original spenddown model write-up, with two-phase scenarios
function sim(m::SimModelOld{S}, strategy::Function, x) where {S}
  Threads.@threads for i ∈ 1:m.nt
    δ = Vector{S}(undef,2)  # holder for discount rates in each phase

    @inbounds for j ∈ m.batches[i]  # iterate over this thread's simulations
      p = m.params[i]
      for (i,u) ∈ enumerate(m.uncertain_params)  # put uncertain params' current values in the param dict
        p[first(u)] = m.V[i,j]
      end

      _z, _C = m.cs[i].parent.z, m.cs[i].parent.C
      _z[1] = zₜ = p[:z₁]
      _C[1] = Cₜ = p[:C₁]
      g_z = one(S) + p[:g]
      g_C = p[:∂C] ^ (one(S)/m.T₁)
      @inbounds for t ∈ 2:m.T₁+1
        zₜ *= g_z
        _z[t] = zₜ                             # exogenous spending
        _C[t] = (Cₜ *= g_C)  # crowding-in rate
      end
      @inbounds for t ∈ m.T₁+2:m.T₁ + m.T₂
        zₜ *= g_z
        _z[t] = zₜ
        _C[t] = Cₜ
      end

      _δ = (1-p[:∂CE]) * (1-p[:f]) * (1-p[:e]) * (1-p[:v])
      δ[1] = _δ * p[:Lₘₐₓ]^(one(S)/m.T₁)
      δ[2] = _δ
      p[:Δ₂] = 1-_δ + 1-(1+p[:g])^-p[:η]
      strategy(m.cs[i], p, x)  # compute spending path
      m.dist[j] = utility(m.cs[i]; ḅ=p[:ḅ], ẋ=p[:ẋ], η=p[:η], f=p[:f], δ)  # return utility thereof
    end
  end
  m.dist
end

# make a simulation model work like a function that computes utility distribution for initial spending rate x
(m::SimModelOld{S})(x) where {S} = sim(m, two_part!, S.(x))