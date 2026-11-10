# Status line with the registered PDEStudioCore 0.4.4 (run_all_simulations returns nothing)
using PDEStudio, Pkg
println("PDEStudioCore ", pkgversion(PDEStudioCore), ", RunSummary defined: ", isdefined(PDEStudioCore, :RunSummary))
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_heat_2d(); style = :heatmap)
s = studio_state(); println("[", s.status.level, "] ", s.status.text)
PDEStudio.manager.widgets[:run_button].clicks[] += 1
s = studio_state(); println("[", s.status.level, "] ", s.status.text)
