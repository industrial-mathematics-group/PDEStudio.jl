using PDEStudio
const P = @__DIR__
macro try_(ex)
    s = string(ex)
    quote
        try
            r = $(esc(ex)); println("OK   ", $s, " => ", r)
        catch e
            println("ERR  ", $s, " => ", typeof(e), ": ", first(sprint(showerror, e), 300))
        end
    end
end
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
s0 = studio_state(); auto = s0.plots[1]
@show auto.xlims auto.ylims s0.style s0.axes
# docs example
@try_ studio_set!(:t => 1.0)
@try_ studio_zoom!(4; center = (0.5, 0.0))
studio_snapshot(joinpath(P, "p02_doc_zoom.png"))
@try_ (d = studio_data(1); maximum(abs, d.methods[:upwind].u .- d.methods[:lax_wendroff].u))
@try_ studio_reset_view!()
@show studio_state().plots[1].xlims studio_state().plots[1].ylims
println("--- A: zoom then change the x axis variable (camera stays locked)")
@try_ studio_zoom!(4; center = (0.3, 0.5))
@try_ studio_set!(:x_axis => :t)
s = studio_state(); @show s.axes.x s.plots[1].xlabel s.plots[1].xlims s.plots[1].ylims s.camera_locked
studio_snapshot(joinpath(P, "p02_xaxis_t_locked.png"))
@try_ studio_reset_view!()
s = studio_state(); @show s.plots[1].xlims s.plots[1].ylims
studio_snapshot(joinpath(P, "p02_xaxis_t_reset.png"))
@try_ studio_set!(:x_axis => :x)
println("--- B: invalid inputs")
@try_ studio_view!(xlims = (NaN, 1))
@try_ studio_view!(xlims = (0, Inf))
@try_ studio_view!(xlims = (0, 1, 2))
@try_ studio_view!(xlims = (1, 1))
@try_ studio_view!(xlims = ("a", "b"))
@try_ studio_view!(plot = 0, xlims = (0, 1))
@try_ studio_view!(plot = 1.0, xlims = (0, 1))
@try_ studio_view!(plot = true, xlims = (0, 1))
@try_ studio_view!(plot = :first, xlims = (0, 1))
@try_ studio_zoom!(NaN)
@try_ studio_zoom!(-1)
@try_ studio_zoom!(1e300)
@try_ studio_zoom!(2; center = (0.5,))
@try_ studio_zoom!(2; center = 0.5)
@try_ studio_zoom!(2; dims = :q)
@try_ studio_zoom!(2; dims = :z)
@try_ studio_pan!(Inf)
@try_ studio_pan!(1e308)
@try_ studio_pan!(0, 0, 1)
@try_ studio_rotate!(NaN)
@try_ studio_set!(:t => NaN)
@try_ studio_set!(:t => "1.0")
@try_ studio_set!(:cfl => 2.0)
@try_ studio_set!(:x_axis => "Time (T)")
@try_ studio_set!(:x_axis => "x")
@try_ studio_set!(:plot_width => 600.0)
@try_ studio_set!(:methods => Symbol[])
@try_ studio_set!(:methods => :exact)
@try_ studio_set!("t" => 0.5)
@try_ studio_set!(:legend_base => :top)
@try_ studio_snapshot(; plot = 2)
@try_ studio_snapshot(; px_per_unit = 0)
@try_ studio_snapshot(joinpath(P, "nonexistent_dir", "x.png"))
@try_ studio_snapshot(joinpath(P, "p02_x.jpg"))
@try_ studio_options(:export)
@try_ studio_option!(:labels, :title, 5)
@try_ studio_option!(:labels, :title, "Advection")
@try_ studio_state().plots[1].title
@try_ studio_option!(:x_axis_1d, :lims, [0.2, 0.4])
@try_ studio_state().plots[1].xlims
@try_ studio_option!(:x_axis_1d, :lims, Float64[])
@try_ studio_state().plots[1].xlims
@try_ studio_data(0)
println("--- C: state truthful")
s = studio_state()
@show s.status s.camera_locked s.pending s.sliders
@show studio_controls()[end-3:end]
println("--- D: log scale")
@try_ studio_option!(:y_axis_1d, :log_scale, true)
@try_ studio_state().plots[1].ylims
@try_ studio_zoom!(2)
studio_snapshot(joinpath(P, "p02_log_zoom.png"))
@try_ studio_set!(:t => 0.5)
@try_ studio_state().plots[1].ylims
@try_ studio_reset_view!()
@try_ studio_state().plots[1].ylims
@try_ studio_option!(:y_axis_1d, :log_scale, false)
println("--- E: lock button interplay")
@try_ studio_zoom!(2)
@try_ studio_press!(:lock_camera)    # unlock via button
s = studio_state(); @show s.camera_locked s.plots[1].xlims
@try_ studio_set!(:t => 0.25)
s = studio_state(); @show s.camera_locked s.plots[1].xlims
@try_ studio_press!(:lock_camera)    # lock
@try_ studio_set!(:t => 0.75)
s = studio_state(); @show s.camera_locked s.plots[1].xlims
@try_ studio_reset_view!()
println("--- F: two step kinds in one call")
@try_ studio_set!(:methods => [:exact, :upwind], :plot_style => :scatter_1d)
s = studio_state(); @show s.style s.drawn_methods s.pending
@try_ studio_set!(:plot_style => :lines_1d, :x_axis => :t)
s = studio_state(); @show s.style s.axes s.pending
