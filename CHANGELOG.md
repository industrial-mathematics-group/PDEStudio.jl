# Changelog

What has changed since the last release. Released versions are described in the
[releases](https://github.com/industrial-mathematics-group/PDEStudio.jl/releases) and the git history.

## Unreleased

### New
- **No-compute mode:** `set_compute!(false)` or `launch_plotter(config; compute = false)`: nothing is computed or
  written (a dry run); missing runs stay gaps and are listed (status line, `studio_state().missing_runs`,
  `describe_studio`). Exports record the save path and the run files (`save_path`, `run_files`); loading one where
  files are missing names them.
- **Lines over a swept parameter or time** (Plot tab, *Lines* and *Line Values*; `studio_set!(:line_target => …,
  :line_values => …)`): 1D plots draw one line per method and value, labelled in the legend, e.g. the initial
  conditions of a study in one panel or profiles at several times.
- **Joint sweeps** (`joint_sweep` of PDEStudioCore 0.6.2: several parameters changing together, e.g. `N` and a cell
  width `6/N`) are shown over their first parameter: one numeric slider named by it, usable as a plot axis. Scripts
  name it by its first parameter (sliders, axis and compare menus); titles name all of its parameters
  (`N = 80, IC Cell = 0.075`).
- **Statistics on references:** a reference evaluates the registered statistics that need no reference and runs the
  configuration's post-processor, so derived fields (primitive variables, …) can be drawn against it. A
  post-processor that fails on reference data is reported once; the reference is then drawn without its fields.
- **Compare Values** (Plot tab, `studio_set!(:compare_values => …)`): a comparison shows the values listed, e.g.
  `1e-5, 1e-3` (the nearest swept values or times), `1, 4` (components) or method names; `all` as before. It is a
  layout option, so presets and exported CSV files keep it.
- **Reference slopes** (`:reference`) are labelled (`slope −2`) and run just below the curve whose log-log slope is
  closest to them, instead of from an axis corner across the whole plot.
- **`studio_export(name; formats, dpi, fps, duration)`:** the *Export* button for scripts and agents. It writes the
  figure (or an animation for a name ending in `.mp4`, `.gif`, …) and the CSV state, and returns the paths.
- **`set_figure_path!` / `get_figure_path`:** the folder for exports (`figures/`, `animations/`) and
  `studio_snapshot` (`snapshots/`), so figures can be saved on your own computer while the data stays on a server
  (`set_save_path!`). The default is still the save path; configuration files are also searched for in the figure
  path's export folders.
- **Exports name the code they can't run again:** solvers, reference, post-processor and statistics (`calc_stat`
  methods) defined neither in a file of the configuration's `sources` nor in a package are named in the status line
  and the log, and recorded in the CSV (`Metadata, General, code_outside_sources`). The CSV also lists the registered
  statistics (`statistics`), and loading it warns about those the session doesn't register.

### Fixed
- **Labels of reference slopes keep apart**, also for several slopes next to one curve: each goes to the first of a few
  places along its line (and on either side of it) that is clear of the other labels, slopes and curves.
- **Compare Values goes back to `all`** when a configuration with other swept values is bound or launched (a relaunch
  of the same sweep keeps it); the values it named may not exist there.
- **Titles:** a tuple value shows its elements (`jitter = 0.200`, was `(0.2,)`), and the values of one parameter or
  comparison use one notation (`1e-5, 1e-4, 1e-3`, was `1e-5, 0.0001, 0.001`).
- **A grid of subplots shows the axis labels once** per row and column (they repeated on every subplot).
- **References of 1-D data are drawn at 1000 points** in space by default (were 200), so shocks stay sharp; a
  resolution set with `set_resolution!(…; is_ref = true)` or on the Resolution page is kept.
- **Log-axis ticks fit the panel:** narrow panels get decades or every k-th decade instead of overlapping 1-2-5
  labels such as `2×10⁻⁵` (the label sizes are estimated from the axis size and the tick label size), and the
  axis option `tick_count` limits the number of log ticks (it was ignored on log axes).
- **Exports in a headless studio no longer hang:** the export ended with `display` of the window, which with
  CairoMakie opened the image in a viewer (`xdg-open`) that never returned. `studio_headless!` also turns that
  viewer off (`CairoMakie.activate!(visible = false)`).
