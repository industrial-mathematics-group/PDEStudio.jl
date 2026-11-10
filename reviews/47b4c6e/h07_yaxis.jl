using PDEStudio
studio_headless!(); set_save_path!(mktempdir())
config = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :tag => "a", :sim_func_name => :advection_solver_1d),
                          create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                             :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
                          [:upwind, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.25, 0.5, 0.75, 1.0], :tag => ["a", "b"]),
                          reference = :exact_advection_factory)
launch_plotter(config)
y() = only(c for c in studio_controls() if c.name === :y_axis).choices
@show y() studio_state().axes
studio_set!(:plot_style => :heatmap_flat); @show y() studio_state().axes studio_state().style
studio_set!(:x_axis => :x); @show y()
studio_set!(:plot_style => :lines_1d)
studio_set!(:x_axis => :t); studio_set!(:x_axis => :x)
studio_set!(:plot_style => :heatmap_flat); @show y()
