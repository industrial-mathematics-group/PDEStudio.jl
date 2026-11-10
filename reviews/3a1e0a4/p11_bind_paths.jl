# Attack the binding paths of 5037fcd (headless): bind without Run, presets, Reset Simulation after an editor sweep
# change, CSV into an open window, a failed launch_plotter (stale launch_run), animation while binding.
using PDEStudio
studio_headless!()
sp = mktempdir(); set_save_path!(sp)
const M = PDEStudio.manager
st(tag) = (s = studio_state(); println(rpad(tag, 34), "axes=", (s.axes.x, s.axes.y), " sliders=", [(x.name, x.value) for x in s.sliders],
            " anim=", get(M.exploration_cache, :anim_target, :-), " animating=", M.is_animating[],
            "\n", " "^34, "[", s.status.level, "] ", s.status.text, "\n", " "^34, "title=", isempty(s.plots) ? "-" : s.plots[1].title))
adv(; schemes = ["upwind", "lax_friedrichs", "lax_wendroff"], extra = ()) =
    SimulationConfig(create_param_dict(:N => 60, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                       :sim_func_name => :solve_advection_1d),
                     create_method_dict(:fd => create_param_dict()), [:fd];
                     varied = create_varied_dict(:scheme => schemes, extra...))

println("== 1: set_sim_config!(other) into an open window, no Run yet (what the window shows meanwhile)")
launch_plotter(adv(); style = :heatmap)
studio_set!(:scheme => "lax_wendroff")
st("1 adv")
set_sim_config!(test_heat_2d())
st("1 after bind, before Run")
println("   menus: ", [(k, M.widgets[k].selection[]) for k in (:x_axis, :y_axis, :anim_target)], " t range ", M.widgets[:t].range[])
studio_snapshot(joinpath(@__DIR__, "img", "p11_bound_before_run.png"); area = :window)
force_simulation()
st("1 after Run")

println("== 2: preset that adds a swept parameter (set_sim_preset!, replace)")
reset_plotter!()
launch_plotter(adv(); style = :lines)
studio_set!(:scheme => "lax_wendroff")
cfg2 = deepcopy(M.active_config); cfg2.varied[:cfl] = [0.25, 0.5]
M.active_config = cfg2                     # (only to save it as a preset)
save_sim_preset("pluscfl")
M.active_config.varied = delete!(copy(cfg2.varied), :cfl)
st("2 before preset")
set_sim_preset!("pluscfl"; mode = :replace)
force_simulation()
st("2 after preset + run")
studio_set!(:cfl => 0.5)
reset_sim_config!()
force_simulation()
st("2 after Reset Simulation + run")

println("== 3: editor adds a swept parameter in the open window, then Reset Simulation")
reset_plotter!()
launch_plotter(adv(); style = :lines)
studio_set!(:scheme => "lax_friedrichs")
M.active_config.varied[:cfl] = [0.25, 1.0]              # (what the Sweep editor does: in place, then remaps)
PDEStudio._after_raw_change!(:sweep, "cfl added")
M.widgets[:run_button].clicks[] += 1
studio_set!(:cfl => 1.0, :scheme => "lax_wendroff")
st("3 edited sweep, cfl=1, lw")
println("   slider_cache: ", M.slider_cache, " bound_setup: ", M.bound_setup)
reset_sim_config!()
M.widgets[:run_button].clicks[] += 1
st("3 after Reset Simulation")
println("   slider_cache: ", M.slider_cache)

println("== 4: CSV of another setup loaded into an open window (applies its own view?)")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
studio_set!(:r => 0.3)
studio_set!(:x_axis => :x, :y_axis => :t)
st("4 heat x-t r=0.3 (to save)")
PDEStudio.save_params_to_csv("heatview", sp, Dict("Save Type" => "probe"))
reset_plotter!()
launch_plotter(adv(); style = :heatmap)
st("4 adv")
r = set_sim_config!(joinpath(sp, "heatview.csv"))
println("   staged: ", r)
force_simulation()
st("4 after CSV load + run")

println("== 5: launch_plotter(B; style = typo) fails after the prepare run; Run in the old window")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
st("5 heat window")
try
    launch_plotter(adv(; schemes = ["upwind", "lax_wendroff"]); style = :heatmapp)
catch e
    println("   launch error: ", sprint(showerror, e)[1:min(end, 90)])
end
println("   launch_run after failure: ", M.launch_run)
M.widgets[:run_button].clicks[] += 1
st("5 Run click in the heat window")

println("== 6: animation over a parameter while another config is bound")
reset_plotter!()
launch_plotter(adv(); style = :lines)
studio_set!(:anim_target => :scheme)
M.ui[:export][:animation_time] = 3.0
M.widgets[:play_anim_button].clicks[] += 1
sleep(0.5)
println("   animating: ", M.is_animating[])
set_sim_config!(test_heat_2d()); force_simulation()
for k in 1:4
    sleep(0.4)
    s = studio_state()
    println("   t+$(0.4k)s: animating=", M.is_animating[], " anim=", M.widgets[:anim_target].selection[],
            " sliders=", [(x.name, x.value) for x in s.sliders])
end
M.is_animating[] = false