- **An animation export leaves the view as it was:** the animated slider is put back after recording (it stayed at
  its last value), and a locked camera's view is no longer skipped once after an export without a lock.
- **Titles of statistics** no longer show the slider value of a dimension the statistic doesn't keep (an error over
  `N` showed "Position (X) = −0.0101").
- **Log axes** have ticks at 1, 2, 3, 5 × 10ᵏ (as the range allows), written as numbers, instead of ticks like
  `10^2.5`.
- **Log-axis labels** are plain numbers if all ticks lie in [0.001, 10⁵) and powers of ten (10⁻⁶, 2×10⁻⁶) otherwise,
  instead of decimals such as `0.000001`. A custom tick format or scale offset is kept.
- **Small and large values in titles** are written as `1e-5` and `2.5e6`, in compare titles (were `1.0e-5`) and in
  the other titles (were `1e-05`, `2.5e+06`).
- **Lines with markers:** the docs of the lines styles and of `studio_set!` point to *Scatter Lines*
  (`:scatter_lines`), and the scatter page lists its marker options.
- **Smaller default markers** (8 px, were 15 px) in the 1-D and particle styles.
- **Loading the package prints nothing** (the reset of the look at start-up logged an Info line).
- **Results of earlier source code** (kept after editing a configuration) are still counted in the status line, but no
  longer turn it orange.

- **A reference method first in the plot data hid every statistic** (e.g. methods `(:analytic, :godunov)`: the
  axis menus lost the errors and `studio_set!(:u_axis => :l2error)` threw). The menus and the agent API now take a
  non-reference method's data as the template.
- **Configurations without `methods`** (the shared parameters alone, supported by PDEStudioCore) ran and were drawn
  as the single method `:default` instead of "No methods selected".
- **The studio works on a copy of the bound `SimulationConfig`**: edits in the window (methods, parameters, the
  sweep) no longer change the configuration passed to `set_sim_config!` / `launch_plotter`.
- `reset_manager!()` with an open window closes it first (it was left without widgets and with its animation running).
- An animation export stops a playing animation first (its timer moved the slider while the frames were recorded).
- Display resolutions are limited in total (50 million points of one dataset), not only per axis.
- Relaunching the window after Run (more dimensions, a structural CSV) no longer calls `display` in a browser session.
- Uploads over the size limit are refused by the server as well, not only by the page.
- The load confirmation of an export covers every file it may run (the bundled copies wherever they are found and
  their originals).
- `studio_set!(:plot_style => :particles)` picks the particle style of the data's dimension (it chose the 1D style).
- CSV files keep small integer types (`Int32(5)`), `missing` and empty strings inside containers; `_needs_type`
  writes integers other than `Int` with their type.
- Preset names cannot contain path separators or `..` (a preset file is only looked up inside the preset folder).
- Colour ranges must be finite and ordered (`[hi, lo]`, `[a, a]` and `NaN` were accepted).
- The docstring of `save_params_to_csv` described the old `<name>_source_<i>.jl` layout; a `:None` typo in the
  title helper.
- **`particles_lines` joins the particles along the axis**, not in storage order: particle management stores inserted
  particles last, so the lines ran back and forth across the plot.
- **`studio_set!` makes the changes of one call in the order the controls depend on each other** (style, methods,
  layout and comparison, axes, dependent field, then the sliders after the rest is applied): ending a comparison and
  setting the slider it held, or setting the x axis and a statistic it offers, works in one call. Every name is
  checked before anything is set (and so are the values of the sliders that are usable), and a slider the same call
  puts on an axis or into the comparison is left as it is.
- **Small and large values in titles, slider labels and descriptions** have 3 significant digits (`τ = 1e-05`, was
  `0.000`; `0.0125`, was `0.013`); values from 0.1 to 10⁵ keep 3 decimals.
- **Names of parameters without a label:** an entry of a tuple parameter is shown in brackets (`Grid_Ns__1` is
  "Grid Ns[1]", was "Grid Ns  1"; `__all` is "(all)"), and words written with capitals keep them (`PDE_tau` is
  "PDE Tau", was "Pde Tau").
