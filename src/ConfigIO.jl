# ==============================================================================
# --- CSV serialisation of the studio state ---
# ==============================================================================
#
# Every file is a table `Category, Scope, Parameter, Value`; values are written with `val2str` and read back
# with the safe literal parser `str2val` (no code is evaluated). Categories:
#   Metadata    General (export info, blueprint) / Preset (description, type, mode)
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

# A row of a simulation parameter: its literal (`_csv_text`) as it is (the empty text as `<empty>`, like `add_row!`)
function _add_param_row!(rows::_CSVRows, cat, scope, param, value)
    text = _csv_text(value)
    push!(rows.cats, string(cat))
    push!(rows.scopes, string(scope))
    push!(rows.params, string(param))
    push!(rows.vals, isempty(text) ? "<empty>" : text)
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

# The text of a simulation parameter in the CSV: PDEStudioCore's literal of the value (`param_literal`), which reads
# back with the value's type (and so with its data-file hash): quoted text where needed ("1e3"), `1.5f0`, `:a => 1`.
_csv_text(v) = param_literal(v)

# What the CSV reads back for a value written as `text` (see `add_row!` and `_parse_csv_value`).
_csv_readback(text) = _parse_csv_value(text)

"""
    _csv_object(v) -> Bool

Whether the parameter value `v` is an *object*: a value the CSV holds as text only, because its text doesn't read back
as the value (a struct, an enum, a container holding one; PDEStudioCore's `is_param_object`). Objects come from the
source files: an export writes them as `Object` rows, a reload takes them from the configuration the blueprint
build (see `csv_to_simulation_config`), and the editors don't overwrite them.
"""
_csv_object(v) = v === Nothing || v === Missing || is_param_object(v)   # (a cell `Nothing` reads back as `nothing`)

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
        _csv_object(v) && push!(entries, (:Sweep, Symbol(k)))
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
`Simulation` rows: a reload takes them from the blueprint's configuration.
"""
function _add_simulation_rows!(rows::_CSVRows, config::SimulationConfig)
    # (objects as `Object` rows of the same scope)
    category(v) = _csv_object(v) ? "Object" : "Simulation"
    for (k, v) in _sorted_pairs(config.shared)
        _add_param_row!(rows, category(v), "Shared", k, v)
    end
    method_names = sort!(filter(m -> haskey(config.methods, m), unique(config.defaults)))
    for m in method_names
        if string(m) in _RESERVED_SIM_SCOPES
            @warn "Method :$m clashes with a reserved CSV scope; its parameters are not saved."
            continue
        end
        for (k, v) in _sorted_pairs(config.methods[m])
            _add_param_row!(rows, category(v), m, k, v)
        end
    end
    add_row!(rows, "Simulation", "Config", "methods", method_names)
    add_row!(rows, "Simulation", "Config", "defaults", config.defaults)
    add_row!(rows, "Simulation", "Config", "reference", isnothing(config.reference) ? "none" : string(config.reference))
    add_row!(rows, "Simulation", "Config", "postprocess", isnothing(config.postprocess) ? "none" : string(config.postprocess))
    for (k, v) in _sorted_pairs(config.varied)
        _add_param_row!(rows, category(v), "Sweep", k, v)
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
# Blueprints
# ------------------------------------------------------------------------------
# The *blueprint* of a configuration is the code that builds it: its source files, copied into a folder that runs on
# its own (PDEStudioCore's `bundle_sources`: the sources and the files they include, `manager.source_extras`, each with
# its path relative to the folder they share), or a function of a package. An export is a *realization* of its
# blueprint: the CSV holds the values (and the active methods), and names the blueprint, which several exports can
# share: the folder is named after its content (`<name>-<first 8 digits of its digest>`, `bundle_digest`), and its
# `blueprint.csv` says what it holds. Loading an export checks the folder against its digest, runs it (an `include`
# of a file outside it is refused) and applies the CSV's rows to the configuration it builds.

const _BLUEPRINT_FILE = "blueprint.csv"

# The files the sources of `config` include themselves: as recorded when they ran last (for these sources). Sources
# that haven't run as these sources yet (a configuration bound as a value, or with a function) run now, as *Run
# Simulation* would run them, so an export copies every file they need. (An `include` that a file does only in some
# runs can't be seen: include unconditionally what the code needs.)
function _source_extras(config::SimulationConfig)
    manager.extras_of == config.sources || _record_extras!(config, include_sources(config.sources; within = _blueprint_within(config)))
    return filter(isfile, manager.source_extras)
end

function _record_extras!(config::SimulationConfig, files::AbstractVector{<:AbstractString})
    sources = String[abspath(src) for src in config.sources]
    manager.extras_of = copy(config.sources)
    manager.source_extras = String[f for f in files if !(f in sources)]
    return nothing
end

# The folder the sources of `config` run in on their own: the blueprint folder of the export it was loaded from;
# `nothing` for any other configuration. The sources of a loaded export are its blueprint's (to change the code, load
# the configuration file): other sources (e.g. edited in the Advanced tab) are an error, so code that the digest
# doesn't pin can't run as part of the blueprint.
function _blueprint_dir(config::SimulationConfig)
    bp = manager.blueprint
    (isnothing(bp) || isempty(bp.dir)) && return nothing
    normpath.(abspath.(config.sources)) == normpath.(bp.sources) ||
        throw(ArgumentError("the sources of a loaded export are the files of its blueprint $(basename(bp.dir)), and " *
                            "the configuration lists others now: load the configuration's file to change its code"))
    return bp.dir
end

# What the sources of `config` may include (`include_sources(...; within)`): for a loaded export exactly the files its
# blueprint lists (a file added to the folder later doesn't run), otherwise anything
function _blueprint_within(config::SimulationConfig)
    isnothing(_blueprint_dir(config)) && return nothing
    return String[manager.blueprint.sources; manager.blueprint.extras]
end

# What identifies a blueprint: the digest of its files together with what builds the configuration (`bundle_digest`
# with that as its label), so a `blueprint.csv` that says another thing than the one an export was made with (or a
# configuration of the same code built in another way) is another blueprint: another folder, another digest, another
# confirmation.
_blueprint_id(sources, extras, builds::Symbol, func::Symbol) =
    bundle_digest(sources; extra = extras, label = "pdestudio blueprint, builds: $builds, function: $func")

# What a session remembers of a blueprint it ran (`_CONFIRMED_CODE`): its identity, or its function
_code_key(bp::_Blueprint) = isempty(bp.dir) ? "function:$(bp.func)" : bp.digest
# The blueprint of a configuration that a configuration file built (its last source), before an export copies its code
const _FILE_BLUEPRINT = _Blueprint("", "", String[], String[], :file, Symbol(""))

# The blueprint of a configuration that `builder` builds: the function, if the target module finds it by its name (as
# a loaded export will); `nothing` otherwise (an anonymous or local function: the configuration has no blueprint).
function _function_blueprint(builder::Function)
    name = nameof(builder)
    found = Base.CoreLogging.with_logger(() -> PDEStudioCore.resolve_dynamic_function(name), Base.CoreLogging.NullLogger())
    found === builder && return _Blueprint("", "", String[], String[], :function, name)
    @info "The function $name isn't one the target module $(get_target_module()) defines: the configuration is bound " *
          "without a blueprint (exports can't get its objects back)."
    return nothing
end

# The folder of a blueprint must hold what it held when the export was loaded: it runs as it was exported, or not at all.
function _check_blueprint(bp::_Blueprint)
    isempty(bp.dir) && return nothing
    digest = try
        _blueprint_id(bp.sources, bp.extras, bp.builds, bp.func)
    catch e
        e isa ArgumentError || rethrow()
        ""
    end
    digest == bp.digest ||
        throw(ArgumentError("the blueprint $(basename(bp.dir)) changed since the export was loaded (a file edited or " *
                            "removed): it runs as it was exported, or not at all. Restore it, or load its " *
                            "configuration file to develop the code"))
    return nothing
end

"""
    _run_simulations(config; kwargs...)

