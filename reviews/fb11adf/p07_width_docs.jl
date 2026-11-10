# Title fitted to an unapplied plot width; text width vs fallback; the agents.md example output (headless)
using PDEStudio; using PDEStudio.Makie: Axis
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
println("text_bb width: ", PDEStudio._text_width("Time (T) = 0.000", :bold, 26), "  fallback estimate: ", 0.6 * 26 * 16)

# docs/src/agents.md example, verbatim start
launch_plotter(test_heat_2d(); style = :heatmap)
describe_studio()

ax() = only(b for b in M.master_fig.content if b isa Axis)
cfg = SimulationConfig(create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                         :sim_func_name => :solve_advection_1d),
                       create_method_dict(:fd => create_param_dict()), [:fd];
                       varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"], :cfl => [0.25, 0.5]))
reset_plotter!()
launch_plotter(cfg)
println("applied width 500: ", repr(ax().title[]), " axis width ", ax().scene.viewport[].widths[1])
studio_set!(:plot_width => 150; apply = false)       # typed into the box, Apply Layout not pressed
studio_set!(:scheme => "lax_wendroff")                 # a slider move
println("pending width 150, after a slider move: ", repr(ax().title[]), " axis width ", ax().scene.viewport[].widths[1])
studio_snapshot(joinpath(@__DIR__, "img", "pending_width.png"); area = :window)
