# Attempt to run the model on Apple GPUs. The Metal.jl package (to support Apple GPUs) is "experimental." The code below is crashing. :shrug:

module SpendDown
export SimModel, sim, TwoPieceUniform, utility

using Distributions, Statistics, Copulas, LinearAlgebra, DataFrames

if Sys.iswindows()
  using CUDA
  const GPUlib = CUDA
  const GPUArray = CuArray
  const GPUMatrix = CuMatrix
  const GPUVector = CuVector
else
  using Metal
  const GPUlib = Metal
  const GPUArray = MtlArray
  const GPUMatrix = MtlMatrix
  const GPUVector = MtlVector
end

const sims_t = Int32
const years_t = Int16

# asset & spending curves for all simulations, t=1,...
@kwdef struct Scenario{V,S}
  M       ::sims_t = zero(sims_t)     # number of simulations
  T       ::years_t  = zero(years_t)  # length of scenario (in years)
  zero2tm1::V = V(0:T-1)
  A       ::S = S(undef,T,M)  # $ assets at *start* of each period
  y       ::S = S(undef,T,M)  # $ spending
  z       ::S = S(undef,T,M)  # $ exogenous spending
  C ::S = S(undef,T,M)  # crowd-in rate
end
Base.show(io::IO, s::Scenario) = print(io, DataFrame("Assets (A)"=>s.A, raw"Spending $ (y)"=>s.y, "Spending % (x)"=>s.y./s.A*100, raw"Exog spend $ (z)"=>s.z, raw"C"=>s.C))

# composite scenario--with potentially multiple phases. Each phase holds partial views onto vectors representing full scenario.
struct CompositeScenario{S}
  parent::Scenario{GPUVector{S},GPUMatrix{S}}  # holds entire timeline
  n::years_t                     # number of phases
  M::sims_t                      # number of simulations
  phases::Vector{Scenario}  # phases based on views onto parent scenario

  function CompositeScenario{S}(M, args...) where S  # constructor; args should be # of sims, then episode lengths
    T = sum(args)
    s = Scenario{GPUVector{S},GPUMatrix{S}}(;M,T)  # parent scenario holding full history
    @views new{S}(s, years_t(length(args)), sims_t(M), [Scenario{GPUVector{S},typeof(s.A[1:1,:])}(M=sims_t(M), T=years_t(length(I)), A=s.A[I,:], y=s.y[I,:], z=s.z[I,:], C=s.C[I,:])
                                          for I ∈ Iterators.accumulate((I,i) -> last(I).+(1:i), args, init=0:0)])
  end
end

# utility of a single phase
utility(s::Scenario; η, δ) = sum(@. δ^s.zero2tm1 * ((s.y * (1+s.C) + s.z)^(1-η) - s.z^(1-η)); dims=1) ./ (1 .- η)

# utility of scenario with multiple phases, allowing different discount rates in each
function utility(cs::CompositeScenario{S}; η, ḅ, ẋ, f, δ) where {S}
  U = GPUlib.fill(zero(S), 1, cs.M)
  δc = GPUlib.fill(one(S), 1, cs.M)  # cumulative discount
  @inbounds for i ∈ 1:cs.n
    δᵢ, pᵢ = view(δ,i:i,:), cs.phases[i]
    U .+= utility(pᵢ; η, δ=δᵢ) .* δc
    @. δc *= δᵢ^S(pᵢ.T)
  end
  @. U * ḅ * ẋ^η * (one(S)+f)^S(75)
end


# Spending stragies:
#   Functions that take a Scenario as first arg, which will be written into, and parameters as keyword args
#   Any unneeded parameters passed are ignored

# fixed-rate spending path for inital assets A₀, asset return rate r, spending rate x
function fixed_rate!(s::Scenario; A₀, r, x, kwargs...)
  @. s.A[1:s.T,:] = A₀ * ((1 - x) * (1 + r)) ^ s.zero2tm1
  @. s.y = s.A * x
end

# Exact optimal spending path NOT quite according to the spec https://docs.google.com/document/d/136494mE4MrxbbinCU9RliaJ2tkLjFuvsg6c1p2Mt1RI/edit
# The spec inclues an approximation. Under the exact solution computations are more parallelizable over time
function optimal_finite_hor!(s::Scenario; A₀, r, Δ, η, kwargs...)
  rp1 = @. 1+r
  ρ   = @. ((1-Δ)*rp1)^(1/η)
  _ρ  = @. ρ / rp1
  _ρ̂T =    _ρ.^eltype(r)(s.T)
  @. s.y = A₀ * (1 - _ρ) / (1 - _ρ̂T) * ρ^s.zero2tm1
  @. s.A = rp1 ^ s.zero2tm1 * (ρ^s.zero2tm1 - _ρ̂T) / (1 - _ρ̂T)
