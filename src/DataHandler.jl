"""
    _template_data(sim_config::SimulationConfig)

Loads the first dataset on disk that belongs to a non-reference method of the configuration (`:raw`, as stored).
Returns `nothing` if nothing has been simulated yet.
"""
function _template_data(sim_config::SimulationConfig)
    active_keys, active_values = analyze_configuration(sim_config)
    for m_name in sim_config.defaults
        is_reference_method(m_name) && continue
        base_params = assemble_params(sim_config.shared, sim_config.methods, m_name)
        ik = get_ignore_keys(sim_config.methods, m_name)
        tasks, _ = generate_method_tasks(base_params, active_keys, active_values; ignore_keys = ik)
        for params in tasks
            does_sim_data_exist(params) || continue
            try
                # Load via :raw to bypass any resolution requirements
                return load_sim_data(params, Val(:raw))
            catch e
                @warn "Failed to load template domain for $m_name." exception = (e, catch_backtrace())
                break
            end
        end
    end
    return nothing
end

"""
    _get_template_domain(sim_config::SimulationConfig)

The domain of `_template_data`: used to lay out reference solutions and to pick the display resolution of
Eulerian data. Returns `nothing` if nothing has been simulated yet.
"""
function _get_template_domain(sim_config::SimulationConfig)
    data = _template_data(sim_config)
    return isnothing(data) ? nothing : data.domain
end

"""
    _dims_for_data(domain) -> Union{Tuple, Nothing}

The dimensions the studio needs to show data of `domain`: `nothing` if the allowed dimensions
([`set_allowed_dims!`](@ref)) already contain its axes, otherwise the allowed dimensions plus the missing ones (the
time axis last, e.g. `(:x, :y, :z, :t, :iteration)` for data with the axes `(:x, :y, :iteration)`).
"""
function _dims_for_data(domain)
    (isnothing(domain) || issubset(domain.dim_keys, manager.allowed_dims)) && return nothing
    t = domain.time_dim
    allowed = collect(manager.allowed_dims)
    dims = Symbol[filter(!=(t), allowed); filter(d -> !(d in allowed) && d != t, collect(domain.dim_keys))]
    isnothing(t) || push!(dims, t)
    return Tuple(dims)
end

# Allows the dimensions of `domain` (see `_dims_for_data`); a time axis with another name than `:t` gets the
# display resolution of a time axis. Resets the plotter (like `set_allowed_dims!`) if the dimensions change.
function _allow_dims_of!(domain)
    dims = _dims_for_data(domain)
    isnothing(dims) && return false
    t = domain.time_dim
    if !isnothing(t)
        get!(manager.resolution_base, t, 50)
        get!(manager.resolution_ref, t, 100)
    end
    set_allowed_dims!(dims)
    return true
end

"""
    analyze_configuration(sim_config::SimulationConfig)

Extracts the swept parameter keys (sorted by name, the order the sliders use) and their values from the configuration.
Returns a tuple of `(active_keys, active_values)` used to map the Cartesian sweep grid.
"""
function analyze_configuration(sim_config::SimulationConfig)
    active_keys = sort!(collect(keys(sim_config.varied)))
    active_values = Vector{Any}[collect(Any, sim_config.varied[k]) for k in active_keys]
    return active_keys, active_values
end

"""
    validate_plot_dimensions(sim_data::AbstractSimData)

Validates that the spatial and temporal dimensions of the loaded simulation data natively fit within the allowed UI dimensions.
Returns `false` and drops the data if the dimensional structures are incompatible.
"""
function validate_plot_dimensions(sim_data::AbstractSimData)
    allowed = manager.allowed_dims
    actual = sim_data.domain.dim_keys

    if !issubset(actual, allowed)
        @warn "Incompatible data loaded. Data dimensions $actual are not a subset of the configured UI dimensions $allowed. Dropping data."
        return false
    end
    return true
end

"""
    _get_first_valid(pd::PlotSweepData)

Safely extracts the first non-`nothing` simulation object from a multi-dimensional sweep data array.
"""
function _get_first_valid(pd)
    isnothing(pd) && return nothing
    for d in pd.data
        isnothing(d) || return d
    end
    return nothing
end

# ==============================================================================
# --- SWEEP VALUES (numeric and non-numeric parameters) ---
# ==============================================================================

