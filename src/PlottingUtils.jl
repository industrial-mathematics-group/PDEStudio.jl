"""
    sort_methods_robust(methods::AbstractVector)

Sorts method names, guaranteeing that analytical baselines or exact reference solutions are evaluated and drawn first.

Reference methods (as recognised by `PDEStudioCore.is_reference_method`, e.g. `:analytic`, `:exact_solution`) get priority rank `0`,
ensuring they appear at the bottom of Z-index stacks (behind numerical overlays) and at the top of Legends.
"""
function sort_methods_robust(methods::AbstractVector)
    syms = Symbol[Symbol(m) for m in methods]
    return sort(syms, by = m -> (is_reference_method(m) ? 0 : 1, string(m)))
end

# ------------------------------------------------------------------------------
# Value formatting & comparison helpers
# ------------------------------------------------------------------------------

# Maximum number of subplots a "compare over time / parameter" layout creates (values are subsampled evenly).
const MAX_COMPARE_PLOTS = 12

# Numbers in titles, slider labels and descriptions: 3 decimals, small and large values with 3 significant digits
# (τ = 1e-5, not 0.000; 0.0015, not 0.002; 0.0125, not 0.013). `sci = true` writes every value of a set
# scientifically (see `_sci_set`); a one-element tuple is its element, other tuples and vectors are written elementwise.
function _fmt_value(v; sci::Bool = false)
    v isa Union{Tuple, AbstractVector} && return _fmt_elements(x -> _fmt_value(x; sci), v)
    v isa AbstractFloat || return string(v)
    (iszero(v) || !isfinite(v)) && return @sprintf("%.3f", v)
    (sci || !(1e-3 <= abs(v) < 1e5)) && return _fmt_sci(v, 3)
    return abs(v) >= 0.1 ? @sprintf("%.3f", v) : @sprintf("%.3g", v)
end
# Values in compare titles: 4 significant digits, scientific outside [1e-3, 1e5) (τ = 1e-5, not 1.0e-5)
function _fmt_compare(v; sci::Bool = false)
    v isa Union{Tuple, AbstractVector} && return _fmt_elements(x -> _fmt_compare(x; sci), v)
    v isa AbstractFloat || return string(v)
    (iszero(v) || !isfinite(v)) && return string(v)
    (sci || !(1e-3 <= abs(v) < 1e5)) && return _fmt_sci(v, 4)
    return string(round(v, sigdigits = 4))
end

_fmt_elements(f, v) = length(v) == 1 ? f(only(v)) : "(" * join((f(x) for x in v), ", ") * ")"

# Scientific notation with up to `digits` significant digits and no padding: 1e-5, 2.5e6, -1.234e-7
_fmt_sci(v, digits) = _clean_exponent(replace(@sprintf("%.*e", digits - 1, v), r"\.?0+e" => "e"))

# "1e-05" -> "1e-5", "2.5e+06" -> "2.5e6"
_clean_exponent(s::AbstractString) = replace(s, r"e\+?(-?)0*(\d)" => s"e\1\2")

# Whether the values of a set (a parameter's sweep, the values of a comparison) are all written scientifically: if one
# of them needs it (1e-5, 1e-4, 1e-3 instead of 1e-5, 0.0001, 0.001)
_sci_set(vals) = any(_needs_sci, vals)
_needs_sci(v) = v isa Union{Tuple, AbstractVector} ? any(_needs_sci, v) :
                v isa AbstractFloat && isfinite(v) && !iszero(v) && !(1e-3 <= abs(v) < 1e5)

# Evenly spread indices into 1:n, at most MAX_COMPARE_PLOTS of them.
function _compare_picks(n::Int)
    n <= MAX_COMPARE_PLOTS && return collect(1:n)
    @info "Comparing $MAX_COMPARE_PLOTS of $n values (evenly spaced)."
    return unique(round.(Int, range(1, n, length = MAX_COMPARE_PLOTS)))
end

"""
    _compare_selection(text, vals, kind) -> Vector{Int}

The indices into `vals` a comparison shows for the text of *Compare Values* (`ValuesBox`): all of them for `"all"`
(evenly spread, see `_compare_picks`), otherwise the entries in the order given, each matched by `kind`: `:numbers`
the nearest value (swept values, times), `:components` a component number, `:names` a value, label or name
written as in the titles (methods, non-numeric sweeps) or its position (`2`). Entries that match nothing are reported in
the status line and left out; if none matches, all values are shown.
"""
function _compare_selection(text::AbstractString, vals::AbstractVector, kind::Symbol)
    (text == "all" || isempty(vals)) && return _compare_picks(length(vals))
    picks, unknown = Int[], String[]
    for item in split(text, ", ")
        i = _compare_match(String(item), vals, kind)
        isnothing(i) ? push!(unknown, String(item)) : (i in picks || push!(picks, i))
    end
    if !isempty(unknown)
        shown = kind === :names ? join((_fmt_compare(v) for v in vals), ", ") :
                kind === :components ? "1 … $(length(vals))" : "numbers"
        _report(:warn, "Compare Values: no match for $(join(repr.(unknown), ", ")) (values: $(_short(shown, 80)))" *
                       (isempty(picks) ? "; showing all." : "."))
    end
    isempty(picks) && return _compare_picks(length(vals))
    length(picks) > MAX_COMPARE_PLOTS && @info "Comparing the first $MAX_COMPARE_PLOTS of $(length(picks)) values."
    return picks[1:min(end, MAX_COMPARE_PLOTS)]
end

function _compare_match(item::String, vals, kind::Symbol)
    if kind === :numbers
        x = tryparse(Float64, item)
        return isnothing(x) || !isfinite(x) ? nothing : argmin(abs.(Float64.(vals) .- x))
    elseif kind === :components
        k = tryparse(Int, item)
        return !isnothing(k) && 1 <= k <= length(vals) ? k : nothing
    end
    i = findfirst(v -> item in (string(v), _fmt_compare(v), frontend_key(v)), vals)
    isnothing(i) || return i
    k = tryparse(Int, item)
    return !isnothing(k) && 1 <= k <= length(vals) ? k : nothing
end

# Value of a selector that has no slider widget: the first swept value (or its index for non-numeric sweeps).
function _fallback_selector_value(name::Symbol)
    config = manager.active_config
    if !isnothing(config) && haskey(config.varied, name) && !isempty(config.varied[name])
        vals = _shown_sweep_values(name, config.varied[name])
        return _is_numeric_sweep(vals) ? first(vals) : 1
    end
    return 0.0
end

# ------------------------------------------------------------------------------
# Export formats
# ------------------------------------------------------------------------------

# Extensions typed into the Name / path box of the Files tab: an animation format records an animation, a static format exports exactly
# that format, anything else is part of the name.
const ANIMATION_EXPORT_FORMATS = ("mp4", "gif", "webm", "mkv")
const STATIC_EXPORT_FORMATS = ("png", "pdf", "svg", "eps", "jpg", "jpeg")
# The plotted numbers instead of a figure (`studio_export_data`): a Markdown table (.md) or CSV (.csv, .txt)
const DATA_EXPORT_FORMATS = ("md", "csv", "txt")

"""
    _export_formats(setting)

Normalises the `save_formats` export setting (a vector, tuple or single entry, with or without leading dots) to a
list of lower-case static formats. Animation formats (which must be typed into the filename instead) and unknown
formats are dropped with a warning.
"""
function _export_formats(setting)
    items = (setting isa AbstractVector || setting isa Tuple) ? collect(setting) : [setting]
    fmts = String[lowercase(lstrip(strip(string(f)), '.')) for f in items if !isnothing(f)]
    anim = filter(in(ANIMATION_EXPORT_FORMATS), fmts)
    isempty(anim) || @warn "Animation formats $anim in the export settings are ignored. To export an animation, add the extension (e.g. '.mp4') to the filename instead."
    unknown = filter(f -> !(f in STATIC_EXPORT_FORMATS) && !(f in ANIMATION_EXPORT_FORMATS) && !(f in DATA_EXPORT_FORMATS) && !isempty(f), fmts)
    isempty(unknown) || @warn "Unknown export formats $unknown are ignored. Supported: $(join(STATIC_EXPORT_FORMATS, ", ")) " *
                              "and $(join(DATA_EXPORT_FORMATS, ", ")) (the plotted numbers)."
    return unique!(filter(f -> f in STATIC_EXPORT_FORMATS || f in DATA_EXPORT_FORMATS, fmts))
end

# A joint sweep of several parameters (`joint_sweep`: their names joined by `&`)
_is_joint_key(k) = k isa Symbol && length(split(String(k), '&')) > 1

# The value of a joint sweep with every parameter (`N = 40, IC Cell = 0.15`), for the shown value `shown` (its first
# entry, or the whole tuple, see `_shown_sweep_values`); `fmt` is `_fmt_value` or `_fmt_compare`, one notation per
# parameter over the sweep
function _joint_text(key::Symbol, shown, fmt)
    config = manager.active_config
    raw = isnothing(config) ? Any[] : collect(get(config.varied, key, Any[]))
    parts = Symbol.(split(String(key), '&'))
    i = findfirst(r -> r isa Tuple && length(r) == length(parts) && (isequal(r, shown) || isequal(first(r), shown)), raw)
    isnothing(i) && return "$(frontend_key(key)) = $(fmt(shown))"
    return join(("$(frontend_key(p)) = $(fmt(raw[i][j]; sci = _sci_set([r[j] for r in raw])))" for (j, p) in enumerate(parts)), ", ")
end

# The tuple of a joint sweep shown by its first entry `shown` (or `shown` itself), or `nothing`
function _joint_raw(key::Symbol, shown)
    config = manager.active_config
    raw = isnothing(config) ? Any[] : collect(get(config.varied, key, Any[]))
    i = findfirst(r -> r isa Tuple && (isequal(r, shown) || isequal(first(r), shown)), raw)
    return isnothing(i) ? nothing : raw[i]
end

# A swept value as titles, compared subplots and lines show it: its name (`set_value_label!`), every parameter of a
# joint sweep, or `parameter = value` (`fmt`: `_fmt_value` or `_fmt_compare`; `sci`: one notation for the sweep)
function _param_text(key::Symbol, v, fmt; sci::Bool = false)
    label = _value_label(key, v)
    isnothing(label) || return label
    _is_joint_key(key) && return _joint_text(key, v, fmt)
    return "$(frontend_key(key)) = $(fmt(v; sci))"