end

# 2-stage scenario: fixed-rate, then optimized, finite-horizon. Δ₂ is the discount rate for *2nd* phase
function two_part_spend!(cs::CompositeScenario; A₀, r, Δ₂, η, x₁, kwargs...)
  fixed_rate!(cs.phases[1]; A₀, r, x=x₁)
  optimal_finite_hor!(cs.phases[2]; r, Δ=Δ₂, η, A₀= @. @views (cs.phases[1].A[end:end,:] - cs.phases[1].y[end:end,:]) * (1 + r))
  cs
end

struct PiecewiseUniform{T<:Real} <: ContinuousUnivariateDistribution
  x::Vector{T}; Fx::Vector{T}  # not used
  iter::Base.Iterators.Zip{Tuple{Vector{T}, Vector{T}, Vector{T}}}  # holds x[2:end] and corresponding percentiles and densities

  function PiecewiseUniform{T}(x, Fx) where {T<:Real}  # constructor
    length(x)==length(Fx) || throw(ArgumentError("`x` and `Fx` must have the same length."))
    issorted(Fx)          || throw(ArgumentError("`Fx` must be sorted."))
    iszero(Fx[1])         || throw(ArgumentError("The first value for `Fx` must be 0."))
    isone(Fx[end])        || throw(ArgumentError("The last value for `Fx` must be 1."))

    return new{T}(x, Fx, zip(x[2:end], Fx[2:end], (Fx[2:end] - Fx[1:end-1]) ./ (x[2:end] - x[1:end-1])))
  end
end
PiecewiseUniform(x::Vector{T}, Fx::Vector{T}) where {T<:Real} = PiecewiseUniform{T}(x,Fx)

# quantile function for this distribution--given p ∈ [0,1], return quantile
# all that's needed for rand() to work with the distribution
function Statistics.quantile(d::PiecewiseUniform, q::Real)
  for (x,Fx,density) ∈ d.iter
    q ≤ Fx && return x - (Fx - q) / density
  end
end

TwoPieceUniform(x) = PiecewiseUniform(x, eltype(x)[0, .5, 1])

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
  T₁      ::years_t     # initial learning period (e.g., 10 years)
  T₂      ::years_t     # spend-down deadline (e.g., 40 years)
  τ       ::S         # Kendall correlation among uncertain parameters
  M       ::sims_t     # number of simulations

  # internal
  T               ::years_t  = T₁ + T₂
  uncertain_params::Vector{Pair{Symbol,<:UnivariateDistribution}}  # alternate-format storage of above parameters, allowing more model-agnostic code
    certain_params::Vector{Pair{Symbol,S}}
  params          ::Dict{Symbol, Union{S,GPUMatrix{S}}}  # instances of all params, certain and uncertain, over all simulations, as Dict of scalars & 1xM arrays
  V               ::GPUMatrix{S}                                      # ~9xM matrix of parameter draws
  cs              ::CompositeScenario{S} = CompositeScenario{S}(M,T₁,T₂)  # spending & asset paths for each CPU thread
  dist            ::GPUMatrix{S} = GPUMatrix{S}(undef,1,M)  # holder for simulated distribution of utility
end

# constructor
function SimModel{S}(rng; M, T₁, T₂, τ, kwargs...) where {S}
  uncertain_params = [first(p)=>  last(p)  for p ∈ kwargs if   last(p) isa UnivariateDistribution ]  # "first(p)=>  last(p)" logically same as p, but more type-stable
    certain_params = [first(p)=>S(last(p)) for p ∈ kwargs if !(last(p) isa UnivariateDistribution)]
            params = Dict{Symbol, Union{S,GPUMatrix{S}}}(certain_params...)
  
  l = length(uncertain_params)
  Σ = fill(sinpi(S(τ)/2),l,l)  # Convert Kendall's τ to regular correlation https://math.stackexchange.com/questions/3058888/kendalls-tau-of-bivariate-normal
  Σ[diagind(Σ)] .= 1
  V = rand(rng, SklarDist(GaussianCopula(Σ), Tuple(last.(uncertain_params))), M)

  @inbounds for (i,u) ∈ enumerate(uncertain_params)
    params[first(u)] = GPUArray(@view V[i:i,:])
  end

  SimModel{S}(; rng, M, T₁, T₂, T=T₁+T₂, τ=S(τ), kwargs..., V, uncertain_params, certain_params, params)
