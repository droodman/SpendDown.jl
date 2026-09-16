# Spenddown modeling
 
This code file implements two versions of the spenddown model. Version 1 has not been made public. Version 2 makes major changes, including unconstrained optimization over spending paths, learning by doing, simulation of market returns, and a revamped handling of flow-through.

`src/PriorDistributions.jl` defines the `PieceWiseUniform` and `Bitriangular` distributions. src/SpendDownv1.jl implements version 1 of the model. src/SpendDown.jl does version 2.

`src/examples.jl` runs some models and generate plots.

`src/SpendDownJuliaCUDA.jl` is an alternative implementation that requries an NVIDIA CPU, and so doesn't work on the Mac. On a PC, it is ~2X faster than the CPU implementation. It was written before the addition of several features, including learning-by-doing and simulation of market returns.

`src/SpendDownJuliaMetal.jl` is an attempted, contemporaneous implementation on Apple GPUs, but it ran aground on the immaturity of Metal support in Julia (as of summer 2024).

`src/frontend.jl` is the Pluto notebook.

`src/Sobol demo.jl` demonstrates sensitivity analysis using Sobol indices.


## Installation
This is a Julia package, so you need Julia.

As of September 2026, underlying packages are not loading properly in Julia 1.13, which was just released. So use Julia 1.12:
1. Follow the [installation instructions for Julia](https://julialang.org/downloads).
2. In a command shell, type `juliaup add 1.12`.
3. Start Julia 1.12 with `julia +1.12`. Or configure the Julia extension in VS Code to point to a 1.12.x installation.
4. In Julia, install this package with `using Pkg; Pkg.add(url="https://github.com/droodman/SpendDown.jl")`.

If you want to use the model through the Pluto front end (recommended):
1. In Julia 1.12, do
```
using Pkg; Pkg.add("Pluto")
using Pluto; Pluto.run()
```
2. The Pluto home screen should appear in a new browser tab.
6. In the browser, under "Open a notebook", click in the text box and navigate to the file src/frontend.jl inside the unzipped repo.
7. Click Open on the right.
8. Once the notebook loads, click "Run notebook code".
9. Wait a long time for the needed packages to download and compile.
