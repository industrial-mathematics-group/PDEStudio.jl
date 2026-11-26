# ==============================================================================
# --- CSV serialisation of the studio state ---
# ==============================================================================
#
# Every file is a table `Category, Scope, Parameter, Value`; values are written with `val2str` and read back
# with the safe literal parser `str2val` (no code is evaluated). Categories:
#   Metadata    General (export info, bundled sources) / Preset (description, type, mode)
#   Git, Julia  reproducibility information (full exports)
#   Scene       Plot, Layout, Camera, Labels, Exploration
#   UI          one scope per `manager.ui` scope
#   Simulation  Shared, Sweep, Config (methods, defaults, reference, postprocess), one scope per method
#   Config      Dimensions, Resolution_Base, Resolution_Ref (structure of the studio)
# Keys are the backend names (`animation_FPS`, `sim_func_name`); display labels never appear in files.

# ------------------------------------------------------------------------------
# Writing
# ------------------------------------------------------------------------------

struct _CSVRows
    cats::Vector{String}
    scopes::Vector{String}
    params::Vector{String}
    vals::Vector{String}
end
_CSVRows() = _CSVRows(String[], String[], String[], String[])

function add_row!(rows::_CSVRows, cat, scope, param, value)
    push!(rows.cats, string(cat))
    push!(rows.scopes, string(scope))
    push!(rows.params, string(param))
    push!(rows.vals, val2str(to_value(value)))
    return rows
end

function _write_rows(path::AbstractString, rows::_CSVRows)
    mkpath(dirname(abspath(path)))
    CSV.write(path, DataFrame(Category = rows.cats, Scope = rows.scopes, Parameter = rows.params, Value = rows.vals))
    return path
end

_sorted_pairs(d) = sort!(collect(d), by = p -> string(first(p)))

function _add_scene_rows!(rows::_CSVRows)
    # The persistent caches hold the state even when no window is open; open widgets take precedence.
    plot_opts = merge(copy(manager.plot_cache), extract_plot_options())
    for (k, v) in _sorted_pairs(plot_opts)
        add_row!(rows, "Scene", "Plot", k, v)
    end
    layout_opts = merge(copy(manager.layout_cache), extract_layout_options())
    for (k, v) in _sorted_pairs(layout_opts)
        add_row!(rows, "Scene", "Layout", k, v)
    end
    for (k, v) in _sorted_pairs(manager.camera_cache)
        add_row!(rows, "Scene", "Camera", k, v)
    end
    for (k, v) in _sorted_pairs(manager.labels)   # (all of them: a label equal to its key isn't the default, e.g. "t")
        add_row!(rows, "Scene", "Labels", k, v)
    end
    exp_opts = merge(copy(manager.exploration_cache), extract_exploration_options())
    for (k, v) in _sorted_pairs(exp_opts)
        add_row!(rows, "Scene", "Exploration", k, v)
    end
    for (k, names) in _sorted_pairs(manager.value_labels)   # (names of swept values: value => name)
        isempty(names) || add_row!(rows, "Scene", "Value_Labels", k, Dict{Any, String}(names))
    end
    return rows
end

function _add_ui_rows!(rows::_CSVRows)
    for (scope, dict) in _sorted_pairs(manager.ui)
        for (k, v) in _sorted_pairs(dict)
            add_row!(rows, "UI", scope, k, v)
        end
    end
    return rows
end

const _RESERVED_SIM_SCOPES = ("Shared", "Sweep", "Config")

# Text parameters that would read back as something else ("1e3", "Float64", "Nothing") are written quoted, and numbers
# and static vectors whose type `val2str` doesn't write are written with it (see `_typed_text`), so a simulation
# parameter keeps its type (and its data-file hash, which is computed from `val2str`) through a CSV round trip.
function _csv_text(v)
    v isa AbstractString && return (!isempty(v) && !isequal(_parse_csv_value(v), v)) ? repr(String(v)) : v
    return _needs_type(v) ? _typed_text(v) : v
end

# Values `val2str` writes without their type: `Float32`/`Float16` numbers (as `1.5`, read back as `Float64`) and static
# vectors (as `Float64[…]`, read back as `Vector`), also inside tuples, untyped vectors and dictionaries; and values
# it writes as something else: pairs (as `Pair(first=…, second=…)`), and `nothing` and `missing` inside a container
# (as the types `Nothing`, `Missing`). (Other number types are no parameter values, see PDEStudioCore.)
_needs_type(v) = v isa Union{Float32, Float16} || v isa SVector ||
                 v isa Pair || (v isa Tuple && any(_needs_type_inside, v)) ||
                 (v isa AbstractVector && ((!isconcretetype(eltype(v)) && any(_needs_type, v)) || any(_literal_inside, v))) ||
                 (v isa AbstractDict && any(p -> _needs_type_inside(p.first) || _needs_type_inside(p.second), v))
_literal_inside(x) = x === nothing || x === missing || x isa Pair
_needs_type_inside(x) = _literal_inside(x) || _needs_type(x)

# The literal of `v` with these types (`1.5f0`, `Float16(1.5)`, `SA{Float64}[1.0, 2.0]`, `(nothing, 1.0)`,
# `:a => 1`, `Dict{Symbol, Any}(:a => nothing)`), which `str2val` reads back; everything else as `val2str` writes it.
# (What still doesn't read back as the value is an object, see `_csv_object`.)
function _typed_text(v)
    v === nothing && return "nothing"
    v === missing && return "missing"
    _needs_type(v) || return val2str(v; top_level = false)
    v isa Union{Float32, Float16} && return repr(v)
    if v isa Pair
        side(x) = x isa Pair ? "($(_typed_text(x)))" : _typed_text(x)
        return "$(side(v.first)) => $(side(v.second))"
    end
    if v isa AbstractDict
        entries = sort!(["$(_typed_text(k)) => $(_typed_text(x))" for (k, x) in v])
        return "Dict{$(keytype(v)), $(valtype(v))}($(join(entries, ", ")))"
    end
    elements = join(map(_typed_text, collect(v)), ", ")
    v isa SVector && return "SA{$(eltype(v))}[$elements]"
    v isa Tuple && return length(v) == 1 ? "($elements,)" : "($elements)"
    return (eltype(v) === Any ? "Any" : string(eltype(v))) * "[$elements]"
end

# The text a sweep is written as (`Simulation, Sweep`): no quoting of text, the types `_typed_text` adds.
_sweep_text(v) = _needs_type(v) ? _typed_text(v) : v

# What the CSV reads back for a value written as `text` (see `add_row!` and `_parse_csv_value`).
_csv_readback(text) = _parse_csv_value(val2str(to_value(text)))

"""
    _csv_object(v; sweep = false) -> Bool

Whether the parameter value `v` is an *object*: a value the CSV holds as text only, because its text doesn't read back
as the value (a struct, an enum, a container holding one). Objects come from the source files: an export writes them
as `Object` rows, a reload takes them from the configuration the bundled sources build (see
`csv_to_simulation_config`), and the editors don't overwrite them. `sweep = true` for the values of a sweep.
"""
function _csv_object(v; sweep::Bool = false)
    return try
        !isequal(_csv_readback(sweep ? _sweep_text(v) : _csv_text(v)), v)
    catch
        true
    end
end

# The parameters of a configuration that are objects, as `(scope, key)`: `(:Shared, key)`, `(method, key)` (of the
# methods `method_names`) and `(:Sweep, key)`.
function _object_entries(config::SimulationConfig, method_names = keys(config.methods))
    entries = Tuple{Symbol, Symbol}[]
    for (k, v) in _sorted_pairs(config.shared)
        _csv_object(v) && push!(entries, (:Shared, Symbol(k)))
    end
    for m in sort!(collect(Symbol, method_names), by = string)
        haskey(config.methods, m) || continue
        for (k, v) in _sorted_pairs(config.methods[m])
            _csv_object(v) && push!(entries, (m, Symbol(k)))
        end
    end
    for (k, v) in _sorted_pairs(config.varied)
        _csv_object(v; sweep = true) && push!(entries, (:Sweep, Symbol(k)))
    end
    return entries
end

# The `Object` rows of a parsed CSV: `(scope, key) => value` (the text the CSV holds), scopes `Shared`, `Sweep` and
# method names.
function _object_rows(parsed::Dict)
    rows = Dict{Tuple{Symbol, Symbol}, Any}()
    for (scope, params) in get(parsed, "Object", Dict())
        scope == "Config" && throw(ArgumentError("Object rows have the scopes Shared, Sweep and the methods, not Config"))
        for (k, v) in params
            rows[(Symbol(scope), Symbol(k))] = v
        end
    end
    return rows