`run_all_simulations(config; kwargs...)`, with the sources included here: a loaded export runs its blueprint on its
own (`_blueprint_dir`, unchanged: `_check_blueprint`), and the files the sources include are recorded for the next
export (`_record_extras!`). A dry run that records the missing runs (`manager.missing_runs`) with
`set_compute!(false)`.
"""
function _run_simulations(config::SimulationConfig; kwargs...)
    compute = _COMPUTE[]   # (`set_compute!(false)`: a dry run, the missing runs are listed)
    within = _blueprint_within(config)
    isnothing(within) || _check_blueprint(manager.blueprint)
    _record_extras!(config, include_sources(config.sources; within = within))
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

# Writes what a blueprint folder holds into its `blueprint.csv`: the sources in their order, the other files, what
# builds the configuration (`file`: the last source; `function` and its name; `nothing`) and the digest of the files.
function _write_blueprint_file(dir::AbstractString, names, digest::AbstractString, builds::Symbol, func::Symbol)
    rows = _CSVRows()
    add_row!(rows, "Blueprint", "General", "sources", String[names.sources...])
    isempty(names.extra) || add_row!(rows, "Blueprint", "General", "files", String[names.extra...])
    add_row!(rows, "Blueprint", "General", "builds", builds === :none ? "nothing" : string(builds))
    builds === :function && add_row!(rows, "Blueprint", "General", "function", string(func))
    add_row!(rows, "Blueprint", "General", "digest", digest)
    _write_rows(joinpath(dir, _BLUEPRINT_FILE), rows)
    return nothing
end

# A text cell of `raw` (names and digests are kept as text: a digest of digits would be read as a number), or `nothing`
function _text_cell(raw, cat, scope, key)
    text = _raw_value(raw, cat, scope, key)
    return (isnothing(text) || isempty(strip(text))) ? nothing : String(strip(text))
end

"""
    _read_blueprint(dir, what) -> _Blueprint