"""
    _is_numeric_sweep(vals)

`true` if every swept value is a real number. Non-numeric sweeps (strings, symbols, tuples, …) are driven by
index sliders (`1:length(vals)`).
"""
_is_numeric_sweep(vals) = all(v -> v isa Real, vals)

"""
    _param_index(vals, sel)

Index of the swept value selected by the slider position `sel`: the nearest value for numeric sweeps, the
(rounded, clamped) index for non-numeric sweeps.
"""
function _param_index(vals::AbstractVector, sel)
    isempty(vals) && return 1
    sel isa Real || return 1
    if _is_numeric_sweep(vals)
        return findmin(v -> abs(v - sel), vals)[2]
    end
    return clamp(round(Int, sel), 1, length(vals))
end

# The swept value shown for slider position `sel` of the `i`-th parameter.
function _param_display_value(i::Int, sel)
    data = manager.plot_data[]
    isempty(data) && return sel
    pd = first(values(data))
    i <= length(pd.active_param_values) || return sel
    vals = pd.active_param_values[i]
    (isempty(vals) || _is_numeric_sweep(vals)) && return sel
    return vals[_param_index(vals, sel)]
end

# ==============================================================================
# --- MAIN TENSOR CREATION ROUTINE (Unified) ---
# ==============================================================================

function _load_for_display(params::ParamDict, domain, mode::Val)
    try
        mode === Val(:eulerian) || return load_sim_data(params, mode)
        res = build_res_tuple(domain.dim_keys; is_ref = false)
        isnothing(domain.time_dim) && return load_sim_data(params, mode, res)
        return _load_snapshots(params, res, findfirst(==(domain.time_dim), domain.dim_keys))
    catch e
        # A missing file is normal (the simulation has not run yet); anything else is worth a warning.
        e isa SimFileNotFoundError || @warn "Could not load the data of $(params)" exception = (e, catch_backtrace())
        return nothing
    end
end

"""
    _load_snapshots(params, res, D)

Eulerian display data with a time axis (dimension `D`): the space axes at the display resolution `res`, the time axis
not interpolated but made of stored snapshots, so every time value drawn (and printed in the title) is the time of the
snapshot shown. With at most `res[D]` stored snapshots all of them are shown (PDEStudioCore keeps a time axis whose
length doesn't change, and caches the conversion); with more, `res[D]` of them, evenly spread over the stored ones.
This holds for grid data and for particle data drawn on a grid (scattered to the grid by `convert_to_eulerian`).
"""
function _load_snapshots(params::ParamDict, res::Tuple, D::Int)
    path = get_file_name(params)
    key = string(path, '#', mtime(path))
    nt = get(manager.stored_time_counts, key, nothing)
    raw = nothing
    if isnothing(nt)
        raw = load_sim_data(params, Val(:raw))
        nt = _stored_steps(raw, D)
        manager.stored_time_counts[key] = nt
    end
    nt == 0 && return load_sim_data(params, Val(:eulerian), res)
    # (PDEStudioCore keeps the stored times when the time resolution is their number, for grids and particles)
    nt <= res[D] && return load_sim_data(params, Val(:eulerian), Base.setindex(res, nt, D))
    isnothing(raw) && (raw = load_sim_data(params, Val(:raw)))
    idx = unique(round.(Int, range(1, nt, length = res[D])))
    sub = _select_snapshots(raw, idx)
    sub_res = Base.setindex(res, length(idx), D)
    return sub isa LSimData ? convert_to_eulerian(sub, sub_res) : resample_eulerian(sub, sub_res)
end

# The number of stored snapshots of data with the time axis `D` (grid or particles), 0 for anything else.
_stored_steps(raw::ESimData, D::Int) = ndims(raw.u) == D && !isnothing(raw.domain.time_dim) ? length(raw.axes[D]) : 0
_stored_steps(raw::LSimData, D::Int) = length(raw.domain.dim_keys) == D && !isnothing(raw.domain.time_dim) ? length(raw.t) : 0
_stored_steps(raw, D::Int) = 0

# The snapshots `idx` of particle data: positions, values and the statistics stored per snapshot.
function _select_snapshots(data::LSimData{D, DS, M, T}, idx::AbstractVector{Int}) where {D, DS, M, T}
    nt = length(data.t)
    stats = Dict{Symbol, Any}()
    for k in keys(data.stats)
        k === :Solution && continue
        v = data.stats[k]
        keeps_time = data.domain.time_dim in get_kept_dims(k, data.domain)
        stats[k] = keeps_time && v isa AbstractVector && !(v isa SVector) && length(v) == nt ? v[idx] : v
    end
    return LSimData{D, DS, M, T}(data.params, data.domain, data.t[idx], data.x[idx], data.u[idx], stats)
