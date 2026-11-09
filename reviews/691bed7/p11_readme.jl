using PDEStudio
const P = @__DIR__
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_heat_2d(); style = :heatmap)
r = studio_set!(:t => 0.02, :plot_style => :heatmap_surface)
@show r
s = studio_state(); @show s.style [(x.name, x.value) for x in s.sliders] s.plots[1].title
studio_rotate!(30, 10); studio_zoom!(2)
studio_snapshot(joinpath(P, "p11_readme.png"))
d = studio_data(1); @show keys(d.methods) d.variables
m = first(values(d.methods)); @show size(m.x) size(m.y) size(m.u) typeof(m.z)
