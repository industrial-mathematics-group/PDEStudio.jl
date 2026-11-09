# ==============================================================================
# --- SCRIPTING AND AGENT API ---
# ==============================================================================
# Everything a person does in the studio window, as functions: read what is shown (`describe_studio`,
# `studio_state`, `studio_data`), look at it (`studio_snapshot`, rendered by CairoMakie, so it works without any
# display), operate the controls (`studio_controls`, `studio_set!`, `studio_press!`, `studio_option!`) and move the
# camera (`studio_view!`, `studio_zoom!`, `studio_pan!`, `studio_rotate!`, `studio_reset_view!`). The functions work
# on the open window (`launch_plotter`) through the same widgets and observables as a mouse, so the window shows
# what an agent does, and every cascade has finished when a function returns.

"""
    studio_headless!()

Makes CairoMakie the active Makie backend, so the studio runs without any display (no window, no X server, no
browser): `launch_plotter` then builds the studio in memory, and an agent or script works with it through the
`studio_*` functions (see [`describe_studio`](@ref)) and looks at it with [`studio_snapshot`](@ref). Not needed
for snapshots of a visible window (they are always rendered by CairoMakie).

```julia
using PDEStudio
studio_headless!()
launch_plotter(test_heat_2d(); style = :heatmap)
describe_studio()
studio_snapshot("heat.png")
```
"""
function studio_headless!()
    CairoMakie.activate!()
    return nothing
end

# --- the window, its plots and their axes ---------------------------------------------------------------------

function _studio_window()
    (manager.is_open && !isnothing(manager.master_fig)) ||
        throw(ArgumentError("no studio window is open: start one with `launch_plotter(config; style)` " *
                            "(after `studio_headless!()` to run without a display)"))
    return manager.master_fig
end

# The layout of the plot grid (the right column of the window, see `launch_plotter`).
function _plot_layout()
    fig = _studio_window()
    gl = findfirst(c -> c isa GridLayout, Makie.GridLayoutBase.contents(fig[1, 2]))
    isnothing(gl) && throw(ArgumentError("the studio window has no plot area"))
    return Makie.GridLayoutBase.contents(fig[1, 2])[gl]
end

# The plot axes in the order of the subplots (the order `_initialize_render_layout!` creates them in).
_plot_axes() = Any[c.content for c in _plot_layout().content if c.content isa Union{Axis, Axis3}]

function _selected_axes(plot)
    axes = _plot_axes()
    isempty(axes) && throw(ArgumentError("nothing is plotted yet: run a simulation first (`studio_press!(:run)`)"))
    plot === :all && return axes
    (plot isa Integer && !(plot isa Bool) && 1 <= plot <= length(axes)) ||
        throw(ArgumentError("plot = $(repr(plot)): there are $(length(axes)) plot(s); use 1…$(length(axes)) or :all"))
    return Any[axes[plot]]
end

# The shown limits of an axis: one (lo, hi) per axis direction (2 for `Axis`, 3 for `Axis3`).
function _view_limits(ax)
    l = ax.finallimits[]
    return [(Float64(l.origin[d]), Float64(l.origin[d] + l.widths[d])) for d in 1:length(l.origin)]
end

_is_log(ax, d) = ax isa Axis && (d == 1 ? ax.xscale[] : ax.yscale[]) === log10

function _check_view_limits(ax, lims)
    for (d, (lo, hi)) in enumerate(lims)
        (isfinite(lo) && isfinite(hi) && lo < hi) ||
            throw(ArgumentError("limits ($lo, $hi) of the $("xyz"[d]) axis: two finite numbers, the lower one first"))
        _is_log(ax, d) && lo <= 0 && throw(ArgumentError("the $("xyz"[d]) axis has a log scale: its limits must be positive"))
    end
    return nothing
end

# Applies new limits to the axes (`plan`: axis => limits), after checking all of them (an invalid one changes none).
function _apply_view!(plan)
    for (ax, lims) in plan
        _check_view_limits(ax, lims)
    end
    for (ax, lims) in plan
        limits!(ax, Float64[v for l in lims for v in l]...)
    end
    return nothing
end

# What a view set by the API belongs to: when the plotted variables, the style or the comparison change, the limits
# of the old view would show the wrong range, so `studio_set!` releases the view (see `_release_stale_view!`).
_view_context() = (style = manager.widgets[:plot_style].selection[], mode = manager.mode[],
                   axes = Tuple(_menu_value(k) for k in PLOT_AXIS_OPTIONS),
                   compare = first(manager.compare_state), plots = length(_plot_axes()))

# Keeps the view the API set: the camera lock (the *Lock Camera* button) re-applies it after every data update.
function _lock_view!(msg::AbstractString)
    manager.camera_locked[] = true
    extract_and_store_camera_state!(_plot_layout())
    manager.view_context = (context = _view_context(),)   # (cleared by the Lock Camera button and loaded cameras)
    _status!(msg * " (camera locked: `studio_reset_view!()` or Lock Camera releases it)", :info)
    return nothing
end

# Whether the camera is locked to a view the API set (not taken over by the Lock Camera button or a loaded camera)
_api_view_locked() = manager.camera_locked[] && !isnothing(manager.view_context)

# After changes of the plotted variables, the style or the comparison: releases a view the API set (it belonged to
# the old plot). Returns whether it did.
function _release_stale_view!()
    _api_view_locked() || return false
    manager.view_context.context == _view_context() && return false
    studio_reset_view!()
    return true
end

# --- the camera ------------------------------------------------------------------------------------------------

_limits_arg(v, name) = isnothing(v) ? nothing :
    (v isa Union{Tuple, AbstractVector} && length(v) == 2 && all(x -> x isa Real, v)) ? (Float64(v[1]), Float64(v[2])) :
    throw(ArgumentError("$name = $(repr(v)): give the limits as (lo, hi)"))