end

# Whether the values of the `i`-th parameter are written scientifically (all of them, see `_sci_set`)
function _param_sci(i::Int)
    data = manager.plot_data[]
    isempty(data) && return false
    pd = _primary_sweep(data)
    return i <= length(pd.active_param_values) && _sci_set(pd.active_param_values[i])
end

# Text next to a slider: the swept value for non-numeric parameters, the formatted number otherwise.
function _slider_value_text(widget_key::Symbol, v)
    param = get(manager.param_map, widget_key, nothing)
    if !isnothing(param)
        i = findfirst(isequal(param), manager.plot_vars)
        if !isnothing(i)
            shown = _param_display_value(i, v)
            return something(_value_label(param, shown), Some(_fmt_value(shown; sci = _param_sci(i))))
        end
    end
    return _fmt_value(v)
end

"""
    generate_dynamic_title(plot_dims::Tuple, dim_names::Vector{Symbol}, sel_vals, sim_data)

Dynamically constructs a plot title reflecting the exact position within a multi-dimensional parameter sweep.

Iterates through all registered UI axes. If a dimension is actively mapped to a spatial or parameter axis (found in `plot_dims`), it is left out (the axis label names it). Otherwise, it prints the fixed value (e.g., `T = 0.500 | N = 100`): for a dimension of the data, the value of the snapshot or grid line drawn (the one of `sim_data`, the drawn dataset, nearest to the slider), not the slider position.
"""
function generate_dynamic_title(
    plot_dims::Tuple, 
    dim_names::Vector{Symbol}, 
    sel_vals,
    sim_data::Union{Nothing, AbstractSimData} = nothing
)
    return join(first.(_title_parts(plot_dims, dim_names, sel_vals, sim_data)), " | ")
end

# The parts of a title (see `generate_dynamic_title`), each with the other texts it can show (its other values: the
# swept values, or the ends of the axis), so the line breaks of a title don't move with the sliders.
function _title_parts(plot_dims::Tuple, dim_names::Vector{Symbol}, sel_vals, sim_data = nothing)
    parts = Tuple{String, Vector{String}}[]
    base_vars = get_base_variables()
    n_params = length(dim_names) - length(base_vars)
    kept = _kept_by_field(sim_data)

    for i in 1:length(dim_names)
        name_sym = dim_names[i]

        # Skip base variables that do not physically exist in this simulation, or that the plotted statistic doesn't
        # keep (an error over N has no position: its slider value would be meaningless in the title)
        if !isnothing(sim_data) && (name_sym in base_vars) && (!(name_sym in sim_data.domain.dim_keys) || !(name_sym in kept))
            continue
        end

        name = frontend_key(name_sym)   # custom display labels (set_label!) apply to titles too

        if i in plot_dims
            continue
        elseif i <= length(sel_vals)
            val = i <= n_params ? _param_display_value(i, sel_vals[i]) : _drawn_value(sim_data, name_sym, sel_vals[i])
            # (a named value, every parameter of a joint sweep: N = 40, IC Cell = 0.15)
            if i <= n_params && (_is_joint_key(name_sym) || haskey(manager.value_labels, name_sym))
                data = manager.plot_data[]
                shown = isempty(data) ? Any[] : get(_primary_sweep(data).active_param_values, i, Any[])
                sci = _param_sci(i)
                push!(parts, (_param_text(name_sym, val, _fmt_value; sci), [_param_text(name_sym, v, _fmt_value; sci) for v in shown]))
                continue
            end
            others = ["$name = $v" for v in _title_values(i, i <= n_params, name_sym, sim_data)]
            push!(parts, ("$name = $(_fmt_value(val; sci = i <= n_params && _param_sci(i)))", others))
        end
    end
    return parts
end

# The dimensions the plotted field keeps: every dimension for the solution, those of a statistic otherwise
function _kept_by_field(sim_data)
    isnothing(sim_data) && return Symbol[]
    u = haskey(manager.widgets, :u_axis) ? manager.widgets[:u_axis].selection[] : :Solution
    (u isa Symbol && u !== :Solution && haskey(sim_data.stats, u)) || return collect(Symbol, sim_data.domain.dim_keys)
    return collect(Symbol, PDEStudioCore.get_kept_dims(u, sim_data.domain))
end

# The texts the value of title part `i` can show: every swept value of a parameter, the ends of an axis of the data
function _title_values(i::Int, is_param::Bool, dim::Symbol, sim_data)
    try
        if is_param
            data = manager.plot_data[]
            isempty(data) && return String[]
            pd = _primary_sweep(data)
            i <= length(pd.active_param_values) || return String[]
            sci = _sci_set(pd.active_param_values[i])
            return unique!([_fmt_value(v; sci) for v in pd.active_param_values[i]])
        end
        # (the range of the dimension's slider spans every dataset: the texts don't change with the parameter sliders)
        slider = get(manager.widgets, dim, nothing)
        vals = slider isa Makie.Slider && length(slider.range[]) > 1 ? slider.range[] :
               isnothing(sim_data) ? nothing : _get_dim_vals(Val(manager.mode[]), sim_data, dim)
        (isnothing(vals) || isempty(vals)) && return String[]
        return unique!([_fmt_value(v) for v in (first(vals), last(vals), minimum(vals), maximum(vals))])
    catch
        return String[]
    end
end

# The title of a subplot: the custom title of the UI settings, or the default title fitted to the plot width (its parts,
# or a text such as the label of a compared method)
function _set_title!(ax, default_title)
    custom = manager.ui[:labels][:title]
    text = custom != "default" ? custom : default_title isa AbstractString ? String(default_title) :
           join((first(p) for p in default_title), " | ")
    manager.title_texts[objectid(ax)] = replace(text, "\n" => " | ")   # (the title in one line, as the API reports it)
    if custom != "default"
        ax.title[] = custom
    elseif ax isa Axis3
        # (the space above a 3D axis doesn't grow with the title: one line, shortened to the plot width)
        width, font, size = _title_metrics(ax)
        ax.title[] = default_title isa AbstractString ? _fit_label(default_title, ax) :
                     _shorten_middle(text, s -> _text_width(s, font, size) <= width)
    else
        ax.title[] = default_title isa AbstractString ? _fit_label(default_title, ax) : _fit_title(default_title, ax)
    end
    return nothing
end

# The plot width and the title font of an axis (the size of the UI settings: the axis gets it after its title)
function _title_metrics(ax)
    width = Float64(haskey(manager.widgets, :plot_width) ? manager.widgets[:plot_width].selection[] :
                    get(manager.layout_cache, :plot_width, 500))
    gen = get(manager.ui, :axis_general, Dict{Symbol, Any}())
    return width, ax.titlefont[], Float64(get(gen, :title_size, ax.titlesize[]))
end

# A title of one text (e.g. the label of a compared method) that fits the plot width: broken after spaces or underscores
# where a line would be wider, a word wider than the plot shortened with "…"
function _fit_label(label::AbstractString, ax)
    width, font, size = _title_metrics(ax)
    fits(s) = _text_width(s, font, size) <= width
    (isempty(label) || fits(label)) && return String(label)
    label = _without_common_start(label)
    (ax isa Axis3 || fits(label)) && return _shorten_middle(label, fits)   # (3D axes: one line)
    lines = String[""]
    for word in (m.match for m in eachmatch(r"[^ _]+[ _]*|[ _]+", label))   # (a word with the separators after it)
        if isempty(lines[end]) || fits(rstrip(lines[end] * word))
            lines[end] *= word
        else
            push!(lines, word)
        end
    end
    if length(lines) > 2   # (at most two lines: the rest is shortened in its middle, the ends of names differ)
        return join([_shorten_to(rstrip(lines[1]), fits), _shorten_middle(rstrip(join(lines[2:end])), fits)], "\n")
    end
    return join((_shorten_middle(rstrip(l), fits) for l in lines), "\n")
end

# A compared value's label (e.g. a method name) without the words it shares at its start with the labels of the other
# compared plots it is most alike (`upwind_scheme_without_limiter` next to `upwind_scheme_with_limiter`: "…without_limiter")
function _without_common_start(label::AbstractString)
    labels = String.(string.(manager.compare_state[3]))
    (label in labels && length(labels) > 1) || return String(label)
    words(s) = [m.match for m in eachmatch(r"[^ _]+[ _]*|[ _]+", s)]
    mine = words(label)
    n = 0   # (the most words it shares with another label: those it is confused with)
    for other in labels
        other == label && continue
        w = words(other)
        n = max(n, something(findfirst(i -> i > length(w) || w[i] != mine[i], 1:length(mine)), length(mine) + 1) - 1)
    end
    n = min(n, length(mine) - 1)   # (the last word stays)
    return n <= 0 ? String(label) : "…" * join(mine[(n + 1):end])
end

# `s` shortened in its middle ("upwind_first…without_limiter") until it fits: the start and the end, where names of
# compared methods (or the time of a title) differ, stay
function _shorten_middle(s::AbstractString, fits)
    fits(s) && return String(s)
    n = length(s)
    for keep in (n - 1):-1:2
        head = cld(keep, 2)
        t = first(s, head) * "…" * last(s, keep - head)
        fits(t) && return t
    end
    return first(s, 1) * "…"
end

function _shorten_to(s::AbstractString, fits)
    fits(s) && return String(s)
    n = length(s)
    while n > 1 && !fits(first(s, n - 1) * "…")
        n -= 1
    end
    return first(s, max(n - 1, 1)) * "…"
end

# A title that fits the width of its plot (the plot width of the layout): its parts are broken into lines where a
# line would be wider. The breaks are chosen for the widest text of each part, so they stay as the values change.
function _fit_title(parts::AbstractVector, ax)
    texts = String[first(p) for p in parts]
    length(texts) > 1 || return join(texts, " | ")
    width, font, size = _title_metrics(ax)
    widest = [maximum(s -> _text_width(s, font, size), [text; others]) for (text, others) in parts]
    sep = _text_width(" | ", font, size)
    lines, used = [[texts[1]]], widest[1]
    for k in 2:length(texts)
        if used + sep + widest[k] <= width
            push!(lines[end], texts[k])
            used += sep + widest[k]
        else
            push!(lines, [texts[k]])
            used = widest[k]
        end
    end
    return join((join(l, " | ") for l in lines), "\n")
end

