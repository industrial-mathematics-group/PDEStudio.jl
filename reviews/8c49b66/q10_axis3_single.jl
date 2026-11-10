include(joinpath(@__DIR__, "fixtures.jl"))
const M = PDEStudio.manager
using PDEStudio.Makie: Axis3
out = joinpath(@__DIR__, "out")
reset_plotter!(); launch_plotter(adv_config(); style = :lines)
studio_set!(:plot_style => :heatmap_surface, :x_axis => :x, :y_axis => :tag)
for w in (400, 300, 250)
    studio_set!(:plot_width => w)
    println("w=$w drawn: ", repr([b.title[] for b in M.master_fig.content if b isa Axis3]), " api: ", [p.title for p in studio_state().plots])
end
studio_snapshot(joinpath(out, "q10_axis3_single250.png"); area = :window)
reset_plotter!()
