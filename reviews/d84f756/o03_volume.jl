# How many saturated pixels a CairoMakie snapshot of a volume plot (empty axes + colorbar) has: the old (691bed7)
# GLMakie path rendered snapshots with CairoMakie, so this is what the strengthened plots-2 assertion saw there.
using PDEStudio, StaticArrays
include(joinpath(dirname(@__DIR__), "repo", "reviews", "47b4c6e", "o01_simfuncs.jl"))
studio_headless!(); set_save_path!(mktempdir())
config = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :tag => "a", :sim_func_name => :advection_solver_1d),
                          create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                             :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
                          [:upwind, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.25, 0.5, 0.75, 1.0], :tag => ["a", "b"]),
                          reference = :exact_advection_factory)
launch_plotter(config)
for style in (:heatmap_surface, :volume_3d)
    studio_set!(:plot_style => style, :y_axis => :t, :z_axis => (style === :volume_3d ? :cfl : :none))
    img = PDEStudio.Makie.FileIO.load(studio_snapshot(joinpath(@__DIR__, "o03_cairo_$style.png")))
    println(style, ": coloured = ", count(p -> abs(p.r - p.g) + abs(p.g - p.b) > 0.3, img), " of ", length(img), "  status ", studio_state().status.level)
end
