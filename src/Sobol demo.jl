# this script demonstrates analysis of variance in the model using Sobol indices
# variance is analyzed only for parameters represented as uncertain

using SpendDown, Markdown, Random, Optim, LogExpFunctions, AxisKeys, QuasiMonteCarlo, GlobalSensitivity, LinearAlgebra, Distributions

S = Float32

uncertain_params = [:lnA₀, :η, :r, :∂CE, :g, :C₁, :f, :X, :v, :Lₘₐₓ, :δₗ, :c]
τ  = KeyedArray(Symmetric(
 [ 1  0  0   0  0  0   0  0   0  0  0  0
   0  1 -0.3 0  0  0.1 0 -0.5 0  0  0  0
   0  0  1   0  0 -0.1 0  0.3 0  0  0  0
   0  0  0   1  0  0   0  0   0  0  0  0
   0  0  0   0  1  0   0  0.2 0  0  0  0
   0  0  0   0  0  1   0 -0.1 0  0  0  0
   0  0  0   0  0  0   1  0   0  0  0  0
   0  0  0   0  0  0   0  1   0  0  0  0
   0  0  0   0  0  0   0  0   1  0  0  0
   0  0  0   0  0  0   0  0   0  1  0  0
   0  0  0   0  0  0   0  0   0  0  1  0
   0  0  0   0  0  0   0  0   0  0  0  1 ]), 
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

params = (rng = Xoshiro(102398),                                     # random number generator
            M        = 10_000,                                   # number of simulations
            lnA₀     = log(1000),                                     # initial $ assets (Aₜ = assets at end of period t)
            ẋ        = 1,                                      # reference level of GW giving
            ḅ        = 1,                                      # CE at that level
            calibrate_b₁ = false,
            η        = TwoPieceUniform([.25,.5,.99]),        # "inverse elasticity of intertemporal substitution"--0=linear utility, 1=log utility
            simr     = true,                                     # simulate using S&P 500 history
            r        = TwoPieceUniform([.11, .061, .035]),     # rate of return on assets
            ∂CE      = TwoPieceUniform([.025,.0475,.0725]),       # annual decline in cost effectiveness because world is getting better
            z₁       = 10,                                      # initial exogenous spending
            g        = TwoPieceUniform([0, .05, .1]),            # growth rate of exogenous spending
            C₁ = TwoPieceUniform([0, .5, 2]),             # initial crowd-in rate
            ∂C = .5,                                    # per-decade multiplier for crowd-in decay/growth (e.g., .5)
            d        = 0,                                     # pure time preference
            f        = TwoPieceUniform([0, .01, .03]), # flow-through rate
            δf      = .01,
            timeline,
            t₁       = 2025,
            X        = TwoPieceUniform([.01,.06,.1666]),   # risk of extinction/end of scarcity, by 2100
            e        = .002,    # annual risk of expropriation
            v        = TwoPieceUniform([-.0035, .0035, .02]),   # annual loss from values drift
            c        = TwoPieceUniform([.1,.3,.6]),                                     # learning rate: elasticity of effectiveness to cumulative disbursement
            λ        = 1e6,
            σ = .5,
            μ = 2,
            GPD = false,
            δₗ        = TwoPieceUniform([0,.05,.1]),                                  # annual knowledge depreciation rate
            ϕ        = 1,
            yhist    = [1.53775, 2.738676, 12.549013, 57.978152, 45.126544, 298.377962, 216.060149, 244.227109, 265.018214, 216.817577, 423.728273, 563.436754, 432.340644, 432.340644],
            Lₘₐₓ     = 1 #=TwoPieceUniform([3.5, 1.42, 1.15])=#,      # learning cap
            T₁       = 10,                                       # initial learning period length
            T₂       = 40,                                       # spend-down period length
            τ        = τ  #=(.4)=#                              # Kendall correlation among uncertain parameters
)

uncertain_params = [key for (key,value) ∈ zip(keys(params), params) if value isa UnivariateDistribution]
l = length(uncertain_params)

# given a vector draws in [0,1] for the uncertain parameters, map those to their distributions and compute optimal year-1 spending rate (%)
function optimal_first_year_spending(seq)
  m = SimModel{S}([seq;;]; params...)  # "[seq;;]" converts vector to 1-col matrix

  start = fill(logit(.05), m.T₁+m.T₂-1)
  objective = (F, G, H, x) -> sim(m, F, G, H, x)  # function to be maximized, which provides gradient & Hessian too
  o = Optim.optimize(Optim.only_fgh!(objective), start, NewtonTrustRegion(), #=Optim.Options(show_trace=true, extended_trace=true)=#)
  
  return logistic(Optim.minimizer(o)[1])
end

Nsamples = 500  # number of points in l-dimensional space to sample for numerical integration
samples = QuasiMonteCarlo.generate_design_matrices(Nsamples, zeros(S,l), ones(S,l), QuasiMonteCarlo.SobolSample(R=Shift(params[:rng])))
sobol_result = gsa(optimal_first_year_spending, Sobol(; order=[0,1,2]), samples...)  # dropping 2 saves time if 2nd-order not needed

display(md"[Total-effect indices](https://en.wikipedia.org/wiki/Variance-based_sensitivity_analysis#Total-effect_index)")
display(KeyedArray(sobol_result.ST, col=uncertain_params))
display(md"[First-order indices](https://en.wikipedia.org/wiki/Variance-based_sensitivity_analysis#First-order_indices)")
display(KeyedArray(sobol_result.S1, col=uncertain_params))
display(md"Second-order indices")
display(KeyedArray(sobol_result.S2, row=uncertain_params, col=uncertain_params))
