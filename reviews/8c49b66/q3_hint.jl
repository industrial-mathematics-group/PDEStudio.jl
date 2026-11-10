include(joinpath(@__DIR__, "fixtures.jl"))
const M = PDEStudio.manager
set_stat_preset!("hyperbolic")
hint() = only(c for c in studio_controls() if c.name === :u_axis).label
example(h) = (m = match(r"e\.g\. (studio_set!\(.*\))$", h); isnothing(m) ? nothing : m.captures[1])
function follow(tag)
    h = hint()
    ex = example(h)
    println("[$tag] style=$(studio_state().style) axes=$(studio_state().axes[(:x, :y, :z, :u)]) compare=$(studio_state().compare.target)")
    println("    hint: ", h)
    isnothing(ex) && return println("    (no example)")
    want = Symbol(match(r":u_axis => :([^\)]+)\)", ex).captures[1])
    r = try
        eval(Meta.parse(ex)); a = studio_state().axes
        a.u === want ? "OK u=$(a.u) x=$(a.x) style=$(studio_state().style)" : "WRONG u=$(a.u)"
    catch e
        "THROWS " * first(sprint(showerror, e), 300)
    end
    println("    follow: ", r)
end
function adv_x_solver(params::ParamDict)
    d = advection_solver_1d(params)
    N = params[:N]; add_stat!(d, :xprofile, [sin(2π * (i - 1) / N) for i in 1:N], [:x])
    d
end
println("=== 1D data, every style")
reset_plotter!()
launch_plotter(adv_config(); style = :lines)
for st in PDEStudio._style_choices()
    try
        studio_set!(:plot_style => st)
    catch e
        println("[$st] cannot set: ", first(sprint(showerror, e), 120)); continue
    end
    follow(st)
    studio_set!(:plot_style => :lines); studio_set!(:x_axis => :x, :u_axis => :Solution)
end
println("=== compare target = first param, only scalar stats missing")
studio_set!(:plot_style => :lines, :x_axis => :t)
studio_set!(:compare_target => :cfl)
follow("compare cfl, x=t")
studio_set!(:compare_target => :none, :x_axis => :x, :u_axis => :Solution, :plot_style => :lines)
println("=== x=cfl in heatmap with y=tag (all offered?)")
studio_set!(:plot_style => :heatmap, :x_axis => :cfl, :y_axis => :tag)
follow("heatmap cfl/tag")
println("=== no sweep")
reset_plotter!()
cfg = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
    create_method_dict(:upwind => create_param_dict(:scheme => "upwind")), [:upwind]; reference = :exact_advection_factory)
launch_plotter(cfg; style = :lines)
follow("no sweep lines")
studio_set!(:plot_style => :heatmap); follow("no sweep heatmap")
println("=== mixed kept dims (custom :xprofile keeps x), no sweep")
reset_plotter!()
cfg2 = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :sim_func_name => :adv_x_solver),
    create_method_dict(:upwind => create_param_dict(:scheme => "upwind")), [:upwind]; reference = :exact_advection_factory)
launch_plotter(cfg2; style = :heatmap)
follow("mixed, heatmap, no sweep")
studio_set!(:plot_style => :lines, :x_axis => :t, :u_axis => :Solution); follow("mixed, lines x=t")
println("=== mixed kept dims with sweep")
reset_plotter!()
cfg3 = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :sim_func_name => :adv_x_solver),
    create_method_dict(:upwind => create_param_dict(:scheme => "upwind")), [:upwind];
    varied = create_varied_dict(:cfl => [0.25, 0.5]), reference = :exact_advection_factory)
launch_plotter(cfg3; style = :heatmap)
follow("mixed, heatmap, sweep")
println("=== 2D data heat_2d")
reset_plotter!()
launch_plotter(test_heat_2d())
follow("heat2d default")
for st in (:lines, :contour, :heatmap_surface, :volume)
    try studio_set!(:plot_style => st) catch e; println("[$st] cannot: ", first(sprint(showerror, e), 100)); continue end
    follow("heat2d $st")
    try studio_set!(:plot_style => :heatmap, :x_axis => :x, :y_axis => :y, :u_axis => :Solution) catch e; println("reset fail ", e) end
end
println("=== particles")
reset_plotter!()
launch_plotter(test_particles_2d())
follow("particles")
reset_plotter!()