end

"""
    _add_simulation_rows!(rows, config::SimulationConfig)

Writes the simulation category of a configuration: shared parameters, the parameters of the *active* methods
(`defaults`; inactive methods are left out, like they are left out of the plots), the method list, the active
methods, the reference and post-processing function names, and the sweep (`Simulation, Sweep`). Parameters that are objects
(see `_csv_object`) are written as `Object` rows with the same scopes (`Object, Shared, bc, Wall(id=1)`) instead of
`Simulation` rows: a reload takes them from the bundled sources.
"""
function _add_simulation_rows!(rows::_CSVRows, config::SimulationConfig)
    # (objects as `Object` rows of the same scope)
    category(v; sweep = false) = _csv_object(v; sweep = sweep) ? "Object" : "Simulation"
    for (k, v) in _sorted_pairs(config.shared)
        add_row!(rows, category(v), "Shared", k, _csv_text(v))
    end
    method_names = sort!(filter(m -> haskey(config.methods, m), unique(config.defaults)))
    for m in method_names
        if string(m) in _RESERVED_SIM_SCOPES
            @warn "Method :$m clashes with a reserved CSV scope; its parameters are not saved."
            continue
        end
        for (k, v) in _sorted_pairs(config.methods[m])
            add_row!(rows, category(v), m, k, _csv_text(v))
        end
    end
    add_row!(rows, "Simulation", "Config", "methods", method_names)
    add_row!(rows, "Simulation", "Config", "defaults", config.defaults)
    add_row!(rows, "Simulation", "Config", "reference", isnothing(config.reference) ? "none" : string(config.reference))
    add_row!(rows, "Simulation", "Config", "postprocess", isnothing(config.postprocess) ? "none" : string(config.postprocess))
    for (k, v) in _sorted_pairs(config.varied)
        add_row!(rows, category(v; sweep = true), "Sweep", k, _sweep_text(v))
    end
    return rows
end

# ------------------------------------------------------------------------------
# Reading
# ------------------------------------------------------------------------------

function _parse_csv_value(s::AbstractString)
    txt = strip(String(s))
    txt == "Nothing" && return nothing  # `val2str(nothing)` writes "Nothing"
    txt == "Missing" && return missing  # ... and `val2str(missing)` "Missing"
    return str2val(txt)
end

# The column numbers of `Category, Scope, Parameter, Value` in the rows of a studio CSV (header names stripped, so a
# hand-written header with spaces after the commas works); an ArgumentError for any other header.
function _csv_columns(row, filepath::AbstractString)
    names = Dict(strip(string(n)) => i for (i, n) in enumerate(propertynames(row)))
    cols = map(c -> get(names, c, nothing), ("Category", "Scope", "Parameter", "Value"))
    any(isnothing, cols) && throw(ArgumentError("$(basename(filepath)) is no studio CSV: its header must be " *
                                                "Category, Scope, Parameter, Value"))
    return cols
end

# The text of a value cell: an unquoted value is stripped (`…, Upwind scheme` written by hand), a quoted one keeps its
# spaces (the studio's writer quotes such texts). `text` holds the file's text, read only when a value needs it.
function _csv_value_text(val::String, filepath::AbstractString, text::Ref)
    val == strip(val) && return val
    isnothing(text[]) && (text[] = read(filepath, String))
    return occursin('"' * replace(val, '"' => "\"\"") * '"', text[]) ? val : String(strip(val))
end

"""
    _read_csv(filepath)

Reads a studio CSV into two nested dictionaries `[Category][Scope][Parameter]`: the parsed values and the raw cell
texts (used where text must stay text, e.g. labels and string-valued UI options).
"""
function _read_csv(filepath::AbstractString)
    parsed = Dict{String, Dict{String, Dict{String, Any}}}()
    raw = Dict{String, Dict{String, Dict{String, String}}}()
    cols = nothing
    text = Ref{Union{Nothing, String}}(nothing)
    for row in CSV.Rows(filepath)
        # Hand-written files may have spaces after the commas (`Category, Scope, Parameter, Value`): the column names
        # and the key cells are stripped.
        isnothing(cols) && (cols = _csv_columns(row, filepath))
        # CSV.Rows yields lazy string types; plain `String`s are needed by the parser (and as dict keys)
        cat, scope, param = (String(strip(String(coalesce(row[c], "")))) for c in cols[1:3])
        val_str = _csv_value_text(String(coalesce(row[cols[4]], "")), filepath, text)
        (isempty(cat) || isempty(param)) && continue
        get!(Dict{String, Any}, get!(Dict{String, Dict{String, Any}}, parsed, cat), scope)[param] = _parse_csv_value(val_str)
        get!(Dict{String, String}, get!(Dict{String, Dict{String, String}}, raw, cat), scope)[param] = val_str
    end
    return parsed, raw
end

"""
    parse_csv_to_dict(filepath::AbstractString)

Reads an RFC 4180 CSV file into a nested `Dict` hierarchy `[Category][Scope][Parameter]`, parsing every value with the
safe literal parser `str2val` (vectors, tuples, symbols, numbers, …). No code is evaluated.
"""
parse_csv_to_dict(filepath::AbstractString) = first(_read_csv(filepath))

# The raw cell text of an entry ("<empty>" is the empty string), or `nothing`.
function _raw_value(raw, cat, scope, key)
    isnothing(raw) && return nothing
    r = get(get(get(raw, string(cat), Dict()), string(scope), Dict()), string(key), nothing)
    isnothing(r) && return nothing
    return r == "<empty>" ? "" : String(r)
end

# The `manager.ui` / MASTER_UI_DICT scope behind a UI scope name: `x_axis`, `y_axis` and `z_axis` stand for the axis
# variant of the active plot type (`x_axis_1d` for 1D plots, `x_axis_nd` for 2D and 3D plots, `z_axis_3d`), the
# editor pages of the plot types (`:lines_1d`, …) for the shared `plot_style` scope.
function _ui_template_scope(scope::Symbol)
    haskey(STYLE_DEPENDENCIES, scope) && return :plot_style
    scope === :z_axis && return :z_axis_3d
    scope in (:x_axis, :y_axis) || return scope
    ptype = manager.active_plot_type
    one_d = get(PLOT_DIM_MAP, ptype, 1) == 1 && !is_surface(ptype)
    return Symbol(scope, one_d ? "_1d" : "_nd")
end

# The options of the axis `:x_axis`, `:y_axis` or `:z_axis` for the active plot type.
_axis_ui(axis::Symbol) = manager.ui[_ui_template_scope(axis)]

function _ui_template_value(scope::Symbol, key::Symbol)
    template = _ui_template_scope(scope)
    haskey(manager.ui, template) && haskey(manager.ui[template], key) && return manager.ui[template][key]
    haskey(MASTER_UI_DICT, template) && return get(MASTER_UI_DICT[template], key, nothing)
    return nothing
end

# Text-valued options stay text, even if the text looks like a number, symbol or type ("1e3", "Float64", ...).
function _coerce_ui_value(scope::Symbol, key::Symbol, value, raw_value)
    template = _ui_template_value(scope, key)
    if template isa AbstractString && !(value isa AbstractString)
        return isnothing(raw_value) ? val2str(value) : raw_value
    end
    return value
end

function _parse_dims(raw)
    raw isa Tuple && return Tuple(Symbol(d) for d in raw)
    raw isa AbstractVector && return Tuple(Symbol(d) for d in raw)
    raw isa Symbol && return (raw,)
    @warn "Ignoring invalid allowed_dims $(repr(raw)); expected a tuple of symbols such as (:x, :t)."
    return manager.allowed_dims
end

_scene_source(parsed::Dict, name::String) = get(get(parsed, "Scene", Dict()), name, nothing)

_has_visual_data(parsed::Dict) = haskey(parsed, "Scene") || haskey(parsed, "UI")

_keysyms(d) = Dict{Symbol, Any}(Symbol(k) => v for (k, v) in d)

# ------------------------------------------------------------------------------
# Bundled source files
# ------------------------------------------------------------------------------

