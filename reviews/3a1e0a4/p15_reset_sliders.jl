# Does _reset_open_view! leave slider positions in slider_cache (range [0.0] -> value 0.0)? A sweep through 0 then
# starts at 0 instead of at its first value (headless)
using PDEStudio
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
sl() = [(x.name, x.value) for x in studio_state().sliders]
mk(varied...) = SimulationConfig(create_param_dict(:N => 40, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                                   :dummy => 0.0, :sim_func_name => :solve_advection_1d),
                                 create_method_dict(:fd => create_param_dict()), [:fd]; varied = create_varied_dict(varied...))
other = mk(:dummy => [-2.0, 0.0, 2.0])
launch_plotter(other; style = :lines)
println("fresh launch of `other`:            ", sl())
reset_plotter!()
launch_plotter(mk(:scheme => ["upwind", "lax_wendroff"]); style = :lines)
set_sim_config!(other)
println("slider_cache right after the bind:  ", M.slider_cache)
force_simulation()
println("`other` bound into the open window: ", sl())
reset_plotter!()
launch_plotter(mk(:scheme => ["upwind", "lax_wendroff"]); style = :lines)
launch_plotter(other; style = :lines)
println("launch_plotter(other) relaunch:     ", sl())
