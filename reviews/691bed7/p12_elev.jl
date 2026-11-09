using PDEStudio
const P = @__DIR__
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_heat_2d(); style = :heatmap_surface)
@show studio_view!(azimuth = 45, elevation = 90)
studio_snapshot(joinpath(P, "p12_elev90.png"))
@show studio_view!(elevation = -90)
studio_snapshot(joinpath(P, "p12_elevm90.png"))
for i in 1:4; studio_rotate!(120); end
@show studio_state().plots[1].azimuth