"""
    studio_view!(; plot = :all, xlims = nothing, ylims = nothing, zlims = nothing, azimuth = nothing, elevation = nothing)

Sets what the plots show: the limits of their axes (`(lo, hi)` in data coordinates) and, for 3D plots, the camera
angles in degrees (`azimuth` around the vertical axis, `elevation` above the horizontal plane). Arguments left at
`nothing` keep their current value; `plot` selects one subplot (1, 2, … as in [`studio_state`](@ref)) or `:all`.
The view stays while sliders move and the data updates (the camera is locked, as with *Lock Camera*), until the
plotted variables, the plot style or the comparison change, or [`studio_reset_view!`](@ref) returns to the automatic
view. Returns the new limits per subplot.

```julia
studio_view!(xlims = (0, 1), ylims = (-0.1, 1.1))        # a 2D plot
studio_view!(azimuth = 30, elevation = 20)                 # a 3D plot from another side
studio_view!(plot = 2, zlims = (0, 0.5))                   # the second subplot only
```
"""
function studio_view!(; plot = :all, xlims = nothing, ylims = nothing, zlims = nothing, azimuth = nothing,
                      elevation = nothing)
    axes = _selected_axes(plot)
    want = (_limits_arg(xlims, :xlims), _limits_arg(ylims, :ylims), _limits_arg(zlims, :zlims))
    angles = !isnothing(azimuth) || !isnothing(elevation)
    for (name, a) in ((:azimuth, azimuth), (:elevation, elevation))
        isnothing(a) || (a isa Real && isfinite(a)) || throw(ArgumentError("$name = $(repr(a)): a finite number of degrees"))
    end
    !isnothing(want[3]) && !any(ax -> ax isa Axis3, axes) &&
        throw(ArgumentError("zlims: the selected plot(s) are 2D (only 3D plots have a z axis)"))
    angles && !any(ax -> ax isa Axis3, axes) &&
        throw(ArgumentError("azimuth / elevation: the selected plot(s) are 2D; move them with xlims / ylims, " *
                            "studio_zoom! or studio_pan!"))
    plan = map(axes) do ax
        lims = _view_limits(ax)
        for d in eachindex(lims)
            isnothing(want[d]) || (lims[d] = want[d])
        end
        ax => lims
    end
    _apply_view!(plan)
    for ax in axes
        ax isa Axis3 || continue
        isnothing(azimuth) || (ax.azimuth[] = deg2rad(Float64(azimuth)))
        isnothing(elevation) || (ax.elevation[] = deg2rad(clamp(Float64(elevation), -90.0, 90.0)))
    end
    _lock_view!("View set")
    return _view_summary()
end

"""
    studio_zoom!(factor = 2; plot = :all, center = nothing, dims = :all)

Zooms the plots in (`factor > 1`) or out (`factor < 1`): the shown range of each axis shrinks by `factor` around
`center` (a tuple of data coordinates, one per axis direction) or around the middle of the current view. `dims`
restricts the zoom to some axis directions (`:x`, `(:x, :y)`, …; log-scaled axes zoom on the log scale). Zooming a
3D plot narrows its limits, so what lies outside is cut off, as when zooming with the mouse. The view stays when the
data updates (see [`studio_view!`](@ref)). Returns the new limits per subplot.

```julia
studio_zoom!(4)                              # 4× closer, around the middle
studio_zoom!(2; center = (1.5, 0.3))        # around a point of interest
studio_zoom!(0.5; dims = :y)                 # show twice the y range
```
"""
function studio_zoom!(factor::Real = 2; plot = :all, center = nothing, dims = :all)
    (isfinite(factor) && factor > 0) || throw(ArgumentError("factor = $factor: a positive number (> 1 zooms in)"))
    axes = _selected_axes(plot)
    sel = _zoom_dims(dims)
    any(ax -> any(d -> d in sel, eachindex(_view_limits(ax))), axes) ||
        throw(ArgumentError("dims = $(repr(dims)): the selected plot(s) have no such axis (2D plots have x and y)"))
    plan = map(axes) do ax
        lims = _view_limits(ax)
        for d in eachindex(lims)
            d in sel || continue
            log = _is_log(ax, d)
            lo, hi = log ? log10.(lims[d]) : lims[d]
            c = isnothing(center) ? (lo + hi) / 2 : _center_coordinate(center, d, log)
            half = (hi - lo) / (2 * factor)
            lims[d] = log ? (10^(c - half), 10^(c + half)) : (c - half, c + half)
        end
        ax => lims
    end
    _apply_view!(plan)
    _lock_view!(factor >= 1 ? "Zoomed in ×$(_fmt_value(factor))" : "Zoomed out ×$(_fmt_value(1 / factor))")
    return _view_summary()
end

function _zoom_dims(dims)
    dims === :all && return (1, 2, 3)
    ds = dims isa Symbol ? (dims,) : Tuple(dims)
    all(d -> d in (:x, :y, :z), ds) || throw(ArgumentError("dims = $(repr(dims)): :all, or some of :x, :y, :z"))
    return Tuple(findfirst(==(d), (:x, :y, :z)) for d in ds)
end

function _center_coordinate(center, d, log)
    (center isa Union{Tuple, AbstractVector} && all(x -> x isa Real && isfinite(x), center)) ||
        throw(ArgumentError("center = $(repr(center)): a tuple of finite data coordinates, e.g. (x, y)"))
    d <= length(center) || throw(ArgumentError("center = $(repr(center)) has no coordinate for the $("xyz"[d]) axis"))
    c = Float64(center[d])
    log && c <= 0 && throw(ArgumentError("center: the $("xyz"[d]) axis has a log scale, the coordinate must be positive"))
    return log ? log10(c) : c
end

"""
    studio_pan!(dx, dy = 0, dz = 0; plot = :all)

Moves the shown part of the plots by fractions of the current view: `studio_pan!(0.25)` shows what lies a quarter
of the view width to the right, `studio_pan!(0, -0.5)` half a view height further down (`dz` for 3D plots).
Log-scaled axes move on the log scale. The view stays when the data updates (see [`studio_view!`](@ref)).
Returns the new limits per subplot.
"""
function studio_pan!(dx::Real, dy::Real = 0, dz::Real = 0; plot = :all)
    all(isfinite, (dx, dy, dz)) || throw(ArgumentError("studio_pan!: finite fractions of the view"))
    axes = _selected_axes(plot)
    shift = (Float64(dx), Float64(dy), Float64(dz))
    dz != 0 && !any(ax -> ax isa Axis3, axes) && throw(ArgumentError("dz: the selected plot(s) are 2D"))
    plan = map(axes) do ax
        lims = _view_limits(ax)
        for d in eachindex(lims)
            shift[d] == 0 && continue
            log = _is_log(ax, d)
            lo, hi = log ? log10.(lims[d]) : lims[d]
            step = shift[d] * (hi - lo)
            lims[d] = log ? (10^(lo + step), 10^(hi + step)) : (lo + step, hi + step)
        end
        ax => lims
    end
    _apply_view!(plan)
    _lock_view!("View moved")
    return _view_summary()
end