"""
    _include_as(mod, file, as, copies = Dict{String, String}())

Runs the code of `file` in `mod` as if it were the file `as`: `@__DIR__` and relative `include`s resolve next to
`as`. Used to run the snapshot of a source file bundled with an export at the place of its original, so it finds the
files next to the original that aren't bundled (helpers it includes, data files). `include`s of the files in `copies`
(original path => bundled copy) run the copy instead, also as the original (see `_redirect_includes`). (Sets the
task-local source path that `Base.include` uses.)
"""
function _include_as(mod::Module, file::AbstractString, as::AbstractString,
                     copies::Dict{String, String} = Dict{String, String}(), mapexpr = identity)
    tls = task_local_storage()
    previous = get(tls, :SOURCE_PATH, nothing)
    tls[:SOURCE_PATH] = as
    try
        return Base.include_string(ex -> _redirect_includes(mapexpr(ex), dirname(as), copies), mod, read(file, String), as)
    finally
        isnothing(previous) ? delete!(tls, :SOURCE_PATH) : (tls[:SOURCE_PATH] = previous)
    end
end

# `include` and `Base.include` for code that runs in `dir`: a file in `copies` (original path => bundled copy) runs
# its copy as the original, any other file runs as usual, its `include`s redirected in the same way.
struct _BundledInclude
    mod::Module
    dir::String
    copies::Dict{String, String}
end
(inc::_BundledInclude)(path::AbstractString) = _bundled_include(inc.mod, inc.dir, path, inc.copies, identity)
(inc::_BundledInclude)(mapexpr::Function, path::AbstractString) =
    _bundled_include(inc.mod, inc.dir, path, inc.copies, mapexpr)
struct _BundledBaseInclude
    dir::String
    copies::Dict{String, String}
end
(inc::_BundledBaseInclude)(mod::Module, path::AbstractString) = _bundled_include(mod, inc.dir, path, inc.copies, identity)
(inc::_BundledBaseInclude)(mapexpr::Function, mod::Module, path::AbstractString) =
    _bundled_include(mod, inc.dir, path, inc.copies, mapexpr)

function _bundled_include(mod::Module, dir::AbstractString, path::AbstractString, copies::Dict{String, String},
                          mapexpr)
    file = normpath(isabspath(path) ? path : joinpath(dir, path))
    copy = get(copies, file, nothing)
    isnothing(copy) || return _include_as(mod, copy, file, copies, mapexpr)
    return Base.include(ex -> _redirect_includes(mapexpr(ex), dirname(file), copies), mod, file)
end

# Replaces `include` (calls such as `include("h.jl")` and `include(f, "h.jl")`, and `include` as a value, as in
# `foreach(include, files)` or `include.(files)`) and `Base.include` in code that runs in `dir` by `_BundledInclude`
# / `_BundledBaseInclude`. `include` is replaced only where its value is the module's `include` (`_redirected`), so a
# variable or keyword of that name keeps its value; names are kept: of definitions (`include(p) = …` of a baremodule),
# assigned variables (also in tuples and `for`), declarations, keyword shorthands (`(; include)`) and macro arguments.
const _NO_VALUE_HEADS = (:import, :using, :export, :public, :struct, :abstract, :primitive, :quote, :inert, :braces)
const _NAME_HEADS = (:global, :local, :const, :parameters, :macrocall)   # (their bare Symbol arguments are names)
function _redirect_includes(ex, dir::AbstractString, copies::Dict{String, String})
    isempty(copies) && return ex
    ex === :include && return Expr(:call, _redirected, :include, _MODULE_EXPR, dir, copies)
    ex isa Expr || return ex
    ex == _BASE_INCLUDE && return Expr(:call, _BundledBaseInclude, dir, copies)
    ex.head in _NO_VALUE_HEADS && return ex
    redirect(a) = _redirect_includes(a, dir, copies)
    # (kept: the signature of a definition, the name of an assigned variable or keyword, the name of a module)
    kept = ex.head in (:function, :macro, :->, :kw) ||
           (ex.head === :(=) && (ex.args[1] isa Symbol || _is_signature(ex.args[1]) || Meta.isexpr(ex.args[1], :tuple))) ? 1 :
           ex.head === :module ? 2 : 0
    names = ex.head in _NAME_HEADS
    return Expr(ex.head, (i <= kept || (names && a isa Symbol) ? a : redirect(a) for (i, a) in enumerate(ex.args))...)
end
_is_signature(ex) = ex isa Expr && ex.head in (:call, :where, :(::))
_redirected(value, mod::Module, dir, copies) =
    isdefined(mod, :include) && value === getglobal(mod, :include) ? _BundledInclude(mod, dir, copies) : value
const _MODULE_EXPR = Expr(:macrocall, GlobalRef(Base, Symbol("@__MODULE__")), LineNumberNode(0))
const _BASE_INCLUDE = Expr(:., :Base, QuoteNode(:include))

# The original a bundled copy runs in place of (`manager.source_origins`, recorded when its export is loaded; also after
# the copy was edited), or `nothing`. The entries are dropped when a `.jl` file is loaded (its configuration replaces
# the loaded one), and an entry when an export writes another file over the copy (see `save_params_to_csv`).
_origin_of(copy::AbstractString) = isfile(copy) ? get(manager.source_origins, abspath(copy), nothing) : nothing

"""
    _include_sources(sources)

Includes the source files of a configuration before a run, as loading its export ran them: a bundled copy runs in place
of its original (see `_run_bundled_sources`), and `include`s of the originals of the bundled copies run the copies.
The rest is included as PDEStudioCore's `run_all_simulations` does.
"""
function _include_sources(sources::AbstractVector{<:AbstractString})
    copies = Dict{String, String}()
    for src in sources
        origin = _origin_of(src)
        isnothing(origin) || (copies[normpath(origin)] = abspath(src))
    end
    for src in sources
        path = abspath(src)
        isfile(path) || throw(ArgumentError("source file not found: $path"))
        origin = _origin_of(path)
        if isnothing(origin)
            Base.include(ex -> _redirect_includes(ex, dirname(path), copies), get_target_module(), path)
        else
            _include_as(get_target_module(), path, origin, copies)
        end
    end
    return nothing
end

"""
    _run_simulations(config; kwargs...)

`run_all_simulations(config; kwargs...)`, with the sources included by `_include_sources` (so a loaded export runs as
it loaded); a dry run that records the missing runs (`manager.missing_runs`) with `set_compute!(false)`.
"""
function _run_simulations(config::SimulationConfig; kwargs...)
    compute = _COMPUTE[]   # (`set_compute!(false)`: a dry run, the missing runs are listed)
    _include_sources(config.sources)
    summary = run_all_simulations(config; kwargs..., dry_run = !compute, load_sources = false)
    manager.missing_runs = compute ? ParamDict[] : copy(summary.ran)
    return summary
end

"""
    set_compute!(on::Bool = true) -> Bool

Whether the studio may compute: with `set_compute!(false)` *Run Simulation*, `launch_plotter(config)` and loaded
configuration files only look at what is stored (a dry run of `run_all_simulations`): nothing is computed or
written, runs that are missing stay gaps in the plots, and the status line, [`studio_state`](@ref) (`missing_runs`)
and [`describe_studio`](@ref) list them. For expensive data (GPU runs, a copy of the data on another machine): with
a wrong save path, loading a configuration file would otherwise start the simulations. Statistics and post-processing
are not computed either: the plots show what the data files hold. Stays set for the session; returns the setting.
`launch_plotter(config; compute = false)` sets it, too.
"""
function set_compute!(on::Bool = true)
    changed = _COMPUTE[] != on
    _COMPUTE[] = on
    _sync_data_buttons!()
    changed && haskey(manager.widgets, :status_label) &&
        _status!(on ? "Computing is on: Run Simulation computes missing runs." :
                      "Computing is off: Run Simulation only shows stored runs (missing ones are listed).", :ok)
    return on
end
const _COMPUTE = Ref(true)

