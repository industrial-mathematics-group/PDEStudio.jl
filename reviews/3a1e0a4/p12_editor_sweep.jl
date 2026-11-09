# The Sweep editor changes the setup in place (bound_setup is not updated); then Reset Simulation (headless)
using PDEStudio
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
sl() = [(x.name, x.value) for x in studio_state().sliders]
adv() = SimulationConfig(create_param_dict(:N => 60, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                           :sim_func_name => :solve_advection_1d),
                         create_method_dict(:fd => create_param_dict()), [:fd];
                         varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))
launch_plotter(adv(); style = :lines)
studio_set!(:scheme => "lax_friedrichs")
println("start:                 ", sl(), "  slider_cache ", filter(p -> startswith(string(p[1]), "param"), M.slider_cache))
M.active_config.varied[:c] = [1.0, 2.0, 3.0]          # the Sweep editor: in place, then remaps the sliders
PDEStudio._after_raw_change!(:sweep, "c added")
M.widgets[:run_button].clicks[] += 1
println("after edit + Run:      ", sl(), "  bound_setup ", M.bound_setup)
studio_set!(:c => 3.0, :scheme => "upwind")
println("user sets c=3, upwind: ", sl(), "  slider_cache ", filter(p -> startswith(string(p[1]), "param"), M.slider_cache))
reset_sim_config!()                                    # Files → Reset Simulation
M.widgets[:run_button].clicks[] += 1
println("after Reset + Run:     ", sl(), "  (scheme was upwind; slot 1 held c = 3.0)")
