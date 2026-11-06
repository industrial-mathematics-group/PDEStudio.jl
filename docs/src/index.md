# PDEStudio.jl

**PDEStudio.jl** is an interactive, Makie-driven graphical frontend for the real-time visualization and exploration of Partial Differential Equation (PDE) simulations.

It is built directly on top of its numerical backend **PDEStudioCore.jl** (reexported, so `using PDEStudio` is enough) and turns its simulation data into responsive 1D, 2D and 3D visualizations. It features a tabbed control panel with editors for the physics and the look (and an *Advanced* tab for the raw `SimulationConfig`), CSV-based presets for both the look and the physics of a study, and a rendering engine that handles Eulerian grids and Lagrangian particle systems.

PDE simulations often have to run on servers. There are two ways to work with remote machines:

> **Headless Mode:** The backend `PDEStudioCore` runs and stores simulations on its own, so it can create `PDEStudio`-compatible data on the server, which you then copy for local exploration with `GLMakie`. This gives the best performance, but can mean large data transfers.

> **Web Mode:** `PDEStudio` is Makie-backend agnostic, so you can use `WGLMakie` (powered by `Bonito`) to serve the studio from the server to a web browser. This greatly reduces data transfer, at the cost of performance and latency.

---

## 🎨 Interactive Architecture

The studio is built around a central, reactive state manager that links the live simulation data to the Makie render loop.

*   **Eulerian & Lagrangian Support:** Rendering primitives adapt to the data: grid-based heatmaps, surfaces and volumes, or point-based scatter plots. Data stored in the other representation is converted on the fly.
*   **Editors:** the shared parameters (*Shared*), the methods with their parameters and drawing order (*Methods*), the look and the display names (*UI*), presets, export settings and resolution (*Files*) and the raw `SimulationConfig`: sweep, fields, all methods (*Advanced*); one row per entry (see [Editors](editors.md)).
*   **Dynamic Layouts:** Multi-plot comparisons (methods, components, time steps or any swept parameter), linked or decoupled axes and detached legends.
*   **Any Sweep:** Swept parameters can be numbers or anything else (scheme names, tuples, …); non-numeric sweeps get index sliders that display the swept value.

---

## 💾 Serialization & Presets

**PDEStudio.jl** stores its state in plain CSV files (`Category, Scope, Parameter, Value`, RFC 4180).

| File | What it holds | Created with |
| :--- | :--- | :--- |
| **Export CSV** | Everything: physics, look, sweep, git commits, Julia versions, bundled sources | *Export* (next to every figure/animation) |
| **Look (visual) Preset** | The look only (layout, axes, camera, labels, UI styles) | *Files → Look → Save*, [`save_plot_preset`](@ref) |
| **Simulation Preset** | The physics only (shared/method parameters, active methods, sweep, functions) | *Files → Simulation → Save*, [`save_sim_preset`](@ref) |

Visual presets apply to any simulation; simulation presets swap the physics while the look stays as it is. See [Presets](presets.md).

*   **Readable & Editable:** Keys are written as their raw backend names (`animation_FPS`, `sim_func_name`), values in Julia literal syntax (`Float64[0.2, 0.5]`, `:upwind`). Display labels never appear in files, so renaming a label does not affect saved states.
*   **Type-Preserving Parsing:** Values are read back with the safe literal parser `str2val` into the type they were saved as (vectors, tuples, symbols, dictionaries, …). Text stays text.
*   **Loading:** Drop a CSV (or a Julia configuration file) onto the studio window, choose it with *Files → Browse…*, or type its path or file name into *Files → Name / path* and click **Load** to recreate a saved state.

> **Security Note:** CSV values are parsed safely; no code in a value is ever evaluated. However, an export CSV can *bundle source files* (the `sources` of a `SimulationConfig`, copied next to the export), and loading such a CSV **executes those files** to restore the solvers, as does loading a Julia configuration file (`set_sim_config!("config.jl")`). Only load files you trust; the studio asks for a second click before it runs code. Presets never contain source files.

---

## 🎬 Exporting & Animations

The export pipeline renders a pristine copy of the plot, independent of the interactive window.

*   **Static Frames:** High-DPI `.png`/`.jpg`, and vector `.pdf`, `.svg` and `.eps` via CairoMakie, with optional rasterization of heavy 3D plots.
*   **Animations:** `.mp4`, `.webm`, `.mkv` or `.gif`, sweeping any slider (time, a physical dimension or a swept parameter) with a locked camera, a custom frame rate and duration.

See [File Operations](file_ops.md) for the details.

---

## 🛠️ Main API Functions

