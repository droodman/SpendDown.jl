# this file demonstrates CUDA implementation of the version 1 model and an early take of the version 2 model

module SpendDownCUDA
export SimModel, sim, TwoPieceUniform, utility, unrestricted_rates!, fixed_rate!

using Distributions, Statistics, Copulas, LinearAlgebra, DataFrames, CUDA, LogExpFunctions

include("PriorDistributions.jl")

const sims_t = Int32
const years_t = Int16

# asset & spending curves for all simulations, t=1,...
@kwdef struct Scenario{S}
  M       ::sims_t              # number of simulations
  T       ::years_t             # length of scenario (in years)
  zero2tm1::CuVector{years_t} = CuVector{years_t}(0:T-1)
  A       ::S = S(undef,T,M)  # $ assets at *start* of each period
  y       ::S = S(undef,T,M)  # $ spending
  z       ::S = S(undef,T,M)  # $ exogenous spending
  C ::S = S(undef,T,M)  # crowd-in rate
end
Base.show(io::IO, s::Scenario) = print(io, DataFrame("Assets (A)"=>s.A, raw"Spending $ (y)"=>s.y, "Spending % (x)"=>s.y./s.A*100, raw"Exog spend $ (z)"=>s.z, raw"C"=>s.C))

# composite scenario--with potentially multiple phases. Each phase holds partial views onto vectors representing full scenario.
struct CompositeScenario{S}
  parent::Scenario{CuMatrix{S}}  # holds entire timeline
  n::years_t                     # number of phases
  T::years_t                     # length in years
  M::sims_t                      # number of simulations
  phases::Vector{Scenario{SubArray{S, 2, CuArray{S, 2, CUDA.DeviceMemory}, Tuple{UnitRange{Int64}, Base.Slice{Base.OneTo{Int64}}}, false}}}  # phases based on views onto parent scenario

  function CompositeScenario{S}(M, args...) where S  # constructor; args should be # of sims, then episode lengths
    T = years_t(sum(args))
    s = Scenario{CuMatrix{S}}(;M,T)  # parent scenario holding full history
    @views new{S}(s, years_t(length(args)), T, sims_t(M), [Scenario(M=sims_t(M), T=years_t(length(I)), A=s.A[I,:], y=s.y[I,:], z=s.z[I,:], C=s.C[I,:])
                                          for I ∈ Iterators.accumulate((I,i) -> last(I).+(1:i), args, init=0:0)])
  end
end

# utility of a single phase
utility(s::Scenario; η, δ) = sum(@. δ^s.zero2tm1 * ((s.y * (1+s.C) + s.z)^(1-η) - s.z^(1-η)); dims=1) ./ (1 .- η)

# utility of scenario with multiple phases, allowing different discount rates in each
function utility(cs::CompositeScenario{S}; η, ḅ, f, δ) where {S}
  U = CUDA.fill(zero(S), 1, cs.M)
  δc = CUDA.fill(one(S), 1, cs.M)  # cumulative discount
  @inbounds for i ∈ 1:cs.n
    δᵢ, pᵢ = view(δ,i:i,:), cs.phases[i]
    U .+= utility(pᵢ; η, δ=δᵢ) .* δc
    @. δc *= δᵢ^pᵢ.T
  end
  @. U * ḅ^(1+η) # * (1+f)^75
end


# Spending strategies:
#   Functions that take a Scenario as first arg, which will be written into, and parameters as keyword args
#   Any unneeded parameters passed are ignored

# fixed-rate spending path for inital assets A₀, asset return rate r, spending rate x
function fixed_rate!(s::Scenario{<:AbstractMatrix{S}}; A₀, rp1, x, kwargs...) where {S}
  @. s.A[1:s.T,:] = A₀ * ((one(S) - x) * rp1) ^ s.zero2tm1
  @. s.y = s.A * x
end

# Exact optimal spending path NOT quite according to the spec https://docs.google.com/document/d/136494mE4MrxbbinCU9RliaJ2tkLjFuvsg6c1p2Mt1RI/edit
# The spec inclues an approximation. Under the exact solution computations are more parallelizable over time
function optimal_finite_hor!(s::Scenario{<:AbstractMatrix{S}}; A₀, rp1, Δ, η, kwargs...) where {S}
  ρ   = @. ((1-Δ)*rp1)^(1/η)
  _ρ  = @. ρ / rp1
  _ρ̂T = @. _ρ^s.T
  @. s.y = A₀ * (1 - _ρ) / (1 - _ρ̂T) * ρ^s.zero2tm1
  @. s.A = rp1 ^ s.zero2tm1 * (ρ^s.zero2tm1 - _ρ̂T) / (1 - _ρ̂T)
end

# 2-stage scenario: fixed-rate, then optimized, finite-horizon. Δ₂ is the discount rate for *2nd* phase
function two_part_spend!(cs::CompositeScenario; A₀, rp1, Δ₂, η, x, kwargs...)
  fixed_rate!(cs.phases[1]; A₀, rp1, x)
  optimal_finite_hor!(cs.phases[2]; rp1, Δ=Δ₂, η, A₀= @. @views (cs.phases[1].A[end:end,:] - cs.phases[1].y[end:end,:]) * rp1)