const _TEXT_WIDTHS = Dict{Tuple{String, Any, Float64}, Float64}()   # (measured once per text, font and size)

# The width of `str` in pixels, drawn with `font` (a font or the name of one of the theme's fonts, e.g. `:bold`)
function _text_width(str::AbstractString, font, size::Real)
    length(_TEXT_WIDTHS) > 10_000 && empty!(_TEXT_WIDTHS)
    return get!(() -> _measure_text(String(str), font, Float64(size)), _TEXT_WIDTHS, (String(str), font, Float64(size)))
end

function _measure_text(str::String, font, size::Float64)
    try
        f = font isa Symbol ? Makie.to_font(Makie.to_value(Makie.current_default_theme().fonts[font])) : Makie.to_font(font)
        return Float64(Makie.widths(Makie.text_bb(str, f, Float32(size)))[1])
    catch
        return 0.6 * size * length(str)   # (an estimate, should Makie's text layout change)
    end
end

# The value of the dimension `dim` that is drawn for the slider value `v`: the nearest one on the axis of the dataset
# (each dataset shows its snapshot / grid line nearest to the slider).
function _drawn_value(sim_data, dim::Symbol, v)
    (isnothing(sim_data) || !(v isa Real)) && return v
    vals = _get_dim_vals(Val(manager.mode[]), sim_data, dim)
    (isnothing(vals) || isempty(vals)) && return v
    return vals[findmin(x -> abs(x - v), vals)[2]]
end

"""
    plot_reference_lines!(ax::Axis, exponents::Vector; label, color, line_style, curves, kwargs...)

Draws reference slopes `C xᵖ` (convergence rates on a log-log plot), labelled `slope −2` at their middle. With the
drawn data `curves` (one vector of `(x, y)` points per method, see `_drawn_curves`) a slope runs just below the curve
whose slope (fitted on the log-log points) is closest to it, over that curve's x range, and stays inside the visible y
range; without data it spans the axis from a corner.
"""
function plot_reference_lines!(
    ax::Axis,
    exponents::Vector;
    label::String = "Reference Lines",
    color = :black,
    line_style = :dash,
    curves = Vector{Tuple{Float64, Float64}}[],
    kwargs...
)
    if isnothing(exponents) || isempty(exponents); return []; end
    curves = [c for c in ([(x, y) for (x, y) in c if isfinite(x) && isfinite(y) && x > 0 && y > 0] for c in curves)
              if length(unique(first.(c))) >= 2]
    isempty(curves) && return _corner_reference_lines!(ax, exponents; label, color, line_style, kwargs...)

    plotted_lines = []
    slopes = [_loglog_slope(c) for c in curves]
    used = zeros(Int, length(curves))
    log_x = ax.xscale[] === log10
    lims = ax.finallimits[]
    ylo, yhi = lims.origin[2], lims.origin[2] + lims.widths[2]
    lines_drawn = Tuple{Real, Vector{Float64}, Vector{Float64}}[]
    for p in exponents
        (p isa Real && p != 0) || continue
        j = argmin(abs.(slopes .- p))
        used[j] += 1
        c = curves[j]
        x0, x1 = extrema(first.(c))
        xs = log_x ? 10 .^ range(log10(x0), log10(x1), length = 50) : collect(range(x0, x1, length = 50))
        C = 0.5^used[j] * minimum(y / x^p for (x, y) in c)   # (below the curve, a further slope lower still)
        ys = C .* xs .^ p
        lo, hi = extrema(ys)
        # (inside the visible y range, as long as it fits in it)
        lo < ylo && ylo > 0 && hi * ylo / lo <= yhi && (ys .*= 1.02 * ylo / lo)
        push!(lines_drawn, (p, xs, ys))
        push!(plotted_lines, lines!(ax, Point2f.(xs, ys); color = color, linestyle = line_style, label = label, kwargs...))
    end
    # (the labels once all lines are known: clear of each other, of the other slopes and of the data, as far as possible)
    placed = NTuple{4, Float64}[]
    data_pts = reduce(vcat, (_densify(c, log_x, ax.yscale[] === log10) for c in curves); init = Tuple{Float64, Float64}[])
    for (k, (p, xs, ys)) in enumerate(lines_drawn)
        others = [data_pts; [(x, y) for (q, (_, xq, yq)) in enumerate(lines_drawn) if q != k for (x, y) in zip(xq, yq)]]
        text = "slope " * _fmt_exponent(p)
        m, below = _slope_label_place(ax, xs, ys, p < 0, length(text), placed, others)
        left = (p < 0) == below   # (beside the line, not on it)
        t = text!(ax, xs[m], ys[m]; text = text, color = color, label = label, fontsize = ax.xticklabelsize[],
                  align = (left ? :right : :left, below ? :top : :bottom), offset = (left ? -4 : 4, below ? -4 : 4))
        push!(plotted_lines, t)
    end
    return plotted_lines
end

# Where the label of a slope (`xs`, `ys`) goes: `(i, below)`, beside point `i` of the line, below it (left of a falling,
# right of a rising slope) or above it on the other side. The middle of the line first, then other points along it
# and the other side, the first whose label box (estimated from the text length) stays inside the axis and clear of the
# boxes in `placed` and of the points `others` (the other lines, the data), else the one with the least overlap. Its
# box is added to `placed`.
function _slope_label_place(ax, xs, ys, falling::Bool, nchars::Int, placed, others = Tuple{Float64, Float64}[])
    lims = ax.finallimits[]
    lo, hi = lims.origin, lims.origin .+ lims.widths
    W, H = Makie.widths(ax.layoutobservables.computedbbox[])
    W, H = W > 0 && H > 0 ? (W, H) : (500.0, 400.0)   # (before the first layout)
    frac(v, a, b, scale) = scale === log10 ? (v > 0 && a > 0 ? (log10(v) - log10(a)) / (log10(b) - log10(a)) : 0.5) :
                                             (v - a) / (b - a)
    fs = Float64(ax.xticklabelsize[])
    w, h = 0.55 * fs * nchars, 1.2 * fs
    px(x, y) = (frac(x, lo[1], hi[1], ax.xscale[]) * W, frac(y, lo[2], hi[2], ax.yscale[]) * H)
    obstacles = [px(x, y) for (x, y) in others]
    function box(i, below)
        X, Y = px(xs[i], ys[i])
        left = falling == below   # (the side away from the line)
        x0 = left ? X - 4 - w : X + 4
        return below ? (x0, x0 + w, Y - 4 - h, Y - 4) : (x0, x0 + w, Y + 4, Y + 4 + h)
    end
    overlap(a, b) = max(0, min(a[2], b[2]) - max(a[1], b[1]) + 2) * max(0, min(a[4], b[4]) - max(a[3], b[3]) + 2)
    n = length(xs)
    best, best_cost = (cld(n, 2), true), Inf
    for f in (0.5, 0.3, 0.7, 0.15, 0.85, 0.05, 0.95), below in (true, false)
        i = clamp(round(Int, f * (n - 1)) + 1, 1, n)
        b = box(i, below)
        outside = (b[1] < 0) + (b[2] > W) + (b[3] < 0) + (b[4] > H)
        crossed = count(o -> b[1] <= o[1] <= b[2] && b[3] <= o[2] <= b[4], obstacles)
        cost = 50 * sum((overlap(b, q) for q in placed); init = 0.0) + 100 * crossed + 1e6 * outside   # (labels apart first)
        cost == 0 && (best = (i, below); break)
        cost < best_cost && ((best, best_cost) = ((i, below), cost))
    end
    push!(placed, box(best...))
    return best
end

# Points along a curve, a few per segment (evenly on the axis scales), so a label box can't sit on it unnoticed
function _densify(c, log_x::Bool, log_y::Bool)
    fwd(v, lg) = lg ? log10(v) : v
    bwd(v, lg) = lg ? 10^v : v
    out = Tuple{Float64, Float64}[]
    for i in 1:length(c) - 1, s in range(0, 1, length = 9)[1:end-1]
        (a, b), (d, e) = c[i], c[i + 1]
        push!(out, (bwd(fwd(a, log_x) + s * (fwd(d, log_x) - fwd(a, log_x)), log_x),
                    bwd(fwd(b, log_y) + s * (fwd(e, log_y) - fwd(b, log_y)), log_y)))
    end
    isempty(c) || push!(out, last(c))
    return out
end

# The slope of a curve on a log-log plot (least squares)
function _loglog_slope(c)
    lx, ly = log10.(first.(c)), log10.(last.(c))
    mx = sum(lx) / length(lx)
    den = sum((lx .- mx) .^ 2)
    return den > 0 ? sum((lx .- mx) .* (ly .- sum(ly) / length(ly))) / den : 0.0
end

# An exponent as in a slope label: −2, 1.5
_fmt_exponent(p) = replace(isinteger(p) ? string(Int(p)) : _fmt_compare(Float64(p)), "-" => "−")

# The curves drawn in subplot `i` by a 1D style, as `(x, y)` points (one vector per method), for anchoring reference
# slopes to the data
function _drawn_curves(i::Int)
    out = Vector{Tuple{Float64, Float64}}[]
    haskey(manager.caches, i) || return out
    for cache in values(manager.caches[i])
        try
            u = cache.obs_u[]
            x = cache isa EulerianPlotCache ? cache.obs_x[] : [first(p) for p in cache.obs_pts[]]
            (x isa AbstractVector && u isa AbstractVector && length(x) == length(u)) || continue
            push!(out, [(Float64(a), Float64(b)) for (a, b) in zip(x, u) if a isa Real && b isa Real])
        catch
        end
    end
    return out
end