"""
    studio_rotate!(dazimuth, delevation = 0; plot = :all)

Turns the camera of the 3D plots by `dazimuth` degrees around the vertical axis and `delevation` degrees up (the
elevation stays within ±90°). 2D plots don't rotate; with `plot = :all` they are skipped. The view stays when the
data updates (see [`studio_view!`](@ref)). Returns the new limits and angles per subplot.
"""
function studio_rotate!(dazimuth::Real, delevation::Real = 0; plot = :all)
    all(isfinite, (dazimuth, delevation)) || throw(ArgumentError("studio_rotate!: finite angles in degrees"))
    axes = filter(ax -> ax isa Axis3, _selected_axes(plot))
    isempty(axes) && throw(ArgumentError("studio_rotate!: the selected plot(s) are 2D (only 3D plots rotate); " *
                                         "use studio_pan! / studio_zoom! / studio_view!"))
    for ax in axes
        ax.azimuth[] = deg2rad(mod(rad2deg(ax.azimuth[]) + Float64(dazimuth), 360.0))
        ax.elevation[] = deg2rad(clamp(rad2deg(ax.elevation[]) + Float64(delevation), -90.0, 90.0))
    end
    _lock_view!("Camera turned")
    return _view_summary()
end

# Makie's default camera of an `Axis3`
const _DEFAULT_AZIMUTH, _DEFAULT_ELEVATION = 1.275π, π / 8

"""
    studio_reset_view!()

Returns all plots to the automatic view: the limits follow the data again (also after the data changes), 3D plots
get the default camera angles, and the camera lock is released.
"""
function studio_reset_view!()
    axes = _plot_axes()
    manager.camera_locked[] = false
    manager.camera_cache = Dict{Symbol, Any}()
    manager.view_context = nothing
    for ax in axes
        if ax isa Axis3
            ax.azimuth[], ax.elevation[] = _DEFAULT_AZIMUTH, _DEFAULT_ELEVATION
            ax.limits[] = (nothing, nothing, nothing)
            reset_limits!(ax)
        else
            autolimits!(ax)   # (the data step below sets the studio's limits where it computes them)
        end
    end
    manager.triggers[:PlotData][] += 1   # recomputes the automatic limits of the 2D plots
    _status!("View reset: the plots follow the data.", :info)
    return isempty(axes) ? NamedTuple[] : _view_summary()
end

function _view_summary()
    return [_axis_view(i, ax) for (i, ax) in enumerate(_plot_axes())]
end

function _axis_view(i, ax)
    lims = _view_limits(ax)
    if ax isa Axis3
        return (plot = i, xlims = lims[1], ylims = lims[2], zlims = lims[3],
                azimuth = round(mod(rad2deg(ax.azimuth[]), 360.0), digits = 2),
                elevation = round(rad2deg(ax.elevation[]), digits = 2))
    end
    return (plot = i, xlims = lims[1], ylims = lims[2])
end

# --- looking at the window -------------------------------------------------------------------------------------

"""
    studio_snapshot(path = nothing; plot = :all, area = :plots, px_per_unit = 1) -> String

Renders what the studio shows to a PNG file and returns its path (by default a new file in
`<save path>/snapshots/`), without changing the window. `area = :plots` gives the plot grid (with colorbars and
legends), `:window` the whole studio with the control panel, as a person sees it; `plot = i` gives subplot `i` with
its axis labels, title and its own colorbar or legend. `px_per_unit` scales the image (2 for twice the resolution).

A GLMakie window renders the snapshot itself; otherwise (without a display, see [`studio_headless!`](@ref), or in a
browser) CairoMakie renders it. CairoMakie can't draw volumes: a snapshot of a volume plot then shows the empty
axes, and the status line warns about it.

```julia
studio_snapshot()                          # the plots, e.g. "…/snapshots/studio_2026-11-09_14-03-12-123_1.png"
studio_snapshot("overview.png"; area = :window)
studio_snapshot("detail.png"; plot = 2, px_per_unit = 2)
```
"""
function studio_snapshot(path::Union{Nothing, AbstractString} = nothing; plot = :all, area::Symbol = :plots,
                         px_per_unit::Real = 1)
    fig = _studio_window()
    area in (:plots, :window) || throw(ArgumentError("area = $(repr(area)): :plots or :window"))
    (isfinite(px_per_unit) && px_per_unit > 0) || throw(ArgumentError("px_per_unit = $px_per_unit: a positive number"))
    area === :window && plot !== :all && throw(ArgumentError("plot = $(repr(plot)) needs area = :plots"))
    isnothing(path) || splitext(path)[2] == ".png" ||
        throw(ArgumentError("studio_snapshot writes PNG files: give a path ending in .png, got $(repr(path))"))
    box = area === :window ? nothing : plot === :all ?
          _union_box(_plot_layout().layoutobservables.computedbbox[], (_drawn_box(ax) for ax in _plot_axes())...) :
          _subplot_box(only(_selected_axes(plot)))
    img, renderer = _render_window(fig, Float64(px_per_unit))
    isnothing(box) || (img = _crop(img, box, fig, _controls_right(fig); margin = plot === :all ? 6 : 3))
    file = something(path, joinpath(get_save_path(), "snapshots",
                                    "studio_" * Dates.format(Dates.now(), "yyyy-mm-dd_HH-MM-SS-sss") *
                                    "_$(_SNAPSHOTS[] += 1).png"))
    isempty(dirname(file)) || mkpath(dirname(file))
    Makie.FileIO.save(file, img)
    if renderer === :CairoMakie && manager.active_plot_type === :volume_3d   # (the drawn style)
        _status!("Snapshot: CairoMakie can't draw volumes, the image shows the empty axes (use GLMakie for volumes).", :warn)
    end
    return String(file)
end

const _SNAPSHOTS = Ref(0)   # (numbers the default file names: two snapshots in the same millisecond)

_backend_name() = (b = Makie.current_backend(); ismissing(b) || isnothing(b) ? :none : Symbol(nameof(b)))

# An image of the whole window: rendered by GLMakie if that shows it (it draws everything, also volumes, and
# CairoMakie can't render some plots GLMakie has prepared), by CairoMakie otherwise (no display, or a browser).
function _render_window(fig, ppu)
    screen = Makie.getscreen(fig.scene)
    shown_by = isnothing(screen) ? _backend_name() : Symbol(nameof(parentmodule(typeof(screen))))
    renderer = _backend_name() === :GLMakie ? :GLMakie : :CairoMakie
    try
        renderer === :CairoMakie && return Makie.colorbuffer(fig; backend = CairoMakie, px_per_unit = ppu), :CairoMakie
        # (the window's screen renders it: keep its own resolution, e.g. a HiDPI window)
        own = screen isa Makie.MakieScreen && hasproperty(screen, :px_per_unit) ? screen.px_per_unit[] : nothing
        try
            return Makie.colorbuffer(fig; px_per_unit = ppu), :GLMakie
        finally
            isnothing(own) || screen.px_per_unit[] == own || (screen.px_per_unit[] = own)
        end
    catch e
        e isa InterruptException && rethrow()
        throw(ErrorException("$renderer could not render the studio, which $shown_by has drawn " *
                             "($(_short(sprint(showerror, e), 120))). Choose the backend before opening the studio: " *
                             "reset_plotter!(), then studio_headless!() or GLMakie.activate!(), then launch_plotter(…)"))
    end