- **Long method names in the titles of compared methods** are broken into lines at spaces or underscores (a word
  wider than the plot is shortened in its middle with "…", and the start compared names share is left out, so they
  stay distinct; at most two lines, one line on 3D axes) instead of running into the next plot.

### Changed
- **`set_label!` is exported:** give parameters, methods, statistics and dimensions display names, e.g.
  `set_label!(:Grid_Ns__1, "N")` instead of the automatic "Grid Ns[1]".
- **Statistics for agents:** the `:u_axis` entry of `studio_controls` / `describe_studio` and the error of an
  unavailable `:u_axis` value name the statistics the current axes don't offer and the call that plots them (e.g.
  `studio_set!(:x_axis => :t, :u_axis => :l1error)`, with `:plot_style => :lines` in 2D/3D and particle styles).
  `studio_state` reports titles as one line of text.
- The `:publication` look preset no longer sets the plot size (it set 500×400); it only places the legend.

### Removed
- The `:convergence` look preset: it was listed in the menu but changed nothing.

## 0.6.0

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
- **Scripting and AI agents** (docs: *Scripting & AI Agents*): the studio as functions, also without any display
  (`studio_headless!()`): `describe_studio` / `studio_state` (what is shown, as text or data), `studio_data` (the
  plotted numbers), `studio_snapshot` (a PNG of the plots, one subplot or the whole window; rendered by a GLMakie
  window itself, otherwise by CairoMakie),
  `studio_controls` / `studio_set!` / `studio_press!` (the controls by name; changes are applied), `studio_options` /
  `studio_option!` (the look), and the camera: `studio_view!` (limits, 3D angles), `studio_zoom!`, `studio_pan!`,
  `studio_rotate!`, `studio_reset_view!`. The view they set stays while the data updates (camera lock).
- **The status line after a run** counts the runs that ran, were cached or failed (with the first error message),
  and stored results made with other source code (from the `RunSummary` the next PDEStudioCore release returns; with
  older versions it shows the time only). After `launch_plotter(config)` it reports the run made before the window
  opened.

### Fixed
- **`launch_plotter(config)` after another configuration** started with the view of the old one: its plotted axes,
  slider positions and methods (e.g. the heat equation in 2D opened with `y = t`). A configuration with other swept
  parameters or solvers now starts with its default view (also while an animation plays); launching the same setup
  again keeps the plotted axes, slider positions and comparison. Binding such a configuration into an open window
  (`set_sim_config!`, loading a `.jl` file, a simulation preset) resets the view the same way (it also stops a running
  animation, ends the comparison and unlocks the camera); a CSV file applies its own. A slider that shows another parameter
  after an edit of the sweep starts at its first value.
- **A loaded export runs as it was exported**, at the load and at *Run Simulation*: the bundled copies run in place of
  their originals (files that aren't bundled, such as unlisted helpers and data files, are found next to them), and
  an `include` of a bundled file runs its copy (`include(path)`, `include(f, path)`, `Base.include`, `include` as a
  value). Copies of edited originals are the configuration's sources, so a new export reproduces the old one;
  before, an edited helper included by relative path ran in place of its copy, and the edited originals were bundled
  again. The status line names originals edited or gone since the export, also when a load changes the window. A
  missing copy whose original ran is a source now too (the next export bundles it). *Run Simulation* needs
  PDEStudioCore's `run_all_simulations(...; load_sources = false)` for this; with older versions all copies are the
  sources once an original was edited or is gone, and Run includes them from the bundle folder (only bundled files
  are found).
- **Run Simulation** shows an error in the status line (e.g. a source file that fails) instead of failing silently.
- **A plot that can't be drawn** (e.g. options the style can't use) says so in the status line; before, only the log
  showed it.
- **Symlinked sources** are bundled as files: before, the bundle held the link, so it followed later edits.
- **Time resolution 1** (`set_resolution!(:t, 1)`, a CSV row) made all data with time fail to load; it shows the last
  snapshot now. Resolutions are whole numbers from 1 to 100000 everywhere: `set_resolution!` throws otherwise, CSV
  rows outside that range (also huge ones) are ignored with a warning, the Resolution page accepts 1 (e.g. for
  particles without extent along an axis, as PDEStudioCore advises).