end

# The snapshots `idx` of Eulerian data (time is the last dimension): the solution and every statistic that keeps time.
function _select_snapshots(data::ESimData{D, DS, M, T}, idx::AbstractVector{Int}) where {D, DS, M, T}
    nt = length(data.axes[D])
    axes = ntuple(d -> d == D ? data.axes[d][idx] : data.axes[d], Val(D))
    u = data.u[ntuple(d -> d == D ? idx : Colon(), Val(D))...]
    stats = Dict{Symbol, Any}()
    for k in keys(data.stats)
        k === :Solution && continue
        v = data.stats[k]
        kept = get_kept_indices(k, data.domain)
        pos = findfirst(==(D), kept)
        if v isa AbstractArray && !(v isa SVector) && !isnothing(pos) && ndims(v) == length(kept) && size(v, pos) == nt
            stats[k] = v[ntuple(i -> i == pos ? idx : Colon(), ndims(v))...]
        else
            stats[k] = v
        end
    end
    return ESimData{D, DS, M, T}(data.params, data.domain, axes, u, stats)
end

# The time axis of a dataset (`nothing` without time): the axis the studio draws its snapshots at.
function _time_axis(data::AbstractSimData)
    t = data.domain.time_dim
    isnothing(t) && return nothing
    data isa LSimData && return data.t
    return data.axes[findfirst(==(t), data.domain.dim_keys)]
end

# `domain` with the bounds of its (last, time) dimension set to `[t0, t1]`.
function _with_time_bounds(domain::DomainInfo{D, T}, t0, t1) where {D, T}
    return DomainInfo{D, T}(domain.dim_keys, Base.setindex(domain.mins, T(t0), D), Base.setindex(domain.maxs, T(t1), D),
                            domain.spacing, domain.time_dim, domain.stat_registry)
end

_uniform_axis(a, b, n::Int) = n == 1 ? [a] : collect(range(a, b, length = n))

# `domain` with the grid spacing of `axes` (the integration measure of statistics on data with these axes).
function _with_spacing(domain::DomainInfo{D, T}, axes) where {D, T}
    spacing = SVector{D, T}(ntuple(d -> length(axes[d]) > 1 ? (last(axes[d]) - first(axes[d])) / (length(axes[d]) - 1) : one(T), D))
    return DomainInfo{D, T}(domain.dim_keys, domain.mins, domain.maxs, spacing, domain.time_dim, domain.stat_registry)
end

_ref_elem(::Type{E}, v) where {E} = E(v isa Number ? (v,) : Tuple(v))

# Evaluates `ref_func` on the tensor grid `axes` (Eulerian), for time axes that are not uniform (PDEStudioCore's
# `generate_reference_simdata` lays every axis out uniformly).
function _reference_on_axes(ref_func, params::ParamDict, domain::DomainInfo{D, T}, axes::NTuple{D, Vector{T}}) where {D, T}
    point(I) = SVector{D, T}(ntuple(d -> axes[d][I[d]], Val(D)))
    grid = CartesianIndices(map(length, axes))
    E = SVector{length(ref_func(point(first(grid)))), T}
    u = Array{E, D}(undef, size(grid))
    Threads.@threads for i in eachindex(u)
        u[i] = _ref_elem(E, ref_func(point(grid[i])))
    end
    return ESimData(params, _with_spacing(domain, axes), axes, u)
end

# Evaluates `ref_func` for particles on the uniform grid `res` (space) at the times `t_vec` (Lagrangian).
function _reference_particles_at(ref_func, params::ParamDict, domain::DomainInfo{D, T}, res::Tuple, t_vec) where {D, T}
    DS = D - 1
    s_axes = ntuple(d -> _uniform_axis(domain.mins[d], domain.maxs[d], res[d]), DS)
    points = vec([SVector{DS, T}(ntuple(d -> s_axes[d][I[d]], DS)) for I in CartesianIndices(ntuple(d -> res[d], DS))])
    tv = convert(Vector{T}, t_vec)
    E = SVector{length(ref_func(SVector{D, T}(points[1]..., tv[1]))), T}
    u = Vector{Vector{E}}(undef, length(tv))
    Threads.@threads for n in eachindex(tv)
        u[n] = [_ref_elem(E, ref_func(SVector{D, T}(p..., tv[n]))) for p in points]
    end
    return LSimData{D, DS, length(E), T}(params, _with_spacing(domain, (s_axes..., tv)), tv, fill(points, length(tv)), u)
