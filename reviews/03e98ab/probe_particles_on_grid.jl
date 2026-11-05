# 13b3dfd: particle data drawn with a grid style keeps Core's uniform time resampling (nearest snapshot)
using Test, PDEStudio, StaticArrays
const P = PDEStudio
function parts_1d(params::ParamDict)
    t = [0.0, 0.1, 0.2, 1.0]
    x0 = collect(range(0.0, 1.0, length = 40))
    create_sim_data([[SVector(p) for p in x0] for ti in t], [[SVector(ti) for _ in x0] for ti in t], t, params; time_dim = :t)
end
@testset "particles on a grid: drawn times are stored times" begin
    set_save_path!(mktempdir()); reset_manager!()
    cfg = SimulationConfig(create_param_dict(:N => 40, :sim_func_name => :parts_1d), create_method_dict(:num => create_param_dict()), [:num])
    run_all_simulations(cfg)
    @show P.manager.mode[]
    pd = P.update_plot_data_collection!(Dict{Symbol, P.AbstractPlotData}(), cfg, [:num])
    d = pd[:num].data[1]
    println(typeof(d).name.name, " time axis: ", d.axes[2][1:6], " … (", length(d.axes[2]), " times)")
    # value u = t of the stored snapshot shown vs the time it is labelled with
    k = findfirst(t -> t > 0.3, d.axes[2])
    println("labelled t = ", d.axes[2][k], ", drawn snapshot value (= its time) = ", d.u[20, k][1])
    @test issubset(d.axes[2], [0.0, 0.1, 0.2, 1.0])
end