- **Nearly constant data on an axis with offset tick labels** (`scale_offset`): variations below 1e-6 relative are
  drawn instead of flattened (the offset labels show them); with other labels they stay flat.
- **Advanced tab:** a Char literal `'"'` before `<empty>` in a vector no longer breaks applying the shown value.
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
  clamped into the old range); they are applied once the new data is there. A saved position outside the range of the file's own data
  doesn't stay pending: moving the slider drops it, otherwise the next run applies it (clamped).
- **Reference lines** (`reference` exponents) added a listener to the axis limits on every UI update (every slider
  drag frame, every animation frame); they are removed with the lines now.
- **Float32, Float16 and `SVector` parameters** came back from a CSV (exports, presets) as `Float64` / `Vector`; they
  keep their type now (`1.5f0`, `Float16(0.1)`, `SA{Float64}[1.0, 2.0]`). The data hash is unchanged and files
  written before read as they did. Other integer types, `MVector`/`SMatrix`, ranges, `NamedTuple`s and `missing` still
  come back changed; the docs (*Presets*, "Which values keep their type") list them.
- **Hand-written CSVs with spaces after the commas** (`Category, Scope, Parameter, Value`) failed or put the rows
  into a wrong scope; header and key cells are stripped (and unquoted values, e.g. labels), and unknown categories and
  scopes are warned about.
- **A bundled `.jl` configuration that ends with a function** (as `load_config_file!` accepts) wasn't called when the
  export was loaded again, so function parameters came back as the text `"Closure"`.
- **1-D axis limits of a constant field** (e.g. Float32 noise around a constant state) showed the round-off noise
  with repeated tick labels; they get the relative range of the colour ranges. Variations within the round-off of
  the data's type (100 `eps`) or below what tick labels can show (1e-6 relative) count as constant; larger small
  variations of Float64 data stay visible (they were drawn flat below 1e-5).
- **Style values that can't be drawn** (`colors = []`, empty `markers` / `line_styles`, a `color_range` of one value,
  `levels` below 2) were accepted by the editor and broke every plot update; they are refused now, and filled
  contours draw with at least 2 levels.
- **Style values from files:** the same values in a CSV or a look preset were stored and broke the plot (a one-value
  `color_range` even threw out of the update). They are ignored with a warning now, a `color_range` that isn't
  `[lo, hi]` is automatic, and an error in the style step is logged instead of escaping.
- **Provenance of exports:** the dependencies of local packages (repository `<Name>.jl` of the package `<Name>`) were
  never recorded in the `Julia` category; they are now. The `Git` rows also record whether a repository had uncommitted changes to tracked files (`git_dirty`; new,
  untracked files don't count).
- **◀ ▶ in the Files tab:** the pages of a preset file and of a long preset list couldn't be turned (rows after the
  first page of a look preset were out of reach).
- **The built-in `heatmap` and `compact3d` look presets** wrote their axis options into the axes of the style shown
  (e.g. the 1-D lines); they set the axes of the heatmap / of the 3D styles now, and `publication` sets every axis
  variant.
- **Fewer active methods with Compare = methods:** binding a configuration with fewer methods than subplots broke
  every plot update until the next run.
- **"Click Load again"** confirmed a file by its path only: a second upload with the same name, or a file changed on
  disk in between, ran without the warning. The confirmation is for the content now: of the file and the bundled
  copies a CSV names, not of files the code includes (see *File Operations*).
- **Play Anim with `animation_FPS` or `animation_time` ≤ 0** threw and left the button on *Stop Anim*; it warns
  instead.
- **Exports:** a failed export left the render listeners of its export figure attached (every later update also
  redrew the hidden figure, one more set per failure); they are released now. `animation_FPS`, `animation_time` and
  `dpi` must be positive numbers: the editor refuses others (e.g. `NaN`), and an export reports them instead of
  failing.
- **Deleted preset files** stayed in the preset lists (and *Edit ›* called them built in); the lists follow the files.
- **Preset files written by hand:** *Edit ›* failed on a header with spaces after the commas, and a file that isn't a
  studio CSV threw out of *Apply* / *Edit ›* (in GLMakie that stops the window from updating). Such files open like
  the others or the status line says what is wrong.
- **Status line:** messages with multibyte characters (`→`, `ü`, …) were wrapped inside a word and could exceed the
  line.
