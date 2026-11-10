# Status line after runs: failures, empty runs, no tasks, GUI click (headless CairoMakie)
using PDEStudio
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
st(tag) = (s = studio_state(); println(rpad(tag, 24), "[", s.status.level, "] ", s.status.text))
println("Core RunSummary defined: ", isdefined(PDEStudioCore, :RunSummary))

flaky_solver(p) = p[:cfl] > 0.9 ? error("CFL too large: $(p[:cfl])\nsecond line") : PDEStudioCore.Examples.solve_advection_1d(p)
empty_solver(p) = p[:cfl] > 0.9 ? nothing : PDEStudioCore.Examples.solve_advection_1d(p)
mk(solver; cfls = [0.5, 1.0]) = SimulationConfig(create_param_dict(:N => 50, :c => 1.0, :T => 0.5, :cfl => 0.5, :scheme => "upwind",
                                                  :sim_func_name => solver),
                                create_method_dict(:fd => create_param_dict()), [:fd]; varied = create_varied_dict(:cfl => cfls))

launch_plotter(mk(:flaky_solver))
st("flaky launch")
M.widgets[:run_button].clicks[] += 1
st("flaky Run click")
reset_plotter!()
launch_plotter(mk(:empty_solver))
st("empty launch")
# a fresh run in an open window: new parameter values via the editor-like path
M.active_config.varied[:cfl] = [0.5, 0.6, 0.7]
M.widgets[:run_button].clicks[] += 1
st("new values Run click")
# reference only (no numerical tasks)
reset_plotter!()
try
    cfg = test_heat_2d(); cfg.defaults = [:exact]
    launch_plotter(cfg)
    st("reference only")
catch e
    println("reference only ERROR: ", sprint(showerror, e))
end