# Reference slopes over the whole axis, from its lower (positive exponents) or upper left corner
function _corner_reference_lines!(ax::Axis, exponents::Vector; label, color, line_style, kwargs...)
    if isnothing(exponents) || isempty(exponents); return []; end

    plotted_lines = []
    for p_signed in exponents
        if p_signed == 0; continue; end
        
        pts = lift(ax.finallimits, ax.xscale, ax.yscale) do lims, xscl, yscl
            xmin, xmax = lims.origin[1], lims.origin[1] + lims.widths[1]
            ymin, ymax = lims.origin[2], lims.origin[2] + lims.widths[2]
            
            xmin = max(1e-12, xmin)
            xmax = max(1e-11, max(xmax, xmin + 1e-11))
            ymin = max(1e-12, ymin)
            ymax = max(1e-11, max(ymax, ymin + 1e-11))
            
            if xmin >= xmax || ymin >= ymax
                return [Point2f(1.0, 1.0), Point2f(10.0, 10.0)]
            end
            
            xs = xscl == log10 ? (10 .^ range(log10(xmin), log10(xmax), length=100)) : collect(range(xmin, xmax, length=100))
            
            y_anchor = p_signed > 0 ? ymin : ymax
            ref_x = xs[1]
            C = ref_x > 0 ? (y_anchor / (ref_x^p_signed)) : 0.0
            ys = C .* (xs .^ p_signed)
            
            return Point2f.(xs, ys)
        end
        
        l = lines!(ax, pts; color=color, linestyle=line_style, label=label, kwargs...)
        # Deleting the line (`delete_plots_by_label!` on every UI step) also detaches its listeners from the axis
        # limits; they would otherwise pile up (one per UI step and exponent).
        append!(getfield(l, :deregister_callbacks), pts.inputs)
        push!(plotted_lines, l)
    end
    return plotted_lines
end
"""
    get_colorrange(ui_app::Dict, u_data::AbstractArray)

Extracts the exact color range bounds from the UI dictionary or dynamically calculates the global `[min, max]` extrema if the user has requested automatic default scaling. 

Always returns a `Makie.Vec2f` wrapped in an Observable to prevent ComputePipeline strict typing crashes during contourf level recalculations.
"""
# Widens a (numerically) constant range `[lo, hi]` (relative width up to `rtol`) to a relative width of 1e-3 (absolute
# 1e-6 around zero). A field that is constant up to floating-point noise (e.g. the initial state of a Riemann problem in
# `Float32`) would otherwise get contour levels spaced below the data's precision, which makes Makie's `contourf` fail.
# (Colours are `Float32`, so colour ranges use the default; axis limits the precision of the data, see
# `calculate_padded_axis_range`.)
function _pad_degenerate_range(lo::Real, hi::Real; rtol::Real = 1e-5)
    scale = max(abs(lo), abs(hi))
    hi - lo > rtol * scale && return (lo, hi)
    pad = max(1e-3 * scale, 1e-6)
    return (lo - pad, hi + pad)
end

function get_colorrange(ui_app::Dict, u_data::AbstractArray)
    cr_val = ui_app[:color_range] 
    
    if length(cr_val) != 2 || !all(v -> v isa Real, cr_val)   # automatic (also for a value that isn't [lo, hi])
        valid_u = filter(isfinite, vec(u_data))
        l_u, h_u = isempty(valid_u) ? (0.0, 1.0) : (minimum(valid_u), maximum(valid_u))
        l_u, h_u = _pad_degenerate_range(l_u, h_u)
        
        # Use Makie.Vec2f to perfectly match ComputePipeline's expected output type
        return Observable(Makie.Vec2f(l_u, h_u))
    else
        return Observable(Makie.Vec2f(cr_val[1], cr_val[2]))
    end
end

"""
    apply_axis_limits_overrides!(ax)

Overrides Makie's automatic axis scaling with rigid, user-defined boundary limits set on the axis pages of the UI tab (`lims`). Bypassed if the global Camera Lock is actively tracking a manual pan/zoom state.
"""
function apply_axis_limits_overrides!(ax)
    
    if manager.camera_locked[]
        return
    end
    ui_x = _axis_ui(:x_axis)
    ui_y = _axis_ui(:y_axis)
    
    try
        if haskey(ui_x, :lims) && length(ui_x[:lims]) == 2 
            lx = Float64.(ui_x[:lims])
            if lx[1] < lx[2]; xlims!(ax, lx[1], lx[2]); end
        end
        
        if haskey(ui_y, :lims) && length(ui_y[:lims]) == 2 
            ly = Float64.(ui_y[:lims])
            if ly[1] < ly[2]; ylims!(ax, ly[1], ly[2]); end
        end
        
        if ax isa Axis3 && haskey(manager.ui, :z_axis)
            ui_z = _axis_ui(:z_axis)
            if haskey(ui_z, :lims) && length(ui_z[:lims]) == 2 
                lz = Float64.(ui_z[:lims])
                if lz[1] < lz[2]; zlims!(ax, lz[1], lz[2]); end
            end
        end
    catch
        @warn "Failed to apply manual axis limits. Please ensure the input is a 2-element vector like [-5.0, 5.0]."
    end
end

"""
    delete_plots_by_label!(ax::Axis, label_to_delete::String)

A targeted garbage collector for Makie scenes. 
Iterates through all drawn primitives on an axis and deletes any object whose `label` attribute exactly matches `label_to_delete`. 
Used to instantly clear and redraw HUDs, outlier markers, and extrema lines without destroying the primary data surfaces.
"""
function delete_plots_by_label!(ax::Axis, label_to_delete::String)
    plots_to_delete = [p for p in ax.scene.plots if haskey(p,:label) && p.label[] == label_to_delete]
    
    if !isempty(plots_to_delete)
        for p in plots_to_delete
            delete!(ax.scene, p)
        end
        return true
    end
    return false
end

"""
    set_axis_limits_manager!(ax::Axis, xs, us; precision = Float64)

Safely computes and applies the optimal bounding box for a 2D axis. 

Handles extreme edge cases (like purely horizontal/vertical lines) by applying dynamic padding factors. It also proactively catches negative values before activating `log10` scales to prevent the Makie rendering engine from fatally crashing on domain errors.
"""
function set_axis_limits_manager!(ax::Axis, xs, us; precision::Type{<:AbstractFloat} = Float64)
    
    ui_x = _axis_ui(:x_axis)
    ui_y = _axis_ui(:y_axis)
    
    raw_xlims = _safe_extrema(xs)
    raw_ylims = _safe_extrema(us)

    use_log_x = ui_x[:log_scale] 
    use_log_y = ui_y[:log_scale] 

    if raw_xlims[1] <= 0 && use_log_x
        use_log_x = false
        @warn "X-Axis data contains non-positive values. log_scale temporarily disabled."
    end
    if raw_ylims[1] <= 0 && use_log_y
        use_log_y = false
        @warn "Y-Axis data contains non-positive values. log_scale temporarily disabled."
    end

    new_xscale = use_log_x ? log10 : identity
    new_yscale = use_log_y ? log10 : identity

    # Calculate and apply the valid padded limits before changing the scale
    is_locked = manager.camera_locked[]
    
    if !is_locked
        final_xlims = calculate_padded_axis_range(raw_xlims, ui_x[:padding], use_log_x; precision, fine_labels = _fine_labels(ui_x))
        final_ylims = calculate_padded_axis_range(raw_ylims, ui_y[:padding], use_log_y; precision, fine_labels = _fine_labels(ui_y))
        try limits!(ax, final_xlims..., final_ylims...) catch; end
    else
        # Safety net: If camera is locked but the current limits are invalid for a log scale, 
        # force an override to prevent a hard Makie crash.
        curr_lims = ax.finallimits[]
        if (use_log_x && curr_lims.origin[1] <= 0) || (use_log_y && curr_lims.origin[2] <= 0)
            final_xlims = calculate_padded_axis_range(raw_xlims, ui_x[:padding], use_log_x; precision, fine_labels = _fine_labels(ui_x))
            final_ylims = calculate_padded_axis_range(raw_ylims, ui_y[:padding], use_log_y; precision, fine_labels = _fine_labels(ui_y))
            try limits!(ax, final_xlims..., final_ylims...) catch; end
        end
    end

    # NOW update the scales safely
    if ax.xscale[] !== new_xscale; ax.xscale[] = new_xscale; end
    if ax.yscale[] !== new_yscale; ax.yscale[] = new_yscale; end
    _set_ticks!(ax, ui_x, ui_y)

    return
end

# The ticks of an axis: on a log10 axis decades with 2, 3 or 5 between them as the range and the size of the axis allow
# (`_Log10Ticks`), labelled as plain numbers or powers of ten (Makie's defaults give ticks like 10^2.5 and labels like
# 0.000001); otherwise the UI's tick count, or Makie's default. A custom tick format or scale offset
# (set_axis_styles!) is kept.
function _set_ticks!(ax::Axis, ui_x, ui_y)
    for (ui, format, ticks, scale, horizontal) in ((ui_x, ax.xtickformat, ax.xticks, ax.xscale[], true),
                                                   (ui_y, ax.ytickformat, ax.yticks, ax.yscale[], false))
        # (formatter first, and both only on a change: every assignment redraws the ticks)
        if get(ui, :scale_offset, 0.0) == 0.0 && get(ui, :tick_format, "default") == "default"
            f = scale === log10 ? _log10_labels : Makie.automatic
            format[] === f || (format[] = f)
        end
        t = _axis_ticks(ax, ui, scale, horizontal)
        ticks[] === t || (ticks[] = t)
    end
    return nothing
end

function _axis_ticks(ax, ui, scale, horizontal)
    count = get(ui, :tick_count, 0)
    scale === log10 && return _Log10Ticks(ax.layoutobservables.computedbbox, horizontal, max(count, 0),
                                         Float64((horizontal ? ax.xticklabelsize : ax.yticklabelsize)[]))
    return count > 0 ? LinearTicks(count) : Makie.automatic
end

"""
    _Log10Ticks(box, horizontal, count, labelsize)

The ticks of a log10 axis: 1, 2, 3, 5 × 10ᵏ, 1, 2, 5 × 10ᵏ, the decades or every k-th decade, the densest of them
whose labels don't overlap on the axis (`box`: the observable box of the axis area, which Makie updates before it
recomputes the ticks of a resized axis) and that has at most `count` ticks (`0`: up to 10).
"""
struct _Log10Ticks
    box::Any
    horizontal::Bool
    count::Int
    labelsize::Float64
end

function Makie.get_tickvalues(t::_Log10Ticks, vmin, vmax)
    length_px = Float64(Makie.widths(t.box[])[t.horizontal ? 1 : 2])
    return _log10_ticks(vmin, vmax; max_ticks = t.count > 0 ? t.count : 10,
                        fits = ticks -> _log_labels_fit(ticks, vmin, vmax, length_px, t.horizontal, t.labelsize))
end