end

# The box of a block with its decorations (labels, title, tick labels) in figure coordinates.
function _axis_box(ax)
    bb = ax.layoutobservables.computedbbox[]
    p = ax.layoutobservables.protrusions[]   # (left, right, bottom, top)
    return Rect2f(bb.origin[1] - p.left, bb.origin[2] - p.bottom, bb.widths[1] + p.left + p.right,
                  bb.widths[2] + p.bottom + p.top)
end

# A subplot with its decorations and its own colorbars and legends: those next to it, closer to it than to any other
# subplot (a colorbar shared by the grid is not part of one subplot).
function _subplot_box(ax)
    axes = _plot_axes()
    center(b) = (bb = b.layoutobservables.computedbbox[]; (bb.origin[1] + bb.widths[1] / 2, bb.origin[2] + bb.widths[2] / 2))
    dist(a, b) = (ca = center(a); cb = center(b); hypot(ca[1] - cb[1], ca[2] - cb[2]))
    own = Any[]
    for c in _plot_layout().content
        b = c.content
        b isa Union{Colorbar, Legend} || continue
        nearest = argmin(a -> dist(a, b), axes)
        nearest === ax || continue
        bb, ab = b.layoutobservables.computedbbox[], ax.layoutobservables.computedbbox[]
        overlap = min(bb.origin[2] + bb.widths[2], ab.origin[2] + ab.widths[2]) - max(bb.origin[2], ab.origin[2])
        overlap > 0.5 * min(bb.widths[2], ab.widths[2]) && push!(own, b)   # (beside it, not a row below)
    end
    return _union_box(_axis_box(ax), _drawn_box(ax), (_axis_box(b) for b in own)...)
end

# What a 2D axis draws in the figure (decorations included, e.g. a title wider than the plot); `nothing` if unknown
# and for 3D axes (they draw their decorations inside their box, and the box of their scene is not in pixels).
function _drawn_box(ax)
    ax isa Axis || return nothing
    bb = try
        Makie.boundingbox(ax.blockscene)
    catch
        return nothing
    end
    all(isfinite, bb.origin) && all(isfinite, bb.widths) || return nothing
    return Rect2f(bb.origin[1], bb.origin[2], bb.widths[1], bb.widths[2])
end

# The right edge of the control panel in figure coordinates (crops stay right of it: a long title can reach into it)
function _controls_right(fig)
    cs = Makie.GridLayoutBase.contents(fig[1, 1])
    i = findfirst(c -> c isa GridLayout, cs)
    isnothing(i) && return -Inf
    cb = cs[i].layoutobservables.computedbbox[]
    return Float64(cb.origin[1] + cb.widths[1])
end

function _union_box(boxes...)
    bs = [b for b in boxes if !isnothing(b)]
    lo = (minimum(b -> b.origin[1], bs), minimum(b -> b.origin[2], bs))
    hi = (maximum(b -> b.origin[1] + b.widths[1], bs), maximum(b -> b.origin[2] + b.widths[2], bs))
    return Rect2f(lo[1], lo[2], hi[1] - lo[1], hi[2] - lo[2])
end

# Cuts the box (figure coordinates, origin bottom left) out of an image of the whole figure (first index: rows
# from the top), with a few pixels of margin, but not left of `left_limit`.
function _crop(img, box, fig, left_limit = -Inf; margin = 6)
    h, w = size(img)
    s = w / fig.scene.viewport[].widths[1]   # pixels per figure unit
    x0 = clamp(max(floor(Int, (box.origin[1] - margin) * s), isfinite(left_limit) ? ceil(Int, left_limit * s) + 2 : 0) + 1, 1, w)
    x1 = clamp(ceil(Int, (box.origin[1] + box.widths[1] + margin) * s), x0, w)
    r0 = clamp(h - ceil(Int, (box.origin[2] + box.widths[2] + margin) * s) + 1, 1, h)
    r1 = clamp(h - floor(Int, (box.origin[2] - margin) * s), r0, h)
    return img[r0:r1, x0:x1]
end

# --- what is shown ---------------------------------------------------------------------------------------------

const _STATUS_LEVELS = Dict(v => k for (k, v) in STATUS_COLORS)

# The status line as one line of text (the window wraps it)
_status_text() = replace(String(manager.widgets[:status][]), '\n' => ' ')

_menu_value(key) = haskey(manager.widgets, key) ? manager.widgets[key].selection[] : nothing

# The finite range of the plotted values in `x` (numbers, arrays of numbers or of small vectors), or `nothing`.
function _finite_range(x)
    lo, hi = Inf, -Inf
    for v in _numbers(x)
        isfinite(v) || continue
        lo, hi = min(lo, v), max(hi, v)
    end
    return lo <= hi ? (lo, hi) : nothing
end
_numbers(x::Real) = (Float64(x),)
_numbers(x::AbstractArray{<:Real}) = (Float64(v) for v in x)
_numbers(x::AbstractArray) = (Float64(v) for e in x for v in _numbers(e))
_numbers(x::Union{Tuple, StaticArray, Makie.VecTypes}) = (Float64(v) for v in x if v isa Real)
_numbers(x) = ()

