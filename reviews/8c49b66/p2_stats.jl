include(joinpath(@__DIR__, "fixtures.jl"))
out = joinpath(@__DIR__, "out"); mkpath(out)
set_stat_preset!("hyperbolic")
reset_plotter!()
launch_plotter(adv_config(); style = :lines)
ctl(n) = only(c for c in studio_controls() if c.name === n)
@probe "u_axis label" ctl(:u_axis).label
@probe "x_axis label" ctl(:x_axis).label
@probe "x_axis choices" ctl(:x_axis).choices
@probe "u_axis choices" ctl(:u_axis).choices
@probe "describe u line" join(filter(l -> occursin("dependent", l) || occursin("statistic", lowercase(l)), split(sprint(describe_studio), "\n")), "\n")
@probe "err mass" studio_set!(:u_axis => :mass)
@probe "err bogus stat" studio_set!(:u_axis => :bogus)

# error over time
studio_set!(:plot_style => :lines, :x_axis => :t, :u_axis => :l1error)
s = studio_state()
@probe "err over t" (s.axes, s.plots[1].title, s.plots[1].ylabel)
studio_snapshot(joinpath(out, "p2_err_t.png"))
# error vs param at t slider
r = studio_set!(:x_axis => :cfl, :u_axis => :l1error, :t => 1.0)
s = studio_state()
@probe "err vs cfl" (s.axes, s.plots[1].title, [sl.name => sl.value for sl in s.sliders])
d = studio_data(1)
@probe "err vs cfl data" [(m, v.x, v.values) for (m, v) in d.methods]
studio_snapshot(joinpath(out, "p2_err_cfl.png"))
# does the t slider change the error-vs-cfl curve?
studio_set!(:t => 2.0)
d2 = studio_data(1)
@probe "err vs cfl at t=2 differs" [(m, v.values) for (m, v) in d2.methods]
@probe "title t=2" studio_state().plots[1].title

# stat|dim x entry
studio_set!(:x_axis => :x, :u_axis => :Solution)
@probe "stat|dim x entry" studio_set!(:x_axis => Symbol("l1error|t"))
s = studio_state(); @probe "after stat|dim" (s.axes, s.plots[1].xlabel, s.plots[1].ylabel)
studio_snapshot(joinpath(out, "p2_statdim.png"))
studio_set!(:x_axis => :x, :u_axis => :Solution)

# 2D style: heatmap with x,t; hint example
studio_set!(:plot_style => :heatmap, :x_axis => :x, :y_axis => :t)
@probe "heatmap u label" ctl(:u_axis).label
@probe "heatmap follow hint" studio_set!(:x_axis => :t, :u_axis => :l1error)
s = studio_state(); @probe "heatmap after" (s.style, s.axes)
studio_set!(:plot_style => :lines, :x_axis => :x, :u_axis => :Solution)

# no sweep, scalar stat? Use a config without varied
reset_plotter!()
cfg1 = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
    create_method_dict(:upwind => create_param_dict(:scheme => "upwind")), [:upwind]; reference = :exact_advection_factory)
launch_plotter(cfg1; style = :lines)
@probe "nosweep u label" ctl(:u_axis).label
@probe "nosweep stats" keys(PDEStudio._get_first_valid(first(values(PDEStudio.manager.plot_data[]))).stats)
@probe "nosweep kept dims" [k => PDEStudioCore.get_kept_dims(k, PDEStudio._get_first_valid(first(values(PDEStudio.manager.plot_data[]))).domain) for k in keys(PDEStudio._get_first_valid(first(values(PDEStudio.manager.plot_data[]))).stats)]
