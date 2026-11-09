# Scripting & AI Agents

Everything a person does in the studio window is also available as a function: reading what the plots show, looking
at them, operating the controls and moving the camera. Scripts can use it to drive the studio, and AI agents (or any
program that reads text and looks at images) can explore results the way a person would, with or without a display.

The functions work on the open studio (`launch_plotter`) through the same widgets as a mouse: a visible window shows
what the script does, and when a function returns, the studio has finished updating.

## Without a display

[`studio_headless!`](@ref) makes CairoMakie the active backend. The studio is then built in memory, so no window,
X server or browser is needed (e.g. on a compute node, in CI, or in an agent's sandbox):

```julia
using PDEStudio
studio_headless!()
launch_plotter(test_heat_2d(); style = :heatmap)
describe_studio()                 # what is shown, as text
studio_snapshot("heat.png")       # what it looks like, as an image
```

With a visible window (GLMakie, or WGLMakie in a browser) the same functions work unchanged. A GLMakie window renders
snapshots itself; without a display, and in a browser, CairoMakie renders them. CairoMakie can't draw volumes: a
snapshot of a volume plot then shows the empty axes, and the status line says so.

## Reading what is shown

[`describe_studio`](@ref) prints a summary meant to be read by a person or an agent:

```text
PDEStudio (CairoMakie, 1259×928 px)
Status [ok]: Simulation finished in 1.5 s: 6 runs, 6 ran, 0 cached.
Configuration: solver solve_heat_2d; methods adi, exact, explicit; active exact, explicit, adi
  swept r = 0.1, 0.25, 0.3
Plot: style heatmap_flat (2D); x = x, y = y, z = none, u = Solution, component 1
  plot 1: "R = 0.100 | Time (T) = 0.000" [Position (X) | Position (Y)] x ∈ [0.000, 1.000], y ∈ [0.000, 1.000]
    explicit: values [-0.212, 1.295]
Controls (studio_set! / studio_press!):
  plot_style [style, applies with :apply_layout] = :heatmap_flat  ∈ {:lines_1d, :lines_2d, …}
  x_axis [menu, applies with :update_plot] = :x  ∈ {:x, :y, :r, :t} — X-Axis
  …
  r [slider] = 0.1  (0.100, 0.250, 0.300) — swept parameter (shown: 0.100)
  t [slider] = 0.0  (100 values, 0.000 … 0.050) — dimension
  run [button] — Run Simulation
  …
```

- [`studio_state`](@ref) returns the same as data: status line, configuration, plot style, the variables on the axes,
  comparison, sliders, and per subplot its title, labels, the shown limits (and the camera angles of 3D plots) and the
  range of the plotted values per method.
- Styles that show one method (heatmaps, surfaces, filled contours, volumes, …) show the method chosen by
  `studio_option!(:plot_style, :method_index, i)`; `describe_studio` names it. Compare the methods side by side with
  `studio_set!(:compare_target => :methods)`.
- Swept parameters beyond the window's parameter sliders (`set_max_params!`) have no slider: the plots show their
  first value, and `describe_studio` marks them.
- [`studio_data`](@ref) returns the plotted numbers themselves (coordinates and values per method), so a program can
  compute with what is shown instead of reading it from an image.

## Looking at it

[`studio_snapshot`](@ref) writes a PNG and returns its path (by default a new file in `<save path>/snapshots/`):

```julia
studio_snapshot()                                   # the plot grid with colorbars and legends
studio_snapshot("window.png"; area = :window)       # the whole studio, control panel included
studio_snapshot("detail.png"; plot = 2, px_per_unit = 2)   # subplot 2 alone, twice the resolution
```

## Operating the controls

[`studio_controls`](@ref) lists every control with its kind, value and choices, under the names
[`studio_set!`](@ref) and [`studio_press!`](@ref) take:

```julia
studio_set!(:t => 0.02)                                    # a dimension slider (the nearest value is taken)
studio_set!(:r => 0.25)                                    # a swept parameter, by its name
studio_set!(:plot_style => :contour, :y_axis => :t)        # style and axes (a group name gives its first style)
studio_set!(:compare_target => :methods, :compare_columns => 3)
studio_set!(:methods => [:explicit, :exact])               # the active methods (runs the simulation)
studio_press!(:run)                                        # a button
```

`studio_set!` presses the button a change needs (*Update Plot*, *Apply Layout* or *Run Simulation*) once after all
changes, and returns the new values and the status line. A name or value that doesn't exist throws an
`ArgumentError` listing the valid ones, so an agent can correct itself.

The look (the *UI* tab) is changed with [`studio_option!`](@ref); [`studio_options`](@ref) lists the scopes and keys:

```julia
studio_option!(:plot_style, :color_map, :plasma)
studio_option!(:y_axis_1d, :log_scale, true)
studio_option!(:labels, :title, "Heat equation")
```

## Moving the camera

| Function | What it does |
|:---------|:-------------|
| [`studio_view!`](@ref) | sets the limits (`xlims`, `ylims`, `zlims`) and, for 3D plots, the camera angles in degrees (`azimuth`, `elevation`) |
| [`studio_zoom!`](@ref) | zooms in (`factor > 1`) or out, around the middle or a `center`, optionally along some axes only (`dims = :x`) |
| [`studio_pan!`](@ref) | moves the view by fractions of its size (`studio_pan!(0.25)`: a quarter view to the right) |
| [`studio_rotate!`](@ref) | turns the camera of 3D plots by some degrees |
| [`studio_reset_view!`](@ref) | returns to the automatic view that follows the data |

All of them act on every subplot or on one (`plot = 2`); linked 2D subplots (*Compare Link*) move together, as in
the window. The view they set stays while sliders move and the data updates (the camera is locked, as with the *Lock
Camera* button), until [`studio_reset_view!`](@ref) or until [`studio_set!`](@ref) or [`studio_press!`](@ref) changes
the plotted variables, the plot style or the comparison: the old limits would show the wrong range, so the plots follow
the data again. A view locked with the *Lock Camera* button, or loaded with a preset or CSV file, stays. Angles
are in degrees; log-scaled axes zoom and pan on the log scale. Zooming a 3D plot narrows its limits, so what lies
outside is cut off, as when zooming with the mouse.

## An agent's loop

A typical exploration alternates looking and acting, and checks every step with the returned values or the state:

```julia
studio_headless!()
launch_plotter(test_advection_1d())
describe_studio()                                   # what is there, which controls exist
studio_set!(:t => 1.0)                              # the final time
img = studio_snapshot()                             # look at it
studio_zoom!(4; center = (0.5, 0.0))                # a closer look at a feature
studio_snapshot()
d = studio_data(1)                                  # the numbers, e.g. to compare methods
maximum(abs, d.methods[:upwind].u .- d.methods[:lax_wendroff].u)
studio_reset_view!()
```
