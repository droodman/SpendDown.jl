pushfirst!(LOAD_PATH, ".")

#-----
# version 2 model
#-----

using SpendDown, Random, Optim, Statistics, StatsBase, BenchmarkTools, CairoMakie, LogExpFunctions, DataFrames, AxisKeys, LinearAlgebra

f = Figure(size=(1000,1000))
a1 = Axis(f[3,1], ylabel="spending (billion \$)", xticks=0:10:50, xminorgridvisible=true, xminorticks=(IntervalsBetween(10)),
                  yminorgridvisible=true, yminorticks=(IntervalsBetween(10)),
                  limits=((0.1,50),nothing))
a2 = Axis(f[2,1], ylabel="assets (billion \$)", yticks=0:10:80, yminorgridvisible=true, yminorticks=(IntervalsBetween(10)),
                  xticks=0:10:50, xminorgridvisible=true, xminorticks=(IntervalsBetween(10)),
                  limits=((0,50),nothing))
a3 = Axis(f[1,1], ylabel="spending %", xticks=0:10:50, xminorgridvisible=true, xminorticks=(IntervalsBetween(10)),
                    yticks=(0:.1:1,string.(0:10:100).*"%"), yminorgridvisible=true, yminorticks=(IntervalsBetween(10)),
                    limits=((0.01,50),(0,1)), title="Optimal spending rate path by median asset return rate")
@time begin
df = DataFrame(rate=[], EV=[])

S = Float32  # numerical data type to work in 

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

 # AGI timeline
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

# spending prehistory
yhist = [1.53775
         2.738676
         12.549013
         57.978152
         45.126544
         298.377962
         216.060149
         244.227109
         265.018214
         216.817577
         423.728273
         563.436754
         432.340644
         341.2204228]

start = fill(logit(S(.2)), 49)