end

# unrestricted spending rates as % of assets in each period
function unrestricted_rates!(cs::CompositeScenario; A₀, rp1, x, kwargs...)
  _x = CuVector(x)
  y = [A₀; 1 .- _x]                       # assumes A₀ is a scalar, not a vector of draws from a distribution
  CUDA.cumprod!(y, y)                    # assets at start of each period, not factoring in investment returns
  y[1:cs.T-1] .*= _x                        # spending in each period, not factoring in investment returns
  @. cs.parent.y = y * rp1 ^ (0:cs.T-1)  # spending $
end

@kwdef struct SimModel{S}
  rng = TaskLocalRNG  # random number generator, for replicability
  A₀                  # initial $ assets (Aₜ = assets at end of period t)
  ẋ                  # initial GW cost effectiveness
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
  T₁      ::years_t   # initial learning period (e.g., 10 years)
  T₂      ::years_t   # spend-down deadline (e.g., 40 years)
  τ       ::S         # Kendall correlation among uncertain parameters
  M       ::sims_t    # number of simulations

  # internal
  T               ::years_t  = T₁ + T₂
  uncertain_params::Vector{Pair{Symbol,<:UnivariateDistribution}}  # alternate-format storage of above parameters, allowing more model-agnostic code
    certain_params::Vector{Pair{Symbol,S}}
  params          ::Dict{Symbol, CuMatrix{S}}  # instances of all params, certain and uncertain, over all simulations, as Dict of scalars & 1xM arrays
  V               ::CuMatrix{S}                                      # ~9xM matrix of parameter draws
  cs              ::CompositeScenario{S} = CompositeScenario{S}(M,T₁,T₂)  # spending & asset paths for each CPU thread
  dist            ::CuMatrix{S} = CuMatrix{S}(undef,1,M)  # holder for simulated distribution of utility
  y               ::CuMatrix{S} = CuMatrix{S}(undef,T,M)  # endogenous $ spending
  C         ::CuMatrix{S} = CuMatrix{S}(undef,T,M)  # Crowding-in multiplier
  _y              ::CuMatrix{S} = CuMatrix{S}(undef,T,M)  # endog spending, including crowded-in
  ydivỹ           ::CuMatrix{S} = CuMatrix{S}(undef,T,M)
  z               ::CuMatrix{S} = CuMatrix{S}(undef,T,M)  # exogenous $ spending
  ỹ               ::CuMatrix{S} = CuMatrix{S}(undef,T,M)   # endog + exog spending
  δ               ::CuMatrix{S} = CuMatrix{S}(undef,T,M)  # cumulative discounting
  tmp             ::CuMatrix{S} = CuMatrix{S}(undef,1,M)
  onemη           ::CuMatrix{S} = CuMatrix{S}(undef,1,M)
  C               ::CuMatrix{S} = CuMatrix{S}(undef,1,M)
  u               ::CuMatrix{S} = CuMatrix{S}(undef,T,M)

  x::Vector{S} = Vector{S}(undef,T-1)
  uy::CuMatrix{S}  = CuMatrix{S}(undef, T,M)  # cross-simualation accumulator for ∂uₜ/∂yₜ × yₜ
  CuSuy::CuVector{S} = CuVector{S}(undef,T)  # cross-simualation accumulator for ∂uₜ/∂yₜ × yₜ
  Suy::Vector{S}  = Vector{S}(undef,T)  # cross-simualation accumulator for ∂uₜ/∂yₜ × yₜ
  uy2::Vector{S} = Vector{S}(undef,T)  # cross-simualation accumulator for ∂²uₜ/∂yₜ² × yₜ²
  Luy::SubArray{S, 1, Vector{S}, Tuple{UnitRange{Int64}}, true} = @view Suy[1:end-1]
  _G::Vector{S} = Vector{S}(undef,T-1)
end

# constructor
function SimModel{S}(rng; M, T₁, T₂, A₀, τ, kwargs...) where {S}
  uncertain_params = [first(p)=>  last(p)  for p ∈ kwargs if   last(p) isa UnivariateDistribution ]  # "first(p)=>  last(p)" logically same as p, but more type-stable
    certain_params = [first(p)=>S(last(p)) for p ∈ kwargs if !(last(p) isa UnivariateDistribution)]
            params = Dict{Symbol, CuMatrix{S}}(first(p)=>CUDA.fill(last(p),1,M) for p ∈ certain_params)
  
  l = length(uncertain_params)
  Σ = fill(sinpi(S(τ)/2),l,l)  # Convert Kendall's τ to regular correlation https://math.stackexchange.com/questions/3058888/kendalls-tau-of-bivariate-normal
  Σ[diagind(Σ)] .= 1
  V = rand(rng, SklarDist(GaussianCopula(Σ), Tuple(last.(uncertain_params))), M)

  @inbounds for (i,u) ∈ enumerate(uncertain_params)
    params[first(u)] = CuArray(@view V[i:i,:])
  end

  SimModel{S}(; rng, M, T₁, T₂, T=T₁+T₂, A₀, τ=S(τ), kwargs..., V, uncertain_params, certain_params, params)
