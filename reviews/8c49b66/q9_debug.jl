include(joinpath(@__DIR__, "fixtures.jl"))
const M = PDEStudio.manager
set_stat_preset!("hyperbolic")
reset_plotter!(); launch_plotter(adv_config())
println("t enabled: ", PDEStudio._slider_enabled(:t), " range len ", length(M.widgets[:t].range[]), " style ", studio_state().style)
@probe "heatmap + t" (r = studio_set!(:plot_style => :heatmap, :t => 1.0); (r.status, studio_state().axes))
println("after: axes ", studio_state().axes, " t range len ", length(M.widgets[:t].range[]), " flags ", [k => M.flags[k][] for k in (:Simulation, :Layout, :Plot)])
println("status: ", studio_state().status.text)
# what did the call do? try again
reset_plotter!(); launch_plotter(adv_config())
studio_set!(:plot_style => :heatmap)
println("heatmap alone: axes ", studio_state().axes, " t len ", length(M.widgets[:t].range[]))
# q7 sequence
reset_plotter!(); launch_plotter(adv_config()); studio_set!(:cfl => 1.0, :compare_target => :cfl)
reset_plotter!(); launch_plotter(adv_config())
println("after reset: compare ", studio_state().compare.target, " sliders ", [x.name for x in studio_state().sliders])
@probe "D after C" (r = studio_set!(:t => 1.0, :plot_style => :heatmap, :x_axis => :x, :y_axis => :t); (r.status, studio_state().axes, studio_state().compare.target))