"""
    studio_state() -> NamedTuple

What the studio shows, as data (the same as [`describe_studio`](@ref) prints): the status line, the bound
configuration (solver, methods, swept parameters), the plot style and the variables on the axes, the comparison,
the sliders, and per subplot its title, axis labels, shown limits (and 3D camera angles in degrees) and the range of
the plotted values per method. Use it to check the result of an action; [`studio_data`](@ref) gives the plotted
numbers themselves.
"""
function studio_state()
    fig = _studio_window()
    w = manager.widgets
    config = manager.active_config
    status = (text = _status_text(), level = get(_STATUS_LEVELS, w[:status_color][], :info))
    cfg = isnothing(config) ? nothing :
        (solver = get(config.shared, :sim_func_name, nothing), methods = sort!(collect(keys(config.methods))),
         active_methods = copy(config.defaults),
         swept = Dict{Symbol, Any}(k => copy(v) for (k, v) in config.varied))
    style = _public_style(w[:plot_style].selection[])
    target, _, labels, _ = manager.compare_state
    return (
        backend = _backend_name(),
        window_size = Tuple(Int.(fig.scene.viewport[].widths)),
        status = status,
        config = cfg,
        drawn_methods = copy(manager.methods[]),
        style = style,
        style_dim = PLOT_DIM_MAP[_base_style(style)],
        axes = (x = _menu_value(:x_axis), y = _menu_value(:y_axis), z = _menu_value(:z_axis),
                u = _menu_value(:u_axis), component = _menu_value(:component)),
        compare = (target = target, plots = copy(labels)),
        camera_locked = manager.camera_locked[],
        pending = [k for k in (:Simulation, :Layout, :Plot) if manager.flags[k][]],
        sliders = [_slider_state(key) for key in _shown_sliders()],
        plots = [_plot_state(i, ax) for (i, ax) in enumerate(_plot_axes())],
    )
end

# The sliders the window shows: those with a choice to make (not a plot axis, not the compare target, more than one
# value; see `_sync_slider_rows!`)
_shown_sliders() = [k for k in _slider_keys() if haskey(manager.widgets, k) && length(manager.widgets[k].range[]) > 1]

function _slider_state(key)
    sl = manager.widgets[key]
    name = get(manager.param_map, key, key)
    raw = sl.value[]
    vals = _param_values(key)
    # (a non-numeric sweep runs over the indices of its values: report the value, as `studio_set!` takes it)
    value = !isnothing(vals) && !_is_numeric_sweep(vals) ? vals[clamp(round(Int, raw), 1, length(vals))] : raw
    shown = startswith(String(key), "param_") ? _slider_value_text(key, raw) : _fmt_value(raw)
    choices = _slider_choices(key)
    return (name = name, value = value, shown = shown, range = (first(choices), last(choices), length(choices)))
end

function _plot_state(i, ax)
    caches = get(manager.caches, i, Dict{Symbol, AbstractPlotCache}())
    ranges = Dict{Symbol, Any}(m => _finite_range(c.obs_u[]) for (m, c) in caches)
    return merge(_axis_view(i, ax),
                 (title = string(ax.title[]), xlabel = string(ax.xlabel[]), ylabel = string(ax.ylabel[]),
                  zlabel = ax isa Axis3 ? string(ax.zlabel[]) : nothing, is_3d = ax isa Axis3, value_ranges = ranges))
end

"""
    describe_studio(io::IO = stdout)

Prints what the studio shows, for a person or an agent reading it: the status line, the configuration, the plot
style and the variables on the axes, every subplot (title, labels, shown limits, 3D camera, range of the plotted
values per method) and every control with its value and choices (the names [`studio_set!`](@ref) and
[`studio_press!`](@ref) take). [`studio_state`](@ref) returns the same as data.
"""
function describe_studio(io::IO = stdout)
    s = studio_state()
    println(io, "PDEStudio ($(s.backend), $(s.window_size[1])×$(s.window_size[2]) px)")
    println(io, "Status [$(s.status.level)]: ", s.status.text)
    isempty(s.pending) || println(io, "Pending: ", join(("$k (press :$(_pending_button(k)))" for k in s.pending), ", "))
    if isnothing(s.config)
        println(io, "Configuration: none (set_sim_config! or launch_plotter(config))")
    else
        c = s.config
        println(io, "Configuration: solver $(c.solver); methods $(join(c.methods, ", ")); active $(join(c.active_methods, ", "))")
        unslid = _unslid_parameters()
        for (k, v) in sort!(collect(c.swept), by = first)
            println(io, "  swept $k = ", _short(join(string.(v), ", "), 100),
                    k in unslid ? "  (no slider: the plots show the first value; set_max_params! opens more)" : "")
        end
    end
    a = s.axes
    println(io, "Plot: style $(s.style) ($(s.style_dim)D); x = $(a.x), y = $(a.y), z = $(a.z), u = $(a.u), component $(a.component)",
            s.compare.target === :none ? "" : "; compare $(s.compare.target): $(join(s.compare.plots, ", "))",
            s.camera_locked ? "; camera locked" : "")
    for p in s.plots
        lims = p.is_3d ? "x ∈ $(_fmt_lims(p.xlims)), y ∈ $(_fmt_lims(p.ylims)), z ∈ $(_fmt_lims(p.zlims)); " *
                         "azimuth $(p.azimuth)°, elevation $(p.elevation)°" :
                         "x ∈ $(_fmt_lims(p.xlims)), y ∈ $(_fmt_lims(p.ylims))"
        println(io, "  plot $(p.plot): \"$(p.title)\" [$(p.xlabel) | $(p.ylabel)$(p.is_3d ? " | " * p.zlabel : "")] $lims")
        for (m, r) in sort!(collect(p.value_ranges), by = first)
            println(io, "    $m: values ", isnothing(r) ? "none" : _fmt_lims(r))
        end
        if length(p.value_ranges) == 1 && length(s.drawn_methods) > 1 && :method_index in get(STYLE_DEPENDENCIES, _base_style(s.style), Symbol[])
            order = [filter(m -> !is_reference_method(m), s.drawn_methods); filter(is_reference_method, s.drawn_methods)]
            println(io, "    (this style shows one method: $(only(keys(p.value_ranges))); " *
                        "studio_option!(:plot_style, :method_index, i) shows " *
                        join(("$i = $m" for (i, m) in enumerate(order)), ", ") * ")")
        end
    end
    println(io, "Controls (studio_set! / studio_press!):")
    for c in studio_controls()
        println(io, "  ", _control_line(c))
    end
    return nothing
end

function _slider_choice_text(vals)
    length(vals) <= 12 && return join((v isa Real ? _fmt_value(v) : repr(v) for v in vals), ", ")
    return "$(length(vals)) values, $(_fmt_value(first(vals))) … $(_fmt_value(last(vals)))"
end

_pending_button(k) = k === :Simulation ? :run : k === :Layout ? :apply_layout : :update_plot
_fmt_lims(l) = isnothing(l) ? "-" : "[$(_fmt_value(l[1])), $(_fmt_value(l[2]))]"

function _control_line(c)
    val = c.kind === :button ? "" : " = $(repr(c.value))"
    choices = c.kind === :slider ? "  (" * _slider_choice_text(c.choices) * ")" :
              isnothing(c.choices) ? "" : "  ∈ {" * _short(join(repr.(c.choices), ", "), c.kind === :style ? 1000 : 110) * "}"
    return "$(c.name) [$(c.kind)$(c.applies === :none ? "" : ", applies with :$(c.applies)")]$val$choices — $(c.label)"