The blueprint in the folder `dir` (`what` names the file that links it, for the errors), as its `blueprint.csv`
describes it, checked: every file is there, named inside the folder, and the files are the ones the blueprint was
made with (their digest, `bundle_digest`, is the recorded one, and the one the folder is named after). Nothing runs.
"""
function _read_blueprint(dir::AbstractString, what::AbstractString)
    name = basename(dir)
    isdir(dir) || throw(ArgumentError("$what: its blueprint folder $name is not next to it ($dir). The folder belongs " *
                                      "to the file: copy it along"))
    file = joinpath(dir, _BLUEPRINT_FILE)
    isfile(file) || throw(ArgumentError("$what: the folder $name is no blueprint (it has no $(_BLUEPRINT_FILE))"))
    parsed, raw = _read_csv(file)
    general = get(get(parsed, "Blueprint", Dict()), "General", Dict())
    function names_of(key)
        names = get(general, key, String[])
        names isa AbstractString && (names = isempty(strip(names)) ? String[] : String[names])
        (names isa AbstractVector && all(n -> n isa AbstractString, names)) ||
            throw(ArgumentError("$what: $(_BLUEPRINT_FILE) of $name holds no list of file names as its $key"))
        return String[String(n) for n in names]
    end
    sources, extras = names_of("sources"), names_of("files")
    func = Symbol(lstrip(something(_text_cell(raw, "Blueprint", "General", "function"), ""), ':'))
    builds = Symbol(lowercase(something(_text_cell(raw, "Blueprint", "General", "builds"), "file")))
    builds === :nothing && (builds = :none)
    (builds in (:file, :none) || (builds === :function && func !== Symbol(""))) ||
        throw(ArgumentError("$what: $(_BLUEPRINT_FILE) of $name must say what builds the configuration: file, " *
                            "function (with its name) or nothing"))
    recorded = _text_cell(raw, "Blueprint", "General", "digest")
    (isempty(sources) || isnothing(recorded)) &&
        throw(ArgumentError("$what: $(_BLUEPRINT_FILE) of $name names no sources or no digest"))
    parts = map(n -> split(replace(n, '\\' => '/'), '/'; keepempty = false), [sources; extras])
    all(p -> !isempty(p) && !isabspath(join(p, '/')) && !any(in(("..", ".")), p) && !any(x -> occursin(':', x), p), parts) ||
        throw(ArgumentError("$what: the files of the blueprint $name are named inside its folder; got " *
                            join([sources; extras], ", ")))
    files = String[joinpath(dir, p...) for p in parts]
    gone = filter(!isfile, files)
    isempty(gone) || throw(ArgumentError("$what: file(s) of its blueprint $name are missing: $(join(gone, ", ")). " *
                                         "Restore the folder as it was exported"))
    source_files, extra_files = files[1:length(sources)], files[length(sources)+1:end]
    digest = _blueprint_id(source_files, extra_files, builds, func)
    suffix = match(r"-([0-9a-f]{8})$", name)
    (digest == recorded && (isnothing(suffix) || startswith(digest, suffix[1]))) ||
        throw(ArgumentError("$what: the blueprint $name is not the one it was made with (a file was edited, " *
                            "$(_BLUEPRINT_FILE) changed, or the folder was renamed). A blueprint runs as it was " *
                            "exported: restore it, or load its configuration file to develop the code"))
    return _Blueprint(String(dir), digest, source_files, extra_files, builds, func)
end

"""
    _blueprint(parsed, raw, filepath) -> Union{Nothing, _Blueprint}

