
using SpendDown, Random, Optim, Statistics, StatsBase, BenchmarkTools, CairoMakie, LogExpFunctions, DataFrames, AxisKeys, LinearAlgebra, QuasiMonteCarlo, GlobalSensitivity

S = Float64  # numerical data type to work in 

uncertain_params = [:lnA₀,:η,:r,:∂CE,:g,:C₁,:f,:X,:v,:Lₘₐₓ,:δₗ,:c,:ϕ]
τ  = KeyedArray(Symmetric(
 [ 1  0  0   0  0   0  0  0   0  0  0  0  0
   0  1 -0.3 0  0  0.1 0 -0.5 0  0  0  0  0
   0  0  1   0  0 -0.1 0  0.3 0  0  0  0  0
   0  0  0   1  0  0   0  0   0  0  0  0  0
   0  0  0   0  1  0   0  0.2 0  0  0  0  0
   0  0  0   0  0  1   0 -0.1 0  0  0  0  0
   0  0  0   0  0  0   1  0   0  0  0  0  0
   0  0  0   0  0  0   0  1   0  0  0  0  0
   0  0  0   0  0  0   0  0   1  0  0  0  0
   0  0  0   0  0  0   0  0   0  1  0  0  0
   0  0  0   0  0  0   0  0   0  0  1  0  0
   0  0  0   0  0  0   0  0   0  0  0  1  0
   0  0  0   0  0  0   0  0   0  0  0  0  1]), 
  row = uncertain_params, col = uncertain_params)  # label the rows and cols

 # Ajeya AGI timeline
	timeline = [2020  0
              2025 .05
              2030 .19
              2035 .32
              2040 .44
              2045 .55
              2050 .64
              2055 .71
              2060 .77
              2065 .82
              2070 .86
              2100 .97]

params = (
  M        = 10,                                   # number of simulations
  lnA₀     = log(1000),                                     # initial $ assets (Aₜ = assets at end of period t)
  ẋ        = 1,                                      # reference level of GW giving
  ḅ        = 1,                                      # CE at that level
  calibrate_b₁ = false,
  η        = TwoPieceUniform([.25,.5,.99]),        # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
  simr     = false,                                     # simulate using S&P 500 history
  r        = TwoPieceUniform([.11, .061, .035]),# rate of return on assets
  ∂CE      = TwoPieceUniform([.025,.0475,.0725]),       # annual decline in cost effectiveness because world is getting better
  z₁       = 10,                                      # initial exogenous spending
  g        = TwoPieceUniform([0, .05, .1]),            # growth rate of exogenous spending
  C₁ = TwoPieceUniform([0, .5, 2]),             # initial crowd-in rate
  ∂C = .5,                                    # per-decade multiplier for crowd-in decay/growth (e.g., .5)
  d        = 0,                                     # pure time preference
  f        = TwoPieceUniform([0, .01, .03]), # flow-through rate
  δf      = .01,
  X        = .2,   # total risk of extinction through 2100
  e        = .002,    # annual risk of expropriation
  timeline,
  t₁ = 2025,
  v        = TwoPieceUniform([-.0035, .0035, .02]),   # annual loss from values drift
  c        = TwoPieceUniform([.1,.3,.6]),                                     # learning rate: elasticity of effectiveness to cumulative disbursement
  ϕ        = .1, #TwoPieceUniform([.1,.3,.6]),
  δₗ        = TwoPieceUniform([0,.05,.1]),                                  # annual knowledge depreciation rate      
  yhist    = [1.53775, 2.738676, 12.549013, 57.978152, 45.126544, 298.377962, 216.060149, 244.227109, 265.018214, 216.817577, 423.728273, 563.436754, 432.340644, 432.340644],
  Lₘₐₓ     = 1 #=TwoPieceUniform([3.5, 1.42, 1.15])=#,      # learning cap
  GPD = false,
  λ        = 1e6,
  σ = 1,
  μ = 2,
  T₁       = 10,                                       # initial learning period length
  T₂       = 40,                                       # spend-down period length
  τ        = τ  #=.4=#                              # Kendall correlation among uncertain parameters
)

m = SimModel{S}(Xoshiro(102398); params...)

x = fill(logit(S(.3)), m.T₁+m.T₂-1)
h = 1e-3
i=1; j=1
xi = copy(x); xi[i]+=h
xj = copy(x); xj[j]+=h
xij = copy(xi); xij[j]+=h
G = similar(x); Gh = similar(x)
H = Matrix{S}(undef,49,49)
sim(m, nothing, G, H, x), sum(G), sum(H)
(sim(m, nothing, nothing, nothing, xj)-sim(m, nothing, nothing, nothing, x))/h, G[j], (x₁=logistic(x[1]);  ϕ=m.ϕ; -2√(ϕ * x₁^ϕ *(1-x₁)) * (1-x₁*(1+1/ϕ)))
((sim(m, nothing, nothing, nothing, xij)-sim(m, nothing, nothing, nothing, xi))/h-(sim(m, nothing, nothing, nothing, xj)-sim(m, nothing, nothing, nothing, x))/h)/h, H[i,j], -√(x₁^ϕ*(1-x₁)/ϕ) * (ϕ*(1-x₁) * (ϕ*(1-x₁)-3x₁) - x₁*(ϕ*(1-x₁)+2-3x₁))
# @btime sim(m, nothing, G, H, x)