"""
    _run_bundled_sources(parsed, filepath; run = true)

Includes the source files bundled with an exported CSV (`<name>_sources/`) into the target module (this executes their
code) and returns the configuration the last one returns. The export runs as it was exported: every bundled copy
runs, in place of its original (`@__DIR__` and relative `include`s resolve next to the original, so files that aren't
bundled, such as helpers that aren't listed as sources and data files, are found there), and `include`s of the
originals of bundled files run their copies. If an original was edited since the export, or is gone, the status line
says so (`manager.source_note`).

The sources of the loaded configuration are the originals that are unchanged, and the copies of the others: *Run
Simulation* includes them again (as the load ran them, see `_include_sources`) and the next export bundles them,
recording the originals as their origin.

A bundled copy that is missing, a source that fails, and (with `run`) a last source that returns no configuration (a
`SimulationConfig`, or a function without arguments that returns one, see `_config_value`) are errors: the file isn't
loaded. Returns `(config, sources, sources_of)`: the configuration (`nothing` without `run`), the sources, and the source
of each original (original path => source).

With `run = false` nothing is executed: the sources are worked out as above and returned for *Run Simulation*, which
includes them. A CSV without `Object` rows loads this way (see `load_and_apply_csv!`).
"""
function _run_bundled_sources(parsed::Dict, filepath::AbstractString; run::Bool = true)
    manager.source_note = ""
    meta = get(get(parsed, "Metadata", Dict()), "General", Dict())
    names = get(meta, "bundled_sources", nothing)
    names isa AbstractString && (names = isempty(names) ? String[] : [names])
    (names isa AbstractVector && !isempty(names)) || return nothing, String[], Dict{String, String}()
    origins = get(meta, "source_origins", String[])
    origins = origins isa AbstractString ? [origins] : origins
    origins = origins isa AbstractVector ? String[string(o) for o in origins] : String[]

    dir = dirname(abspath(filepath))
    bundled = String[abspath(joinpath(dir, string(name))) for name in names]
    gone = filter(!isfile, bundled)
    isempty(gone) ||
        throw(ArgumentError("$(basename(filepath)): bundled source file(s) missing: $(join(gone, ", ")). Restore them " *
                            "(the CSV's `<name>_sources/` folder belongs to it), or delete the row Metadata, General, " *
                            "bundled_sources to load the values without code (a CSV without Object rows)"))
    origin(i) = i <= length(origins) ? origins[i] : ""
    copies = Dict{String, String}(normpath(origin(i)) => bundled[i] for i in eachindex(bundled) if !isempty(origin(i)))
    notes = String[]
    unchanged = falses(length(bundled))
    ran_text = run ? "ran" : "is the source"
    for i in eachindex(bundled)
        isempty(origin(i)) && continue
        name = basename(origin(i))
        if !isfile(origin(i))
            push!(notes, "the original $name is gone: the exported one $ran_text")
        elseif read(origin(i)) != read(bundled[i])
            push!(notes, "$name changed since the export: the exported version $ran_text")
        else
            unchanged[i] = true
        end
    end
    manager.source_note = join(unique(notes), "; ")
    isempty(notes) || @warn "Loading $(basename(filepath)): $(manager.source_note)."

    sources = String[]
    sources_of = Dict{String, String}()
    last_result = nothing
    for (i, file) in enumerate(bundled)
        runs_as = isempty(origin(i)) ? file : origin(i)
        # the source: the original while it is unchanged, otherwise the copy, which the next run includes in place of
        # the original again
        source = unchanged[i] ? abspath(runs_as) : file
        if source == file && !isempty(origin(i))
            manager.source_origins[file] = origin(i)
        end
        isempty(origin(i)) || (sources_of[normpath(origin(i))] = source)
        push!(sources, source)
        run || continue
        @info "Executing bundled source: $(basename(file))" * (runs_as == file ? "" : " (as $runs_as)")
        last_result = try
            _include_as(get_target_module(), file, runs_as, copies)
        catch e
            msg = e isa LoadError ? sprint(showerror, e.error) : sprint(showerror, e)
            throw(ArgumentError("$(basename(filepath)): the bundled source $(basename(file)) failed: " *
                                first(split(msg, '\n'))))
        end
    end
    # (the configuration its objects come from: the last file ends with it, or with a function without arguments)
    config = run ? _config_value(last_result, basename(last(bundled))) : nothing
    return config, sources, sources_of
end

"""
    _config_value(result, file) -> SimulationConfig

The configuration a configuration file ends with (`result`, its last value; `file` names it in errors): a
`SimulationConfig`, or a function without arguments (no positional arguments, also no optional or keyword ones) that
returns one, which is called. Anything else is an `ArgumentError`.
"""
function _config_value(result, file::AbstractString)
    if result isa Function
        ms = methods(result)
        isempty(ms) && throw(ArgumentError("$(basename(file)) ends with the function $(nameof(result)), which has no " *
                                           "methods: a configuration file ends with a SimulationConfig, or a function " *
                                           "without arguments that returns one"))
        if any(m -> m.nargs != 1 || m.isva || !isempty(Base.kwarg_decl(m)), ms)
            throw(ArgumentError("$(basename(file)) ends with the function $(nameof(result)), which takes arguments: a " *
                                "configuration file ends with a SimulationConfig, or a function without arguments " *
                                "that returns one. (Methods defined before, e.g. by an earlier version of the file, " *
                                "stay until Julia restarts: rename the function, or end with `() -> …`.)"))
        end
        f, result = result, Base.invokelatest(result)
        result isa SimulationConfig ||
            throw(ArgumentError("the function $(nameof(f)) that $(basename(file)) ends with returned " *
                                "$(result === nothing ? "nothing" : "a $(typeof(result))"), not a SimulationConfig"))
    end
    result isa SimulationConfig ||
        throw(ArgumentError("$(basename(file)) must end with a SimulationConfig (or a function without arguments " *
                            "that returns one); it returned $(result === nothing ? "nothing" : "a $(typeof(result))")."))
    return result
end

# `sources` with `file` as the last entry (moved there if listed, appended otherwise): the file that builds a configuration
# is included after the helper files, so it may use and override what they define (PDEStudioCore's sources contract).
function _with_last(sources::AbstractVector, file::AbstractString)
    same(src) = normpath(abspath(src)) == normpath(abspath(file)) || (isfile(src) && isfile(file) && samefile(src, file))
    return String[String[src for src in sources if !same(src)]; String(file)]
end

# Points the sources of a configuration returned by bundled files at the files that run: the source of a bundled file
# (see `_run_bundled_sources`), any other file as it is.
function _relocate_sources(sources::AbstractVector, sources_of::Dict{String, String})
    out = String[]
    for src in sources
        source = get(sources_of, normpath(abspath(src)), nothing)
        if !isnothing(source)
            push!(out, source)
        elseif isfile(src)
            push!(out, abspath(src))
        else
            @warn "Source file $src not found; it is removed from the configuration."
        end
    end
    return out
end

# ------------------------------------------------------------------------------
# Loading
# ------------------------------------------------------------------------------

"""
    load_config_file!(path::AbstractString) -> Bool

Runs a Julia configuration file and binds the configuration it returns: its last expression is a `SimulationConfig`,
or a function without arguments that returns one. The file runs in the target module (`set_target_module!`) and becomes
the last of the configuration's `sources` (moved there if the configuration lists it elsewhere), so runs include it
after the helper files and exports bundle it. Returns `true` if the configuration needs more
parameter sliders than the open window has (the change is staged until *Run Simulation*), `false` otherwise.

!!! warning
    This **executes the file's code**: only load files you trust. A CSV without bundled sources only holds values
    and never runs code.

A file that loads reliably, also from the snapshot bundled with an export, includes its helpers relative to
`@__DIR__` (or loads them as packages) and uses no absolute paths; see the documentation (*File Operations*).
"""
function load_config_file!(path::AbstractString)
    file = abspath(path)
    manager.source_note = ""
    @warn "Executing $(basename(file)): loading a .jl file runs its code. Only load files you trust (CSV files without bundled sources never run code)."
    result = _config_value(Base.include(get_target_module(), file), file)
    result.sources = _with_last(result.sources, file)
    # The configuration of this file replaces the loaded one: the copies of an export loaded before (this file too, if
    # it is one) run as themselves now.
    empty!(manager.source_origins)

    new_max = max(manager.max_params, length(result.varied))
    if new_max != manager.max_params
        if !manager.is_open
            manager.max_params = new_max
        else
            manager.csv_cache = (dims = manager.allowed_dims, max_params = new_max, parsed = Dict{String, Any}(),
                                 raw = nothing, config = result, sources = result.sources)
            @info "More parameter sliders needed! Configuration staged; press 'Run Simulation' to rebuild the studio."
            return true
        end
    end
    manager.csv_cache = nothing
    _bind_loaded_config!(result)
    return false
end

"""
    _load_runs_code(path) -> Bool

Whether loading the file executes code: a Julia file, or a CSV with bundled source files.
"""
function _load_runs_code(path::AbstractString)
    endswith(lowercase(path), ".jl") && return true
    names = try
        get(get(get(first(_read_csv(path)), "Metadata", Dict()), "General", Dict()), "bundled_sources", nothing)
    catch
        nothing
    end
    return !(isnothing(names) || isempty(names))
end