- **Menus with a meaningful order** (components, compare targets) were sorted by label (`Component 1, 10, 11, 2, …`);
  they keep their order.
- **Renaming a variable** (UI → Labels → Variables) now relabels the axis, animation and compare menus right away,
  without flagging *Apply Layout* / *Update Plot* (renaming a component doesn't flag *Update Plot* either).
- **A method named `#order` or `#methods`** opened the editor's drawing-order or method-list page instead of its own;
  names starting with `#` are refused when adding a method (and warned about in a bound configuration).
- **Empty texts in the editors:** the Advanced tab showed an empty text as `<empty>`, which it refused as input; it shows
  `""` and accepts `<empty>`. Empty texts inside vectors and tuples (`String[<empty>, "a"]`) can be applied again on
  every page, and `<empty>` on the Labels pages is the empty name (it was stored as the text "<empty>"). A menu shows
  the key of an entry with an empty name (Makie's menus overflow the stack on an empty option).
- **Numerical curve and reference at the same time (round 2):** grid data was resampled in time (the nearest stored
  snapshot relabelled with a display time), so the drawn data could be up to half the interval between stored
  snapshots away from the reference and the title, e.g. for output stored every few steps. Data drawn with a grid
  style (grid data, and particle data scattered to the grid) now shows its stored snapshots at their own times (see
  *Changed*).
- **References of particle data** were evaluated at evenly spaced times even when the data was stored at other times,
  and their cost grew with the number of stored times. They are evaluated at the data's times, at most the reference
  time resolution (default 100) of them.
- **Exports of a reloaded export** didn't bundle the configuration file again (a file returning the configuration
  doesn't list itself), so function parameters came back as the text `"Closure"` from the second export on; the
  bundled files are now sources of the loaded configuration.

### Changed
- **Shorter plot titles:** a title lists only the variables that are not on an axis (`R = 0.100 | Time (T) = 0.000`;
  the `Position (X) = [Axis]` parts are gone, the axis labels name them), broken into lines where it would be wider
  than the plot. The breaks are chosen for the widest value of each part, so they stay while the sliders move.
  `studio_state` / `describe_studio` report a title in one line.
- **Default display resolutions in space: 100 points for the data, 200 for references** (were 200 and 400; time
  stays at 50 and 100): 3-D data with time was infeasible with the old defaults. Raise them in *Files → Resolution ›*
  or with `set_resolution!` where needed.
- **Time axis of data drawn with a grid style** (grid data, particle data scattered to the grid): the display
  resolution of a time axis (*Files → Resolution ›*, `set_resolution!`) is the most stored snapshots shown; the data is
  no longer interpolated in time. All snapshots are shown up to it, otherwise that many, evenly spread. Cost: the
  first display of a data file reads its stored data once to count the snapshots (twice when PDEStudioCore's
  conversion cache, `enable_cache!(true)`, writes to the file then). Data with more snapshots than the time resolution
  is read in full and converted on every reload (each *Run*, each sweep point) instead of coming from the cached
  conversion, so with the cache on, large data with many snapshots reloads slower (for a 256² × 401 grid: 266 MiB and
  ~50 ms per dataset instead of 16 MiB and 2 ms); raising the time resolution to the number of snapshots uses the
  cache again. With the cache off (the default) loading costs less than before.
- **Reference resolution in time:** references are evaluated at the time values of the numerical data they are drawn
  with, at most the time entry of the reference resolution (*Files → Resolution ›*) of them; in space the reference
  resolution is used as before.
- **Lagrangian layout presets and CSV files** store the particle style names (`particles_2d`). Files with the
  `Config, Dimensions, mode` row open their particles as before; older files with a scatter style saved in a
  Lagrangian session open it on a grid (choose the particle style again).
- **Quick start with the built-in examples of PDEStudioCore:** `set_sim_config!(test_advection_1d())` (or
  `test_burgers_1d`, `test_heat_1d`, `test_heat_2d`, `test_poisson_2d`, `test_particles_2d`) shows a ready example;
  README and docs start with them. `examples/advection_1d.jl` is removed: the example solvers are maintained in one
  place, PDEStudioCore's `src/Examples/` (needs a PDEStudioCore release that has them).