function _log10_ticks(vmin, vmax; max_ticks::Int = 10, fits = Returns(true))
    (isfinite(vmin) && isfinite(vmax) && 0 < vmin < vmax) || return Float64[]
    lo, hi = floor(Int, log10(vmin)), ceil(Int, log10(vmax))
    decades = hi - lo
    tick(m, e) = e >= 0 ? m * 10.0^e : m / 10.0^(-e)   # (0.3, not 0.30000000000000004)
    in_range(ticks) = filter(t -> vmin <= t <= vmax, ticks)
    # (densest first; every k-th decade: the multiples of k, so 10⁻⁶, 10⁻⁴, 10⁻²)
    candidates = Vector{Float64}[]
    decades <= 1 && push!(candidates, in_range([tick(m, e) for e in lo:hi for m in (1, 2, 3, 5)]))
    decades <= 3 && push!(candidates, in_range([tick(m, e) for e in lo:hi for m in (1, 2, 5)]))
    for k in 1:max(decades, 1)
        push!(candidates, in_range([tick(1, e) for e in lo:hi if mod(e, k) == 0]))
    end
    filter!(c -> length(c) >= 2, candidates)
    # (less than one step of that grid in range: three round values)
    isempty(candidates) && return unique(in_range(round.([vmin, sqrt(vmin * vmax), vmax]; sigdigits = 2)))
    i = findfirst(c -> length(c) <= max_ticks && fits(c), candidates)
    return isnothing(i) ? candidates[argmin(length.(candidates))] : candidates[i]
end

# Whether the labels of log10 ticks keep apart on an axis of `length_px` pixels (estimated sizes: digits are about
# 0.55 em wide, superscripts 0.66 times that); `true` while the axis has no size yet.
function _log_labels_fit(ticks, vmin, vmax, length_px, horizontal, labelsize)
    length_px > 0 || return true
    pos = (log10.(ticks) .- log10(vmin)) ./ (log10(vmax) - log10(vmin)) .* length_px
    labels = _log10_labels(ticks)
    sizes = horizontal ? [_label_width(l, labelsize) for l in labels] :
                         [(l isa Makie.RichText ? 1.3 : 1.0) * labelsize for l in labels]
    gap = (horizontal ? 1.2 : 0.3) * labelsize
    return all(pos[i + 1] - pos[i] >= (sizes[i] + sizes[i + 1]) / 2 + gap for i in 1:length(ticks) - 1)
end

_label_width(l::AbstractString, size) = 0.55 * size * length(l)
_label_width(l::Makie.RichText, size) =
    sum(c -> _label_width(c, l.type === :sup ? 0.66 * size : size), l.children; init = 0.0)

# Labels of log10 ticks: plain numbers if all of them are in [1e-3, 1e5) (0.002, 50, 1000), powers of ten otherwise
# (10⁻⁶, 2×10⁻⁶), as rich text like Makie's own log labels
function _log10_labels(values)
    all(v -> 1e-3 <= abs(v) < 1e5, values) && return [_plain_number(v) for v in values]
    return map(values) do v
        v > 0 || return string(v)
        m, e = _power_parts(v)
        exponent = superscript(e < 0 ? "−$(-e)" : string(e); offset = Vec2f(0.1f0, 0.0f0))
        m == "1" ? rich("10", exponent) : rich(m, "×10", exponent)
    end
end

# Shortest decimal of a rounded value without a trailing ".0" (0.001, 20, 2.5)
_plain_number(v) = (s = string(round(Float64(v), sigdigits = 6)); endswith(s, ".0") ? s[1:end-2] : s)

# v = m × 10^e with 1 <= m < 10 (3 significant digits): ("2", -6) for 2e-6
function _power_parts(v::Real)
    e = floor(Int, log10(v))
    m = round(e >= 0 ? v / 10.0^e : v * 10.0^(-e), sigdigits = 3)
    m >= 10 && ((m, e) = (m / 10, e + 1))
    return _plain_number(m), e
end


"""
    calculate_layout_dictionary(num_plots, cols_req, link_mode, has_legend, is_detached, halign, valign, has_colorbar)

A pure mathematical layout engine. 
Calculates the exact matrix coordinate mapping `(row, column)` for N subplots, intelligently routing space for dynamic grid comparisons, detached external legends, and global vs. local colorbars based on the active axis linking modes.
"""
function calculate_layout_dictionary(num_plots::Int, cols_req::Int, link_mode::Symbol, has_legend::Bool, is_detached::Bool, halign::Symbol, valign::Symbol, has_colorbar::Bool)
    cols = min(num_plots, cols_req)
    rows = ceil(Int, num_plots / cols)
    
    layout_dict = Dict{Symbol, Any}()
    layout_dict[:Plots] = Vector{Tuple{Any, Any}}(undef, num_plots)
    layout_dict[:Colorbars] = Vector{Tuple{Any, Any}}()
    layout_dict[:Legend] = nothing
    
    row_offset = (has_legend && is_detached && valign == :top) ? 1 : 0
    col_offset = (has_legend && is_detached && halign == :left) ? 1 : 0

    if link_mode in (:decoupled, :axes_only) && has_colorbar
        for i in 1:num_plots
            r = (i - 1) ÷ cols + 1
            c = (i - 1) % cols + 1
            
            p_row = r + row_offset
            p_col = (2 * c - 1) + col_offset
            cb_col = (2 * c) + col_offset
            
            layout_dict[:Plots][i] = (p_row, p_col)
            push!(layout_dict[:Colorbars], (p_row, cb_col))
        end
        max_core_col = 2 * cols + col_offset
        max_core_row = rows + row_offset
    else
        for i in 1:num_plots
            r = (i - 1) ÷ cols + 1
            c = (i - 1) % cols + 1
            
            p_row = r + row_offset
            p_col = c + col_offset
            
            layout_dict[:Plots][i] = (p_row, p_col)
        end
        max_core_col = cols + col_offset
        max_core_row = rows + row_offset
        
        if has_colorbar
            cb_col = max_core_col + 1
            max_core_col += 1
            push!(layout_dict[:Colorbars], (1 + row_offset : rows + row_offset, cb_col))
        end
    end
    
    if has_legend
        if is_detached
            if valign == :top
                layout_dict[:Legend] = (1, 1:max_core_col)
            elseif valign == :bottom
                layout_dict[:Legend] = (max_core_row + 1, 1:max_core_col)
            elseif halign == :left
                layout_dict[:Legend] = (1+row_offset : max_core_row, 1)
            else 
                layout_dict[:Legend] = (1+row_offset : max_core_row, max_core_col + 1)
            end
        else
            layout_dict[:Legend] = layout_dict[:Plots][1]
        end
    end
    return layout_dict
end

"""
    _parse_legend_position(target = <active compare target>)

Parses the UI dropdown logic to determine the precise Makie anchoring coordinates for the legend block. 
Returns `(is_detached, halign, valign)`.
"""
function _parse_legend_position(target = manager.compare_state[1])
    base_align = manager.widgets[:legend_base].selection[]
    add_align  = manager.widgets[:legend_add].selection[]
    
    if base_align == :none || add_align == :none
        return (false, :none, :none)
    end
    
    is_detached = (add_align == :detached)
    
    if target != :none && target != :methods && !is_detached
        return (true, :center, :top)
    end
    
    valign = (:top in (base_align, add_align)) ? :top : 
             (:bottom in (base_align, add_align) ? :bottom : :center)
             
    halign = (:left in (base_align, add_align)) ? :left : 
             (:right in (base_align, add_align) ? :right : :center)

    return (is_detached, halign, valign)
end

"""
    create_or_update_legend!(plot_layout::GridLayout, plotted_objects::Vector, labels::Vector)

Destroys any existing legend within the layout and builds a fresh, accurately positioned Makie `Legend` block matching the exact styles (colors, line widths, markers) of the currently drawn primitives.
"""
function create_or_update_legend!(plot_layout::GridLayout, plotted_objects::Vector, labels::Vector)
    
    for c in copy(plot_layout.content)
        if c.content isa Makie.Legend; delete!(c.content); end
    end
    
    if isempty(plotted_objects) || isempty(labels); return; end
    
    layout_dict = manager.layout_dict[]
    if !haskey(layout_dict, :Legend) || isnothing(layout_dict[:Legend]); return; end
    
    ui_style = manager.ui[:axis_general]
    title_str = manager.ui[:labels][:legend_label]
    # (lines over a parameter or time: the default title names it, after the methods if there are several)
    line_target = manager.line_state[1]
    if title_str == "Methods" && !isnothing(manager.line_state[2])
        name = frontend_key(line_target === :time ? :t : line_target)
        # (compared methods are the subplots' titles: the legend names the values only)
        title_str = length(manager.methods[]) > 1 && manager.compare_state[1] !== :methods ? "Methods, $name" : name
    end
    final_title = isempty(strip(title_str)) ? nothing : title_str
    font_size = ui_style[:font_size] 
    
    is_detached, halign, valign = _parse_legend_position()

    if halign==:none && valign==:none; return; end
    leg_pos = layout_dict[:Legend]

    try
        if is_detached
            orientation = (valign == :top || valign == :bottom) ? :horizontal : :vertical
            tw = orientation == :vertical
            th = !tw 
            Legend(plot_layout[leg_pos...], plotted_objects, labels, final_title;
                orientation=orientation, tellheight=th, tellwidth=tw, merge=true, unique=true,
                titlesize=font_size, labelsize=font_size)
        else
            Legend(plot_layout[leg_pos...], plotted_objects, labels, final_title;
                orientation=:vertical, tellheight=false, tellwidth=false,
                halign=halign, valign=valign, merge=true, unique=true,
                titlesize=font_size, labelsize=font_size, margin=(10, 10, 10, 10)
            )
        end
    catch e
        @error "Failed to create legend" exception=(e, catch_backtrace())
    end
end

