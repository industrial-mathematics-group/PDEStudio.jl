using PDEStudio, GLMakie
const P = @__DIR__
macro try_(ex)
    s = string(ex)
    quote
        try
            r = $(esc(ex)); println("OK   ", $s, " => ", r)
        catch e
            println("ERR  ", $s, " => ", typeof(e), ": ", first(sprint(showerror, e), 400))
        end
    end
end
GLMakie.activate!()
set_save_path!(mktempdir())
fig = launch_plotter(test_heat_2d(); style = :heatmap_surface)
display(fig)
s = studio_state(); @show s.backend s.window_size
p = s.plots[1]; @show p.xlims p.ylims p.zlims p.azimuth p.elevation
@try_ studio_set!(:t => 0.03)
p = studio_state().plots[1]; @show p.zlims
@try_ studio_zoom!(2)
@try_ studio_rotate!(40, 5)
@try_ studio_snapshot(joinpath(P, "p07_gl_surface.png"))
@show Makie.current_backend()
# what the GLMakie window itself shows
save(joinpath(P, "p07_gl_window_native.png"), fig)
@try_ studio_reset_view!()
p = studio_state().plots[1]; @show p.xlims p.ylims p.zlims p.azimuth p.elevation
@try_ studio_set!(:t => 0.0)
p = studio_state().plots[1]; @show p.zlims
println("--- volume")
@try_ studio_set!(:plot_style => :volume_3d)
@show studio_state().axes
@try_ studio_snapshot(joinpath(P, "p07_gl_volume_snapshot.png"))
save(joinpath(P, "p07_gl_volume_native.png"), fig)
println("--- px_per_unit with GL")
@try_ studio_set!(:plot_style => :heatmap_flat)
f1 = studio_snapshot(joinpath(P, "p07_gl_1x.png")); f2 = studio_snapshot(joinpath(P, "p07_gl_2x.png"); px_per_unit = 2)
@show size(Makie.FileIO.load(f1)) size(Makie.FileIO.load(f2))
fw = studio_snapshot(joinpath(P, "p07_gl_window.png"); area = :window); @show size(Makie.FileIO.load(fw)) studio_state().window_size
println("--- presets/CSV after API use")
@try_ studio_zoom!(2)
@try_ save_plot_preset("agentview")
@try_ studio_reset_view!()
@show PDEStudio.manager.camera_locked[] PDEStudio.manager.camera_cache
println("--- close with reset_plotter!")
reset_plotter!()
@try_ studio_state()
@try_ studio_zoom!(2)
@try_ studio_snapshot()
@try_ studio_reset_view!()
@try_ studio_options()
@try_ studio_options(:labels)
@try_ studio_option!(:labels, :title, "x")
@try_ studio_data(1)
