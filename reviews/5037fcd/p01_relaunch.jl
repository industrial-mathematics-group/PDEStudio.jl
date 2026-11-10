# Relaunch scenarios (headless). Usage: julia --project=env p01_relaunch.jl
using PDEStudio
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
st(tag) = (s = studio_state(); println(rpad(tag, 28), "style=", s.style, " axes=", (s.axes.x, s.axes.y), " sliders=",
            [(x.name, x.value) for x in s.sliders], " compare=", s.compare.target, " methods=", M.methods[],
            " anim=", get(M.exploration_cache, :anim_target, :-), " filter=", M.method_filter, " tab=", M.active_tab[],
            "\n", " "^28, "status=", s.status.text, "\n", " "^28, "title=", isempty(s.plots) ? "-" : s.plots[1].title))
adv(; methods = (:fd,), schemes = ["upwind", "lax_friedrichs", "lax_wendroff"], cfl = 0.5) =
    SimulationConfig(create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => cfl, :scheme => "upwind",
                                       :sim_func_name => :solve_advection_1d),
                     create_method_dict((m => create_param_dict() for m in methods)...), collect(methods);
                     varied = create_varied_dict(:scheme => schemes))

println("== A: claim (adv sweep -> heat 2d)")
launch_plotter(adv())
studio_set!(:compare_target => :time); studio_set!(:compare_target => :none)
studio_set!(:scheme => "lax_wendroff")
st("A adv end")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
st("A heat launch")

println("== B: same setup again (keeps view?)")
studio_set!(:r => 0.3)
st("B heat r=0.3")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
st("B heat relaunch")

println("== C: same solver + sweep keys, other methods")
reset_plotter!()
launch_plotter(adv())
st("C adv(fd)")
reset_plotter!()
try
    launch_plotter(adv(methods = (:fd_b, :fd_a)))
    st("C adv(fd_b, fd_a)")
catch e
    println("C ERROR: ", sprint(showerror, e))
end

println("== D: same setup, other sweep values (slider position outside)")
reset_plotter!()
launch_plotter(adv(schemes = ["upwind", "lax_wendroff"]))
studio_set!(:scheme => "lax_wendroff")
st("D 2 schemes, at lax_wendroff")
reset_plotter!()
launch_plotter(adv(schemes = ["upwind", "lax_friedrichs"]))
st("D other 2 schemes")

println("== E: documented step-by-step (launch_plotter(); set_sim_config!; force_simulation)")
reset_plotter!()
launch_plotter(adv())
studio_set!(:compare_target => :time); studio_set!(:compare_target => :none)
studio_set!(:scheme => "lax_wendroff")
reset_plotter!()
launch_plotter(; style = :heatmap)
set_sim_config!(test_heat_2d()); force_simulation()
st("E heat via set_sim_config!")

println("== F: launch_plotter() (nothing) then launch_plotter(heat) after adv")
reset_plotter!()
launch_plotter(adv()); studio_set!(:scheme => "lax_wendroff")
reset_plotter!(); launch_plotter()
st("F empty after adv")
reset_plotter!(); launch_plotter(test_heat_2d(); style = :heatmap)
st("F heat")

println("== G: heat -> particles (mode switch)")
reset_plotter!(); launch_plotter(test_particles_2d())
st("G particles")
reset_plotter!(); launch_plotter(test_heat_2d(); style = :heatmap)
st("G heat after particles")
