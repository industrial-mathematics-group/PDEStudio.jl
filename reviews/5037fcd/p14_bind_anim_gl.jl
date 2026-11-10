# set_sim_config!(other) into an open GLMakie window while Play Anim runs over a swept parameter.
# Usage: DISPLAY=:99 julia --project=env p14_bind_anim_gl.jl [play|noplay]
using PDEStudio, GLMakie
GLMakie.activate!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
adv = SimulationConfig(create_param_dict(:N => 60, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                         :sim_func_name => :solve_advection_1d),
                       create_method_dict(:fd => create_param_dict()), [:fd];
                       varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))
display(launch_plotter(adv; style = :lines))
studio_set!(:anim_target => :scheme)
M.ui[:export][:animation_time] = 4.0
play = get(ARGS, 1, "play") == "play"
play && (M.widgets[:play_anim_button].clicks[] += 1)
sleep(0.6)
println("animating before bind: ", M.is_animating[])
heat = test_heat_2d()
set_sim_config!(heat); force_simulation()
for k in 1:3
    sleep(0.5)
    s = studio_state()
    println("t+$(0.5k)s: animating=", M.is_animating[], " button=", M.widgets[:play_anim_button].label[],
            " anim menu=", M.widgets[:anim_target].selection[], " axes=", (s.axes.x, s.axes.y),
            " sliders=", [(x.name, x.value) for x in s.sliders])
end
println("default r = ", first(heat.varied[:r]))
reset_plotter!()
