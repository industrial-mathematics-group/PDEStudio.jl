using PDEStudio
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
studio_headless!()
set_save_path!(mktempdir())
println("=== 1. non-numeric sweep")
shared = create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind", :sim_func_name => :solve_advection_1d)
methods = create_method_dict(:fd => create_param_dict())
cfg = SimulationConfig(shared, methods, [:fd]; varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"]))
launch_plotter(cfg)
s = studio_state(); @show s.sliders
c = only(c for c in studio_controls() if c.name === :scheme); @show c
@try_ studio_set!(:scheme => "lax_wendroff")
@try_ studio_set!(:scheme => :lax_friedrichs)
@try_ studio_set!(:scheme => 2)
@try_ studio_set!(:scheme => "nope")
@show studio_state().plots[1].title
io = IOBuffer(); describe_studio(io); println(filter(l -> occursin("scheme", l), split(String(take!(io)), '\n')))
@try_ studio_set!(:compare_target => :scheme)
@show length(studio_state().plots) [p.title for p in studio_state().plots]
@try_ studio_set!(:compare_target => :time)
@show length(studio_state().plots) [p.title for p in studio_state().plots]
@try_ studio_zoom!(2; plot = 3)
studio_snapshot(joinpath(P, "p04_compare_time_zoom.png"))
@try_ studio_reset_view!()
@try_ studio_set!(:compare_target => :none)

println("=== 2. heat_2d: decoupled compare snapshots, contour, surface reset, volume, lines_3d")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
@try_ studio_set!(:compare_target => :methods, :compare_link => :decoupled)
studio_snapshot(joinpath(P, "p04_decoupled.png"))
studio_snapshot(joinpath(P, "p04_decoupled_p1.png"); plot = 1)
@try_ studio_set!(:compare_target => :none, :plot_style => :contour)
studio_snapshot(joinpath(P, "p04_contour.png"))
@try_ studio_set!(:plot_style => :heatmap_surface)
s0 = studio_state().plots[1]; @show s0.xlims s0.ylims s0.zlims s0.azimuth s0.elevation
@try_ studio_set!(:t => 0.03)
s1 = studio_state().plots[1]; @show s1.zlims
@try_ studio_zoom!(2); @try_ studio_rotate!(30)
@try_ studio_reset_view!()
s2 = studio_state().plots[1]; @show s2.xlims s2.ylims s2.zlims s2.azimuth s2.elevation
@try_ studio_set!(:t => 0.0)
s3 = studio_state().plots[1]; @show s3.zlims
println("--- volume")
@try_ studio_set!(:plot_style => :volume_3d)
s = studio_state(); @show s.style s.axes s.plots s.status
studio_snapshot(joinpath(P, "p04_volume.png"))
@try_ studio_rotate!(45, 10)
studio_snapshot(joinpath(P, "p04_volume_rot.png"))
studio_reset_view!()
println("--- lines_3d")
@try_ studio_set!(:plot_style => :lines_3d)
s = studio_state(); @show s.style s.axes s.status
studio_snapshot(joinpath(P, "p04_lines3d.png"))
println("--- particles style on grid data")
@try_ studio_set!(:plot_style => :particles_2d)
s = studio_state(); @show s.style s.axes s.status s.plots
studio_snapshot(joinpath(P, "p04_particles_on_grid.png"))

println("=== 3. particles")
reset_plotter!()
launch_plotter(test_particles_2d())
a = studio_state().plots[1]; @show a.xlims a.ylims
@try_ studio_zoom!(3)
@try_ studio_set!(:t => 1.0)
@show studio_state().plots[1].xlims
@try_ studio_reset_view!()
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
@try_ studio_set!(:plot_style => :particles_surface)
s = studio_state(); @show s.style s.plots[1].is_3d s.status
@try_ studio_rotate!(20, 10)
studio_snapshot(joinpath(P, "p04_particles_surface.png"))
@try_ studio_set!(:plot_style => :heatmap)
s = studio_state(); @show s.style s.status
