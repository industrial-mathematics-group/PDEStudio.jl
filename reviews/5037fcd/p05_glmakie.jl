# The original reproducer with GLMakie on the Xvfb display, GUI path, with a playing animation at the relaunch
using PDEStudio, GLMakie
GLMakie.activate!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
w() = M.widgets
show_state(tag) = (s = studio_state(); println(tag, ": style=", s.style, " axes=", s.axes, " sliders=", [(x.name, x.value) for x in s.sliders], " compare=", s.compare.target, " title=", s.plots[1].title))
shared = create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind", :sim_func_name => :solve_advection_1d)
cfg = SimulationConfig(shared, create_method_dict(:fd => create_param_dict()), [:fd]; varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))
display(launch_plotter(cfg))
sel!(k, v) = (m = w()[k]; m.i_selected[] = findfirst(o -> o[2] === v, m.options[]))
sel!(:compare_target, :time); w()[:layout_apply].clicks[] += 1
sel!(:compare_target, :none); w()[:layout_apply].clicks[] += 1
studio_set!(:scheme => "lax_wendroff")
show_state("session1 end")
# start the animation (Play Anim) and relaunch while it plays
get(ARGS, 1, "play") == "play" && haskey(w(), :play_anim_button) ? (w()[:play_anim_button].clicks[] += 1) : println("keys: ", filter(k -> occursin("anim", string(k)) || occursin("play", string(k)), collect(keys(w()))))
sleep(1.0)
println("animating: ", M.is_animating[])
display(launch_plotter(test_heat_2d(); style = :heatmap))
sleep(1.0)
show_state("heat launch (GLMakie)")
save(joinpath(@__DIR__, "img", "gl_heat_relaunch.png"), M.master_fig)
reset_plotter!()