end

# --- the controls ----------------------------------------------------------------------------------------------

# The buttons `studio_press!` takes, by name: (widget key, label)
const _STUDIO_BUTTONS = (run = (:run_button, "Run Simulation"), apply_layout = (:layout_apply, "Apply Layout"),
                         update_plot = (:plot_button, "Update Plot"), lock_camera = (:lock_camera_button, "Lock Camera"))
const _MENU_LABELS = Dict(:x_axis => "X-Axis", :y_axis => "Y-Axis", :z_axis => "Z-Axis", :u_axis => "dependent field",
                          :component => "component", :anim_target => "animation target", :compare_target => "Compare",
                          :compare_link => "Compare Link", :legend_base => "Legend", :legend_add => "Legend Placement")
const _NUMBER_LABELS = Dict(:plot_width => "Plot Width (px)", :plot_height => "Plot Height (px)",
                            :compare_columns => "Grid Columns")

# The update a control needs: :update_plot (plot options), :apply_layout (layout options), :run (methods) or :none
_control_step(name) = name in PLOT_AXIS_OPTIONS ? :update_plot : name in LAYOUT_OPTIONS ? :apply_layout :
                      name === :methods ? :run : :none

"""
    studio_controls() -> Vector{NamedTuple}

The controls of the studio, as [`studio_set!`](@ref) and [`studio_press!`](@ref) take them: `(name, kind, value,
choices, label, applies)`, where `kind` is `:slider` (choices: the slider values), `:menu`, `:number` (choices:
`(lo, hi)`), `:style` (the plot styles the data allows), `:methods` (the methods of the configuration; the value is
the active ones, in drawing order) or `:button`, and `applies` the button that applies a change (`studio_set!`
presses it for you). Sliders are named by their parameter or dimension (e.g. `:N`, `:t`).
"""
function studio_controls()
    _studio_window()
    w = manager.widgets
    out = NamedTuple{(:name, :kind, :value, :choices, :label, :applies)}[]
    push!(out, (name = :plot_style, kind = :style, value = _public_style(w[:plot_style].selection[]),
                choices = _style_choices(), label = "plot style (`launch_plotter(; style)` names)", applies = :apply_layout))
    for key in (:x_axis, :y_axis, :z_axis, :u_axis, :component, :anim_target, :compare_target, :compare_link,
                :legend_base, :legend_add)
        haskey(w, key) || continue
        push!(out, (name = key, kind = :menu, value = w[key].selection[], choices = Any[o[2] for o in w[key].options[]],
                    label = _MENU_LABELS[key], applies = _control_step(key)))
    end
    for key in (:plot_width, :plot_height, :compare_columns)
        haskey(w, key) || continue
        nb = w[key]
        push!(out, (name = key, kind = :number, value = nb.selection[], choices = (nb.lo, nb.hi),
                    label = _NUMBER_LABELS[key], applies = :apply_layout))
    end
    config = manager.active_config
    isnothing(config) || push!(out, (name = :methods, kind = :methods, value = copy(config.defaults),
                                     choices = sort!(collect(keys(config.methods))),
                                     label = "active methods, in drawing order", applies = :run))
    for key in _shown_sliders()
        st = _slider_state(key)
        push!(out, (name = st.name, kind = :slider, value = st.value, choices = _slider_choices(key),
                    label = startswith(String(key), "param_") ? "swept parameter (shown: $(st.shown))" : "dimension",
                    applies = :none))
    end
    for (name, (key, label)) in pairs(_STUDIO_BUTTONS)
        haskey(w, key) && push!(out, (name = name, kind = :button, value = nothing, choices = nothing, label = label,
                                      applies = :none))
    end
    return out
end

# The plot styles the data allows, by their user-facing names: what the page of all plot styles offers (the grid
# styles, and the particle styles matching the dimension of the particles)
function _style_choices()
    grid = Symbol[o[2] for b in (:lines, :scatter, :contour, :heatmap, :volume) for o in EULERIAN_PLOT_STYLE_OPTIONS[b]]
    manager.mode[] === :eulerian && !isempty(manager.allowed_styles) && filter!(in(manager.allowed_styles), grid)
    return Symbol[grid; _particle_styles_for_data()]
end

# The values a slider offers: its numbers, or the swept values of a non-numeric parameter
function _slider_choices(key)
    rng = collect(manager.widgets[key].range[])
    vals = _param_values(key)
    return isnothing(vals) || _is_numeric_sweep(vals) ? rng : vals
end

# The swept values of the parameter behind a parameter slider (`nothing` for dimension sliders)
function _param_values(key)
    param = get(manager.param_map, key, nothing)
    (isnothing(param) || isempty(manager.plot_data[])) && return nothing
    pd = first(values(manager.plot_data[]))
    i = findfirst(==(param), pd.active_param_keys)
    return isnothing(i) ? nothing : pd.active_param_values[i]
end

"""
    studio_set!(name => value, ...; apply = true) -> NamedTuple

Sets controls of the studio, as a person would in the window, and applies them: sliders (by parameter or dimension
name, e.g. `:N => 128` or `:t => 1.5`; the nearest slider value is taken, non-numeric sweeps by their value), menus
(`:x_axis => :t`, `:u_axis => :l2error`, `:compare_target => :methods`, … by value or label), the plot style
(`:plot_style => :heatmap_surface`, also groups such as `:contour`), the numbers of the layout (`:plot_width => 600`)
and the active methods (`:methods => [:upwind, :exact]`). See [`studio_controls`](@ref) for the names, values and
choices. With `apply = true` the button a change needs is pressed afterwards (*Update Plot*, *Apply Layout* or *Run
Simulation*, once for all changes, also if a change made before is still pending). Invalid names or values throw an
`ArgumentError` that lists the valid ones. Returns `(values, status)`: the value each control has now and the status
line.

```julia
studio_set!(:plot_style => :heatmap, :x_axis => :x, :y_axis => :t)
studio_set!(:N => 128)
studio_set!(:compare_target => :methods, :compare_columns => 3)
```
"""
function studio_set!(changes::Pair...; apply::Bool = true)
    _studio_window()
    isempty(changes) && throw(ArgumentError("studio_set!(name => value, ...): nothing to set (see studio_controls())"))
    steps = Symbol[]
    names = Symbol[]
    before, failures = _status_text(), manager.render_failures
    for (name, value) in changes
        n = Symbol(name)
        push!(steps, _set_control!(n, value))
        push!(names, n)
    end
    pressed = apply ? _apply_steps!(steps) : nothing
    reported = _status_text() != before || manager.render_failures != failures ?
               (manager.widgets[:status][], manager.widgets[:status_color][]) : nothing
    released = apply && _release_stale_view!()   # (a view set by the API showed the old variables)
    # (the status line tells the person at the window what happened, unless the step reported something itself)
    if isnothing(reported)
        _status!("Set " * join(("$(first(c)) = $(_short(repr(last(c)), 30))" for c in changes), ", ") *
                 (isnothing(pressed) ? (any(!=(:none), steps) ? " (not applied yet)" : "") : " ($pressed)") *
                 (released ? "; the view set before follows the data again" : "") * ".", :ok)
    else
        manager.widgets[:status][], manager.widgets[:status_color][] = reported
    end
    now = Dict{Symbol, Any}(c.name => c.value for c in studio_controls() if c.name in names)
    return (values = now, status = _status_text())
