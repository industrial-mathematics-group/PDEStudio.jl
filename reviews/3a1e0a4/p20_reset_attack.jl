# Attacks on 3a1e0a4's _reset_open_view! (headless): flags/buttons after the reset cascade, CSV of another setup
# with its own compare/camera/anim loaded into an animating, comparing, locked window, presets and Reset Simulation.
using PDEStudio
studio_headless!()
sp = mktempdir(); set_save_path!(sp)
const M = PDEStudio.manager
w() = M.widgets
st(tag) = (s = studio_state(); println(rpad(tag, 34), "axes=", (s.axes.x, s.axes.y), " compare=", s.compare.target,
            " menu=", w()[:compare_target].selection[], " locked=", M.camera_locked[], " animating=", M.is_animating[],
            " anim=", w()[:anim_target].selection[], " sliders=", [(x.name, x.value) for x in s.sliders],
            "\n", " "^34, "flags sim/lay/plot=", (M.flags[:Simulation][], M.flags[:Layout][], M.flags[:Plot][]),
            " buttons=", (w()[:run_button].label[], w()[:layout_apply].label[], w()[:plot_button].label[]),
            " lockbtn=", w()[:lock_camera_button].label[], " play=", w()[:play_anim_button].label[],
            "\n", " "^34, "[", s.status.level, "] ", s.status.text, " | title=", isempty(s.plots) ? "-" : repr(s.plots[1].title),
            isempty(s.plots) ? "" : " xlims=$(s.plots[1].xlims) ylims=$(s.plots[1].ylims)"))
adv(; schemes = ["upwind", "lax_friedrichs", "lax_wendroff"]) =
    SimulationConfig(create_param_dict(:N => 40, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                       :sim_func_name => :solve_advection_1d),
                     create_method_dict(:fd => create_param_dict(), :fd2 => create_param_dict()), [:fd, :fd2];
                     varied = create_varied_dict(:scheme => schemes))
function busy!()   # animate over scheme, compare methods, lock the camera
    studio_set!(:compare_target => :methods)
    studio_press!(:lock_camera)
    studio_set!(:anim_target => :scheme)
    M.ui[:export][:animation_time] = 3.0
    w()[:play_anim_button].clicks[] += 1
    sleep(0.4)
end

println("== A: bind another setup into a busy window, then force_simulation (API) vs Run click")
for how in (:force, :click)
    reset_plotter!()
    launch_plotter(adv(); style = :lines)
    busy!()
    st("A busy adv")
    set_sim_config!(test_heat_2d())
    st("A after bind ($how), before run")
    how === :force ? force_simulation() : (w()[:run_button].clicks[] += 1)
    sleep(0.5)
    st("A after run ($how)")
end

println("== B: CSV of another setup with its own compare/camera/anim, loaded into a busy window")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
studio_set!(:r => 0.3)
studio_set!(:compare_target => :time)
studio_set!(:anim_target => :r)
studio_view!(xlims = (0.2, 0.4), ylims = (0.3, 0.6))
studio_press!(:lock_camera); studio_press!(:lock_camera)   # (person's own lock)
st("B heat to save")
PDEStudio.save_params_to_csv("heatbusy", sp, Dict("Save Type" => "probe"))
reset_plotter!()
launch_plotter(adv(); style = :heatmap)
busy!()
st("B busy adv")
r = set_sim_config!(joinpath(sp, "heatbusy.csv"))
println("   staged: ", r)
st("B after CSV load, before run")
w()[:run_button].clicks[] += 1
sleep(0.5)
st("B after CSV load + Run")

println("== C: preset of another setup, then Reset Simulation, while busy")
reset_plotter!()
launch_plotter(adv(); style = :lines)
cfg2 = deepcopy(M.active_config); cfg2.varied[:cfl] = [0.25, 0.5]
M.active_config = cfg2; save_sim_preset("pluscfl"); M.active_config = adv()
busy!()
set_sim_preset!("pluscfl"; mode = :replace)
st("C after preset (busy before)")
w()[:run_button].clicks[] += 1; sleep(0.3)
st("C after preset + Run")
busy!()
st("C busy again")
w()[:reset_sim_button].clicks[] += 1
st("C after Reset Simulation")
w()[:run_button].clicks[] += 1; sleep(0.3)
st("C after Reset + Run")
M.is_animating[] = false