"""
    load_and_apply_csv!(filepath::AbstractString)

Reads a configuration CSV from disk and applies it.

The simulation configuration is built from the CSV's rows (`csv_to_simulation_config`): parameters, methods, active
methods, sweep, reference and post-processing. Parameters that are objects (structs, enums, … that the CSV holds as
text: the `Object` rows) come from the configuration that the bundled source files build: only then do the bundled
sources run at loading (which executes their code). A CSV without `Object` rows runs no code when it loads; its
bundled sources become the configuration's sources, which *Run Simulation* includes. A bundled file that is missing
or fails is an error (see `_run_bundled_sources`).

It then checks whether the file needs different structural UI limits (allowed dimensions, number of parameter
sliders) and stages the data until *Run Simulation* if the open window has to be rebuilt. Returns `true` if such a
structural rebuild is pending.
"""
function load_and_apply_csv!(filepath::AbstractString)
    @info "Loading configuration from CSV: $filepath"
    parsed, raw = _read_csv(filepath)
    # (a file that can't be loaded leaves the recorded originals of bundled copies, the note and a staged file as they
    # were; code its sources ran can't be undone)
    origins, note = copy(manager.source_origins), manager.source_note
    config, sources = try
        _csv_config(parsed, filepath)
    catch
        manager.source_origins = origins
        manager.source_note = note
        rethrow()
    end
    manager.csv_cache = nothing  # a newer file replaces a staged one
    return _apply_csv_file!(parsed, raw, config, sources)
end

# The configuration of a CSV file and its sources (see `load_and_apply_csv!`): built from the CSV's rows, its objects
# (`Object` rows) from the configuration of the bundled sources, which run only if there are such rows.
function _csv_config(parsed::Dict, filepath::AbstractString)
    objects = _object_rows(parsed)
    run = !isempty(objects)
    has_sources = !isempty(something(get(get(get(parsed, "Metadata", Dict()), "General", Dict()), "bundled_sources", nothing), ""))
    run && !has_sources &&
        throw(ArgumentError("$(basename(filepath)): it bundles no source files, and its parameters " *
                            "$(join(sort!(map(_entry_name, collect(keys(objects)))), ", ")) are objects (Object rows), " *
                            "which come from the configuration that the source files build"))
    bundled_config, ran, sources_of = _run_bundled_sources(parsed, filepath; run = run)
    # (after the bundled sources, which may register statistics; sources that didn't run yet register them at a run)
    (run || isempty(ran)) && _note_missing_statistics!(parsed, filepath)
    _note_missing_run_files!(parsed, filepath)
    # The files that ran are sources of the loaded configuration too (as `load_config_file!` adds the file it runs):
    # a configuration returned by a bundled file doesn't list that file, and the next export must bundle it again.
    # The file that returned the configuration (the last one that ran) stays the last source (PDEStudioCore includes the
    # configuration's own file after the helpers).
    sources = isnothing(bundled_config) ? ran :
              _with_last(unique([_relocate_sources(bundled_config.sources, sources_of); ran]), last(ran))
    config = haskey(parsed, "Simulation") || run ? csv_to_simulation_config(parsed; objects = bundled_config) : nothing
    isnothing(config) || isempty(sources) || (config.sources = sources)
    return config, sources
end

function _apply_csv_file!(parsed::Dict, raw, config, sources)
    new_dims, new_max = manager.allowed_dims, manager.max_params
    dims = get(get(parsed, "Config", Dict()), "Dimensions", nothing)
    if !isnothing(dims)
        haskey(dims, "allowed_dims") && (new_dims = _parse_dims(dims["allowed_dims"]))
        get(dims, "max_params", nothing) isa Real && (new_max = Int(dims["max_params"]))
        # the data kind of files saved by the short-lived Files -> Mode version (now the plot style says it:
        # `particles_*` styles draw Lagrangian data)
        mode = get(dims, "mode", nothing)
        layout = _scene_source(parsed, "Layout")
        if mode === :lagrangian && layout isa AbstractDict && get(layout, "plot_style", nothing) isa Union{Symbol, AbstractString}
            layout["plot_style"] = _public_style(_base_style(Symbol(layout["plot_style"])), :lagrangian)
        end
        mode in (:eulerian, :lagrangian) && set_mode!(mode)
    end
    # Make room for every swept parameter of the loaded configuration.
    new_max = max(new_max, isnothing(config) ? 0 : length(config.varied))

    if new_dims != manager.allowed_dims || new_max != manager.max_params
        if !manager.is_open
            # No window yet: the limits can be applied directly.
            manager.allowed_dims = new_dims
            manager.max_params = new_max
            _sync_resolution_dims!()
        else
            manager.csv_cache = (dims = new_dims, max_params = new_max, parsed = parsed, raw = raw,
                                 config = config, sources = sources)
            @info "Structural limits changed! Configuration staged; press 'Run Simulation' to rebuild the studio."
            return true
        end
    end

    load_and_apply_csv!(parsed, raw; config = config, sources = sources)
    return false
end

function _bind_loaded_config!(config::SimulationConfig)
    for (_, cache_dict) in manager.caches
        empty!(cache_dict)
    end
    set_sim_config!(config)
    @info "Project configuration buffered! Press 'Run Simulation' to compute and apply."
    return config
end

"""
    load_and_apply_csv!(parsed::Dict, raw = nothing; config = nothing, sources = String[])

Applies a parsed (and structurally verified) configuration to the studio: display resolutions, the simulation
configuration (`config` if given, as built by `load_and_apply_csv!(filepath)`, otherwise built from the `Simulation`
category, which then can't hold objects: see `csv_to_simulation_config`),
the plot style, UI overrides, layout, axes and slider positions, camera, labels and exploration options.
`raw` holds the raw cell texts (see `_read_csv`); `sources` replaces the configuration's source files.
"""
# Categories and scopes of the studio CSV format (other categories, e.g. of a newer version, are ignored).
const _CSV_SCOPES = Dict("Metadata" => ("General", "Preset"), "Git" => nothing, "Julia" => nothing,
                         "Scene" => ("Plot", "Layout", "Camera", "Labels", "Exploration", "Value_Labels"), "UI" => nothing,
                         "Simulation" => nothing, "Object" => nothing, "Config" => ("Dimensions", "Resolution_Base", "Resolution_Ref"))

# Warns about categories and scopes the studio doesn't read (typos in hand-written files, e.g. `Scene, plot`).
function _warn_unknown_scopes(parsed::Dict)
    for (cat, scopes) in parsed
        if !haskey(_CSV_SCOPES, cat)
            @warn "Unknown CSV category '$cat' ignored (categories: $(join(sort!(collect(keys(_CSV_SCOPES))), ", ")))."
            continue
        end
        known = _CSV_SCOPES[cat]
        for scope in keys(scopes)
            ok = cat == "UI" ? haskey(MASTER_UI_DICT, _ui_template_scope(Symbol(scope))) :
                 isnothing(known) || scope in known
            ok || @warn "Unknown scope '$scope' of the CSV category '$cat' ignored" *
                        (isnothing(known) ? "." : " (scopes: $(join(known, ", "))).")
        end
    end
    return nothing
end

