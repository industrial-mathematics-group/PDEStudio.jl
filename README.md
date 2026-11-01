<div align="center">

<img alt="PDEStudio.jl" src="logos/svg/logo.svg#gh-light-mode-only" width="480">
<img alt="PDEStudio.jl" src="logos/svg/logo-dark.svg#gh-dark-mode-only" width="480">

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.22962032.svg)](https://doi.org/10.5281/zenodo.22962032)
[![Build Status](https://github.com/blhackslash/PDEStudio.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/blhackslash/PDEStudio.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/blhackslash/PDEStudio.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/blhackslash/PDEStudio.jl)
[![Dev Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://blhackslash.github.io/PDEStudio.jl/dev/)
[![Stable Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://blhackslash.github.io/PDEStudio.jl/stable/)

</div>

**PDEStudio.jl** is a highly interactive, Makie-driven graphical frontend engineered for the real-time visualization and exploration of Partial Differential Equation (PDE) simulations. It serves as the visual counterpart to the autonomous numerical backend, [PDEStudioCore.jl](https://github.com/blhackslash/PDEStudioCore.jl).

The studio seamlessly handles both Eulerian grids and Lagrangian particle systems, dynamically adapting its primitives to support 1D, 2D, and 3D visualization. It features a tabbed control panel (plot and layout options, methods, shared parameters, the look, files and presets, and an advanced editor for the raw configuration), robust CSV serialization for state preservation, and an independent export pipeline for publication-quality static frames and animations.

Because PDE simulations often require dedicated compute servers, `PDEStudio.jl` supports two primary deployment strategies:
*   **Local Exploration (`GLMakie`):** Run the autonomous `PDEStudioCore` backend headlessly on a server, transfer the resulting serialized data, and explore it locally with maximum performance.
*   **Remote Web Server (`WGLMakie`):** Serve interactive plots directly from the compute node to your web browser via `Bonito`, trading a slight latency increase for massive reductions in data transfer overhead.

## Installation

```julia
using Pkg
Pkg.add("PDEStudio")
```

*Note: For the full interactive experience, you must also install a Makie backend of your choice (e.g., `GLMakie` or `WGLMakie`).*

## Documentation

For comprehensive guides on the reactive UI architecture, layout synchronization, parameter sweeping, and advanced server deployment macros, please refer to the **[Official Documentation](https://blhackslash.github.io/PDEStudio.jl/dev/)**.

## Quick Start

```julia
using PDEStudio   # reexports PDEStudioCore
using GLMakie     # or WGLMakie for browser rendering

fig = launch_plotter()
display(fig)

set_sim_config!(test_advection_1d())   # a built-in example: three schemes and the exact solution, swept over the CFL number
force_simulation()                     # or click "Run Simulation"
```

Then explore it: the sliders pick the CFL number and the time, the *Plot* tab the plot style and axes, *Methods* the
schemes. Other built-in examples:

| Example | Equation | Tip |
| :--- | :--- | :--- |
| `test_burgers_1d()` | inviscid Burgers: a shock, conservative vs non-conservative schemes | X-Axis → Time, U-Axis → Mass |
| `test_heat_1d()` | heat equation: explicit (unstable at `r = 0.6`), implicit, Crank–Nicolson | slider R |
| `test_heat_2d()` | heat equation in 2D: explicit vs ADI | Plot Style → Heatmap, Y-Axis → Position (Y) |
| `test_poisson_2d()` | Poisson equation: Jacobi, Gauss–Seidel, SOR; time = iterations | Heatmap, as above |
| `test_particles_2d()` | particles in a rotating flow: Euler, RK2, RK4 | `set_mode!(:lagrangian)` before `launch_plotter()` |

They come from [PDEStudioCore](https://github.com/blhackslash/PDEStudioCore.jl): each is a function returning a
`SimulationConfig`, with its solver in PDEStudioCore's
[`src/Examples/`](https://github.com/blhackslash/PDEStudioCore.jl/tree/main/src/Examples).

## Your Own Simulation

A solver is a function from the parameters of one run to a dataset; a `SimulationConfig` adds the methods, the sweep
and an optional exact solution (see the [PDEStudioCore README](https://github.com/blhackslash/PDEStudioCore.jl), or
copy one of the example solvers). Bind it like an example:

```julia
set_sim_config!(my_config)   # or load a saved CSV / a Julia config file: set_sim_config!("my_run.csv")
```

---

Portions of this codebase and documentation were drafted by Claude Opus 5.5 and Fable 5.1 using Claude Code. All code has been human-reviewed, verified, and tested. If you notice any inaccuracies or unexpected behavior, please open an issue.
