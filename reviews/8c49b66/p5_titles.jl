include(joinpath(@__DIR__, "fixtures.jl"))
const M = PDEStudio.manager
using PDEStudio.Makie: Axis, Axis3
out = joinpath(@__DIR__, "out"); mkpath(out)
long = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
    create_method_dict(:upwind_first_order_scheme_without_limiter => create_param_dict(:scheme => "upwind"),
                       :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs"),
                       :ÄÖÜ_αβγ_Lax_Friedrichs_scheme_with_unicode_name => create_param_dict(:scheme => "lax_friedrichs")),
    [:upwind_first_order_scheme_without_limiter, :lax_friedrichs, :ÄÖÜ_αβγ_Lax_Friedrichs_scheme_with_unicode_name];
    varied = create_varied_dict(:cfl => [0.25, 0.5]))
drawn() = [b.title[] for b in M.master_fig.content if b isa Union{Axis, Axis3}]
reset_plotter!()
launch_plotter(long; style = :lines)
studio_set!(:compare_target => :methods, :plot_width => 300)
@probe "drawn 300" drawn()
@probe "api 300" [p.title for p in studio_state().plots]
studio_snapshot(joinpath(out, "p5_methods_300.png"))
studio_set!(:plot_width => 50)
@probe "drawn 50" drawn()
studio_snapshot(joinpath(out, "p5_methods_50.png"))
studio_set!(:plot_width => 500)
# set_label! with spaces
PDEStudio.set_label!(:upwind_first_order_scheme_without_limiter, "Upwind first order scheme without any limiter at all")
studio_press!(:apply_layout)
@probe "drawn label spaces" drawn()
# custom title with a newline
studio_option!(:labels, :title, "Line one\nLine two")
@probe "custom drawn" drawn()
@probe "custom api" [p.title for p in studio_state().plots]
studio_option!(:labels, :title, "default")
# compare over time
studio_set!(:compare_target => :time, :plot_width => 120)
@probe "time drawn 120" drawn()
@probe "time api" [p.title for p in studio_state().plots]
studio_snapshot(joinpath(out, "p5_time_120.png"))
studio_set!(:compare_target => :cfl, :plot_width => 120)
@probe "cfl drawn 120" drawn()
studio_set!(:plot_width => 500, :compare_target => :none)
@probe "normal api" [p.title for p in studio_state().plots]
# Axis3: heatmap_surface over x,t
studio_set!(:plot_style => :heatmap_surface, :x_axis => :x, :y_axis => :t)
studio_set!(:compare_target => :methods, :plot_width => 250)
@probe "axis3 drawn" [(typeof(b), b.title[]) for b in M.master_fig.content if b isa Union{Axis, Axis3}]
@probe "axis3 api" [p.title for p in studio_state().plots]
studio_snapshot(joinpath(out, "p5_axis3.png"))
studio_set!(:compare_target => :none)
# growth of the cache
for c in (0.25, 0.5, 0.25, 0.5); studio_set!(:cfl => c); end
@probe "title_texts length vs axes" (length(M.title_texts), length([b for b in M.master_fig.content if b isa Union{Axis, Axis3}]))
for k in 1:3; studio_snapshot(joinpath(out, "p5_snap$k.png"); plot = 1); end
@probe "title_texts after snapshots" length(M.title_texts)