"""
    create_or_update_colorbar!(plot_layout::GridLayout, plot_object, color_range_obs, default_label::String, plot_idx::Int=1)

Builds and binds a Makie `Colorbar` to a specific plot primitive, securely linking its colormap and `color_range_obs` bounds to the global UI state.
"""
function create_or_update_colorbar!(plot_layout::GridLayout, plot_object, color_range_obs, default_label::String, plot_idx::Int=1)
    
    ui_stl = manager.ui[:plot_style]
    if !haskey(ui_stl, :color_map); return; end 
    safe_limits = color_range_obs isa Tuple ? color_range_obs : lift(cr -> (Float64(cr[1]), Float64(cr[2])), color_range_obs)
    layout_dict = manager.layout_dict[]
    cb_list = layout_dict[:Colorbars]
    isempty(cb_list) && return
    
    is_global = length(cb_list) == 1
    
    if is_global && plot_idx > 1; return; end
    
    if plot_idx == 1
        for c in copy(plot_layout.content)
            if c.content isa Makie.Colorbar; delete!(c.content); end
        end
    end
    
    cb_pos = is_global ? cb_list[1] : cb_list[plot_idx]
    
    ui_lbl = manager.ui[:labels]
    ui_gen = manager.ui[:axis_general]
    final_label = ui_lbl[:colorbar_label] == "default" ? default_label : ui_lbl[:colorbar_label] 
    
    try
        Colorbar(plot_layout[cb_pos...];
            colormap = ui_stl[:color_map], 
            limits = safe_limits,
            label = final_label,
            labelsize = ui_gen[:label_size], 
            ticklabelsize = ui_gen[:ticklabel_size] 
        )
    catch e
        @error "Failed to create colorbar." exception=(e, catch_backtrace())
    end
end

# The smallest relative width of an axis range that Makie's tick labels resolve (below it every label reads the same):
# narrower ranges are drawn as constant.
const _AXIS_MIN_RTOL = 1e-6

"""
    calculate_padded_axis_range(raw_limits::Tuple, padding_factor::Real, is_log_scale::Bool; precision = Float64,
                                fine_labels = false)

Computes the padding around raw data limits, safely handling both linear and logarithmic coordinate spaces. A range
that is constant up to the round-off of the data's floating-point type `precision` (relative width up to
`100 eps(precision)`), or narrower than the default tick labels can resolve (relative width 1e-6), gets a relative
width of 1e-3 instead, so the noise doesn't fill the axis with repeated tick labels. With `fine_labels` (the axis has a
`scale_offset`, whose offset labels resolve such deviations) only round-off is drawn flat.
"""
function calculate_padded_axis_range(raw_limits::Tuple, padding_factor::Real, is_log_scale::Bool;
                                     precision::Type{<:AbstractFloat} = Float64, fine_labels::Bool = false)
    min_raw, max_raw = raw_limits
    if isnothing(min_raw) || isnothing(max_raw) || !isfinite(min_raw) || !isfinite(max_raw)
        return is_log_scale ? (0.1, 1.0) : (0.0, 1.0)
    end

    if is_log_scale && min_raw > 0
        log_min, log_max = log10(min_raw), log10(max_raw)
        log_range = max(log_max - log_min, 0.1) 
        pad = log_range * padding_factor / 2.0
        return (10^(log_min - pad), 10^(log_max + pad))
    else
        # A field constant up to the round-off of its type (e.g. a constant Float32 state), or varying by less than the
        # tick labels can show (`_AXIS_MIN_RTOL`), gets the relative range of the colour ranges, so noise doesn't fill
        # the axis with repeated tick labels; larger small variations stay visible; an exact zero keeps ±0.1.
        # With labels that resolve small deviations (`fine_labels`: a `scale_offset`) only round-off is flattened.
        min_raw == max_raw == 0 && return (-0.1, 0.1)
        rtol = fine_labels ? 100 * eps(precision) : max(100 * eps(precision), _AXIS_MIN_RTOL)
        lo, hi = _pad_degenerate_range(min_raw, max_raw; rtol)
        (lo, hi) == (min_raw, max_raw) || return (lo, hi)
        pad = (max_raw - min_raw) * padding_factor / 2.0
        return (min_raw - pad, max_raw + pad)
    end
end

# Whether the tick labels of an axis resolve deviations far below the value (`set_axis_styles!`): offset labels
# (`1.0 + 5.0e-10`). A custom tick format doesn't count, it may show fewer digits than the default labels.
_fine_labels(ui) = get(ui, :scale_offset, 0.0) != 0

"""
    _safe_extrema(data_slices)

Calculates the absolute minimum and maximum boundaries across a collection of data slices, gracefully filtering out `NaN` and `Inf` values inserted by outlier masking logic.
"""
function _safe_extrema(data_slices)
    mins, maxs = Float64[], Float64[]
    for slice in data_slices
        valid_data = filter(isfinite, slice)
        if !isempty(valid_data)
            push!(mins, minimum(valid_data))
            push!(maxs, maximum(valid_data))
        end
    end
    isempty(mins) && return (0.0, 1.0)
    return (minimum(mins), maximum(maxs))
end

"""
    plot_extrema_lines_manager!(ax::Axis, data_tuples, valid_methods, is_3d_axis)

Analyzes the active slices to locate the absolute max/min spikes across the domain and overlays dashed targeting lines from the X-axis directly to the extrema coordinates.
"""
function plot_extrema_lines_manager!(ax::Axis, data_tuples, valid_methods, is_3d_axis)
    # Clear old extrema lines
    delete_plots_by_label!(ax, "Extrema_Max")
    delete_plots_by_label!(ax, "Extrema_Min")
    
    is_3d_axis && return
    
    ui_ext = get(manager.ui, :outliers_extrema, Dict())
    track_max = get(ui_ext, :track_max, false)
    track_min = get(ui_ext, :track_min, false)
    (!track_max && !track_min) && return

    ui_stl = manager.ui[:plot_style]
    colors = get(ui_stl, :colors, [:black])
    lw = haskey(ui_stl, :line_width) ? (ui_stl[:line_width] / 2) : 2.0 

    if length(data_tuples) == 2  # 1D data only (x, u)
        xs_all = data_tuples[1]
        us_all = data_tuples[end]
        
        for (m_idx, m_name) in enumerate(valid_methods)
            x_data, u_data = xs_all[m_idx], us_all[m_idx]

            (eltype(x_data) <: Point) && continue
            (x_data isa AbstractVector && u_data isa AbstractVector) || continue

            valid_pairs = filter(p -> isfinite(p[2]), collect(zip(x_data, u_data)))
            isempty(valid_pairs) && continue
            
            c = colors[mod1(m_idx, length(colors))]
            
            if track_max
                max_u, idx = findmax(p -> p[2], valid_pairs)
                max_x = valid_pairs[idx][1]
                linesegments!(ax, [Point2f(max_x, 0), Point2f(max_x, max_u)]; color=(c, 0.7), linestyle=:dash, linewidth=lw, label="Extrema_Max")
            end
            if track_min
                min_u, idx = findmin(p -> p[2], valid_pairs)
                min_x = valid_pairs[idx][1]
                linesegments!(ax, [Point2f(min_x, 0), Point2f(min_x, min_u)]; color=(c, 0.7), linestyle=:dot, linewidth=lw, label="Extrema_Min")
            end
        end
    end
end

plot_extrema_lines_manager!(ax::Axis3, args...) = nothing

"""
    apply_outlier_mask(ax::Axis, data_tuples, valid_methods, is_3d_axis)

Processes raw scalar data arrays based on Interquartile Range (IQR) thresholding. 
Can visually mark statistical outliers with heavy crosses on the plot, completely remove them by injecting `NaN`s, or both, ensuring heavily spiked data does not ruin the global colormap scaling.
"""
function apply_outlier_mask(ax::Axis, data_tuples, valid_methods, is_3d_axis)
    # 1. Always clear the old markers first
    delete_plots_by_label!(ax, "Outlier")
    
    ui_ext = get(manager.ui, :outliers_extrema, Dict())
    remove_outs = get(ui_ext, :remove_outliers, false)
    mark_outs   = get(ui_ext, :mark_outliers, false)

    # 2. If both features are inactive, exit early and return unmodified data
    if !remove_outs && !mark_outs
        return data_tuples
    end

    thresh = get(ui_ext, :outlier_threshold, 1.5)
    u_slices = data_tuples[end]
    new_u_slices = Any[]
    
    # Fetch method colors so the markers match the plot lines
    ui_stl = manager.ui[:plot_style]
    colors = get(ui_stl, :colors, [:red])

    for (m_idx, m_name) in enumerate(valid_methods)
        u_clean = u_slices[m_idx]
        out_idx = _find_outlier_indices(u_clean, thresh)

        # 3. Draw the Outliers immediately on the axis
        if !isempty(out_idx) && mark_outs && !is_3d_axis
            c = colors[mod1(m_idx, length(colors))]
            xs = data_tuples[1][m_idx]
            
            if eltype(xs) <: Real && length(data_tuples) == 2 # 1D Line/Scatter Plot
                segments = Point2f[]
                for idx in out_idx
                    x_val, u_val = Float64(xs[idx]), Float64(u_clean[idx])
                    push!(segments, Point2f(x_val, 0.0), Point2f(x_val, u_val))
                end
                linesegments!(ax, segments; color=(c, 0.6), linewidth=2.0, linestyle=:dash, label="Outlier")
                
            elseif eltype(xs) <: Point2f # Native 2D Lagrangian Point Cloud
                pts = Point2f[xs[idx] for idx in out_idx]
                scatter!(ax, pts; color=c, marker=:xcross, markersize=15, label="Outlier")
                
            elseif length(data_tuples) >= 3 # 2D Eulerian Heatmap/Contour Fallback
                xs, ys = data_tuples[1][m_idx], data_tuples[2][m_idx]
                pts = Point2f[]
                if out_idx isa Vector{CartesianIndex{2}}
                    for idx in out_idx; push!(pts, Point2f(xs[idx[1]], ys[idx[2]])); end
                else
                    for idx in out_idx; push!(pts, Point2f(xs[idx], ys[idx])); end
                end
                scatter!(ax, pts; color=c, marker=:xcross, markersize=15, label="Outlier")
            end
        end

        # 4. Conditionally apply NaN masking
        if remove_outs && !isempty(out_idx)
            u_clean_copy = copy(u_clean)
            if !(eltype(u_clean_copy) <: AbstractFloat)
                u_clean_copy = float.(u_clean_copy)
            end
            for idx in out_idx
                u_clean_copy[idx] = NaN
            end
            push!(new_u_slices, u_clean_copy)
        else
            push!(new_u_slices, u_clean)
        end
    end

    # Return modified tuple only if removal was explicitly requested
    return remove_outs ? (data_tuples[1:end-1]..., new_u_slices) : data_tuples
end

# Safety fallback for Axis3
apply_outlier_mask(ax::Axis3, data_tuples, valid_methods, is_3d_axis) = data_tuples