end

# version 1 model

function sim(m::SimModel{S}; x, spend_strategy=two_part_spend!) where {S}
  _z       = m.cs.parent.z
  _C = m.cs.parent.C
  p = m.params

  @. _z[1:m.T,:] = p[:z₁] * p[:g] ^ (0:m.T-1)  # exogenous spending grows at rate g

  @. _C[1:m.T₁+1,:] = p[:C₁] * p[:∂C] ^ ((0:m.T₁)/S(m.T₁))  # crowding-in grows or decays in 1st phase...
  @. _C[m.T₁+2:end,:] .= @view _C[m.T₁+1:m.T₁+1,:]             # then stops

  _δ = @. (1-p[:∂CE]) * (1-p[:f]) * (1-p[:e]) * (1-p[:v])
  δ = CuMatrix{S}(undef,2,m.M)  # holder for discount rates in each phase
  δ[1,:] = @. _δ * p[:Lₘₐₓ]^(one(S)/m.T₁)  # discount includes learning in first phase
  δ[2,:] =    _δ

  spend_strategy(m.cs; A₀=m.A₀, rp1=p[:r], Δ₂=(@. 1-_δ+1-p[:g]^-p[:η]), η=p[:η], x)  # compute spending path
  m.dist .= utility(m.cs; ḅ=p[:ḅ], η=p[:η], f=p[:f], δ)                              # return utility thereof
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


#----
# early version of version 2 model: spending rates in each period are unrestricted, but no endogenous learning or other new features
#----

function sim(m::SimModel{S}, _, G, H, logitx) where {S}
  dogradient = !isnothing(G)
  dohessian = !isnothing(H)

  p = m.params

  @. m.x = logistic(logitx)
  y = [m.A₀; 1 .- m.x]                       # assumes A₀ is a scalar, not a vector of draws from a distribution
  cumprod!(y, y)                    # assets at start of each period, not factoring in investment returns
  y[1:m.T-1] .*= m.x                        # spending in each period, not factoring in investment returns
  _y = CuVector(y)
  @. m.y = _y * p[:r] ^ (0:m.T-1)  # spending $

  @. m.z = p[:z₁] * p[:g] ^ (0:m.T-1)  # exogenous spending grows at rate g

  @. m.C[1:m.T₁+1,:] = p[:C₁] * p[:∂C] ^ ((0:m.T₁)/S(m.T₁))  # crowding-in grows or decays in 1st phase...
  @. m.C[m.T₁+2:end,:] .= @view m.C[m.T₁+1:m.T₁+1,:]             # then stops

  @. m.tmp = (1-p[:∂CE]) * (1-p[:f]) * (1-p[:e]) * (1-p[:v])
  @. m.δ[1         ,:] = one(S)
  @. m.δ[2:m.T₁+1  ,:] = m.tmp * p[:Lₘₐₓ]^(one(S)/m.T₁)
  @. m.δ[m.T₁+2:end,:] = m.tmp
  cumprod!(m.δ, m.δ; dims=1)

  @. m._y = m.y * (1+m.C)
  @. m.ỹ = m._y + m.z
  @. m.onemη = 1 - p[:η]
  @. m.u = m.δ * m.ỹ^m.onemη
  
  @. m.C = p[:ḅ]^(1+p[:η]) # * (1+p[:f])^75  # fixed scale factor

  if dogradient || dohessian
    @. m.ydivỹ = m._y / m.ỹ
    @. m.uy = m.u * m.C * m.ydivỹ
    sum!(m.CuSuy, m.uy)
    m.CuSuy ./= -m.M  # negate because optim() minimizes, not maximizes
    m.Suy .= Vector(m.CuSuy)

    !dogradient && (G = m._G)
    G .= m.Luy
    rev_cumsum!(m.Suy)
    G .-= m.x .* m.Luy  # ∂U/∂logit xₛ = ∂uₛ/∂yₛ × yₛ - xₛ × Σ_(t=s)^T ∂uₜ/∂yₜ × yₜ

    if dohessian
      m.uy2 .= Vector(dropdims(sum(@. m.uy * p[:η] * m.ydivỹ; dims=2); dims=2))  # formula is "× -η", so this is negated
      m.uy2 ./= m.M # double-negate because optim() minimizes, not maximizes, and because of missing "-" on p[:η] above
      Suy2 = m.uy2[end]
      @inbounds for s ∈ m.T-1:-1:1
        Suy2 += m.uy2[s]
        tₛ = m.x[s] * Suy2 - G[s] - m.uy2[s]
        for r ∈ 1:s-1
          H[s,r] = H[r,s] = m.x[r] * tₛ
        end
        H[s,s] = (S(1) - S(2) * m.x[s]) * (m.uy2[s] + G[s]) + m.x[s]^2 * Suy2
      end
    end
  end

 sum(sum(@. m.u - m.δ * m.z^m.onemη; dims=1) .* (m.C ./ m.onemη)) / -m.M
end

(m::SimModel{S})(x) where {S} = CUDA.@sync sim(m; x=S(x))  # make a simulation model work like a function that computes utility distribution for initial spending rate x₁

end