The blueprint a CSV names (nothing runs): a folder next to it (`Metadata, General, blueprint`, a path relative to the
file; see `_read_blueprint`), which must be the one the file was exported with if the file pins it (`blueprint_digest`),
or a function of the target module (`blueprint_function`); `nothing` for a file without one, which holds values for
solvers of packages. Files of earlier versions (`bundled_sources`) are refused.
"""
function _blueprint(parsed::Dict, raw, filepath::AbstractString)
    what = basename(filepath)
    meta = get(get(parsed, "Metadata", Dict()), "General", Dict())
    haskey(meta, "bundled_sources") &&
        throw(ArgumentError("$what was exported by an earlier version of PDEStudio (it has a row bundled_sources), " *
                            "whose exports are no longer read: load its configuration file and export it again"))
    folder = _text_cell(raw, "Metadata", "General", "blueprint")
    func = _text_cell(raw, "Metadata", "General", "blueprint_function")
    pinned = _text_cell(raw, "Metadata", "General", "blueprint_digest")
    if isnothing(folder)
        isnothing(func) && return nothing
        return _Blueprint("", "", String[], String[], :function, Symbol(lstrip(func, ':')))
    end
    isnothing(func) || throw(ArgumentError("$what names a blueprint folder and a blueprint_function: the function " *
                                           "of a blueprint with source files is named in its $(_BLUEPRINT_FILE)"))
    isabspath(folder) && throw(ArgumentError("$what: the blueprint is named relative to the file, not as $folder"))
    bp = _read_blueprint(normpath(joinpath(dirname(abspath(filepath)), folder)), what)
    (isnothing(pinned) || pinned == bp.digest) ||
        throw(ArgumentError("$what was exported with another blueprint than $(basename(bp.dir)) (its " *
                            "blueprint_digest starts with $(first(pinned, 8)))"))
    return bp
end

# Runs a blueprint and returns the configuration it builds and the files that ran: the sources of its folder on their
# own (an `include` of a file outside it is refused), then the last one returns the configuration, or its function
# does; `nothing` for a blueprint of code only.
function _build_blueprint(bp::_Blueprint, what::AbstractString)
    included = String[]
    try
        if isempty(bp.dir)
            return load_config_function(bp.func), included
        end
        @info "Executing the blueprint $(basename(bp.dir)) of $what: $(join(basename.(bp.sources), ", "))"
        within = String[bp.sources; bp.extras]   # (exactly the files it lists: a file added to the folder doesn't run)
        if bp.builds === :file
            helpers = include_sources(bp.sources[1:end-1]; within = within)
            config = load_config_file(last(bp.sources); within = within, included = included)
            return config, prepend!(included, helpers)
        end
        append!(included, include_sources(bp.sources; within = within))
        return (bp.builds === :function ? load_config_function(bp.func) : nothing), included
    catch e
        e isa InterruptException && rethrow()
        throw(ArgumentError("$what: its blueprint failed: " * first(split(sprint(showerror, _load_error(e)), '\n'))))
    end
end

# The innermost error of a file that failed while it was included (`LoadError`s wrap it per file)
_load_error(e) = e isa LoadError ? _load_error(e.error) : e

# ------------------------------------------------------------------------------
# Loading
# ------------------------------------------------------------------------------

"""
    load_config_file!(path::AbstractString) -> Bool

Runs a Julia configuration file and binds the configuration it returns (PDEStudioCore's `load_config_file`): its last
expression is a `SimulationConfig`, or a function without arguments that returns one. The file runs in the target
module (`set_target_module!`) and becomes the last of the configuration's `sources` (moved there if the configuration
lists it elsewhere), so runs include it after the helper files. The files it includes are recorded: exports bundle
them with the sources. Returns `true` if the configuration needs more parameter sliders than the open window has
(the change is staged until *Run Simulation*), `false` otherwise.

!!! warning
    This **executes the file's code**: only load files you trust. A CSV without a blueprint only holds values
    and never runs code.

