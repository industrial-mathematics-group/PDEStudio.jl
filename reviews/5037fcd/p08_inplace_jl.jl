# (1) relaunch with the same config object after adding a swept parameter in place;
# (2) a .jl config file loaded into an open window after another configuration (headless)
using PDEStudio
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
st(tag) = (s = studio_state(); println(rpad(tag, 30), "axes=", (s.axes.x, s.axes.y), " sliders=", [(x.name, x.value) for x in s.sliders],
            " param_map=", M.param_map, " title=", isempty(s.plots) ? "-" : s.plots[1].title))
cfg = test_advection_1d()
println("adv varied: ", collect(keys(cfg.varied)), " shared keys: ", collect(keys(cfg.shared)))
launch_plotter(cfg; style = :heatmap)
k1 = first(sort!(collect(keys(cfg.varied))))
studio_set!(k1 => last(cfg.varied[k1]))
st("adv, last $k1")
println("slider_cache: ", M.slider_cache)
# add a swept parameter in place that sorts before the existing one (takes slider slot 1)
cfg.varied[:N] = [50, 100]
reset_plotter!()
launch_plotter(cfg; style = :heatmap)
st("same object, +N sweep")
println("_view_setup now: ", PDEStudio._view_setup(cfg))

println("== .jl config loaded into an open window")
reset_plotter!()
launch_plotter(test_advection_1d(); style = :heatmap)          # x, t heatmap
st("adv heatmap")
dir = mktempdir(); f = joinpath(dir, "heatcfg.jl")
write(f, "test_heat_2d()\n")
set_sim_config!(f)
force_simulation()
st("heat via .jl load")
