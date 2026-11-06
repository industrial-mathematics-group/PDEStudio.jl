# Probe: numerical data that IS the exact solution, stored at sparse output times; after the fix the reference is
# evaluated at the display (label) times, the numeric curve shows the nearest stored snapshot. Any drawn difference
# between the two is the time mismatch alone.
using PDEStudio, Test, StaticArrays
PDEStudioCore.set_target_module!(Main)
set_save_path!(mktempdir()); reset_manager!(); set_mode!(:eulerian)
function exact_sparse(params)            # exact transport sin(x - t) + 2, stored every `every`-th step
    N, dt, every = params[:N], params[:dt], params[:every]
    x = collect(range(0.0, step = 2π / N, length = N))
    t = collect(0.0:dt*every:2.0)
    create_sim_data(x, [SVector(sin(xi - ti) + 2.0) for xi in x, ti in t], t, params; time_dim = :t, dims = :x)
end
fac(p) = (xt -> SVector(sin(xt[1] - xt[2]) + 2.0))
@testset "time offsets" begin
@testset "time offset of the drawn reference (every = $every)" for every in (1, 4, 20)
    cfg = SimulationConfig(create_param_dict(:N => 64, :dt => 0.01, :every => every, :sim_func_name => :exact_sparse),
                           create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                           [:num, :analytical_solution]; reference = :fac)
    run_all_simulations(cfg; calculate_stats = false)
    pd = PDEStudio.update_plot_data_collection!(Dict{Symbol, PDEStudio.AbstractPlotData}(), cfg, [:num, :analytical_solution])
    dn, dr = pd[:num].data[1], pd[:analytical_solution].data[1]
    raw = load_sim_data(PDEStudioCore.generate_tasks(cfg)[1], Val(:raw))
    # which stored snapshot each display time shows
    offs = [minimum(abs.(raw.axes[2] .- τ)) for τ in dn.axes[2]]
    # drawn difference: reference vs numeric at the same display time (interpolate the 400-point reference to x of the data)
    maxdiff = maximum(1:length(dn.axes[2])) do k
        τ = dn.axes[2][k]; snap = raw.axes[2][argmin(abs.(raw.axes[2] .- τ))]
        maximum(abs.(getindex.(dn.u[:, k], 1) .- (sin.(dn.axes[1] .- snap) .+ 2)))  # numeric = exact at its snapshot
    end
    drawn = maximum(1:length(dn.axes[2])) do k
        maximum(abs.(getindex.(dn.u[:, k], 1) .- (sin.(dn.axes[1] .- dn.axes[2][k]) .+ 2)))  # vs reference at label time
    end
    println("every = $every: stored dt_out = $(0.01every), $(length(raw.axes[2])) stored times -> $(length(dn.axes[2])) display times; ",
            "max |label - snapshot time| = $(round(maximum(offs), digits = 4)); drawn |num - ref| up to $(round(drawn, digits = 4)) ",
            "for data that is exact (consistency check $(round(maxdiff, sigdigits = 2)))")
    @test dr.axes[2] == dn.axes[2]
    @test drawn < 1e-3
end
end