end

function sim(m::SimModel{S}; x₁) where {S}
  _z       = m.cs.parent.z
  _C = m.cs.parent.C
  p = m.params

  @. _z[1:m.T, :] = p[:z₁] * (1 + p[:g]) ^ S(0:m.T-1)  # exogenous spending grows at rate g

  @. _C[1:m.T₁+1,:] = p[:C₁] * p[:∂C] ^ ((0:m.T₁)/S(m.T₁))  # crowding-in grows or decays in 1st phase...
  @. _C[m.T₁+2:end,:] .= @view _C[m.T₁+1:m.T₁+1,:]             # then stops

  _δ = @. (1-p[:∂CE]) * (1-p[:f]) * (1-p[:e]) * (1-p[:v])
  δ = GPUMatrix{S}(undef,2,m.M)  # holder for discount rates in each phase
  δ[1,:] = @. _δ * p[:Lₘₐₓ]^(one(S)/m.T₁)  # discount includes learning in first phase
  δ[2,:] =    _δ

  two_part_spend!(m.cs; A₀=p[:A₀], r=p[:r], Δ₂=(@. 1-_δ+1-(1+p[:g])^-p[:η]), η=p[:η], x₁)  # compute spending path
  m.dist .= utility(m.cs; ḅ=p[:ḅ], ẋ=p[:ẋ], η=p[:η], f=p[:f], δ)                                    # return utility thereof
end

(m::SimModel{S})(x₁) where {S} = sim(m; x₁=S(x₁))  # make a simulation model work like a function that computes utility distribution for initial spending rate x₁

end # module

using .SpendDown, Random, Optim, Statistics, BenchmarkTools, CairoMakie
try using CUDA catch _ end
try using Metal catch _ end

S = Float32
  m = SimModel{S}( Xoshiro(102398);                                    # random number generator
                   M        = 10_000,                                  # number of simulations
                   A₀       = 5000,                                    # initial $ assets
                   ẋ       = 300,                                      # initial GW cost effectiveness
                   ḅ        = 300,                                     # initial GW giving
                   η        = TwoPieceUniform(S[.15, .37, .99]),       # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
                   r        = TwoPieceUniform(S[.11, .061, .035]),     # rate of return on assets
                   ∂CE      = TwoPieceUniform(S[.025, .04, .06]),      # annual decline in cost effectiveness because world is getting better
                   z₁       = 280,                                     # initial exogenous spending
                   g        = TwoPieceUniform(S[0, .1, .2]),           # growth rate of exogenous spending
                   C₁ = TwoPieceUniform(S[0, .5, 2]),            # initial crowd-in rate
                   ∂C = .5,                                      # per-decade multiplier for crowd-in decay/growth (e.g., .5)
                   f        = TwoPieceUniform(S[0, .01, .03]),         # flow-through rate
                   e        = TwoPieceUniform(S[.0015, .0030, .017]),  # annual risk of extinction, expropriation, etc.
                   v        = TwoPieceUniform(S[-.0035, .0035, .02]),  # annual loss from values drift
                   Lₘₐₓ     = TwoPieceUniform(S[3.5, 1.42, 1.15]),     # learning cap
                   T₁       = 10,                                      # initial learning period length
                   T₂       = 40,                                      # spend-down period length
                   τ        = S(.4))                                   # Kendall correlation among uncertain parameters

m(.03f0)

# @btime CUDA.@sync mean.(m.([2,3,4,5,6,7,8,9,11,13,15]/100))  # EVs for scenarios with the indicated % spending rates in 1st 10 years
#=CUDA.@profile=# @time mean.(m.([2,3,4,5,6,7,8,9,11,13,15]/100))  # EVs for scenarios with the indicated % spending rates in 1st 10 years

# @benchmark m(.03)
@btime o = Optim.minimizer(Optim.optimize(x₁->-sum(m(x₁)), S(0), S(1), GoldenSection()))
# mean(m(o))
# m(o)
# f = Figure()
# Axis(f[1,1])
# for t ∈ 1:m.nt
#   lines!(1:49, m.cs[t].parent.y)
# end
# f |> display

# xplot = exp.(range(log(.0001),log(.2),100))
# lines(xplot, mean.(m.(xplot)))
