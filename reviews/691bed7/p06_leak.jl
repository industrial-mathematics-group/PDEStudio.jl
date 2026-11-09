using PDEStudio
studio_headless!()
set_save_path!(mktempdir())
w() = PDEStudio.manager.widgets
show_state(tag) = (s = studio_state(); println(tag, ": style=", s.style, " axes=", s.axes, " sliders=", [(x.name, x.value) for x in s.sliders], " nplots=", length(s.plots), " compare=", s.compare.target, " title=", s.plots[1].title))
mode = ARGS[1]
shared = create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind", :sim_func_name => :solve_advection_1d)
cfg = SimulationConfig(shared, create_method_dict(:fd => create_param_dict()), [:fd]; varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))
launch_plotter(cfg)
sel!(k, v) = (m = w()[k]; m.i_selected[] = findfirst(o -> o[2] === v, m.options[]))
if mode == "gui"
    sel!(:compare_target, :time); w()[:layout_apply].clicks[] += 1
    sel!(:compare_target, :none); w()[:layout_apply].clicks[] += 1
elseif mode == "api"
    studio_set!(:compare_target => :time); studio_set!(:compare_target => :none)
end
show_state("session1 end")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
show_state("heat launch")