end

function _apply_steps!(steps)
    f = manager.flags
    needs(step, flag) = step in steps || f[flag][]
    any(!=(:none), steps) || return nothing
    button = needs(:run, :Simulation) ? :run : needs(:apply_layout, :Layout) ? :apply_layout :
             needs(:update_plot, :Plot) ? :update_plot : nothing
    isnothing(button) || _press!(button)   # (`studio_set!` releases a stale view itself)
    return button
end

function _set_control!(name::Symbol, value)
    w = manager.widgets
    name === :plot_style && return _set_style_control!(value)
    name === :methods && return _set_methods_control!(value)
    if name in keys(_MENU_LABELS) && haskey(w, name)
        _set_menu_control!(name, w[name], value)
        return _control_step(name)
    end
    if name in keys(_NUMBER_LABELS) && haskey(w, name)
        nb = w[name]
        (value isa Integer && nb.lo <= value <= nb.hi) ||
            throw(ArgumentError("$name = $(repr(value)): a whole number from $(nb.lo) to $(nb.hi)"))
        _set_number!(nb, value)
        return :apply_layout
    end
    key = _slider_key(name)
    name in _unslid_parameters() && throw(ArgumentError("parameter :$name is swept but has no slider: the window has " *
        "$(manager.max_params) parameter slider(s) and draws its first value; open the studio with more (set_max_params!(" *
        "$(manager.max_params + length(_unslid_parameters()))) before launch_plotter)"))
    isnothing(key) && throw(ArgumentError("studio_set!: no control named :$name; controls: " *
                                          join((repr(c.name) for c in studio_controls() if c.kind !== :button), ", ")))
    _set_slider_control!(name, key, value)
    return :none
end

# The swept parameters without a slider (more than `max_params`; the plot shows their first value)
function _unslid_parameters()
    config = manager.active_config
    isnothing(config) && return Symbol[]
    return Symbol[k for k in keys(config.varied) if !(k in values(manager.param_map))]
end

# The widget key of a slider named by its parameter, its dimension or its key (`:param_1`)
function _slider_key(name)
    key = get(manager.reverse_map, name, name)
    return key in _slider_keys() && haskey(manager.widgets, key) && manager.widgets[key] isa Makie.Slider ? key : nothing
end

function _set_slider_control!(name, key, value)
    sl = manager.widgets[key]
    rng = collect(sl.range[])
    length(rng) > 1 || throw(ArgumentError("slider :$name is disabled: it is a plot axis or the compare target, or the " *
                                           "data has a single value for it"))
    vals = _param_values(key)
    target = if !isnothing(vals) && !_is_numeric_sweep(vals)
        # a non-numeric sweep: the slider runs over the indices of its values
        i = findfirst(v -> isequal(v, value) || string(v) == string(value), vals)
        isnothing(i) && throw(ArgumentError("slider :$name has no value $(repr(value)); values: " * join(repr.(vals), ", ")))
        Float64(i)
    else
        value isa Real && isfinite(value) || throw(ArgumentError("slider :$name: a number, got $(repr(value))"))
        lo, hi = extrema(rng)
        tol = (hi - lo) / max(length(rng) - 1, 1) / 2
        (lo - tol <= value <= hi + tol) ||
            throw(ArgumentError("slider :$name = $value is outside its range $(_fmt_value(lo)) … $(_fmt_value(hi))"))
        Float64(value)
    end
    set_close_to!(sl, target)
    return nothing
end

function _set_menu_control!(name, menu, value)
    opts = menu.options[]
    i = findfirst(o -> isequal(o[2], value) || string(o[2]) == string(value), opts)
    isnothing(i) && value isa AbstractString &&
        (i = findfirst(o -> lowercase(string(o[1])) == lowercase(strip(value)), opts))
    isnothing(i) && throw(ArgumentError("$name has no option $(repr(value)); options: " *
                                        join(("$(repr(o[2])) (\"$(o[1])\")" for o in opts), ", ")))
    menu.i_selected[] == i || (menu.i_selected[] = i)
    return nothing
end

function _set_style_control!(value)
    style = value isa Symbol || value isa AbstractString ? Symbol(value) :
            throw(ArgumentError("plot_style: a style name such as :heatmap_flat, got $(repr(value))"))
    _is_plot_style_name(style) || throw(ArgumentError("plot_style = :$style is no plot style; styles: " *
                                                       join(repr.(_style_choices()), ", ")))
    public = _resolve_plot_style(style)
    public in _style_choices() || throw(ArgumentError("plot_style = :$public is not available for this data; " *
                                                       "available: " * join(repr.(_style_choices()), ", ")))
    _set_public_style!(manager.widgets[:plot_style], public)
    return :apply_layout
end

function _set_methods_control!(value)
    config = manager.active_config
    isnothing(config) && throw(ArgumentError("methods: no configuration is bound"))
    ms = value isa Union{Symbol, AbstractString} ? [Symbol(value)] :
         value isa Union{AbstractVector, Tuple} ? Symbol[Symbol(v) for v in value] :
         throw(ArgumentError("methods: a list of method names, got $(repr(value))"))
    isempty(ms) && throw(ArgumentError("methods: at least one method"))
    unknown = setdiff(ms, collect(keys(config.methods)))
    isempty(unknown) || throw(ArgumentError("methods: unknown $(join(repr.(unknown), ", ")); methods: " *
                                            join(repr.(sort!(collect(keys(config.methods)))), ", ")))
    if unique(ms) != config.defaults
        config.defaults = unique(ms)
        manager.flags[:Simulation][] = true
        _status!("Active methods: $(join(unique(ms), ", ")). Run Simulation to apply.", :ok)
    end
    return :run