A file that loads reliably, also from the copy bundled with an export, includes its helpers relative to itself
(or loads them as packages) and uses no absolute paths; see the documentation (*File Operations*).
"""
function load_config_file!(path::AbstractString)
    file = abspath(path)
    manager.source_note = ""
    @warn "Executing $(basename(file)): loading a .jl file runs its code. Only load files you trust (CSV files without a blueprint never run code)."
    included = String[]
    result = load_config_file(file; included = included)   # (PDEStudioCore: the file is the last source)
    # The files it included are copied with its exports. (The file builds the configuration and runs as it is, also a
    # file of a blueprint folder; an export copies the code into a blueprint folder.)
    _record_extras!(result, included)

    new_max = max(manager.max_params, length(result.varied))
    if new_max != manager.max_params
        if !manager.is_open
            manager.max_params = new_max
        else
            manager.csv_cache = (dims = manager.allowed_dims, max_params = new_max, parsed = Dict{String, Any}(),
                                 raw = nothing, config = result, sources = result.sources, blueprint = _FILE_BLUEPRINT)
            @info "More parameter sliders needed! Configuration staged; press 'Run Simulation' to rebuild the studio."
            return true
        end
    end
    manager.csv_cache = nothing
    _bind_loaded_config!(result, _FILE_BLUEPRINT)
    return false
end

"""
    _load_runs_code(path) -> Bool

Whether loading the file executes code: a Julia file, or a CSV that names a blueprint (a folder of source files, or a
function).
"""
function _load_runs_code(path::AbstractString)
    endswith(lowercase(path), ".jl") && return true
    meta = try
        get(get(first(_read_csv(path)), "Metadata", Dict()), "General", Dict())
    catch
        return false
    end
    return any(key -> haskey(meta, key), ("blueprint", "blueprint_function", "bundled_sources"))
end

"""
    load_and_apply_csv!(filepath::AbstractString)

Reads a configuration CSV from disk and applies it.

If the file names a *blueprint* (the code that builds its configuration: a folder of source files next to it,
`Metadata, General, blueprint`, or a function, `blueprint_function`), the blueprint is checked (a folder against its
digest: it runs as it was exported, or not at all) and run (which executes its code; the folder on its own: an
`include` of a file outside it is refused), and the CSV's rows are applied to the configuration it builds
(`csv_to_simulation_config`): an export is the whole realization (`mode` `replace`; the blueprint's other methods stay
as the pool), a file written by hand a patch. Parameters that are objects (structs, enums, … that the CSV holds as
text: the `Object` rows) come from the blueprint's configuration. A blueprint that is missing, changed or fails is an
error (see `_blueprint` and `_csv_config`). A file without a blueprint holds values for solvers of packages, and
runs no code.