"""
    _find_outlier_indices(y_data::AbstractVector, threshold::Real)

Calculates the Q1 and Q3 quartiles of a dataset to determine the Interquartile Range (IQR). Returns the exact indices of elements falling outside `Q1 - threshold * IQR` and `Q3 + threshold * IQR`.
"""
function _find_outlier_indices(y_data::AbstractVector, threshold::Real)
    if length(y_data) < 5; return Int[]; end
    finite_y_data = filter(isfinite, y_data)
    if length(finite_y_data) < 5; return Int[]; end

    q1, q3 = quantile(finite_y_data, 0.25), quantile(finite_y_data, 0.75)
    iqr = q3 - q1
    lower_bound, upper_bound = q1 - threshold * iqr, q3 + threshold * iqr
    
    return findall(y -> isfinite(y) && (y < lower_bound || y > upper_bound), y_data)
end

function _find_outlier_indices(matrix::AbstractMatrix, threshold::Real)
    flat_vector = vec(matrix)
    linear_outlier_indices = _find_outlier_indices(flat_vector, threshold)
    return CartesianIndices(matrix)[linear_outlier_indices]
end

"""
    set_axis_styles!(ax, def_x, def_y, def_title)

Maps the deep hierarchical UI dictionary (fonts, label padding, grid visibility, axis ticks, scale offsets) directly onto a native Makie `Axis` or `Axis3` object.
"""
# Whether a subplot shows its x and y label: the lowest subplot of its column and the leftmost of its row (`true, true`
# for a single plot, or an axis outside the subplot grid of the layout)
function _outer_labels(ax::Axis)
    plots = get(manager.layout_dict[], :Plots, nothing)
    gc = ax.layoutobservables.gridcontent[]
    (isnothing(plots) || length(plots) < 2 || isnothing(gc)) && return true, true
    r, c = first(gc.span.rows), first(gc.span.cols)
    (r, c) in plots || return true, true
    # (Compare: fields: every subplot plots another field, so each keeps its y label)
    return !any(p -> p[2] == c && p[1] > r, plots), manager.compare_state[1] === :fields || !any(p -> p[1] == r && p[2] < c, plots)
end

function set_axis_styles!(ax::Axis, def_x::String, def_y::String, def_title::String)
    
    gen = manager.ui[:axis_general]
    lbl = manager.ui[:labels]
    x_ui, y_ui = _axis_ui(:x_axis), _axis_ui(:y_axis)

    ax.xlabel = lbl[:x_label] == "default" ? def_x : lbl[:x_label] 
    ax.ylabel = lbl[:y_label] == "default" ? def_y : lbl[:y_label] 
    ax.title  = lbl[:title]   == "default" ? def_title : lbl[:title] 
    # (a grid of subplots shows the axis labels once per row and column: they are the same in every subplot)
    show_x, show_y = _outer_labels(ax)
    ax.xlabelvisible[] == show_x || (ax.xlabelvisible = show_x)
    ax.ylabelvisible[] == show_y || (ax.ylabelvisible = show_y)

    ax.titlesize = gen[:title_size] 
    ax.xlabelsize = ax.ylabelsize = gen[:label_size] 
    ax.xticklabelsize = ax.yticklabelsize = gen[:ticklabel_size] 

    haskey(x_ui, :label_offset) && (ax.xlabelpadding = x_ui[:label_offset]) 
    haskey(y_ui, :label_offset) && (ax.ylabelpadding = y_ui[:label_offset]) 
    
    ax.xgridvisible, ax.xticklabelsvisible = x_ui[:grid_visibility], x_ui[:tick_label_visibility] 
    rx, ry = get(x_ui, :reversed, false) === true, get(y_ui, :reversed, false) === true
    ax.xreversed[] == rx || (ax.xreversed = rx)
    ax.yreversed[] == ry || (ax.yreversed = ry)
    ax.ygridvisible, ax.yticklabelsvisible = y_ui[:grid_visibility], y_ui[:tick_label_visibility] 

    x_off = x_ui[:scale_offset] 
    if x_off != 0.0
        ax.xtickformat = (t -> map(v -> "$(round(x_off, sigdigits=3)) + $(@sprintf("%.1e", v - x_off))", t))
    elseif x_ui[:tick_format] != "default"
        ax.xtickformat = x_ui[:tick_format]
    end

    y_off = y_ui[:scale_offset] 
    if y_off != 0.0
        ax.ytickformat = (t -> map(v -> "$(round(y_off, sigdigits=3)) $(v - y_off < 0 ? "-" : "+") $(@sprintf("%.1e", abs(v - y_off)))", t))
    elseif y_ui[:tick_format] != "default"
        ax.ytickformat = y_ui[:tick_format]
    end

    # (after the formats: the ticks are drawn with them; the default format depends on the scale)
    _set_ticks!(ax, x_ui, y_ui)
end

function set_axis_styles!(ax::Axis3, def_x::String, def_y::String, def_z::String, def_title::String)
    
    gen = manager.ui[:axis_general]
    lbl = manager.ui[:labels]
    x_ui, y_ui, z_ui = _axis_ui(:x_axis), _axis_ui(:y_axis), _axis_ui(:z_axis)

    ax.xlabel = lbl[:x_label] == "default" ? def_x : lbl[:x_label] 
    ax.ylabel = lbl[:y_label] == "default" ? def_y : lbl[:y_label] 
    ax.zlabel = lbl[:z_label] == "default" ? def_z : lbl[:z_label] 
    ax.title  = lbl[:title]   == "default" ? def_title : lbl[:title] 

    ax.titlesize = gen[:title_size] 
    ax.xlabelsize = ax.ylabelsize = ax.zlabelsize = gen[:label_size] 
    ax.xticklabelsize = ax.yticklabelsize = ax.zticklabelsize = gen[:ticklabel_size] 

    ax.xgridvisible, ax.xticklabelsvisible = x_ui[:grid_visibility], x_ui[:tick_label_visibility] 
    ax.ygridvisible, ax.yticklabelsvisible = y_ui[:grid_visibility], y_ui[:tick_label_visibility] 
    ax.zgridvisible, ax.zticklabelsvisible = z_ui[:grid_visibility], z_ui[:tick_label_visibility] 
    for (attr, ui) in ((:xreversed, x_ui), (:yreversed, y_ui), (:zreversed, z_ui))
        r = get(ui, :reversed, false) === true
        getproperty(ax, attr)[] == r || setproperty!(ax, attr, r)
    end

    haskey(x_ui, :label_offset) && (ax.xlabeloffset = x_ui[:label_offset]) 
    haskey(y_ui, :label_offset) && (ax.ylabeloffset = y_ui[:label_offset]) 
    haskey(z_ui, :label_offset) && (ax.zlabeloffset = z_ui[:label_offset]) 

    ax.perspectiveness = 0.5
    if !manager.camera_locked[]
        ax.aspect = (1, 1, 0.6)
    end
end

"""
    _valid_color(c)
    _valid_colormap(c)

`true` if Makie can convert `c` to a colour (or every entry of a vector / tuple of colours) or to a colormap.
"""
function _valid_color(c)
    c isa AbstractVector && return all(_valid_color, c)
    try
        Makie.to_color(c)
        return true
    catch
        return false
    end
end
function _valid_colormap(c)
    try
        Makie.to_colormap(c)
        return true
    catch
        return false
    end
end

# `c` if it is a valid colour, otherwise `fallback` (with a warning naming `what`).
function _safe_color(c, fallback, what::AbstractString)
    _valid_color(c) && return c
    @warn "Invalid $what $(repr(c)); using $(repr(fallback)) instead."
    return fallback
end

"""
    plot_HUD!(ax::Axis)

Injects arbitrary user-defined shapes (scatter points, connected polygons, tracking lines) in relative screen-space coordinates (0.0, 1.0) directly on top of the active plot axes to highlight specific regions of interest.
"""
function plot_HUD!(ax::Axis)
    # Always clear the previous HUD before drawing or exiting
    delete_plots_by_label!(ax, "HUD")
    
    ui_hud = manager.ui[:hud]
    if !ui_hud[:visible] || isempty(ui_hud[:points])::Bool; return; end 
    
    pts = ui_hud[:points] 
    try
        x_pct = [Float64(p[1]) for p in pts]
        y_pct = [Float64(p[2]) for p in pts]
        
        if ui_hud[:close_loop] && length(x_pct) > 2 
            push!(x_pct, x_pct[1])
            push!(y_pct, y_pct[1])
        end

        mode  = lowercase(strip(ui_hud[:mode])) 
        color = _safe_color(ui_hud[:color], MASTER_UI_DICT[:hud][:color], "HUD color")
        lw    = ui_hud[:line_width] 
        ls    = ui_hud[:line_style] 
        ms    = ui_hud[:marker_size] 

        # Add label="HUD" to all primitives so they can be targeted and deleted
        if mode == "scatter"
            scatter!(ax, x_pct, y_pct; color=color, markersize=ms, space=:relative, label="HUD")
        elseif mode == "scatterlines"
            scatterlines!(ax, x_pct, y_pct; color=color, linewidth=lw, linestyle=ls, markersize=ms, space=:relative, label="HUD")
        elseif mode == "polygon"
            poly_pts = Point2f.(zip(x_pct, y_pct))
            poly!(ax, poly_pts; color=(color, 0.3), strokecolor=color, strokewidth=lw, space=:relative, label="HUD")
        else
            lines!(ax, x_pct, y_pct; color=color, linewidth=lw, linestyle=ls, space=:relative, label="HUD")
        end
    catch e
        @warn "Failed to plot HUD. Ensure 'points' is a vector of tuples, e.g., [(0.1, 0.1), (0.9, 0.9)]."
    end
end

plot_HUD!(ax::Axis3) = nothing

# The vertical variable of the plot a series' second coordinate lives in: the dependent field of a 1D plot (`u_field`:
# the subplot's own, else the selected one), the y variable of a 2D plot, `nothing` for 3D plots (no series)
function _series_vertical(u_field = nothing)
    w = manager.widgets
    haskey(w, :plot_style) || return nothing
    style = _base_style(w[:plot_style].selection[])
    dim = get(PLOT_DIM_MAP, style, 1)
    (dim == 3 || is_surface(style)) && return nothing
    return dim == 1 ? something(u_field, w[:u_axis].selection[]) : w[:y_axis].selection[]
end