end

"""
    _make_reference(ref_factory, params, domain, mode, t_axis = nothing)

Evaluates the reference solution for `params` on `domain` (the domain of the numerical data at the same sweep point)
at the display resolution of the references. With the time axis `t_axis` of that numerical data (its stored snapshot
times), the reference is evaluated at exactly these times, so at every time slider position the numerical and the
reference curve show the same time. At most the reference resolution in time (`resolution_ref`, default 100) of them
are used, evenly spread over `t_axis` (with more drawn times, e.g. particle styles or a reference time resolution below
the data's, the reference shows the nearest of those).
"""
function _make_reference(ref_factory, params::ParamDict, domain, mode::Val, t_axis = nothing)
    try
        ref_func = ref_factory(params)
        res = build_res_tuple(domain.dim_keys; is_ref = true)
        if !isnothing(t_axis) && !isempty(t_axis) && !isnothing(domain.time_dim)
            D = length(domain.dim_keys)
            cap = res[D]
            length(t_axis) > cap && (t_axis = t_axis[unique(round.(Int, range(1, length(t_axis), length = cap)))])
            res = Base.setindex(res, length(t_axis), D)
            domain = _with_time_bounds(domain, first(t_axis), last(t_axis))
            mode === Val(:lagrangian) && return _reference_particles_at(ref_func, params, domain, res, t_axis)
            if t_axis != _uniform_axis(first(t_axis), last(t_axis), length(t_axis))
                T = eltype(domain.mins)
                axes = ntuple(d -> d == D ? convert(Vector{T}, t_axis) : _uniform_axis(domain.mins[d], domain.maxs[d], res[d]), D)
                return _reference_on_axes(ref_func, params, domain, axes)
            end
        end
        return generate_reference_simdata(ref_func, params, domain, res, mode)
    catch e
        @warn "Could not evaluate the reference solution for $(params)" exception = (e, catch_backtrace())
        return nothing
    end
end

# The dataset of a numerical method at the sweep point `idx` (the first of `numeric` that has one), or `nothing`.
function _numeric_at(numeric, idx::Tuple)
    for pd in numeric
        checkbounds(Bool, pd.data, idx...) || continue
        d = pd.data[idx...]
        isnothing(d) || return d
    end
    return nothing
end

"""
    create_plot_data(method_name::Symbol, base_params::ParamDict, sim_config::SimulationConfig,
                     domain = _get_template_domain(sim_config); numeric = ())

The primary tensor assembly routine.
Calculates the full Cartesian sweep grid (exactly as `run_all_simulations` does), loads the Eulerian or Lagrangian
representation of every task (identical tasks share one dataset), evaluates analytical references for reference methods,
and packages the result into a `PlotSweepData` cache.

A reference is evaluated per sweep point on the domain and at the times of the numerical data of that point (the
`PlotSweepData` of the numerical methods in `numeric`), since a swept parameter may change the domain (final time,
domain length, grid); without numerical data at a point it falls back to the template `domain`.
"""
function create_plot_data(method_name::Symbol, base_params::ParamDict, sim_config::SimulationConfig,
                          domain = _get_template_domain(sim_config); numeric = ())
    active_keys, active_values = analyze_configuration(sim_config)
    ignore_keys = get_ignore_keys(sim_config.methods, method_name)

    tasks, grid_indices = generate_method_tasks(base_params, active_keys, active_values; ignore_keys = ignore_keys)
    isempty(tasks) && return nothing

    grid_dims = isempty(active_values) ? (1,) : Tuple(length.(active_values))
    data_store = Array{Union{Nothing, AbstractSimData}, length(grid_dims)}(nothing, grid_dims...)
    result = PlotSweepData{length(grid_dims)}(data_store, active_keys, active_values)
    isnothing(domain) && return result

    is_reference = is_reference_method(method_name)
    mode = Val(manager.mode[])
    ref_factory = is_reference ? resolve_dynamic_function(sim_config.reference) : nothing
    if is_reference && isnothing(ref_factory)
        @warn "Method :$method_name is a reference method, but the configuration has no resolvable reference function " *
              "(SimulationConfig(...; reference = :my_factory)). It is not drawn."
        return result
    end

    # Numerical data of the same sweep grid (data of an earlier configuration is not used)
    numeric = [pd for pd in numeric if size(pd.data) == grid_dims && pd.active_param_keys == active_keys]
    loaded = Dict{Any, Union{Nothing, AbstractSimData}}()   # identical tasks (and domains) share one dataset
    for (k, params) in enumerate(tasks)
        dest_prefix = isempty(grid_indices[k]) ? (1,) : grid_indices[k]
        key = calculate_hash(get_clean_params(params))
        if is_reference
            src = _numeric_at(numeric, Tuple(dest_prefix))
            ref_domain, t_axis = isnothing(src) ? (domain, nothing) : (src.domain, _time_axis(src))
            key = (key, ref_domain.dim_keys, ref_domain.mins, ref_domain.maxs, t_axis)
        end
        sim_data = get!(loaded, key) do
            # invokelatest: the factory may come from source files included by the run that just finished
            is_reference ? Base.invokelatest(_make_reference, ref_factory, params, ref_domain, mode, t_axis) :
                           _load_for_display(params, domain, mode)
        end

        if !isnothing(sim_data) && validate_plot_dimensions(sim_data)
            data_store[dest_prefix...] = sim_data
        end
    end

    return result
