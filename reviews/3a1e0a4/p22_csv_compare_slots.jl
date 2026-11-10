# (1) A CSV saved while comparing by time (heat, x-y heatmap) loaded into an open window of another setup:
#     which axes come back? Variants: busy window, plain window, fresh window, no comparison.
# (2) Two-step sweep edit with a stale slot position that maps to a non-first value.
# Usage: julia --project=<env> p22_csv_compare_slots.jl
using PDEStudio
studio_headless!()
sp = mktempdir(); set_save_path!(sp)
const M = PDEStudio.manager
w() = M.widgets
st(tag) = (s = studio_state(); println(rpad(tag, 36), "axes=", (s.axes.x, s.axes.y), " compare=", s.compare.target,
            " locked=", M.camera_locked[], " anim=", w()[:anim_target].selection[], " sliders=", [(x.name, x.value) for x in s.sliders],
            " title=", isempty(s.plots) ? "-" : repr(s.plots[1].title)))
adv() = SimulationConfig(create_param_dict(:N => 40, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                           :sim_func_name => :solve_advection_1d),
                         create_method_dict(:fd => create_param_dict(), :fd2 => create_param_dict()), [:fd, :fd2];
                         varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))

for (name, compare) in (("heatcmp", :time), ("heatplain", :none))
    reset_plotter!()
    launch_plotter(test_heat_2d(); style = :heatmap)
    studio_set!(:r => 0.3)
    studio_set!(:compare_target => compare)
    st("save $name")
    PDEStudio.save_params_to_csv(name, sp, Dict("Save Type" => "probe"))
end
for name in ("heatcmp", "heatplain"), into in (:adv_heatmap, :adv_lines, :fresh)
    reset_plotter!()
    if into === :fresh
        launch_plotter(; style = :heatmap)
    else
        launch_plotter(adv(); style = into === :adv_heatmap ? :heatmap : :lines)
    end
    set_sim_config!(joinpath(sp, "$name.csv"))
    w()[:run_button].clicks[] += 1
    st("$name into $into")
end

println("== two-step sweep edit (N, T) -> remove T -> add scheme")
reset_plotter!()
c = adv(); c.varied = create_varied_dict(:N => [40, 50], :T => [1.0, 10.0])
launch_plotter(c; style = :lines)
studio_set!(:T => 10.0)
println("start ", [(x.name, x.value) for x in studio_state().sliders], " cache ", filter(p -> startswith(string(p[1]), "param"), M.slider_cache))
delete!(M.active_config.varied, :T); PDEStudio._after_raw_change!(:sweep, "T removed")
w()[:run_button].clicks[] += 1
println("T removed + Run ", [(x.name, x.value) for x in studio_state().sliders], " cache ", filter(p -> startswith(string(p[1]), "param"), M.slider_cache))
M.active_config.varied[:scheme] = ["upwind", "lax_friedrichs", "lax_wendroff"]; PDEStudio._after_raw_change!(:sweep, "scheme added")
w()[:run_button].clicks[] += 1
println("scheme added + Run ", [(x.name, x.value) for x in studio_state().sliders], "  (fresh window: upwind)")
println("== the same in one edit (T replaced by scheme)")
reset_plotter!()
c = adv(); c.varied = create_varied_dict(:N => [40, 50], :T => [1.0, 10.0])
launch_plotter(c; style = :lines)
studio_set!(:T => 10.0)
delete!(M.active_config.varied, :T); M.active_config.varied[:scheme] = ["upwind", "lax_friedrichs", "lax_wendroff"]
PDEStudio._after_raw_change!(:sweep, "T -> scheme")
w()[:run_button].clicks[] += 1
println("one edit + Run ", [(x.name, x.value) for x in studio_state().sliders])
