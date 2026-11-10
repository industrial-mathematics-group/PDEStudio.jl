include(joinpath(@__DIR__, "fixtures.jl"))
out = joinpath(@__DIR__, "out"); mkpath(out)
set_stat_preset!("hyperbolic")
pcfg = SimulationConfig(create_param_dict(:n => 12, :mode => "plain", :sim_func_name => :shuffled_particle_solver),
    create_method_dict(:a => create_param_dict()), [:a]; reference = :exact_particle_factory)
ctl(n) = only(c for c in studio_controls() if c.name === n)
reset_plotter!()
launch_plotter(pcfg; style = :particles_lines)
@probe "lag u label" ctl(:u_axis).label
@probe "lag u choices" ctl(:u_axis).choices
@probe "lag err" studio_set!(:u_axis => :l1error)
# follow hint literally
lbl = ctl(:u_axis).label
m = match(r"studio_set!\((.*)\)$", lbl)
@probe "hint call" isnothing(m) ? "no call" : m.captures[1]
@probe "follow hint" studio_set!(:plot_style => :lines, :x_axis => :t, :u_axis => :l1error)
s = studio_state(); @probe "after" (s.style, s.axes, PDEStudio.manager.mode[], s.status)
studio_snapshot(joinpath(out, "p2b_lag_err_t.png"))