function load_and_apply_csv!(parsed::Dict, raw = nothing; config = nothing, sources = String[])
    @info "Applying parsed CSV configuration..."
    _warn_unknown_scopes(parsed)
    cfg = get(parsed, "Config", Dict())
    for (scope, target) in (("Resolution_Base", manager.resolution_base), ("Resolution_Ref", manager.resolution_ref))
        for (k, v) in get(cfg, scope, Dict())
            n = v isa Real && !(v isa Bool) && isinteger(v) && 1 <= v <= MAX_RESOLUTION ? Int(v) : nothing
            if _valid_resolution(n)
                target[Symbol(k)] = n
            else
                @warn "Ignoring the $scope row $k = $(repr(v)): a resolution is a number of points from 1 to $(MAX_RESOLUTION)."
            end
        end
    end

    # --- 1. SIMULATION ---
    if !isnothing(config)
        isempty(sources) || (config.sources = sources)
        _bind_loaded_config!(config)
    elseif haskey(parsed, "Simulation")
        new_config = csv_to_simulation_config(parsed)
        isempty(sources) || (new_config.sources = sources)
        _bind_loaded_config!(new_config)
    else
        @info "No simulation data found. Loading as a visual preset."
    end

    _has_visual_data(parsed) || return nothing

    # --- 2. PLOT STYLE FIRST (builds the matching UI templates) ---
    layout_source = _scene_source(parsed, "Layout")
    if !isnothing(layout_source)
        for (k, v) in layout_source
            if k == "plot_style" && v isa Union{Symbol, AbstractString}
                switch_ui_plot_type!(_base_style(Symbol(v)))   # particle styles use the scatter templates
                break
            end
        end
    end

    # --- 3. UI OVERRIDES ---
    for (scope_str, dict) in get(parsed, "UI", Dict())
        scope = Symbol(scope_str)
        for (k_str, v) in dict
            key = Symbol(k_str)
            val = _coerce_ui_value(scope, key, v, _raw_value(raw, "UI", scope_str, k_str))
            # values the plot can't be drawn with are refused, as in the editor (the current value stays)
            reason = _invalid_ui_reason(key, val)
            if !isnothing(reason)
                @warn "Ignoring UI, $scope_str, $k_str = $(repr(val)) from the file: not a valid $reason."
                continue
            end
            set_ui_opt!(scope, key, val)
        end
    end

    # --- 4. LAYOUT ---
    if !isnothing(layout_source)
        apply_layout_options!(_keysyms(layout_source))
    end

    # --- 5. PLOT (axes, field, component and slider positions) ---
    plot_source = _scene_source(parsed, "Plot")
    if !isnothing(plot_source)
        apply_plot_options!(_keysyms(plot_source))
    end

    # --- 6. CAMERA ---
    cam_source = _scene_source(parsed, "Camera")
    if !isnothing(cam_source) && !isempty(cam_source)
        manager.camera_cache = Dict{Symbol, Any}(Symbol(k) => v for (k, v) in cam_source)
        manager.view_context = nothing   # (a loaded camera is not a view set by the API)
        manager.camera_locked[] = true
        manager.skip_next_camera_extract = true
    else
        manager.camera_cache = Dict{Symbol, Any}()
        manager.camera_locked[] = false
    end

    # --- 7. LABELS (kept as text) ---
    labels_source = _scene_source(parsed, "Labels")
    if !isnothing(labels_source)
        for (k, v) in labels_source
            set_label!(Symbol(k), something(_raw_value(raw, "Scene", "Labels", k), string(v)))
        end
    end

    # --- 7b. NAMES OF SWEPT VALUES ---
    vl_source = _scene_source(parsed, "Value_Labels")
    if !isnothing(vl_source)
        for (k, v) in vl_source
            v isa AbstractDict ? set_value_label!(Symbol(k), (key => string(name) for (key, name) in v)...) :
                @warn "Ignoring the Value_Labels row $k = $(repr(v)): a Dict of value => name."
        end
    end

    # --- 8. EXPLORATION ---
    exp_source = _scene_source(parsed, "Exploration")
    if !isnothing(exp_source)
        apply_exploration_options!(_keysyms(exp_source))
    end
    return nothing
end

# ------------------------------------------------------------------------------
# Simulation category <-> SimulationConfig
# ------------------------------------------------------------------------------

_function_name(::Nothing) = nothing
_function_name(v::Symbol) = v === :none ? nothing : v
_function_name(v::Function) = nameof(v)
function _function_name(v::AbstractString)
    s = strip(v)
    return (isempty(s) || lowercase(s) == "none") ? nothing : Symbol(s)
end
_function_name(v) = Symbol(string(v))

"""
    csv_to_simulation_config(parsed_csv::Dict; base = nothing, objects = nothing)

Converts the simulation category of a parsed CSV into a `PDEStudioCore.SimulationConfig`: shared parameters, methods,
active methods (`defaults`), the sweep (`Simulation, Sweep`) and the reference / post-processing function names.

Parameters that are *objects* (structs, enums, … that the CSV holds as text only: the `Object` rows, with the same
scopes) are taken from the configuration `objects` (the one the bundled source files build) at the same parameter
(shared, the same method or the sweep), whose value must have the text the CSV holds. Objects only come from source
files: if `objects` is missing or has no such value, an `ArgumentError` names the parameter. A `Simulation` row for a
parameter that is an object in `objects` (or in `base`) is an error, too: the CSV can't replace an object.

With a `base` configuration, the CSV is applied as a patch: only the entries present in the file change, everything else
(including the source files) is taken from `base`.
"""
function csv_to_simulation_config(parsed_csv::Dict; base::Union{Nothing, SimulationConfig} = nothing,
                                  objects::Union{Nothing, SimulationConfig} = nothing)
    sim = get(parsed_csv, "Simulation", Dict{String, Any}())
    # (PDEStudio 0.8.0 listed objects in this row and wrote their text as Simulation rows, which would read as text now)
    haskey(sim, "Objects") &&
        throw(ArgumentError("the file has a row Simulation, Objects: it was written by PDEStudio 0.8.0, whose CSV files " *
                            "are no longer read (objects are Object rows now). Load its configuration file (or its " *
                            "bundled sources) and export it again"))
    cfg = get(sim, "Config", Dict{String, Any}())
    object_rows = _object_rows(parsed_csv)

    shared      = isnothing(base) ? ParamDict() : copy(base.shared)
    methods     = isnothing(base) ? MethodDict() : MethodDict(k => copy(v) for (k, v) in base.methods)
    varied      = isnothing(base) ? VariedDict() : copy(base.varied)
    defaults    = isnothing(base) ? Symbol[] : copy(base.defaults)
    reference   = isnothing(base) ? nothing : base.reference
    postprocess = isnothing(base) ? nothing : base.postprocess
    sources     = isnothing(base) ? String[] : copy(base.sources)

    # (a data row can't replace an object of the sources' or the base configuration; an object row comes from `objects`)
    function value(scope, k, v)
        key = (scope, Symbol(k))
        haskey(object_rows, key) && throw(ArgumentError("the parameter $(_entry_name(key)) has a Simulation row and an Object row"))
        for c in (objects, base)
            isnothing(c) || isnothing(_object_counterpart(c, scope, Symbol(k))) ||
                throw(ArgumentError("the parameter $(_entry_name(key)) is an object of the configuration (it comes from " *
                                    "the source files), and the CSV has a Simulation row for it ($(_short(repr(v), 60))): " *
                                    "a CSV can't replace an object"))
        end
        return v
    end
    target(scope) = scope === :Shared ? shared : scope === :Sweep ? varied : get!(ParamDict, methods, scope)

    # 1. Shared parameters and method overrides
    for (k, v) in get(sim, "Shared", Dict{String, Any}())
        shared[Symbol(k)] = value(:Shared, k, v)
    end
    for (scope, params) in sim
        scope in _RESERVED_SIM_SCOPES && continue
        method = get!(ParamDict, methods, Symbol(scope))
        for (k, v) in params
            method[Symbol(k)] = value(Symbol(scope), k, v)
        end
    end
    # ... and the objects (`Object` rows), from `objects`
    for ((scope, k), v) in object_rows
        target(scope)[k] = _object_value(scope, k, v, objects)
    end
    method_names = get(cfg, "methods", nothing)
    if method_names isa AbstractVector
        for m in method_names
            get!(ParamDict, methods, Symbol(m))  # methods without parameters have no rows of their own
        end
    end

    # 2. The sweep (a sweep that is an object is an `Object, Sweep` row, from `objects` as a whole)
    for (k, v) in get(sim, "Sweep", Dict{String, Any}())
        vals = value(:Sweep, k, v)
        varied[Symbol(k)] = vals isa AbstractVector ? collect(vals) : Any[vals]
    end

    # 3. Active methods and function names
    raw_defaults = get(cfg, "defaults", nothing)
    if raw_defaults isa AbstractVector
        defaults = Symbol[Symbol(m) for m in raw_defaults]
    elseif raw_defaults isa Union{Symbol, AbstractString}
        defaults = [Symbol(raw_defaults)]
    end
    haskey(cfg, "reference") && (reference = _function_name(cfg["reference"]))
    haskey(cfg, "postprocess") && (postprocess = _function_name(cfg["postprocess"]))
    for m in defaults
        get!(ParamDict, methods, m)
    end
    isempty(defaults) && (defaults = sort_methods_robust(collect(keys(methods))))   # an explicit list keeps its order

    return SimulationConfig(shared, methods, defaults;
                            varied = varied, reference = reference, postprocess = postprocess, sources = sources)
end

_entry_name((scope, k)) = scope === :Shared ? "Shared → $k" : scope === :Sweep ? "Sweep → $k" : "method $scope → $k"