It then checks whether the file needs different structural UI limits (allowed dimensions, number of parameter
sliders) and stages the data until *Run Simulation* if the open window has to be rebuilt. Returns `true` if such a
structural rebuild is pending.
"""
function load_and_apply_csv!(filepath::AbstractString)
    @info "Loading configuration from CSV: $filepath"
    parsed, raw = _read_csv(filepath)
    # (a file that can't be loaded leaves the note, the bound configuration and a staged file as they were; code its
    # blueprint ran can't be undone)
    note = manager.source_note
    config, blueprint, included = try
        _csv_config(parsed, raw, filepath)
    catch
        manager.source_note = note
        rethrow()
    end
    manager.csv_cache = nothing  # a newer file replaces a staged one
    if !isnothing(blueprint)
        push!(_CONFIRMED_CODE, _code_key(blueprint))   # (this code ran: another file with it loads without a question)
        # the files of the blueprint that aren't sources (bundled again by the next export)
        isnothing(config) || _record_extras!(config, String[blueprint.extras; included])
    end
    return _apply_csv_file!(parsed, raw, config, blueprint)
end

# What the rows of a file are for its blueprint's configuration (or, for a simulation preset, the bound one): `:replace`
# (the whole realization: exports, saved presets) or `:patch` (only what the file lists changes: files written by hand).
function _realization_mode(raw)
    text = something(_text_cell(raw, "Metadata", "Preset", "mode"), _text_cell(raw, "Metadata", "General", "mode"), "patch")
    mode = Symbol(lowercase(text))
    return mode in (:replace, :patch) ? mode : :patch
end

# The configuration of a CSV file, its blueprint (`_blueprint`) and the files that ran (see `load_and_apply_csv!`): the
# blueprint is checked and run (if the file names one), and the file's rows are applied to the configuration it builds
# (`csv_to_simulation_config`); a file without simulation rows is the blueprint's configuration as it is.
function _csv_config(parsed::Dict, raw, filepath::AbstractString)
    blueprint = _blueprint(parsed, raw, filepath)
    base, included = isnothing(blueprint) ? (nothing, String[]) : _build_blueprint(blueprint, basename(filepath))
    _note_missing_statistics!(parsed, filepath)   # (after the blueprint, which may register them)
    _note_missing_run_files!(parsed, filepath)
    has_rows = haskey(parsed, "Simulation") || haskey(parsed, "Object")
    config = has_rows ? csv_to_simulation_config(parsed; base = base, mode = _realization_mode(raw)) : base
    # the sources of the loaded configuration are the blueprint's files (the next export shares the folder)
    isnothing(config) || isnothing(blueprint) || isempty(blueprint.dir) || (config.sources = copy(blueprint.sources))
    return config, blueprint, included
end

function _apply_csv_file!(parsed::Dict, raw, config, blueprint)
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
                                 config = config, sources = String[], blueprint = blueprint)
            @info "Structural limits changed! Configuration staged; press 'Run Simulation' to rebuild the studio."
            return true
        end
    end

    load_and_apply_csv!(parsed, raw; config = config, blueprint = blueprint)
    return false
end

# Binds a loaded configuration, with the blueprint it is a realization of (`nothing`: none)
function _bind_loaded_config!(config::SimulationConfig, blueprint::Union{Nothing, _Blueprint} = nothing)
    for (_, cache_dict) in manager.caches
        empty!(cache_dict)
    end
    set_sim_config!(config; keep_blueprint = true)
    manager.blueprint = blueprint
    @info "Project configuration buffered! Press 'Run Simulation' to compute and apply."
    return config
end

"""
    load_and_apply_csv!(parsed::Dict, raw = nothing; config = nothing, sources = String[], blueprint = nothing)

