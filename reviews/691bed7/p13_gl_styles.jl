using PDEStudio, GLMakie
const P = @__DIR__
GLMakie.activate!()
set_save_path!(mktempdir())
fig = launch_plotter(test_heat_2d(); style = :heatmap_flat)
display(fig)
for st in (:lines_3d, :scatter_3d, :contour_3d, :contour_surface, :heatmap_surface, :volume_3d, :heatmap_flat)
    try
        studio_set!(:plot_style => st)
        f = studio_snapshot(joinpath(P, "p13_$(st).png"))
        println("OK  $st -> ", basename(f))
    catch e
        println("ERR $st -> ", first(sprint(showerror, e), 150))
    end
end