# The object of the `Object` row `scope`, `k` (the CSV holds its text `v`): the value of `objects` at the same parameter
# (`_object_counterpart`), which must have that text.
function _object_value(scope::Symbol, k::Symbol, v, objects)
    what = _entry_name((scope, k))
    isnothing(objects) &&
        throw(ArgumentError("the parameter $what: there is no configuration of source files to take it from; it is an " *
                            "object (Object row) that the CSV holds as text only ($(_short(repr(v), 60)))"))
    cand = _object_counterpart(objects, scope, k)
    found = isnothing(cand) ? "has no object $k there" :
            !_same_text(something(cand), scope, v) ? "has another value there ($(_short(repr(_object_text(something(cand), scope)), 60)))" : ""
    isempty(found) ||
        throw(ArgumentError("the parameter $what: the configuration of the source files $found; it is an object that " *
                            "the CSV holds as text ($(_short(repr(v), 60))). Objects come from the source files: " *
                            "restore the one the export used"))
    return something(cand)
end

# The CSV text of an object (as the row of `scope` writes it), read back
_object_text(x, scope::Symbol) = _csv_readback(scope === :Sweep ? _sweep_text(x) : _csv_text(x))
_same_text(x, scope::Symbol, v) = isequal(_object_text(x, scope), v)

# `Some(value)` of the parameter `k` of `config` in `scope` (`:Shared`, `:Sweep` or a method) if it is an object,
# or `nothing`. Objects are only looked up at the same parameter.
function _object_counterpart(config::SimulationConfig, scope::Symbol, k::Symbol)
    d = scope === :Shared ? config.shared : scope === :Sweep ? config.varied : get(config.methods, scope, nothing)
    (isnothing(d) || !haskey(d, k)) && return nothing
    return _csv_object(d[k]; sweep = scope === :Sweep) ? Some(d[k]) : nothing
end

# ------------------------------------------------------------------------------
# Reproducibility information
# ------------------------------------------------------------------------------

function _find_git_repos!(out::Vector{String}, dir::String, depth::Int, max_depth::Int)
    isdir(joinpath(dir, ".git")) && push!(out, dir)
    depth >= max_depth && return out
    entries = try
        readdir(dir)
    catch
        return out
    end
    for name in entries
        (startswith(name, ".") || name in ("build", "node_modules", "docs")) && continue
        path = joinpath(dir, name)
        (isdir(path) && !islink(path)) && _find_git_repos!(out, path, depth + 1, max_depth)
    end
    return out
end

"""
    get_all_git_infos(start_path::String = "."; max_depth = 3)

Searches the filesystem below `start_path` (at most `max_depth` levels, skipping hidden, `build`, `node_modules` and
`docs` folders) for local Git repositories. Returns the commit hash, summary, total commit count and whether the
working tree has uncommitted changes to tracked files (`git_dirty`; untracked files don't count) of each for research reproducibility tracking.
"""
function get_all_git_infos(start_path::String = "."; max_depth::Int = 3)
    git_infos = Dict{String, Dict{String, Any}}()
    for root in _find_git_repos!(String[], abspath(start_path), 0, max_depth)
        try
            repo = LibGit2.GitRepo(root)
            commit = LibGit2.peel(LibGit2.GitCommit, LibGit2.head(repo))
            git_infos[basename(root)] = Dict{String, Any}(
                "git_commit_hash" => string(LibGit2.GitHash(commit)),
                "git_commit_summary" => LibGit2.summary(commit),
                "git_commit_count" => try parse(Int, readchomp(`git -C $root rev-list --count HEAD`)) catch; -1 end,
                # uncommitted changes: the commit alone doesn't reproduce the state
                "git_dirty" => LibGit2.isdirty(repo)
            )
        catch
            # Not a valid repository (or no commits yet): skipped.
        end
    end
    return git_infos
end

"""
    get_julia_info(git_repo_names::Vector{String})

Queries the active Julia `Pkg` environment to log the exact system version and track dependencies.
It focuses specifically on top-level project dependencies and the sub-dependencies of tracked local Git repositories to guarantee exact environmental matching upon reload.
"""
function get_julia_info(git_repo_names::Vector{String})
    info = Dict{String, Dict{String, Any}}()
    info["System"] = Dict{String, Any}("Julia_Version" => string(VERSION))

    deps = Pkg.dependencies()

    top_deps = Dict{String, Any}()
    for (uuid, pkg) in deps
        if pkg.is_direct_dep
            top_deps[pkg.name] = string(pkg.version)
        end
    end
    info["Main_Project"] = top_deps

    # Repository folders are named like their packages, usually with a `.jl` suffix (`PDEStudio.jl` holds `PDEStudio`)
    repo_packages = Set(replace(basename(n), r"\.jl$" => "") for n in git_repo_names)
    for (uuid, pkg) in deps
        if pkg.name in repo_packages
            sub_deps = Dict{String, Any}()
            for (dep_name, dep_uuid) in pkg.dependencies
                if haskey(deps, dep_uuid)
                    sub_deps[dep_name] = string(deps[dep_uuid].version)
                end
            end
            if !isempty(sub_deps)
                info[pkg.name] = sub_deps
            end
        end
    end
    return info
end

# ------------------------------------------------------------------------------
# --- Code the export can't run again ---------------------------------------------------------------------------

# The functions a configuration names (solvers, reference, post-processor) and the `calc_stat` methods of the
# registered statistics that are defined neither in one of its `sources` nor in a package: an export bundles the
# sources and records the package versions, so it can't run these again elsewhere (e.g. defined in the REPL, or in a
# script that isn't a source). Returns descriptions such as "post-processor my_post"; names that don't resolve are
# left out (running the configuration reports them).
function _code_outside_sources(config::SimulationConfig)
    sources = Set(normpath(abspath(s)) for s in config.sources)
    in_package(m::Method) = !isnothing(pkgdir(Base.moduleroot(m.module)))
    in_sources(m::Method) = (file = string(m.file); isabspath(file) && normpath(file) in sources)
    covered(ms) = all(m -> in_package(m) || in_sources(m), ms)
    outside = String[]
    function check!(what, name)
        (isnothing(name) || Symbol(name) === :none) && return
        f = Base.CoreLogging.with_logger(() -> PDEStudioCore.resolve_dynamic_function(name), Base.CoreLogging.NullLogger())
        isnothing(f) || covered(methods(f)) || push!(outside, "$what $name")
    end
    solvers = [get(config.shared, :sim_func_name, nothing); [get(m, :sim_func_name, nothing) for m in values(config.methods)]]
    foreach(s -> check!("solver", s), unique(filter(!isnothing, solvers)))
    check!("reference", config.reference)
    check!("post-processor", config.postprocess)
    for stat in sort!(collect(keys(get_stat_registry())))
        stat === :Solution && continue
        # (a statistic without a `calc_stat` method comes with the data, e.g. from the solver)
        ms = [m for m in methods(PDEStudioCore.calc_stat) if _calc_stat_of(m, stat)]
        isempty(ms) || covered(ms) || push!(outside, "statistic $stat")
    end
    return outside
end

function _calc_stat_of(m::Method, stat::Symbol)
    sig = Base.unwrap_unionall(m.sig)
    return length(sig.parameters) >= 2 && sig.parameters[2] === Val{stat}
end

# The note an export adds to the status line (and the log) when it can't run some code again; "" otherwise
function _export_code_note()
    config = manager.active_config
    isnothing(config) && return ""
    outside = _code_outside_sources(config)
    isempty(outside) && return ""
    note = "defined outside the configuration's sources and packages, so the export can't run them elsewhere: " *
           join(outside, ", ") * " (add their files to the sources, Advanced)"
    @warn "Export: $note."
    return note
end

# The data files the configuration's runs use (those stored now: a dry run), by name, and the message of PDEStudioCore if it
# refuses the configuration (or `nothing`); for exports, which record what to
# copy along with them
function _run_files(config::SimulationConfig)
    try
        s = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            run_all_simulations(config; dry_run = true, calculate_stats = false, post_process = false, load_sources = false)
        end
        return String[basename(f) for f in s.files if !isnothing(f)], nothing
    catch e
        e isa InterruptException && rethrow()
        @debug "Could not list the run files" exception = (e, catch_backtrace())
        # (PDEStudioCore refuses the parameters: the message says which)
        return String[], e isa ArgumentError ? _short(first(split(sprint(showerror, e), '\n')), 160) : nothing
    end
end