# start = fill(logit(.05), m.T₁+m.T₂-1)
# objective = (F, G, H, x) -> sim(m, F, G, H, x)  # function to be maximized, which provides gradient & Hessian too
# @profview o2 = Optim.optimize(Optim.only_fgh!(objective), start, NewtonTrustRegion(), #=Optim.Options(show_trace=true, extended_trace=true)=#)

∂U∂logitx₁= 2*((x₁^ϕ/ϕ)^-.5 * x₁^ϕ*(1-x₁)^1.5 - (x₁^ϕ/ϕ)^.5 * x₁*(1-x₁)^.5)
∂U∂logitx₁= 2*(                               - (x₁^ϕ/ϕ)^.5 * x₁*(1-x₁)^.5)
ϕ=m.ϕ;logitx₁=x[];x₁=logistic(logitx₁)
U(logitx₁, _logitx₁) = begin
    x₁,_x₁ = logistic.((logitx₁,_logitx₁))
    √(_x₁^ϕ/ϕ)*√(1-x₁)/.5/.5
end
h=1e-6
L₂ = x₁^ϕ/ϕ
y₁,y₂ = x₁,1-x₁
((U(logitx₁+2h,logitx₁) - U(logitx₁+h,logitx₁))/h-(U(logitx₁+h,logitx₁) - U(logitx₁,logitx₁))/h)/h, (1-2x₁)*∂U∂logitx₁ - √L₂*x₁^2*√(1-x₁)
((U(logitx₁+h,logitx₁+h) - U(logitx₁,logitx₁+h))/h-(U(logitx₁+h,logitx₁) - U(logitx₁,logitx₁))/h)/h, -√ϕ*x₁*(1-x₁)^1.5

function L(A₀,logitx,r,λ,δₗ,ϕ,t)
  x = logistic.(logitx)
  y = A₀ * cumprod([1; 1 .- x[1:t-1]]) .* x[1:t] .* (1+r).^(0:t-1)
  λ * sum(y[s] ^ ϕ / ϕ * (1-δₗ) .^ (t.-s) for s ∈ 1:t-1)
end

function ∂Lₜ∂logitxₛ(A₀,logitx,r,λ,δₗ,ϕ,t,s)
  x = logistic.(logitx)
  y = A₀ * cumprod([1; 1 .- x[1:t-1]]) .* x[1:t] .* (1+r) .^(0:t-1)
  s≥t ? 0 : λ * (1-δₗ)^t * (y[s]^ϕ/(1-δₗ)^s - x[s] * sum(y[r]^ϕ/(1-δₗ)^r for r ∈ s:t-1))
end

function ∂²Lₜ∂logitxₚ∂logitxₛ(A₀,logitx,r,λ,δₗ,ϕ,t,p,s) 
  x = logistic.(logitx)
  y = A₀ * cumprod([1; 1 .- x[1:t-1]]) .* x[1:t] .* (1+r) .^(0:t-1)
  -ϕ*x[p]*∂Lₜ∂logitxₛ(A₀,logitx,r,λ,δₗ,ϕ,t,s) +
    (p≠s ? 0 : (1-x[s])*(λ*(1-δₗ)^t*(ϕ-1)*y[s]^ϕ/(1-δₗ)^s + ∂Lₜ∂logitxₛ(A₀,logitx,r,λ,δₗ,ϕ,t,s)))
end

A₀,x,r,λ,δₗ,ϕ,t = 1000, logit.([.1,.1,.1,.1]), .07, 1.2, .1, .4, 4
L(A₀,x,r,λ,δₗ,ϕ,t)

i=2;j=3
h = 1e-5
xi = copy(x); xi[i]+=h
xj = copy(x); xj[j]+=h
xij = copy(xi); xij[j]+=h
(L(A₀,xi,r,λ,δₗ,ϕ,t) - L(A₀,x,r,λ,δₗ,ϕ,t))/h, ∂Lₜ∂logitxₛ(A₀,x,r,λ,δₗ,ϕ,t,i)

((L(A₀,xij,r,λ,δₗ,ϕ,t) - L(A₀,xj,r,λ,δₗ,ϕ,t))/h - (L(A₀,xi,r,λ,δₗ,ϕ,t) - L(A₀,x,r,λ,δₗ,ϕ,t))/h)/h, ∂²Lₜ∂logitxₚ∂logitxₛ(A₀,x,r,λ,δₗ,ϕ,t,i,j)