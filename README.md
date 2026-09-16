# Spenddown modeling
 
This code file implements two versions of the spenddown model. Version 1 has not been made public. Version 2 makes major changes, including unconstrained optimization over spending paths, learning by doing, simulation of market returns, and a revamped handling of flow-through.

`src/PriorDistributions.jl` defines the `PieceWiseUniform` and `Bitriangular` distributions. src/SpendDownv1.jl implements version 1 of the model. src/SpendDown.jl does version 2.

`src/examples.jl` runs some models and generate plots.

`src/SpendDownJuliaCUDA.jl` is an alternative implementation that requries an NVIDIA CPU, and so doesn't work on the Mac. On a PC, it is ~2X faster than the CPU implementation. It was written before the addition of several features, including learning-by-doing and simulation of market returns.

`src/SpendDownJuliaMetal.jl` is an attempted, contemporaneous implementation on Apple GPUs, but it ran aground on the immaturity of Metal support in Julia (as of summer 2024).

`src/frontend.jl` is the Pluto notebook.

`src/Sobol demo.jl` demonstrates sensitivity analysis using Sobol indices.


## Installation
```
using Pkg; Pkg.add(url="https://github.com/droodman/SpendDown.jl")
```

If you want to use the model through the Pluto front end:
1. Open a terminal window and type `julia`.
2. In Julia, type `]` to enter the package manager.
3. Type `add Pluto`.
4. Hit delete or backspace to exit the package manager.
5. Type `using Pluto; Pluto.run()`. The Pluto home screen should appear in a new browser tab.
6. In the browser, under "Open a notebook", click in the text box and navigate to the file src/frontend.jl inside the unzipped repo.
7. Click Open on the right.
8. Once the notebook loads, click "Run notebook code".
