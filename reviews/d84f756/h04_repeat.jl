using PDEStudio
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
mark(s) = (println(stderr, "#### ", s); flush(stderr))
mark("A: tick_format broken")
@show studio_option!(:x_axis_1d, :tick_format, "{:nope")
mark("B: a second option while it is still broken")
@show studio_option!(:x_axis_1d, :grid_visibility, false)
@show studio_state().status
mark("C: slider move while broken")
@show studio_set!(:t => 0.4).status
@show studio_state().status
mark("D: style change while broken")
@show studio_set!(:plot_style => :scatter_1d).status
mark("END")
