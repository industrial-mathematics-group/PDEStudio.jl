# 13b3dfd: grid data shows stored snapshots; references at the data's times.
using Test, PDEStudio, StaticArrays
const P = PDEStudio

# exact transport stored at non-uniform times: :few (5 times) or :many (120 times, quadratic spacing)
function nonuni_1d(params::ParamDict)
    N = params[:N]
    x = collect(range(0.0, step = 2π / N, length = N))
    t = params[:kind] === :few ? [0.0, 0.05, 0.1, 0.4, 1.0] : [2.0 * (k / 119)^2 for k in 0:119]
    return create_sim_data(x, [SVector(sin(xi - ti) + 2.0) for xi in x, ti in t], t, params; time_dim = :t, dims = :x)
end
exact_fac(params) = (xt -> SVector(sin(xt[1] - xt[2]) + 2.0))

function nonuni_2d(params::ParamDict)
    N = params[:N]
    x = collect(range(0.0, step = 2π / N, length = N))
    t = [2.0 * (k / (params[:nt] - 1))^2 for k in 0:params[:nt]-1]
    return create_sim_data((x, x), [SVector(sin(xi + yi - ti) + 2.0) for xi in x, yi in x, ti in t], t, params; dims = (:x, :y))
end
exact2_fac(params) = (xt -> SVector(sin(xt[1] + xt[2] - xt[3]) + 2.0))

function load(cfg, methods)
    pd = P.update_plot_data_collection!(Dict{Symbol, P.AbstractPlotData}(), cfg, methods)
    return pd
end
exact_err(d) = maximum(k -> maximum(abs.(getindex.(d.u[:, k], 1) .- (sin.(d.axes[1] .- d.axes[2][k]) .+ 2))), axes(d.u, 2))

@testset "non-uniform stored times (1-D)" begin
    set_save_path!(mktempdir()); reset_manager!(); set_stat_preset!("hyperbolic")
    for kind in (:few, :many)
        cfg = SimulationConfig(create_param_dict(:N => 200, :kind => kind, :sim_func_name => :nonuni_1d),
                               create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                               [:num, :analytical_solution]; reference = :exact_fac)
        run_all_simulations(cfg; calculate_stats = true)
        pd = load(cfg, [:num, :analytical_solution])
        dn, dr = pd[:num].data[1], pd[:analytical_solution].data[1]
        stored = load_sim_data(PDEStudioCore.generate_tasks(cfg)[1], Val(:raw)).axes[2]
        println(kind, ": stored ", length(stored), " shown ", length(dn.axes[2]), " ref ", length(dr.axes[2]))
        @test length(dn.axes[2]) == min(length(stored), 50) && issubset(dn.axes[2], stored)
        @test dr.axes[2] == dn.axes[2]
        @test exact_err(dn) < 1e-10 && exact_err(dr) < 1e-10
        @test length(dn.stats[:l2error]) == length(dn.axes[2])
        @show dn.domain.spacing dr.domain.spacing
    end
end

@testset "2-D, spatial resampling + time subsampling, stats" begin
    set_save_path!(mktempdir()); reset_manager!(); set_stat_preset!("hyperbolic")
    set_resolution!(:x, 20); set_resolution!(:y, 20)
    for nt in (30, 80)
        cfg = SimulationConfig(create_param_dict(:N => 40, :nt => nt, :sim_func_name => :nonuni_2d),
                               create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                               [:num, :analytical_solution]; reference = :exact2_fac)
        run_all_simulations(cfg; calculate_stats = true)
        pd = load(cfg, [:num, :analytical_solution])
        dn, dr = pd[:num].data[1], pd[:analytical_solution].data[1]
        stored = load_sim_data(PDEStudioCore.generate_tasks(cfg)[1], Val(:raw)).axes[3]
        println("2-D nt=$nt: size ", size(dn.u), " ref ", size(dr.u), " stats ", Dict(k => size(v) for (k, v) in dn.stats if v isa AbstractArray))
        @test size(dn.u)[1:2] == (20, 20) && issubset(dn.axes[3], stored) && length(dn.axes[3]) == min(nt, 50)
        @test dr.axes[3] == dn.axes[3]
        # the drawn snapshot k is the stored one at dn.axes[3][k] (exact up to linear interpolation in space)
        k = length(dn.axes[3]) - 1
        raw = load_sim_data(PDEStudioCore.generate_tasks(cfg)[1], Val(:raw))
        j = findfirst(==(dn.axes[3][k]), raw.axes[3])
        # value at a node shared by both grids (x = 0)
        @test dn.u[1, 1, k] == raw.u[1, 1, j]
    end
end

@testset "cache invalidation: same path, rewritten with another time count" begin
    set_save_path!(mktempdir()); reset_manager!()
    cfg = SimulationConfig(create_param_dict(:N => 200, :kind => :few, :sim_func_name => :nonuni_1d),
                           create_method_dict(:num => create_param_dict()), [:num])
    run_all_simulations(cfg)
    params = PDEStudioCore.generate_tasks(cfg)[1]
    pd = load(cfg, [:num]); @test length(pd[:num].data[1].axes[2]) == 5
    path = get_file_name(params)
    # overwrite the file with 120 snapshots under the same parameters
    d = nonuni_1d(merge(copy(params), Dict(:kind => :many))); d.params[:kind] = :few
    save_sim_data(d; overwrite = true, verbose = false)
    @show get_file_name(params) == path length(P.manager.stored_time_counts)
    pd = load(cfg, [:num]); @test length(pd[:num].data[1].axes[2]) == 50
end

@testset "time resolution 1 from code" begin
    set_save_path!(mktempdir()); reset_manager!(); set_stat_preset!("hyperbolic")
    cfg = SimulationConfig(create_param_dict(:N => 200, :kind => :many, :sim_func_name => :nonuni_1d),
                           create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                           [:num, :analytical_solution]; reference = :exact_fac)
    run_all_simulations(cfg)
    set_resolution!(:t, 1)
    pd = load(cfg, [:num, :analytical_solution])
    @test haskey(pd, :num) && !isnothing(pd[:num].data[1])
    set_resolution!(:t, 50)
end