end

# ==============================================================================
# --- DATA EXTRACTION (On-The-Fly Cross-Plotting) ---
# ==============================================================================

# Splits an axis selection "stat|dim" into (stat, loop dimension); plain selections map to themselves.
function _split_axis_symbol(ax_sym)
    ax_str = string(ax_sym)
    occursin("|", ax_str) || return ax_str, ax_str
    parts = split(ax_str, "|")
    return String(parts[1]), String(parts[2])
end

# Component `c` of a statistic entry as Float64 (clamped to the available components).
function _component_value(v, c)
    if v isa Union{AbstractArray, Tuple}
        isempty(v) && return NaN
        idx = c isa Integer ? clamp(c, 1, length(v)) : 1
        return Float64(v[idx])
    end
    return Float64(v)
end

"""
    extract_eulerian_data(...)

The core slicing engine for Eulerian grids.
Dynamically resolves axis substitutes (e.g., plotting runtime over a varied spatial resolution parameter), performs point-by-point bounds-checking, and collapses high-dimensional data into flat arrays suitable for Makie primitives.
"""
function extract_eulerian_data(pd::PlotSweepData, param_indices, sel_vals, plot_vars, active_plot_axes::Vector{Symbol}, u_key::Symbol, target_c)
    first_sim = _get_first_valid(pd)
    isnothing(first_sim) && return nothing
    # Coordinates of physical axes: the dataset selected by the sliders (sweeps may change the domain).
    ref_sim = something(pd.data[param_indices...], first_sim)

    active_loop_dims = Symbol[]
    plot_axes_data = Any[]
    ax_lengths = Int[]

    # 1. Parse Substitutes and Build Target Axes
    for ax_sym in active_plot_axes
        stat_name, loop_dim_str = _split_axis_symbol(ax_sym)
        loop_dim = Symbol(loop_dim_str)
        push!(active_loop_dims, loop_dim)
        p_idx = findfirst(isequal(loop_dim), pd.active_param_keys)

        if stat_name == loop_dim_str
            # Standard Parameter or Physical Dimension lookup
            if !isnothing(p_idx)
                vals = pd.active_param_values[p_idx]
                # Non-numeric sweeps are laid out at their index positions.
                push!(plot_axes_data, _is_numeric_sweep(vals) ? Float64.(vals) : collect(1.0:length(vals)))
                push!(ax_lengths, length(vals))
            else
                d_idx = findfirst(==(loop_dim), ref_sim.domain.dim_keys)
                if !isnothing(d_idx)
                    push!(plot_axes_data, ref_sim.axes[d_idx])
                    push!(ax_lengths, length(ref_sim.axes[d_idx]))
                else
                    push!(plot_axes_data, [0.0]); push!(ax_lengths, 1)
                end
            end
        else
            # Substitute Statistic Lookup (e.g. Runtime over N)
            stat_vec = Float64[]
            sym_stat = Symbol(stat_name)

            if !isnothing(p_idx)
                for i in 1:length(pd.active_param_values[p_idx])
                    curr_p = Any[param_indices...]
                    curr_p[p_idx] = i
                    sim = pd.data[curr_p...]
                    val = isnothing(sim) || !haskey(sim.stats, sym_stat) ? NaN : _component_value(sim.stats[sym_stat], target_c)
                    push!(stat_vec, val)
                end
            else
                sim = pd.data[param_indices...]
                if isnothing(sim) || !haskey(sim.stats, sym_stat)
                    push!(stat_vec, NaN)
                else
                    append!(stat_vec, map(v -> _component_value(v, target_c), sim.stats[sym_stat]))
                end
            end
            push!(plot_axes_data, stat_vec)
            push!(ax_lengths, length(stat_vec))
        end
    end

    u_out = fill(NaN, Tuple(ax_lengths)...)

    # 2. Populate Point-by-Point mapping against `active_loop_dims`
    for I in CartesianIndices(u_out)
        curr_param_idx = Any[param_indices...]
        for (dim_out, loop_dim) in enumerate(active_loop_dims)
            p_idx = findfirst(isequal(loop_dim), pd.active_param_keys)
            if !isnothing(p_idx)
                curr_param_idx[p_idx] = I[dim_out]
            end
        end

        sim_data = pd.data[curr_param_idx...]
        isnothing(sim_data) && continue

        tensor = get(sim_data.stats, u_key, nothing)
        isnothing(tensor) && continue

        # The tensor dimensions are ordered like the domain (independent of how the statistic was registered).
        domain = sim_data.domain
        tensor_dim_syms = Tuple(domain.dim_keys[i] for i in get_kept_indices(u_key, domain))

        in_bounds = true
        u_raw = nothing

        # If there are no kept dimensions, it's a pure scalar stat.
        if isempty(tensor_dim_syms)
            u_raw = tensor isa SVector ? tensor : (tensor isa AbstractArray && !isempty(tensor) ? first(tensor) : tensor)
        elseif tensor isa AbstractArray && ndims(tensor) == length(tensor_dim_syms)
            tensor_indices = ntuple(length(tensor_dim_syms)) do d
                dim_sym = tensor_dim_syms[d]
                out_idx = findfirst(isequal(dim_sym), active_loop_dims)

                if !isnothing(out_idx)
                    idx = I[out_idx]
                else
                    var_idx = findfirst(isequal(dim_sym), plot_vars)
                    if isnothing(var_idx); in_bounds = false; return 1; end

                    target_val = sel_vals[var_idx]
                    axis_idx = findfirst(==(dim_sym), domain.dim_keys)
                    idx = findmin(v -> abs(v - target_val), sim_data.axes[axis_idx])[2]
                end
                if idx > size(tensor, d); in_bounds = false; return 1; end
                return idx
            end
            in_bounds && (u_raw = tensor[tensor_indices...])
        else
            in_bounds = false
        end

        if in_bounds && !isnothing(u_raw)
            u_out[I] = _component_value(u_raw, target_c)
        end
    end

    return Tuple(plot_axes_data), u_out
