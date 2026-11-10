include(joinpath(@__DIR__, "fixtures.jl"))
out = joinpath(@__DIR__, "out"); mkpath(out)
pcfg(mode; style = :particles_lines) = SimulationConfig(create_param_dict(:n => 12, :mode => mode, :sim_func_name => :shuffled_particle_solver),
    create_method_dict(:a => create_param_dict()), [:a]; reference = :exact_particle_factory)

reset_plotter!()
launch_plotter(pcfg("plain"); style = :particles_lines)
pts() = first(values(studio_data(1).methods)).points
@probe "lines t=0 sorted" issorted(first.(pts()))
studio_set!(:t => 0.5)
@probe "lines t=0.5 sorted" issorted(first.(pts()))
@probe "studio_data keys" keys(first(values(studio_data(1).methods)))
studio_snapshot(joinpath(out, "p1_lines.png"))
# u values follow their points?
d = first(values(studio_data(1).methods))
@probe "u follows x (sin(2pi(x-0.05)))" maximum(abs.(d.values .- sin.(2π .* (first.(d.points) .- 0.05)))) < 1e-12

# particles_colors (no lines): storage order kept
studio_set!(:plot_style => :particles_colors)
@probe "colors style" (studio_state().style, issorted(first.(pts())))
studio_set!(:plot_style => :particles_lines)
@probe "back to lines" (studio_state().style, issorted(first.(pts())))

# NaN position at t = 0.5
reset_plotter!()
launch_plotter(pcfg("nan"); style = :particles_lines)
studio_set!(:t => 0.5)
@probe "nan: points" first.(pts())
studio_snapshot(joinpath(out, "p1_nan.png"))
# duplicate x
reset_plotter!()
launch_plotter(pcfg("dup"); style = :particles_lines)
@probe "dup: points" first.(pts())

# Compare over time with lines
reset_plotter!()
launch_plotter(pcfg("plain"); style = :particles_lines)
studio_set!(:compare_target => :time)
@probe "compare time plots sorted" [issorted(first.(first(values(studio_data(i).methods)).points)) for i in 1:length(studio_state().plots)]
studio_snapshot(joinpath(out, "p1_compare_time.png"))
studio_set!(:compare_target => :none)

# animation export frames go through sync?
println("render files: ", readdir(out))