end

"""
    studio_press!(name) -> String

Presses a button of the studio: `:run` (*Run Simulation*), `:apply_layout`, `:update_plot` or `:lock_camera`
(toggles the camera lock). The work is done when it returns; it returns the status line.
"""
function studio_press!(name::Symbol)
    _studio_window()
    haskey(_STUDIO_BUTTONS, name) ||
        throw(ArgumentError("studio_press!: no button :$name; buttons: " * join(repr.(keys(_STUDIO_BUTTONS)), ", ")))
    _press!(name)
    name in (:run, :apply_layout, :update_plot) && _release_stale_view!()   # (e.g. after `studio_set!(…; apply = false)`)
    return _status_text()
end

_press!(name::Symbol) = (manager.widgets[_STUDIO_BUTTONS[name][1]].clicks[] += 1; nothing)

# --- the look (the UI tab) -------------------------------------------------------------------------------------

"""
    studio_options([scope]) -> Dict

The options of the look (the *UI* tab), by scope: `:plot_style` (colours, colormap, line width, levels, …),
`:labels` (title and axis labels), `:axis_general` (font sizes), the axis scopes (`:x_axis_1d`, `:y_axis_1d` for 1D
plots, `:x_axis_nd`, `:y_axis_nd`, `:z_axis_3d` for 2D and 3D plots: log scale, limits, ticks, …), `:hud` and
`:outliers_extrema`. Returns a copy; change them with [`studio_option!`](@ref).
"""
function studio_options()
    return Dict{Symbol, Dict{Symbol, Any}}(s => deepcopy(manager.ui[s]) for s in UI_SCOPES if haskey(manager.ui, s) && s !== :export)
end
function studio_options(scope::Symbol)
    _check_ui_scope(scope)
    return deepcopy(manager.ui[scope])
end

function _check_ui_scope(scope)
    (scope !== :export && haskey(manager.ui, scope)) ||
        throw(ArgumentError("no option scope :$scope; scopes: " *
                            join(repr.(s for s in UI_SCOPES if haskey(manager.ui, s) && s !== :export), ", ")))
    return nothing
end

"""
    studio_option!(scope, key, value) -> String

Changes an option of the look, as the *UI* tab does (see [`studio_options`](@ref) for the scopes and keys), checked
like the tab's input, and redraws: e.g. `studio_option!(:plot_style, :color_map, :plasma)`,
`studio_option!(:y_axis_1d, :log_scale, true)` or `studio_option!(:labels, :title, "Advection")`. Returns the
status line.
"""
function studio_option!(scope::Symbol, key::Symbol, value)
    _studio_window()
    _check_ui_scope(scope)
    target = manager.ui[scope]
    haskey(target, key) || throw(ArgumentError("scope :$scope has no option :$key; options: " *
                                               join(repr.(sort!(collect(keys(target)))), ", ")))
    default = _option_default(scope, key, target[key])
    reason = something(_option_type_reason(key, default, value), Some(_invalid_ui_reason(key, value)))
    isnothing(reason) || throw(ArgumentError("$scope.$key = $(repr(value)) is not a valid $reason"))
    if key === :method_index
        n = length(manager.methods[])
        1 <= value <= max(n, 1) || throw(ArgumentError("method_index = $value: the studio draws $n method(s), give 1…$n"))
    end
    failures = manager.render_failures
    # (a list option takes a tuple as its list; a colour tuple such as (:red, 0.5) stays one colour)
    target[key] = value isa Tuple && default isa AbstractVector && !(key in _COLOR_UI_KEYS) ? collect(Any, value) : value
    _after_editor_change!(:ui, scope, key, target)
    # (a drawing that failed reports itself in the status line: keep that)
    manager.render_failures == failures && _status!(_change_message(:ui, scope, key, target), :ok)
    return _status_text()
end

# The built-in default of an option (its type is the type the option takes), or its current value for options
# without one
function _option_default(scope, key, current)
    template = scope in UI_AXIS_SCOPES ? MASTER_UI_DICT[scope] : get(MASTER_UI_DICT, scope, Dict{Symbol, Any}())
    return get(template, key, current)
end

# Options that count something: whole numbers only
const _WHOLE_NUMBER_OPTIONS = (:levels, :tick_count, :method_index, :bottom_margin, :animation_FPS, :dpi,
                               :rasterization_quality, :mp4_compression)

# Why `val` doesn't fit the option `key` whose default is `default` (the types the UI tab keeps), or `nothing`;
# colours and colormaps are checked by `_invalid_ui_reason`.
function _option_type_reason(key, default, val)
    key in (_COLOR_UI_KEYS..., :color_map) && return nothing
    old = default
    old isa Bool && return val isa Bool ? nothing : "true or false"
    key in _WHOLE_NUMBER_OPTIONS && return val isa Integer && !(val isa Bool) ? nothing : "whole number"
    old isa Real && return val isa Real && !(val isa Bool) && isfinite(val) ? nothing : "number"
    old isa AbstractString && return val isa AbstractString ? nothing : "text (a String)"
    old isa Symbol && return val isa Symbol ? nothing : "name (a Symbol, e.g. :$old)"
    old isa AbstractVector && return val isa Union{AbstractVector, Tuple} ? nothing : "list (a vector)"
    return nothing
end

# --- the plotted numbers ---------------------------------------------------------------------------------------

"""
    studio_data(plot = 1) -> NamedTuple

The numbers subplot `plot` draws, per method: `(plot, variables, methods)` where `variables` names what the axes
show (`x`, `y`, `z`, the dependent field `u` and its component) and `methods[m]` holds the drawn coordinates and
values of method `m` (`x`, `y`, `z`, `u` for grid data, `points` and `u` for particles), as plotted (after the
display resolution). Use it to compute with what is shown instead of reading it from an image.
"""
function studio_data(plot::Integer = 1)
    n = length(_plot_axes())
    1 <= plot <= n || throw(ArgumentError("plot = $plot: there are $n plot(s)"))
    caches = get(manager.caches, plot, Dict{Symbol, AbstractPlotCache}())
    data = Dict{Symbol, Any}()
    for (m, c) in caches
        data[m] = c isa EulerianPlotCache ?
            (x = deepcopy(c.obs_x[]), y = deepcopy(c.obs_y[]), z = deepcopy(c.obs_z[]), u = deepcopy(c.obs_u[])) :
            (points = deepcopy(c.obs_pts[]), u = deepcopy(c.obs_u[]))
    end
    a = studio_state().axes
    return (plot = plot, variables = a, methods = data)
end
