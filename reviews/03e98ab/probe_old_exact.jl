using Test, PDEStudio, StaticArrays
function exact_sparse_1d(params::ParamDict)
    N, dt, every = params[:N], params[:dt], params[:every]
    x = collect(range(0.0, step = 2π / N, length = N))
    t = collect(0.0:dt*every:2.0)
    return create_sim_data(x, [SVector(sin(xi - ti) + 2.0) for xi in x, ti in t], t, params; time_dim = :t, dims = :x)
end
exact_sparse_factory(params) = (xt -> SVector(sin(xt[1] - xt[2]) + 2.0))
set_save_path!(mktempdir()); reset_manager!(); set_stat_preset!("hyperbolic")
for every in (1, 4, 20)
    cfg = SimulationConfig(create_param_dict(:N => 200, :dt => 0.01, :every => every, :sim_func_name => :exact_sparse_1d),
                           create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                           [:num, :analytical_solution]; reference = :exact_sparse_factory)
    run_all_simulations(cfg; calculate_stats = true)
    pd = PDEStudio.update_plot_data_collection!(Dict{Symbol, PDEStudio.AbstractPlotData}(), cfg, [:num, :analytical_solution])
    dn, dr = pd[:num].data[1], pd[:analytical_solution].data[1]
    exact_error(d) = maximum(k -> maximum(abs.(getindex.(d.u[:, k], 1) .- (sin.(d.axes[1] .- d.axes[2][k]) .+ 2))), axes(d.u, 2))
    println("every=$every: nt shown ", length(dn.axes[2]), " exact_error(dn) = ", exact_error(dn), " exact_error(dr) = ", exact_error(dr))
    # drawn difference between data and reference at the same index
    println("   max |num - ref| = ", maximum(abs.(getindex.(dn.u, 1) .- getindex.(dr.u[1:2:end, :], 1))))
end
