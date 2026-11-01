# Changelog

What has changed since the last release. Released versions are described in the
[releases](https://github.com/blhackslash/PDEStudio.jl/releases) and the git history.

## Unreleased

### New
- **`@launch [style] [config]`**: runs a configuration and opens the studio with it, optionally in a plot style:
  `@launch heatmap test_heat_2d()`. A style is a group (`lines`, `scatter`, `contour`, `heatmap`, `volume`: its
  first style) or a style (`heatmap_surface`, `contour_3d`, …); the axes follow from the data (x–y for 2D data,
  x–t for 1D data). `launch_plotter(config; style)` is the same without showing the window.
- **Axes of the data:** `@launch` / `launch_plotter(config)` set up the window for the data: Lagrangian data opens as
  particles (unless the style needs a grid) and axes outside `(:x, :y, :z, :t)`, e.g. `time_dim = :iteration`, are
  added to the allowed dimensions (a time axis gets the time resolution).

### Fixed
- **Data with axes the window doesn't have** (e.g. a time axis `:iteration` without `set_allowed_dims!`) was dropped
  silently: an empty plot, "Simulation finished" and the sliders of the previous configuration. Now the status line
  names the missing axes, the old data is cleared and *Run Simulation* rebuilds the window with them.

### Changed
- **Quick start with the built-in examples of PDEStudioCore:** `set_sim_config!(test_advection_1d())` (or
  `test_burgers_1d`, `test_heat_1d`, `test_heat_2d`, `test_poisson_2d`, `test_particles_2d`) shows a ready example;
  README and docs start with them. `examples/advection_1d.jl` is removed: the example solvers are maintained in one
  place, PDEStudioCore's `src/Examples/` (needs a PDEStudioCore release that has them).