# The External Series (`manager.ui[:series]`, `studio_add_series!`) as `(label, x, y)`, sorted by label, if the plot
# shows the x variable and the vertical variable they were added for (else none); `u_field`: the subplot's field
function _shown_series(u_field = nothing)
    ui = get(manager.ui, :series, nothing)
    out = Tuple{String, Vector{Float64}, Vector{Float64}}[]
    (isnothing(ui) && return out)
    (ui[:visible] === true && _valid_series_data(ui[:data]) && !isempty(ui[:data])) || return out
    vertical = _series_vertical(u_field)
    isnothing(vertical) && return out
    x_sel = haskey(manager.widgets, :x_axis) ? manager.widgets[:x_axis].selection[] : nothing
    (ui[:x_axis] === :none || ui[:x_axis] === x_sel) || return out
    (ui[:y_axis] === :none || ui[:y_axis] === vertical) || return out
    for (label, pts) in sort!(collect(ui[:data]); by = p -> string(first(p)))
        push!(out, (string(label), Float64[p[1] for p in pts], Float64[p[2] for p in pts]))
    end
    return out
end

# The colour / marker index of the `j`-th series: after the methods (or the lines) in the lists of `plot_style`
_series_style_index(j::Int) = (isempty(manager.series) ? length(manager.methods[]) : length(manager.series)) + j

"""
    plot_series!(ax::Axis, u_field)

Draws the External Series (*UI → External Series*, `studio_add_series!`) in a 1D or 2D subplot, in the plot's
coordinates (above a heatmap: e.g. a curve `y(x)` separating regions), tagged "External Series" (replaced on every
UI step); nothing if the plot does not show their x and vertical variable.
"""
function plot_series!(ax::Axis, u_field)
    delete_plots_by_label!(ax, "External Series")
    ui_app, ui = manager.ui[:plot_style], get(manager.ui, :series, nothing)
    isnothing(ui) && return nothing
    for (j, (label, x, u)) in enumerate(_shown_series(u_field))
        k = _series_style_index(j)
        color = Makie.to_color(ui_app[:colors][mod1(k, end)])
        mrk, ms = _marker_and_size(ui_app, k)
        lw, ls = Float32(ui[:line_width]), ui[:line_style]
        p = if ms > 0 && !_no_marker(mrk)
            scatterlines!(ax, x, u; color, linewidth = lw, linestyle = ls, marker = mrk, markersize = Float32(ui[:marker_size]),
                          label = "External Series")
        else
            lines!(ax, x, u; color, linewidth = lw, linestyle = ls, label = "External Series")
        end
        translate!(p, 0, 0, 50)   # (above a heatmap or filled contours; CairoMakie draws by z)
    end
    return nothing
end
plot_series!(ax::Axis3, u_field) = nothing

# The slices of a 1D subplot with the shown External Series added (for the axis limits); `field` is `:x` or `:y`
function _with_series(slices, field::Symbol)
    shown = _shown_series()
    isempty(shown) && return slices
    return Any[collect(slices); [field === :x ? s[2] : s[3] for s in shown]]
end


function _apply_axis_styles!(ax, T::Symbol; u = nothing)
    u_field = u
    x = frontend_key(manager.widgets[:x_axis].selection[])
    y = frontend_key(manager.widgets[:y_axis].selection[])
    z = frontend_key(manager.widgets[:z_axis].selection[])
    u = frontend_key(something(u, manager.widgets[:u_axis].selection[]))   # (Compare: fields: the subplot's own)
    
    dim = PLOT_DIM_MAP[T] 
    def_title = ax.title[]
    
    if ax isa Axis
        def_y = dim == 1 ? u : y
        set_axis_styles!(ax, x, def_y, def_title)
        plot_HUD!(ax)
        plot_series!(ax, u_field)   # (1D and 2D plots)
    elseif ax isa Axis3
        def_z = dim == 2 ? u : z
        set_axis_styles!(ax, x, y, def_z, def_title)
    end
end

function _find_first_drawable_primitive(cache_dict)
    for method_name in keys(cache_dict)
        prims = cache_dict[method_name].primitives
        for (pkey, prim) in prims
            if pkey in COLORBAR_SUPPORTED_PLOTS
                return prim
            end
        end
    end
    return nothing
end

"""
    _collect_legend_elements(ui_app::Dict)

Scans the active `PlotCache` and constructs the precise array of `Makie.LineElement`, `Makie.MarkerElement`, and `Makie.PolyElement` prototypes needed to render a visually accurate legend block.
"""
# The plot cache of a method or series in the first subplot that draws it, or `nothing`
function _legend_cache(key::Symbol)
    for i in sort!(collect(keys(manager.caches)))
        haskey(manager.caches[i], key) && return manager.caches[i][key]
    end
    return nothing
end

function _collect_legend_elements(ui_app::Dict)
    
    plotted_objects = []
    labels_for_legend = String[]
    
    isempty(manager.caches) && return [], []
    
    get_color(idx) = get(ui_app, :colors, nothing) !== nothing ? ui_app[:colors][mod1(idx, end)] : :black 

    seen = Set{String}()
    for method_name in (isempty(manager.series) ? manager.methods[] : manager.series)
        cache = _legend_cache(method_name)   # (any subplot: compared methods draw their lines in their own)
        if !isnothing(cache)
            m_idx = something(_style_index(method_name), 1)
            prims = cache.primitives
            color = get_color(m_idx)
            
            group = []
            is_base = false
            
            method_label_str = frontend_key(method_name)
            # (compared methods with lines over a parameter: the lines of a value share the label and colour)
            method_label_str in seen && continue
            push!(seen, method_label_str)
            
            for (pkey, prim) in prims
                deps = get(STYLE_DEPENDENCIES, pkey, Symbol[])
                
                if pkey == :contour_f
                    push!(plotted_objects, [Makie.PolyElement(color=Makie.to_colormap(ui_app[:color_map])[end])]) 
                    push!(labels_for_legend, "$(method_label_str) (Base)")
                    is_base = true
                end
                
                if :line_width in deps && :colors in deps
                    ls = (ui_app[:dashed_lines] && :dashed_lines in deps) ? ui_app[:line_styles][mod1(m_idx, end)] : nothing 
                    push!(group, Makie.LineElement(color=color, linewidth=ui_app[:line_width], linestyle=ls)) 
                end
                
                if :markers in deps && :colors in deps && !_no_marker(ui_app[:markers][mod1(m_idx, end)])
                    mrk = ui_app[:markers][mod1(m_idx, end)] 
                    push!(group, Makie.MarkerElement(color=color, marker=mrk, markersize=ui_app[:marker_size])) 
                end
            end
            
            if !isempty(group)
                push!(plotted_objects, group)
                if !is_base
                    push!(labels_for_legend, method_label_str)
                end
            end
        end
    end
    # (the External Series, after the methods, if the plot shows them)
    ui = get(manager.ui, :series, nothing)
    for (j, (label, _, _)) in enumerate(_shown_series())
        k = _series_style_index(j)
        c = Makie.to_color(get_color(k))
        group = Any[Makie.LineElement(color = c, linewidth = Float32(ui[:line_width]), linestyle = ui[:line_style])]
        mrk, ms = _marker_and_size(ui_app, k)
        (ms > 0 && !_no_marker(mrk)) && push!(group, Makie.MarkerElement(color = c, marker = mrk, markersize = Float32(ui[:marker_size])))
        push!(plotted_objects, group)
        push!(labels_for_legend, label)
    end

    return plotted_objects, labels_for_legend
end

"""
    extract_and_store_camera_state!(plot_layout::GridLayout)

Scrapes the precise mathematical bounding boxes, Azimuth, and Elevation angles from all actively drawn Makie axes and locks them into the persistent `Camera_Cache`. Used for exporting perfectly aligned animation frames.
"""
function extract_and_store_camera_state!(plot_layout::GridLayout)
    cam_opts = Dict{Symbol, Any}()
    axes = [c.content for c in plot_layout.content if c.content isa Axis || c.content isa Axis3]
    for (i, ax) in enumerate(axes)
        if ax isa Axis
            lims = ax.finallimits[]
            cam_opts[Symbol("Axis_$(i)_Limits")] = Float64[lims.origin[1], lims.origin[1] + lims.widths[1], lims.origin[2], lims.origin[2] + lims.widths[2]]
        elseif ax isa Axis3
            lims = ax.finallimits[]
            cam_opts[Symbol("Axis_$(i)_Limits3D")]  = Float64[
                lims.origin[1], lims.origin[1] + lims.widths[1], 
                lims.origin[2], lims.origin[2] + lims.widths[2], 
                lims.origin[3], lims.origin[3] + lims.widths[3]
            ]
            cam_opts[Symbol("Axis_$(i)_Azimuth")]   = Float64(ax.azimuth[])
            cam_opts[Symbol("Axis_$(i)_Elevation")] = Float64(ax.elevation[])
        end
    end
    manager.camera_cache = cam_opts
end

"""
    _enforce_camera_lock!(axes::Vector)

Overrides the automatic scaling of a newly drawn plot to forcibly match the bounding box stored in the `Camera_Cache`. 
If the camera is not globally locked by the user, the cache is instantly cleared after application to allow auto-scaling to resume on the next frame.
"""
function _enforce_camera_lock!(axes::Vector)
    
    is_locked = manager.camera_locked[]
    cam_opts = manager.camera_cache
    
    if !isempty(cam_opts)
        for (i, ax) in enumerate(axes)
            if ax isa Axis && haskey(cam_opts, Symbol("Axis_$(i)_Limits"))
                l = cam_opts[Symbol("Axis_$(i)_Limits")]
                try limits!(ax, l[1], l[2], l[3], l[4]) catch; end
            elseif ax isa Axis3
                try
                    if haskey(cam_opts, Symbol("Axis_$(i)_Limits3D"))
                        l = cam_opts[Symbol("Axis_$(i)_Limits3D")]
                        limits!(ax, l[1], l[2], l[3], l[4], l[5], l[6])
                    end
                    if haskey(cam_opts, Symbol("Axis_$(i)_Azimuth"))
                        ax.azimuth[] = Float32(cam_opts[Symbol("Axis_$(i)_Azimuth")])
                    end
                    if haskey(cam_opts, Symbol("Axis_$(i)_Elevation"))
                        ax.elevation[] = Float32(cam_opts[Symbol("Axis_$(i)_Elevation")])
                    end
                catch
                end
            end
        end
        
        # If it wasn't permanently locked by the user, clear the camera again
        if !is_locked
            empty!(manager.camera_cache)
        end
    end
end