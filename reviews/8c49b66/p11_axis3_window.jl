include(joinpath(@__DIR__, "fixtures.jl"))
using PDEStudio.Makie: Axis3
out = joinpath(@__DIR__, "out"); mkpath(out)
long = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
    create_method_dict(:upwind_first_order_scheme_without_limiter => create_param_dict(:scheme => "upwind"),
                       :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs"),
                       :ÄÖÜ_αβγ_Lax_Friedrichs_scheme_with_unicode_name => create_param_dict(:scheme => "lax_friedrichs")),
    [:upwind_first_order_scheme_without_limiter, :lax_friedrichs, :ÄÖÜ_αβγ_Lax_Friedrichs_scheme_with_unicode_name])
reset_plotter!()
launch_plotter(long; style = :heatmap_surface)
studio_set!(:x_axis => :x, :y_axis => :t)
studio_set!(:compare_target => :methods, :plot_width => 250, :compare_columns => 2)
studio_snapshot(joinpath(out, "p11_axis3_window.png"); area = :window)
ax = first(b for b in PDEStudio.manager.master_fig.content if b isa Axis3)
println("[protrusions attr] ", hasproperty(ax, :protrusions) ? ax.protrusions[] : "none")