# Notes (log and status line) the run files a loaded export recorded that the current save path doesn't hold, and
# where the export found them: what to copy (or the save path to set) before running it
function _note_missing_run_files!(parsed::Dict, filepath::AbstractString)
    general = get(get(parsed, "Metadata", Dict()), "General", Dict())
    files = get(general, "run_files", nothing)
    files isa AbstractString && (files = isempty(files) ? String[] : [files])
    files isa AbstractVector || return nothing
    data_dir = joinpath(get_save_path(), "data")
    missing_files = String[string(f) for f in files if !isfile(joinpath(data_dir, string(f)))]
    isempty(missing_files) && return nothing
    origin = get(general, "save_path", nothing)
    note = "$(length(missing_files)) of the $(length(files)) run files the export used are not in $(data_dir)" *
           (isnothing(origin) ? "" : " (they were in $(origin)/data)") *
           (_COMPUTE[] ? "; Run Simulation would compute them" : "")
    @warn "Loading $(basename(filepath)): $note: " * join(missing_files, ", ")
    manager.source_note = join(filter(!isempty, [manager.source_note, note]), "; ")
    return nothing
end

# Warns (and notes for the status line) when a loaded export computed statistics this session doesn't register
function _note_missing_statistics!(parsed::Dict, filepath::AbstractString)
    names = get(get(get(parsed, "Metadata", Dict()), "General", Dict()), "statistics", nothing)
    names isa AbstractString && (names = isempty(names) ? String[] : [names])
    names isa AbstractVector || return nothing
    missing_stats = sort!(setdiff(Symbol.(string.(names)), keys(get_stat_registry())))
    isempty(missing_stats) && return nothing
    note = "the export used statistics this session doesn't register: " * join(string.(missing_stats), ", ") *
           " (set_stat_preset! / register_stat!, or add their files to the sources)"
    @warn "Loading $(basename(filepath)): $note."
    manager.source_note = join(filter(!isempty, [manager.source_note, note]), "; ")
    return nothing
end

# ------------------------------------------------------------------------------
# Full exports and visual presets
# ------------------------------------------------------------------------------

"""
    save_params_to_csv(base_filename::AbstractString, save_dir::AbstractString, metadata_general::Dict)

The primary serialization engine. It writes the full state of the studio—the `SimulationConfig`, scene (axes,
sliders, layout, camera, labels, exploration), UI styles, structural limits and display resolutions—plus Git and
Julia environment information to `<save_dir>/<base_filename>.csv`. The configuration's source files are copied next
to the CSV (`<name>_sources/<file>`, with their originals recorded) so the export can be reloaded elsewhere. The
registered statistics are recorded (`Metadata, General, statistics`), and so is code the export can't run again
(`code_outside_sources`: solvers, reference, post-processor or statistics defined outside the sources and packages),
the save path and the data files of the runs (`save_path`, `run_files`: loading the export elsewhere names those
missing there).

Returns `true` on a successful write.
"""
function save_params_to_csv(base_filename::AbstractString, save_dir::AbstractString, metadata_general::Dict)::Bool
    csv_filename = joinpath(save_dir, base_filename * ".csv")
    csv_dir = dirname(abspath(csv_filename))

    try
        rows = _CSVRows()

        # --- 1. CATEGORY: Metadata ---
        for (k, v) in _sorted_pairs(metadata_general)
            add_row!(rows, "Metadata", "General", k, v)
        end

        config = manager.active_config
        if !isnothing(config) && !isempty(config.sources)
            # The sources are copied into `<name>_sources/` under their own file names, so a bundled file that
            # includes another bundled one (`include("solvers.jl")`) still finds it when the originals are gone.
            bundled_names, origins = String[], String[]
            bundle_dir = "$(basename(base_filename))_sources"
            for src_path in config.sources
                if isfile(src_path)
                    name = basename(src_path)
                    while joinpath(bundle_dir, name) in bundled_names   # two sources with the same file name
                        name = "$(length(bundled_names) + 1)_$name"
                    end
                    bundled_name = joinpath(bundle_dir, name)
                    dst_path = joinpath(csv_dir, bundled_name)
                    mkpath(dirname(dst_path))
                    # (a symlinked source is copied as a file: the snapshot must not follow later edits)
                    # the copy of a loaded export ran in place of its original, which stays the origin
                    push!(origins, something(_origin_of(src_path), abspath(src_path)))
                    if abspath(src_path) != abspath(dst_path)
                        cp(src_path, dst_path; force = true, follow_symlinks = true)
                        delete!(manager.source_origins, abspath(dst_path))   # (another file now: no copy of a loaded one)
                    end
                    push!(bundled_names, bundled_name)
                else
                    @warn "Source file not found and skipped: $src_path"
                end
            end
            if !isempty(bundled_names)
                add_row!(rows, "Metadata", "General", "bundled_sources", bundled_names)
                add_row!(rows, "Metadata", "General", "source_origins", origins)
            end
        end
        if !isnothing(config)
            objects = _object_entries(config, filter(m -> haskey(config.methods, m), unique(config.defaults)))
            listed = join(map(_entry_name, objects), ", ")
            if isempty(objects)
            elseif !any(isfile, config.sources)
                @warn "Exporting $(basename(csv_filename)): the parameters $listed are objects (e.g. structs) the " *
                      "CSV holds as text only, and the configuration has no source files that build " *
                      "them: the CSV can't be loaded again. Build the configuration in a file (load it, or list it " *
                      "in `sources`)."
            else
                @info "Exporting $(basename(csv_filename)): the parameters $listed are objects; loading the CSV takes " *
                      "them from the configuration that the last of its bundled source files returns (a " *
                      "SimulationConfig, or a function without arguments that returns one)."
            end
        end
        if !isnothing(config)
            # what a load elsewhere needs besides the sources: the statistics, and the code it can't rerun
            add_row!(rows, "Metadata", "General", "statistics",
                     sort!([string(k) for k in keys(get_stat_registry()) if k !== :Solution]))
            outside = _code_outside_sources(config)
            isempty(outside) || add_row!(rows, "Metadata", "General", "code_outside_sources", outside)
            # (and the data it shows: the run files and where they are, so a load elsewhere says what to copy)
            add_row!(rows, "Metadata", "General", "save_path", get_save_path())
            run_files, refused = _run_files(config)
            # (a configuration PDEStudioCore refuses, e.g. a function as a parameter, can't run: neither can its export)
            isnothing(refused) ||
                @warn "Exporting $(basename(csv_filename)): the configuration can't run ($refused); the CSV can't be " *
                      "run again either."
            isempty(run_files) || add_row!(rows, "Metadata", "General", "run_files", run_files)
        end

        # --- 2. Git (Scope = Repo Name) & Julia (Scope = Main Project or Local Sub-Package) ---
        git_infos = get_all_git_infos(pwd())
        for (repo_name, info) in _sorted_pairs(git_infos)
            for (k, v) in _sorted_pairs(info); add_row!(rows, "Git", repo_name, k, v); end
        end
        for (scope, info) in _sorted_pairs(get_julia_info(collect(keys(git_infos))))
            for (k, v) in _sorted_pairs(info); add_row!(rows, "Julia", scope, k, v); end
        end

        # --- 3. Scene & UI ---
        _add_scene_rows!(rows)
        _add_ui_rows!(rows)

        # --- 4. Simulation & Config ---
        isnothing(config) || _add_simulation_rows!(rows, config)
        add_row!(rows, "Config", "Dimensions", "allowed_dims", manager.allowed_dims)
        add_row!(rows, "Config", "Dimensions", "max_params", manager.max_params)
        for (dim, res) in _sorted_pairs(manager.resolution_base)
            add_row!(rows, "Config", "Resolution_Base", dim, res)
        end
        for (dim, res) in _sorted_pairs(manager.resolution_ref)
            add_row!(rows, "Config", "Resolution_Ref", dim, res)
        end

        _write_rows(csv_filename, rows)
        @info "Metadata and Parameters saved to $csv_filename"
        return true
    catch e
        @error "CSV Save Failed" exception=(e, catch_backtrace())
        return false
    end
end

"""
    save_preset_to_csv(preset_name::Symbol, save_dir::AbstractString)

A lightweight serialization pipeline that exclusively writes the visual state (scene, camera, labels, exploration
and UI styles) without any simulation parameters. Used to generate reusable aesthetic templates; see `save_plot_preset`.
"""
function save_preset_to_csv(preset_name::Symbol, save_dir::AbstractString)
    csv_filename = joinpath(save_dir, string(preset_name) * ".csv")

    try
        rows = _CSVRows()
        desc = get(manager.presets, preset_name, "User custom preset")
        add_row!(rows, "Metadata", "Preset", "description", desc)
        add_row!(rows, "Metadata", "Preset", "type", "visual")
        _add_scene_rows!(rows)
        _add_ui_rows!(rows)
        _write_rows(csv_filename, rows)
        @info "Preset saved to $csv_filename"
        return true
    catch e
        @error "Preset Save Failed" exception=(e, catch_backtrace())
        return false
    end
end
