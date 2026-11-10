# Animation export over a slider whose values change the number of title lines (headless CairoMakie)
using PDEStudio; using PDEStudio.Makie: Axis, Axis3
studio_headless!()
sp = mktempdir(); set_save_path!(sp)
const M = PDEStudio.manager
out = joinpath(@__DIR__, "img"); mkpath(out)
cfg = SimulationConfig(create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                         :sim_func_name => :solve_advection_1d),
                       create_method_dict(:fd => create_param_dict()), [:fd];
                       varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"],
                                                   :cfl => [0.25, 0.5]))
launch_plotter(cfg)
title() = only(b for b in M.master_fig.content if b isa Axis).title[]
w = 0
for ww in 300:10:700
    studio_set!(:plot_width => ww); studio_set!(:scheme => "upwind"); a = count(==('\n'), title())
    studio_set!(:scheme => "lax_friedrichs"); b = count(==('\n'), title())
    a != b && (global w = ww; break)
end
println("width ", w)
studio_set!(:plot_width => w)
for s in ("upwind", "lax_friedrichs", "lax_wendroff")
    studio_set!(:scheme => s)
    println(s, ": ", repr(only(b for b in M.master_fig.content if b isa Axis).title[]))
end
studio_set!(:scheme => "upwind")
studio_set!(:anim_target => :scheme)
M.ui[:export][:animation_time] = 1.0
M.ui[:export][:animation_FPS] = 3
M.ui[:export][:dpi] = 96
M.widgets[:export_text].stored_string[] = "anim.mp4"
M.widgets[:export_button].clicks[] += 1
println("status: ", studio_state().status.text)
mp4 = joinpath(sp, "animations", "anim.mp4")
println("mp4 exists: ", isfile(mp4))
ff = PDEStudio.Makie.FFMPEG_jll.ffmpeg()
run(pipeline(`$ff -loglevel error -y -i $mp4 $(joinpath(out, "anim_w$(w)_%02d.png"))`))
println(readdir(out))
