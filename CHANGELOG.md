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

### Changed
- **Lagrangian layout presets and CSV files** store the particle style names (`particles_2d`). Files with the
  `Config, Dimensions, mode` row open their particles as before; older files with a scatter style saved in a
  Lagrangian session open it on a grid (choose the particle style again).
- **Quick start with the built-in examples of PDEStudioCore:** `set_sim_config!(test_advection_1d())` (or
  `test_burgers_1d`, `test_heat_1d`, `test_heat_2d`, `test_poisson_2d`, `test_particles_2d`) shows a ready example;
  README and docs start with them. `examples/advection_1d.jl` is removed: the example solvers are maintained in one
  place, PDEStudioCore's `src/Examples/` (needs a PDEStudioCore release that has them).
