# Does a slider move that changes the number of title lines resize the figure (tall plots)? (headless)
using PDEStudio; using PDEStudio.Makie: Axis
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
cfg = SimulationConfig(create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                         :sim_func_name => :solve_advection_1d),
                       create_method_dict(:fd => create_param_dict()), [:fd];
                       varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"], :cfl => [0.25, 0.5]))
launch_plotter(cfg)
studio_set!(:plot_width => 380, :plot_height => 1000)
ax() = only(b for b in M.master_fig.content if b isa Axis)
for s in ("upwind", "lax_friedrichs", "upwind")
    studio_set!(:scheme => s)
    println(rpad(s, 16), "figure ", Tuple(M.master_fig.scene.viewport[].widths), " axis origin ", Tuple(round.(Int, ax().scene.viewport[].origin)),
            " lines ", count(==('\n'), ax().title[]) + 1)
end
