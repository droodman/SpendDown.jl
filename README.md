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

The front end is built in Pluto, which does not yet support Julia 1.13 (as of September 2026). Install and run Julia 1.12:
1. [Install Julia](https://julialang.org/downloads)--just takes a few clicks or a single shell command!
2. In a command shell, type:
   ```
   juliaup add 1.12
   julia +1.12
   
   ```
3. After Julia starts, install this package with
   ```julia-repl
   julia> using Pkg; Pkg.add(url="https://github.com/droodman/SpendDown.jl")
   ```

To run the front end (recommended):
1. Download the front end directly from this repo by going here, and clicking the download icon toward the upper right.
2. In Julia 1.12, do
```julia-repl
julia> using SpendDown
julia> SpendDown.notebook()

```
3. The Pluto home screen should appear in a new browser tab.
4. Especially on firs use, wait a long time for the needed packages to download and compile.