for s ∈ .25:.1:1.25
  params = (
        QMC = false,                                          # quasi-Monte Carlo vs pseudo-random draws for uncertain params
        M        = 10_000,                                   # number of simulations
        lnA₀     = log(1000),                                     # initial $ assets (Aₜ = assets at end of period t)
        ẋ        = 300,                                      # reference level of GW giving
        ḅ        = 300,                                      # CE at that level
        calibrate_b₁ = false,
        η        = TwoPieceUniform([.25,.5,.99]),        # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
        simr     = true,                                     # simulate using S&P 500 history
        r        = s * TwoPieceUniform([.11, .061, .035]),# rate of return on assets
        r_geo    = false,                                    # interpret r as geometric mean (true) vs arithmetic mean (false)
        r_sd     = 2,                                        # standard deviation of return on assets (ignored if simr=false)
        ∂CE      = TwoPieceUniform([.025,.0475,.0725]),       # annual decline in cost effectiveness because world is getting better
        z₁       = 10,                                      # initial exogenous spending
        g        = TwoPieceUniform([0, .05, .1]),            # growth rate of exogenous spending
        C₁       = TwoPieceUniform([0, .5, 2]),             # initial crowd-in rate
        ∂C       = .5,                                    # per-decade multiplier for crowd-in decay/growth
        d        = 0,                                     # pure time preference
        f        = TwoPieceUniform([0, .01, .03]), # flow-through rate
        δf      = .01,                            # flow-through decay rate
        timeline,
        t₁       = 2025,                           # simulation start date in calendar time
        X        = TwoPieceUniform([.01,.06,.1666]),   # risk of extinction/end of scarcity, by 2100
        e        = .002,    # annual risk of expropriation
        v        = TwoPieceUniform([-.0035, .0035, .02]),   # annual loss from values drift
        c        = TwoPieceUniform([.1,.3,.6]),                                     # learning rate: elasticity of effectiveness to cumulative disbursement
        δₗ        = TwoPieceUniform([0,.05,.1]),                                  # annual knowledge depreciation rate      
        yhist,
        Lₘₐₓ     = TwoPieceUniform([3.5, 1.42, 1.15]),      # learning cap
        λ        = 1,
        ϕ        = .5,
        σ        = .5,
        μ        = 2,
        GPD      = false,
        T₁       = 10,   # initial learning period length
        T₂       = 40,   # spend-down period length
        τ        #=.4=#  # Kendall correlation among uncertain parameters
    )

  m = SimModel{S}(Xoshiro(102398); params...)  # first argument is a random number generator with an arbitrarily chosen seed

  objective(F, G, H, x) = sim(m, F, G, H, x)  # function to be maximized, which provides gradient & Hessian too
  @time o = Optim.optimize(Optim.only_fgh!(objective), start, NewtonTrustRegion(), #=Optim.Options(show_trace=true, extended_trace=true)=#)

  rmed = median(params.r)
  A₀med = exp(median(params.lnA₀))

  push!(df, Dict(:rate => rmed, :EV => -Optim.minimum(o)))

  start = Optim.minimizer(o)  # starting point for next fit
  x = [logistic.(Optim.minimizer(o)); 1]  # add spending 100% at end
  A = [A₀med/1000; Base.accumulate( (Aₜ,xₜ) -> Aₜ*(1-xₜ)*(1+rmed), x, init=A₀med/1000)]
  lines!(f[3,1], 1:length(x), x.*A[1:end-1], color=s, colorrange=(.25,1.25), linewidth=2, label=string(round(rmed*100, digits=1))*"%")
  lines!(f[2,1], 1:length(A), A, color=s, colorrange=(.25,1.25), linewidth=2)
  x = x[1:findfirst(>(.98),x)]
  lines!(f[1,1], 1:length(x), x, color=s, colorrange=(.25,1.25), linewidth=2)
end

axislegend(a1, position=:lt, framevisible = false)
f |> display
df
end

params = (
  QMC = false,                                          # quasi-Monte Carlo vs pseudo-random draws for uncertain params
  M        = 10_000,                                   # number of simulations
  lnA₀     = log(1000),                                     # initial $ assets (Aₜ = assets at end of period t)
  ẋ        = 300,                                      # reference level of GW giving
  ḅ        = 300,                                      # CE at that level
  calibrate_b₁ = false,
  η        = TwoPieceUniform([.25,.5,.99]),        # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
  simr     = true,                                     # simulate using S&P 500 history
  r        = TwoPieceUniform([.11, .061, .035]),# rate of return on assets
  ∂CE      = TwoPieceUniform([.025,.0475,.0725]),       # annual decline in cost effectiveness because world is getting better
  z₁       = 10,                                      # initial exogenous spending
  g        = TwoPieceUniform([0, .05, .1]),            # growth rate of exogenous spending
  C₁       = TwoPieceUniform([0, .5, 2]),             # initial crowd-in rate
  ∂C       = .5,                                    # per-decade multiplier for crowd-in decay/growth
  d        = 0,                                     # pure time preference
  f        = TwoPieceUniform([0, .01, .03]), # flow-through rate
  δf      = .01,                            # flow-through decay rate
  timeline,
  t₁       = 2025,                           # simulation start date in calendar time
  X        = TwoPieceUniform([.01,.06,.1666]),   # risk of extinction/end of scarcity, by 2100
  e        = .002,    # annual risk of expropriation
  v        = TwoPieceUniform([-.0035, .0035, .02]),   # annual loss from values drift
  c        = TwoPieceUniform([.1,.3,.6]),                                     # learning rate: elasticity of effectiveness to cumulative disbursement
  δₗ        = TwoPieceUniform([0,.05,.1]),                                  # annual knowledge depreciation rate      
  yhist,
  Lₘₐₓ     = TwoPieceUniform([3.5, 1.42, 1.15]),      # learning cap
  λ        = 1,
  ϕ        = .5,
  σ        = .5,
  μ        = 2,
  GPD      = false,
  T₁       = 10,   # initial learning period length
  T₂       = 40,   # spend-down period length
  τ        #=.4=#  # Kendall correlation among uncertain parameters
)

m = SimModel{S}(Xoshiro(102398); params...)  # first argument is a random number generator with an arbitrarily chosen seed

objective(F, G, H, x) = sim(m, F, G, H, x)  # function to be maximized, which provides gradient & Hessian too
o = Optim.optimize(Optim.only_fgh!(objective), start, NewtonTrustRegion(), #=Optim.Options(show_trace=true, extended_trace=true)=#)


#-----
# "replication" of version 1 model
#-----

# To install packages below, run julia from terminal, hit "]", then type "add [package name list]"
using Random, Optim, Statistics, StatsBase, BenchmarkTools, CairoMakie, AxisKeys, LinearAlgebra
using SpendDown

S = Float32  # numerical data type to work in 

uncertain_params = [:A₀, :r, :∂CE, :XX, :v, :Lₘₐₓ, :e, :η, :C₁, :f, :z₁, :g]
τ  = KeyedArray(Symmetric(
    S[ 1  0  0   0  0  0   0   0   0   0  0   0
       0  1 -0.3 0  0  0   0.1 0  -0.5 0  0  -0.5
       0  0  1   0  0  0  -0.1 0   0.3 0  0   0.3
       0  0  0   1  0  0   0   0   0   0  0   0
       0  0  0   0  1  0   0   0   0   0  0   0
       0  0  0   0  0  1   0   0   0.2 0  0   0
       0  0  0   0  0  0   1   0  -0.1 0  0  -0.1
       0  0  0   0  0  0   0   1   0   0  0   0
       0  0  0   0  0  0   0   0   1   0  0   0.65
       0  0  0   0  0  0   0   0   0   1  0   0
       0  0  0   0  0  0   0   0   0   0  1   0
       0  0  0   0  0  0   0   0   0   0  0   1 ]), 
    row = uncertain_params, col = uncertain_params)  # label the rows and cols

m = SimModelOld{S}(
      Xoshiro(102398);                                    # random number generator
      M        = 10_000,                                  # number of simulations
      A₀       = 5000,                                    # initial $ assets (Aₜ = assets at end of period t)
      ẋ        = 300,                                     # reference level of GW giving
      ḅ        = 300,                                     # CE at that level
      η        = TwoPieceUniform(S[.15, .37, .99]),       # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
      r        = TwoPieceUniform(S[.11, .061, .035]),     # rate of return on assets
      ∂CE      = TwoPieceUniform(S[.025, .04, .06]),      # annual decline in cost effectiveness because world is getting better
      z₁       = 280,                                     # initial exogenous spending
      g        = TwoPieceUniform(S[0, .1, .2]),           # growth rate of exogenous spending
      C₁       = TwoPieceUniform(S[0, .5, 2]),            # initial crowd-in rate
      ∂C       = S(.5),                                   # per-decade multiplier for crowd-in decay/growth (e.g., .5)
      f        = TwoPieceUniform(S[0, .01, .03]),         # flow-through rate
      e        = TwoPieceUniform(S[.0015, .0030, .017]),  # annual risk of extinction, expropriation, etc.
      v        = TwoPieceUniform(S[-.0035, .0035, .02]),  # annual loss from values drift
      Lₘₐₓ     = TwoPieceUniform(S[3.5, 1.42, 1.15]),     # learning cap
      T₁       = 10,                                      # initial learning period length
      T₂       = 40,                                      # spend-down period length
      τ        = τ  # S(0.4)                              # Kendall correlation(s)
);

x = S[2,3,4,5,6,7,8,9,11,13,15]  # trial spending rates, in %
@btime [x mean.(m.(x/100))]  # EVs for scenarios with the indicated % spending rates in 1st 10 years

m(.03)
@time o = Optim.minimizer(Optim.optimize(x₁ -> -sum(m(x₁)), S(0), S(1), GoldenSection()))
mean(m(o))
m(o)

xplot = exp.(range(log(.0001),log(.2),100))
lines(xplot, mean.(m.(xplot)))

# -----
# stack of density plots 
rates = [2,3,4,5,6,7,8,9,11,13,15]

dists = Vector{Vector}(undef, length(rates))
@time @inbounds for (i,r) ∈ enumerate(rates)
  CUDA.@sync dists[i] = vec(m(r/100))
end
display(DataFrame("Rate"=>rates, "EV"=>mean.(dists)))  # EVs for scenarios with the indicated % spending rates in 1st 10 years

f = Figure(size=(750,750))
Axis(f[1, 1], xlabel="utility", ylabel="Initial spending rate", yticks=(rates*2e-7,  string.(rates).*"%"))
for i ∈ 1:length(dists)
  d = collect(vec(dists[i]))
  density!(d[d .< percentile(d,90)], offset=rates[i]*2e-7,
              color=(:slategray, .4))
end
lines!(mean.(dists), rates*2e-7, linestyle=:dash, label="mean")
lines!(median.(dists), rates*2e-7, linestyle=:dash, label="median")
axislegend(position=:rt, framevisible = false)
f |> display


#-----
# early iteration of version 2 model, using NVIDIA GPU (CUDA)
#-----

using .SpendDownCUDA, Random, Optim, Statistics, StatsBase, BenchmarkTools, CairoMakie, LogExpFunctions, DataFrames

f = Figure(size=(1000,1000))
a1 = Axis(f[3,1], ylabel="spending (billion \$)", xticks=0:10:50, xminorgridvisible=true, xminorticks=(IntervalsBetween(10)),
                  yminorgridvisible=true, yminorticks=(IntervalsBetween(10)),
                  limits=((0,50),nothing))
a2 = Axis(f[2,1], ylabel="assets (billion \$)", yticks=0:10:80, yminorgridvisible=true, yminorticks=(IntervalsBetween(10)),
                  xticks=0:10:50, xminorgridvisible=true, xminorticks=(IntervalsBetween(10)),
                  limits=((0,50),nothing))
a3 = Axis(f[1,1], ylabel="spending %", xticks=0:10:50, xminorgridvisible=true, xminorticks=(IntervalsBetween(10)),
                    yticks=(0:.1:1,string.(100*(0:.1:1)).*"%"), yminorgridvisible=true, yminorticks=(IntervalsBetween(10)),
                    limits=((0,50),(0,1)), title="Optimal spending rate path by median asset return rate")

@time for s ∈ .25:.1:1.25
  m = SimModel{Float64}(
        Xoshiro(102398);                                    # random number generator
        M        = 10_000,                                  # number of simulations
        A₀       = 5000,                                    # initial $ assets (Aₜ = assets at end of period t)
        ẋ        = 300,                                     # reference level of GW giving
        ḅ        = 300,                                     # CE at that level
        η        = TwoPieceUniform([.15, .37, .99]),        # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
        r        = 1. .+ s * TwoPieceUniform([.11, .061, .035]),  # rate of return on assets
        ∂CE      = TwoPieceUniform([.025, .04, .06]),       # annual decline in cost effectiveness because world is getting better
        z₁       = 280,                                     # initial exogenous spending
        g        = TwoPieceUniform([1, 1.1, 1.2]),          # growth rate of exogenous spending
        C₁ = TwoPieceUniform([0, .5, 2]),             # initial crowd-in rate
        ∂C = .5,                                      # per-decade multiplier for crowd-in decay/growth (e.g., .5)
        f        = TwoPieceUniform([0, .01, .03]),          # flow-through rate
        e        = TwoPieceUniform([.0015, .0030, .017]),   # annual risk of extinction, expropriation, etc.
        v        = TwoPieceUniform([-.0035, .0035, .02]),   # annual loss from values drift
        Lₘₐₓ     = TwoPieceUniform([3.5, 1.42, 1.15]),      # learning cap
        T₁       = 10,                                      # initial learning period length
        T₂       = 40,                                      # spend-down period length
        τ        = τ  # .4                                  # Kendall correlation among uncertain parameters
  );

  start = fill(logit(.03), m.T₁+m.T₂-1)
  o = Optim.optimize(Optim.only_fgh!((F, G, H, x) -> sim(m, F, G, H, x)), start, NewtonTrustRegion())

  rmed = median(m.r) - 1

  x = [logistic.(Optim.minimizer(o));1]  # add spending 100% at end
  A = [m.A₀/1000; collect(Iterators.accumulate( (Aₜ,xₜ) -> Aₜ*(1-xₜ)*(1+rmed), x, init=m.A₀/1000))]
  lines!(f[3,1], 1:length(x), x.*A[1:end-1], color=s, colorrange=(.25,1.25), linewidth=2, label=string(round(rmed*100, digits=1))*"%")
  lines!(f[2,1], 1:length(A), A, color=s, colorrange=(.25,1.25), linewidth=2)
  x = x[1:findfirst(>(.999),x)]
  lines!(f[1,1], 1:length(x), x, color=s, colorrange=(.25,1.25), linewidth=2)
end

axislegend(a1, position=:lt, framevisible = false)
f |> display
df