| Function | Purpose |
| :--- | :--- |
| [`@launch`](@ref)` [style] [config]` | Runs a configuration (optional) and opens the studio with it, in a plot style (optional, e.g. `heatmap`). |
| [`launch_plotter`](@ref)`(config; style)` | Builds the studio window (the same without showing it); returns the `Figure`. |
| [`set_sim_config!`](@ref)`(config)` | Binds a `SimulationConfig` (or a CSV: `set_sim_config!("name.csv")`). Also the baseline for *Files → Simulation → Reset*. |
| [`force_simulation`](@ref)`()` | Runs the bound configuration (same as clicking *Run Simulation*). |
| [`set_plot_preset!`](@ref)`(name)` | Applies a built-in or saved visual preset; `set_plot_preset!()` restores the default look. |
| [`save_plot_preset`](@ref)`(name)` | Saves the current look as a visual preset. |
| [`save_sim_preset`](@ref)`(name)` | Saves the bound simulation as a simulation preset. |
| [`set_sim_preset!`](@ref)`(name)` | Applies a simulation preset (replace or patch). |
| [`reset_sim_config!`](@ref)`()` | Restores the configuration last bound with `set_sim_config!`. |
| [`set_mode!`](@ref)`(:eulerian / :lagrangian)` | The data behind the styles (grid / particles); set by choosing a particle or another plot style. |
| [`set_allowed_dims!`](@ref)`(dims)`, [`set_max_params!`](@ref)`(n)` | Structural limits: the dimensions (axes, default `(:x, :y, :z, :t)`; `@launch` adds the axes of the data) and the number of parameter sliders. |
| [`set_resolution!`](@ref)`(dim, n)` | Display resolution of a dimension (data is resampled in space for display; in time, the most stored snapshots shown; also *Files → Resolution ›*). |
| [`reset_plotter!`](@ref)`()`, [`reset_manager!`](@ref)`()` | Closes the window / resets the whole studio without restarting Julia. |

---

## 🚀 Basic Workflow

```julia
using PDEStudio   # reexports PDEStudioCore
using GLMakie     # or WGLMakie for browser rendering

@launch test_advection_1d()              # run a configuration and open the studio with it
@launch heatmap test_heat_2d()           # ... in a plot style (a group: lines, scatter, contour, heatmap, volume, or a style)
```

`@launch` runs the configuration first (the results are cached) and opens the studio set up for its data: particle
data in a particle style (unless another style is given), and axes the studio doesn't know yet (e.g. a time axis named
`:iteration`) added to [`set_allowed_dims!`](@ref). The same step by step:

```julia
fig = launch_plotter(; style = :heatmap)  # build the window
display(fig)
set_sim_config!(test_heat_2d())           # bind a configuration
force_simulation()                        # run it (or click "Run Simulation")
```

If the data then has axes the window lacks, the status line says so and the next *Run Simulation* rebuilds the
window with them.

`test_advection_1d()` is one of the built-in examples of PDEStudioCore, each a function returning a ready
`SimulationConfig`: `test_advection_1d`, `test_burgers_1d`, `test_heat_1d`, `test_heat_2d`, `test_poisson_2d` and
`test_particles_2d` (Lagrangian data, opened as particles). Their solvers, in PDEStudioCore's
[`src/Examples/`](https://github.com/blhackslash/PDEStudioCore.jl/tree/main/src/Examples), show how to write your own;
a configuration of your own is bound the same way:

```julia
config = SimulationConfig(create_param_dict(:N => 100, :cfl => 0.5, :sim_func_name => :my_solver),
                          create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                             :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
                          [:upwind, :lax_friedrichs];                   # active methods (`defaults`)
                          varied = create_varied_dict(:cfl => [0.3, 0.5, 0.8]),
                          reference = :my_exact_solution)
set_sim_config!(config)
```

---

## ⚙️ Advanced Workflow (Custom Macros & Web Servers)

For extensive experiment libraries or remote servers, PDEStudio can be wrapped in custom macros for rapid deployment.

Below is a pattern that configures a `Bonito` web server for `WGLMakie`, resolves configuration paths, backs up executed configurations for reproducibility, and binds the physics to the studio in a single macro call.

```julia
using PDEStudio
using WGLMakie
using Bonito

# 1. Configure the Web Server for Remote Viewing
Bonito.configure_server!(
    listen_url = "0.0.0.0",
    listen_port = 9384
)
WGLMakie.activate!()

# 2. Build a one-click macro to load, archive, and plot your experiments
macro plot(name)
    return quote
        # Launch studio
        fig = Base.invokelatest(() -> launch_plotter())
        
        # Resolve path and archive the config 
        path = joinpath(@__DIR__, "Configs", $(esc(name)) * ".jl")
        cp(path, joinpath(@__DIR__, "Archive", $(esc(name)) * "_backup.jl"), force=true)
        
        # Load physics and trigger rendering
        config = include(path) 
        set_sim_config!(config)
        force_simulation()
        
        fig
    end
end

# Usage: 
# julia> @plot "Euler2D_Shock"
```

Simpler: load the configuration file itself with `set_sim_config!("Configs/Euler2D_Shock.jl")` (or *Files → Browse…*); it is added to the config's `sources`. Every export copies the `sources` into `<name>_sources/` next to the exported CSV, and loading that CSV later runs the copies and so recreates the experiment, solvers included. The exported copies run in place of the originals (so files next to them that aren't bundled are found), also if the originals were edited since; *Run Simulation* and later exports use the exported version of edited files, so the export reproduces itself. How to write configuration files that reload reliably: [File Operations](file_ops.md#Config-Files-and-Bundled-Sources).
