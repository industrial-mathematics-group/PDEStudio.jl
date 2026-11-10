# set_sim_config!(other setup) into an open window that compares: compare menu vs compare state (headless)
using PDEStudio; using PDEStudio.Makie: Axis, Axis3
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
nax() = count(b -> b isa Axis || b isa Axis3, M.master_fig.content)
show_(tag) = (s = studio_state(); println(rpad(tag, 30), "compare state=", s.compare.target, " menu=", M.widgets[:compare_target].selection[],
               " layout_cache=", M.layout_cache[:compare_target], " axes=", nax(), " plot axes=", (s.axes.x, s.axes.y),
               " sliders=", [(x.name, x.value) for x in s.sliders], " flags lay=", M.flags[:Layout][]))
adv = SimulationConfig(create_param_dict(:N => 40, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                         :sim_func_name => :solve_advection_1d),
                       create_method_dict(:fd => create_param_dict()), [:fd];
                       varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))
for target in (:time, :scheme)
    println("== compare $target")
    reset_plotter!()
    launch_plotter(adv; style = :lines)
    studio_set!(:compare_target => target)
    show_("adv comparing")
    set_sim_config!(test_heat_2d()); force_simulation()
    show_("heat bound + run")
    studio_press!(:apply_layout)
    show_("after Apply Layout")
    reset_plotter!()
    launch_plotter(adv; style = :lines); studio_set!(:compare_target => target)
    launch_plotter(test_heat_2d(); style = :lines)
    show_("(relaunch instead)")
end