Applies a parsed (and structurally verified) configuration to the studio: display resolutions, the simulation
configuration (`config` if given, as built by `load_and_apply_csv!(filepath)` with its `blueprint`, otherwise built
from the `Simulation` category alone, which then can't hold objects: see `csv_to_simulation_config`),
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

function load_and_apply_csv!(parsed::Dict, raw = nothing; config = nothing, sources = String[], blueprint = nothing)
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
        _bind_loaded_config!(config, blueprint)
    elseif haskey(parsed, "Simulation") || haskey(parsed, "Object")
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
    csv_to_simulation_config(parsed_csv::Dict; base = nothing, mode = :patch)

The configuration that the simulation rows of a parsed CSV describe, as a *realization* of the configuration `base`
(the one its blueprint builds, or for a simulation preset the bound one; `nothing`: none, the file holds everything):
shared parameters, methods, active methods (`defaults`), the sweep (`Simulation, Sweep`) and the reference /
post-processing function names.

- `mode = :patch` (files written by hand): only what the file lists changes. Everything else is `base`'s: its other
  parameters, sweeps, methods and active methods.
- `mode = :replace` (exports, saved presets): the file is the whole realization. The shared parameters, the sweep,
  the active methods and the parameters of the methods it lists are the file's (what `base` has and the file
  doesn't is not part of it); `base`'s other methods stay as the pool of methods to choose from.

Parameters that are *objects* (structs, enums, … that the CSV holds as text only: the `Object` rows, with the same
scopes) are taken from `base` at the same parameter (shared, the same method or the sweep), whose value must have the
text the CSV holds. Objects only come from code: without `base`, or if it has no such value, an `ArgumentError` names
the parameter. A `Simulation` row for a parameter that is an object in `base` is an error, too: a CSV can't replace an
object. The source files are `base`'s.
"""
function csv_to_simulation_config(parsed_csv::Dict; base::Union{Nothing, SimulationConfig} = nothing, mode::Symbol = :patch)
    mode in (:patch, :replace) || throw(ArgumentError("mode = :$mode: :patch or :replace"))
    sim = get(parsed_csv, "Simulation", Dict{String, Any}())
    # (PDEStudio 0.8.0 listed objects in this row and wrote their text as Simulation rows, which would read as text now)
    haskey(sim, "Objects") &&
        throw(ArgumentError("the file has a row Simulation, Objects: it was written by PDEStudio 0.8.0, whose CSV files " *
                            "are no longer read (objects are Object rows now). Load its configuration file and " *
                            "export it again"))
    cfg = get(sim, "Config", Dict{String, Any}())
    object_rows = _object_rows(parsed_csv)
    whole = mode === :replace   # (the file is the whole realization)

    shared      = (isnothing(base) || whole) ? ParamDict() : copy(base.shared)
    methods     = isnothing(base) ? MethodDict() : MethodDict(k => copy(v) for (k, v) in base.methods)   # (the pool)
    varied      = (isnothing(base) || whole) ? VariedDict() : copy(base.varied)
    defaults    = isnothing(base) ? Symbol[] : copy(base.defaults)
    reference   = (isnothing(base) || whole) ? nothing : base.reference
    postprocess = (isnothing(base) || whole) ? nothing : base.postprocess
    sources     = isnothing(base) ? String[] : copy(base.sources)

    # the methods the file lists: their own scopes, the methods of object rows, and `Config, methods`
    listed = Symbol[Symbol(scope) for scope in keys(sim) if !(scope in _RESERVED_SIM_SCOPES)]
    append!(listed, (scope for (scope, _) in keys(object_rows) if !(scope in (:Shared, :Sweep))))
    method_names = get(cfg, "methods", nothing)
    method_names isa AbstractVector && append!(listed, Symbol.(method_names))
    for m in unique!(listed)
        whole ? (methods[m] = ParamDict()) : get!(ParamDict, methods, m)   # (methods without parameters have no rows)
    end

    # (a data row can't replace an object of the base configuration; an object row is taken from it)
    function value(scope, k, v)
        key = (scope, Symbol(k))
        haskey(object_rows, key) && throw(ArgumentError("the parameter $(_entry_name(key)) has a Simulation row and an Object row"))
        # (in any scope: a method's or the sweep's value of a key overrides the shared one, and a struct and its text
        # have the same identity, so text in another scope would replace the struct for the runs just as well)
        where_ = isnothing(base) ? nothing : _object_scope(base, Symbol(k))
        isnothing(where_) ||
            throw(ArgumentError("the parameter $(_entry_name(key)): $k is an object of the configuration (" *
                                "$(_entry_name((where_, Symbol(k)))), it comes from the code), and the CSV has a " *
                                "Simulation row for it ($(_short(repr(v), 60))): a CSV can't replace an object"))
        return v
    end
    target(scope) = scope === :Shared ? shared : scope === :Sweep ? varied : methods[scope]

    # 1. Shared parameters and method overrides
    for (k, v) in get(sim, "Shared", Dict{String, Any}())
        shared[Symbol(k)] = value(:Shared, k, v)
    end
    for (scope, params) in sim
        scope in _RESERVED_SIM_SCOPES && continue
        method = methods[Symbol(scope)]
        for (k, v) in params
            method[Symbol(k)] = value(Symbol(scope), k, v)
        end
    end

    # 2. The sweep
    for (k, v) in get(sim, "Sweep", Dict{String, Any}())
        vals = value(:Sweep, k, v)
        varied[Symbol(k)] = vals isa AbstractVector ? collect(vals) : Any[vals]
    end

    # 3. The objects (`Object` rows; a sweep that is an object as a whole), from `base`
    for ((scope, k), v) in object_rows
        target(scope)[k] = _object_value(scope, k, v, base)
    end

    # 4. Active methods and function names
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

# The object of the `Object` row `scope`, `k` (the CSV holds its text `v`): the value of `objects` (the configuration the
# blueprint builds) at the same parameter (`_object_counterpart`), which must have that text.
function _object_value(scope::Symbol, k::Symbol, v, objects)
    what = _entry_name((scope, k))
    isnothing(objects) &&
        throw(ArgumentError("the parameter $what is an object (Object row) that the CSV holds as text only " *
                            "($(_short(repr(v), 60))), and the file has no blueprint that builds the configuration " *
                            "to take it from: objects come from the code"))
    cand = _object_counterpart(objects, scope, k)
    found = isnothing(cand) ? "has no object $k there" :
            !_same_text(something(cand), scope, v) ? "has another value there ($(_short(repr(_object_text(something(cand), scope)), 60)))" : ""
    isempty(found) ||
        throw(ArgumentError("the parameter $what: the blueprint's configuration $found; it is an object that " *
                            "the CSV holds as text ($(_short(repr(v), 60))). Objects come from the code: " *
                            "restore the blueprint the export used"))
    return something(cand)
end

# The CSV text of an object (as the row of `scope` writes it), read back
_object_text(x, scope::Symbol) = _csv_readback(_csv_text(x))
_same_text(x, scope::Symbol, v) = isequal(_object_text(x, scope), v)

# The scope (`:Shared`, a method, `:Sweep`) in which the key `k` is an object in `config`, or `nothing`
function _object_scope(config::SimulationConfig, k::Symbol)
    isnothing(_object_counterpart(config, :Shared, k)) || return :Shared
    isnothing(_object_counterpart(config, :Sweep, k)) || return :Sweep
    for m in sort!(collect(keys(config.methods)), by = string)
        isnothing(_object_counterpart(config, m, k)) || return m
    end
    return nothing
end

# `Some(value)` of the parameter `k` of `config` in `scope` (`:Shared`, `:Sweep` or a method) if it is an object,
# or `nothing`. Objects are only looked up at the same parameter.
function _object_counterpart(config::SimulationConfig, scope::Symbol, k::Symbol)
    d = scope === :Shared ? config.shared : scope === :Sweep ? config.varied : get(config.methods, scope, nothing)
    (isnothing(d) || !haskey(d, k)) && return nothing
    return _csv_object(d[k]) ? Some(d[k]) : nothing
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
    # (the files the sources include themselves are bundled with them)
    sources = Set(normpath(abspath(s)) for s in Iterators.flatten((config.sources, _source_extras(config))))
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
Julia environment information to `<save_dir>/<base_filename>.csv`. The configuration's code is copied next to the CSV
as its blueprint, a folder that runs on its own and is shared by the exports with the same code (`<config>-<digest>/`:
the sources and the files they include, with their folders, and `blueprint.csv`), so the export can be reloaded
elsewhere; a source that is missing fails the export. A function that builds the configuration is named instead. The
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
        if !isnothing(config)
            # The blueprint: what builds the configuration (its file, a function, or nothing: the code only), and the
            # code, copied into a folder that runs on its own and is named after its content, so exports with the same
            # code share it (PDEStudioCore's `bundle_sources`, `bundle_digest`; a source that is missing fails the
            # export: it couldn't be loaded again)
            bp = manager.blueprint
            builds = isnothing(bp) ? :none : bp.builds
            func = builds === :function ? bp.func : Symbol("")
            if !isempty(config.sources)
                extras = _source_extras(config)
                digest = _blueprint_id(config.sources, extras, builds, func)
                stem = builds === :function ? string(func) : first(splitext(basename(last(config.sources))))
                folder = replace(stem, r"[^A-Za-z0-9_.]" => "_") * "-" * first(digest, 8)
                target = joinpath(csv_dir, folder)
                # (a folder of that name holds this blueprint, or another one whose digest starts alike: never overwritten)
                if isfile(joinpath(target, _BLUEPRINT_FILE))
                    existing = try
                        _read_blueprint(target, basename(csv_filename))
                    catch
                        nothing
                    end
                    (!isnothing(existing) && existing.digest == digest) ||
                        throw(ArgumentError("the folder $folder next to the export holds another blueprint (or a changed " *
                                            "one): move it away, it is never overwritten"))
                end
                names = bundle_sources(config.sources, target; extra = extras)
                _write_blueprint_file(target, names, digest, builds, func)
                add_row!(rows, "Metadata", "General", "blueprint", folder)
                add_row!(rows, "Metadata", "General", "blueprint_digest", digest)
            elseif builds === :function
                add_row!(rows, "Metadata", "General", "blueprint_function", string(func))
            end
            add_row!(rows, "Metadata", "General", "mode", "replace")   # (the rows are the whole realization)
            objects = _object_entries(config, filter(m -> haskey(config.methods, m), unique(config.defaults)))
            if !isempty(objects) && (builds === :none || (builds === :file && isempty(config.sources)))
                @warn "Exporting $(basename(csv_filename)): the parameters $(join(map(_entry_name, objects), ", ")) " *
                      "are objects (e.g. structs) the CSV holds as text only, and nothing builds the configuration " *
                      "again (no configuration file, no function): the CSV can't be loaded. Load the configuration " *
                      "from a file, or bind the function that builds it (`set_sim_config!(my_config)`)."
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
