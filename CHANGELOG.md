# Changelog

What has changed since the last release. Released versions are described in the
[releases](https://github.com/blhackslash/PDEStudio.jl/releases) and the git history.

## Unreleased

### New
- **`@launch [style] [config]`**: runs a configuration and opens the studio with it, optionally in a plot style:
  `@launch heatmap test_heat_2d()`. A style is a group (`lines`, `scatter`, `contour`, `heatmap`, `volume`,
  `particles`: its first style) or a style (`heatmap_surface`, `contour_3d`, `particles_2d`, …); the axes follow
  from the data (x–y for 2D data, x–t for 1D data). `launch_plotter(config; style)` is the same without showing
  the window.
- **Axes of the data:** `@launch` / `launch_plotter(config)` set up the window for the data: without a style,
  particle data opens in a particle style, and axes outside `(:x, :y, :z, :t)`, e.g. `time_dim = :iteration`, are
  added to the allowed dimensions (a time axis gets the time resolution).
- **Particle styles instead of a mode:** the style page has a *Particles* group (`particles_1d`, `particles_lines`,
  `particles_colors`, `particles_2d`, `particles_surface`, `particles_3d`; those of the particles' dimension). They
  draw the data as particles (Lagrangian), every other style on a grid (Eulerian); data of the other kind is
  converted. Switching between both is live: the window, the bound configuration, the look and the editors are
  kept, the data is reloaded (cached) and redrawn. Presets and CSV files store the style name, so they restore the
  particles. `set_mode!` still exists (it no longer closes the window or resets the manager) but is set by the style.
- **Resolution page with particle styles:** only the references (particles are shown as computed).

### Fixed
- **Data with axes the window doesn't have** (e.g. a time axis `:iteration` without `set_allowed_dims!`) was dropped
  silently: an empty plot, "Simulation finished" and the sliders of the previous configuration. Now the status line
  names the missing axes, the old data is cleared and *Run Simulation* rebuilds the window with them.
- **Export message:** an image exported to a path typed into *Name / path* was reported as saved to the default
  `figures` folder; the status line now names the folder it went to.
- **References in sweeps that change the domain** (final time, domain length, grid): every sweep point's reference
  was laid out on the domain of the first one, so it was drawn at the wrong times or places. Each reference now
  covers the domain of the numerical data of its own sweep point.
- **Numerical curve, reference and title at the same time:** at one time slider position the numerical data, the
  reference (on a finer time grid) and the title (the slider value) showed up to one display step apart. The
  reference is now evaluated at the times of the numerical data, and the title shows the time of the drawn data.
- **Slider positions of a CSV loaded while other data is shown** were lost (the slider came back at the value
  clamped into the old range); they are applied once the new data is there.
- **Reference lines** (`reference` exponents) added a listener to the axis limits on every UI update (every slider
  drag frame, every animation frame); they are removed with the lines now.
- **Float32, Float16 and `SVector` parameters** came back from a CSV (exports, presets) as `Float64` / `Vector`; they
  keep their type now (`1.5f0`, `Float16(0.1)`, `SA{Float64}[1.0, 2.0]`). The data hash is unchanged and files
  written before read as they did.
- **Hand-written CSVs with spaces after the commas** (`Category, Scope, Parameter, Value`) failed or put the rows
  into a wrong scope; header and key cells are stripped, and unknown categories and scopes are warned about.
- **A bundled `.jl` configuration that ends with a function** (as `load_config_file!` accepts) wasn't called when the
  export was loaded again, so function parameters came back as the text `"Closure"`.
- **1-D axis limits of a constant field** (e.g. Float32 noise around a constant state) showed the round-off noise
  with repeated tick labels; they get the relative range of the colour ranges.
- **Style values that can't be drawn** (`colors = []`, empty `markers` / `line_styles`, a `color_range` of one value,
  `levels` below 2) were accepted by the editor and broke every plot update; they are refused now, and filled
  contours draw with at least 2 levels.
- **Provenance of exports:** the dependencies of local packages (repository `<Name>.jl` of the package `<Name>`) were
  never recorded in the `Julia` category; they are now.
- **◀ ▶ in the Files tab:** the pages of a preset file and of a long preset list couldn't be turned (rows after the
  first page of a look preset were out of reach).
- **The built-in `heatmap` look preset** wrote its axis options into the 1-D axes of the style shown before; it sets
  the axes of the heatmap now.

### Changed
- **Reference resolution in time:** references are evaluated at the time values of the numerical data they are drawn
  with (the time entry of *Files → Resolution ›* for references applies only without numerical data); in space the
  reference resolution is used as before.
- **Lagrangian layout presets and CSV files** store the particle style names (`particles_2d`). Files with the
  `Config, Dimensions, mode` row open their particles as before; older files with a scatter style saved in a
  Lagrangian session open it on a grid (choose the particle style again).
- **Quick start with the built-in examples of PDEStudioCore:** `set_sim_config!(test_advection_1d())` (or
  `test_burgers_1d`, `test_heat_1d`, `test_heat_2d`, `test_poisson_2d`, `test_particles_2d`) shows a ready example;
  README and docs start with them. `examples/advection_1d.jl` is removed: the example solvers are maintained in one
  place, PDEStudioCore's `src/Examples/` (needs a PDEStudioCore release that has them).
