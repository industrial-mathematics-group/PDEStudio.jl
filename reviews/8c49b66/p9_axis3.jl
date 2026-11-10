include(joinpath(@__DIR__, "fixtures.jl"))
tag = isempty(ARGS) ? "new" : ARGS[1]
out = joinpath(@__DIR__, "out"); mkpath(out)
long = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
    create_method_dict(:upwind_first_order_scheme_without_limiter => create_param_dict(:scheme => "upwind"),
                       :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
    [:upwind_first_order_scheme_without_limiter, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.25, 0.5]))
reset_plotter!()
launch_plotter(long; style = :heatmap_surface)
studio_set!(:x_axis => :x, :y_axis => :t)
studio_set!(:compare_target => :methods, :plot_width => 250)
studio_snapshot(joinpath(out, "p9_$(tag)_axis3_compare.png"))
studio_set!(:compare_target => :none, :plot_width => 150)
println("[title] ", studio_state().plots[1].title)
studio_snapshot(joinpath(out, "p9_$(tag)_axis3_single150.png"))