end

"""
    extract_lagrangian_data(...)

Extracts Lagrangian particle fields by locating the closest requested UI time step and mapping raw coordinates into native Makie `Point` types.
"""
function extract_lagrangian_data(pd::PlotSweepData, param_indices, sel_vals, plot_vars, u_key::Symbol, target_c)
    sim_data = pd.data[param_indices...]
    isnothing(sim_data) && return nothing

    tensor = get(sim_data.stats, u_key, nothing)
    isnothing(tensor) && return nothing

    time_dim = sim_data.domain.time_dim
    ui_time_idx = isnothing(time_dim) ? nothing : findfirst(isequal(time_dim), plot_vars)

    if !isnothing(ui_time_idx) && !isempty(sim_data.t)
        target_t = sel_vals[ui_time_idx]
        t_idx = findmin(v -> abs(v - target_t), sim_data.t)[2]
    else
        t_idx = 1
    end

    # Per-particle fields are stored per time step; everything else is not a particle field.
    is_particle_field = tensor isa AbstractVector && eltype(tensor) <: AbstractVector && !(eltype(tensor) <: SVector)
    is_particle_field || return nothing
    u_raw = tensor[t_idx]
    x_step = sim_data.x[t_idx]
    (isempty(x_step) || length(u_raw) != length(x_step)) && return nothing

    u_flat = Float64[_component_value(v, target_c) for v in u_raw]
    DS = length(x_step[1])

    if DS == 1
        pts = Float64[Float64(p[1]) for p in x_step]
    elseif DS == 2
        pts = Point2f[Point2f(p[1], p[2]) for p in x_step]
    else
        pts = Point3f[Point3f(p[1], p[2], p[3]) for p in x_step]
    end

    return pts, u_flat
