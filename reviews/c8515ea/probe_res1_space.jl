# 3b58cb8 side effect: a space resolution of 1 (what PDEStudioCore advises for particles without extent along a dimension)
using Test, PDEStudio, StaticArrays
const P = PDEStudio
function line_parts(params::ParamDict)          # 2-D particles all on the line y = 0.5
    t = [0.0, 0.5, 1.0]
    pts = [SVector(x, 0.5) for x in range(0.0, 1.0, length = 20)]
    create_sim_data([pts for _ in t], [[SVector(p[1] + ti) for p in pts] for ti in t], t, params; time_dim = :t)
end
set_save_path!(mktempdir()); reset_manager!()
cfg = SimulationConfig(create_param_dict(:sim_func_name => :line_parts), create_method_dict(:num => create_param_dict()), [:num])
run_all_simulations(cfg)
ok = try set_resolution!(:y, 1); true catch e; println("set_resolution!(:y, 1): ", sprint(showerror, e)); false end
pd = P.update_plot_data_collection!(Dict{Symbol, P.AbstractPlotData}(), cfg, [:num])
d = pd[:num].data[1]
println("set ok = $ok; loaded: ", isnothing(d) ? "nothing" : size(d.u))
