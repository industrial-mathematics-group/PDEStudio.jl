include(joinpath(@__DIR__, "fixtures.jl"))
const M = PDEStudio.manager
using PDEStudio.Makie: Axis, Axis3
out = joinpath(@__DIR__, "out"); mkpath(out)
cfg = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :tag => "a", :sim_func_name => :advection_solver_1d),
    create_method_dict(:upwind_first_order_scheme_without_limiter => create_param_dict(:scheme => "upwind"),
                       :upwind_first_order_scheme_with_limiter => create_param_dict(:scheme => "lax_friedrichs")),
    [:upwind_first_order_scheme_without_limiter, :upwind_first_order_scheme_with_limiter];
    varied = create_varied_dict(:cfl => [0.25, 0.5], :tag => ["a", "b"]))
reset_plotter!()
launch_plotter(cfg; style = :lines)
studio_set!(:compare_target => :methods)
for w in (500, 300, 200, 150)
    studio_set!(:plot_width => w)
    drawn = [b.title[] for b in M.master_fig.content if b isa Axis]
    println("2D w=$w: ", repr(drawn), " distinct=", allunique(drawn))
end
studio_snapshot(joinpath(out, "q5_2d_150.png"); area = :window)
for w in (500, 400, 300)
    studio_set!(:plot_style => :heatmap_surface, :plot_width => w)
    drawn = [b.title[] for b in M.master_fig.content if b isa Axis3]
    println("3D w=$w: ", repr(drawn), " distinct=", allunique(drawn), "  api: ", [p.title for p in studio_state().plots])
end
studio_snapshot(joinpath(out, "q5_3d_300.png"); area = :window)
# single 3D plot: default tuple title
studio_set!(:compare_target => :none, :plot_width => 300)
drawn = [b.title[] for b in M.master_fig.content if b isa Axis3]
println("3D single w=300: ", repr(drawn), "  api: ", [p.title for p in studio_state().plots])
studio_snapshot(joinpath(out, "q5_3d_single300.png"); area = :window)
studio_set!(:plot_width => 500)
println("3D single w=500: ", repr([b.title[] for b in M.master_fig.content if b isa Axis3]))
# 2D single plot narrow: _fit_title (no cap)
studio_set!(:plot_style => :lines, :plot_width => 150)
println("2D single w=150: ", repr([b.title[] for b in M.master_fig.content if b isa Axis]))
# compare over a parameter in 3D: titles are "Cfl = 0.250" etc.
studio_set!(:plot_style => :heatmap_surface, :compare_target => :cfl, :plot_width => 300)
println("3D compare cfl: ", repr([b.title[] for b in M.master_fig.content if b isa Axis3]))
# custom title with newline on Axis3
studio_option!(:labels, :title, "first line\nsecond line")
println("3D custom: ", repr([b.title[] for b in M.master_fig.content if b isa Axis3]), " api ", [p.title for p in studio_state().plots])
studio_option!(:labels, :title, "default")
reset_plotter!()