end

"""
    update_plot_data_collection!(plot_data_dict, sim_config, active_methods; force_reload=false)

Synchronizes the global plot data dictionary against the currently active simulation methods.
Assembles missing tensors into `PlotSweepData` caches and prunes inactive ones from memory.
"""
function update_plot_data_collection!(plot_data_dict, sim_config, active_methods; force_reload=false)
    force_reload && empty!(plot_data_dict)
    missing_methods = filter(m -> !haskey(plot_data_dict, m), active_methods)
    if !isempty(missing_methods)
        domain = _get_template_domain(sim_config)  # loaded once for all methods
        # The numerical methods first: the references are laid out on their domains and times (per sweep point).
        for m_name in sort(missing_methods, by = is_reference_method)
            base_params = assemble_params(sim_config.shared, sim_config.methods, m_name)
            numeric = [plot_data_dict[m] for m in active_methods if !is_reference_method(m) && haskey(plot_data_dict, m)]
            new_data = create_plot_data(m_name, base_params, sim_config, domain; numeric = numeric)
            isnothing(new_data) || (plot_data_dict[m_name] = new_data)
        end
    end
    # Collect first: deleting while iterating a Dict skips entries.
    for k in collect(keys(plot_data_dict))
        Symbol(k) in active_methods || delete!(plot_data_dict, k)
    end
    return plot_data_dict
end

"""
    fetch_pipeline_tuples(::Val{:eulerian}, ...)

Consolidates extracted Eulerian axes and scalar fields across all active methods into a unified tuple structure `(ax_cols..., u_col)` for the rendering pipeline.
"""
function fetch_pipeline_tuples(::Val{:eulerian}, data, local_methods, _build_param_indices, mutated_sel_vals, x_sel, y_sel, z_sel, u_sel, target_c_int)
    active_plot_axes_syms = Symbol[s for s in (x_sel[], y_sel[], z_sel[]) if !isnothing(s) && s !== :none]
    ax_cols = [Any[] for _ in 1:length(active_plot_axes_syms)]
    u_col = Any[]

    valid_methods = Symbol[]

    for m_name in local_methods
        !haskey(data, m_name) && continue
        pd = data[m_name]
        p_idx = _build_param_indices(pd, mutated_sel_vals)

        res = extract_eulerian_data(pd, p_idx, mutated_sel_vals, manager.plot_vars, active_plot_axes_syms, u_sel[], target_c_int)
        if !isnothing(res)
            p_axes, u_flat = res
            for d in 1:length(active_plot_axes_syms)
                push!(ax_cols[d], p_axes[d])
            end
            push!(u_col, u_flat)
            push!(valid_methods, m_name)
        end
    end
    return Tuple([ax_cols..., u_col]), valid_methods
end

"""
    fetch_pipeline_tuples(::Val{:lagrangian}, ...)

Consolidates extracted Lagrangian point clouds and values across all active methods into a standardized `(pts_col, u_col)` tuple for the rendering pipeline.
"""
function fetch_pipeline_tuples(::Val{:lagrangian}, data, local_methods, _build_param_indices, mutated_sel_vals, x_sel, y_sel, z_sel, u_sel, target_c_int)

    pts_col = Any[]
    u_col = Any[]
    valid_methods = Symbol[]

    for m_name in local_methods
        !haskey(data, m_name) && continue
        pd = data[m_name]
        p_idx = _build_param_indices(pd, mutated_sel_vals)

        res = extract_lagrangian_data(pd, p_idx, mutated_sel_vals, manager.plot_vars, u_sel[], target_c_int)
        if !isnothing(res)
            pts, u_flat = res
            push!(pts_col, pts)
            push!(u_col, u_flat)
            push!(valid_methods, m_name)
        end
    end
    # Lagrangian is ALWAYS length 2: (Points, U)
    return (pts_col, u_col), valid_methods
end
