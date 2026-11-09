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
st() = (s = studio_state(); (locked = s.camera_locked, lims = [(p.xlims, p.ylims) for p in s.plots], api = PDEStudio._api_view_locked(), status = s.status))
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
println("--- A: zoom, then lines -> heatmap_flat with y = t (stale view?)")
studio_zoom!(4; center = (0.3, 0.5))
@try_ studio_set!(:plot_style => :heatmap_flat, :y_axis => :t)
@show st()
studio_snapshot(joinpath(P, "h02_A_heatmap_after_zoom.png"))
studio_reset_view!(); @show st()
studio_snapshot(joinpath(P, "h02_A_heatmap_reset.png"))
studio_set!(:plot_style => :lines_1d, :y_axis => :none); studio_reset_view!()
println("--- B: option types")
@try_ studio_option!(:labels, :title, 5)
@try_ studio_option!(:y_axis_1d, :log_scale, "yes")
@try_ studio_option!(:y_axis_1d, :padding, "a")
@try_ studio_option!(:plot_style, :line_width, :thick)
@try_ studio_option!(:plot_style, :line_width, 2)      # Int into a Float option: accepted
@show PDEStudio.manager.ui[:plot_style][:line_width]
@try_ studio_option!(:plot_style, :line_width, 2.5)    # rejected now?
@try_ studio_option!(:plot_style, :line_width, 3.0)
@try_ studio_option!(:y_axis_1d, :padding, 0)
@try_ studio_option!(:y_axis_1d, :padding, 0.05)
@try_ studio_option!(:axis_general, :font_size, 20.5)
@try_ studio_option!(:export, :dpi, 150.0)
@try_ studio_option!(:export, :animation_FPS, 29.97)
@try_ studio_option!(:plot_style, :line_direction, "vertical")
@show typeof(PDEStudio.manager.ui[:plot_style][:line_direction])
@try_ studio_option!(:plot_style, :line_direction, :horizontal)
@try_ studio_option!(:plot_style, :colors, ((:red, 0.5), :blue))
@try_ studio_option!(:plot_style, :colors, [(:black, 0.8), :blue, :green, :orange, :purple, :yellow])
@try_ studio_option!(:plot_style, :color_range, (0, 1))
@show PDEStudio.manager.ui[:plot_style][:color_range]
@try_ studio_option!(:plot_style, :color_range, [])
@try_ studio_option!(:x_axis_1d, :lims, (0.2, 0.8))
@show studio_state().plots[1].xlims
@try_ studio_option!(:x_axis_1d, :lims, [])
@try_ studio_option!(:hud, :points, [(0.2, 0.0), (0.8, 0.5)])
@try_ studio_option!(:hud, :points, ((0.2, 0.0), (0.8, 0.5)))
@try_ studio_option!(:hud, :visible, true)
@show studio_state().status
studio_snapshot(joinpath(P, "h02_hud.png"))
@try_ studio_option!(:hud, :visible, false)
@try_ studio_option!(:plot_style, :reference, [:exact])
@show studio_state().status
@try_ studio_option!(:plot_style, :reference, :exact)
@try_ studio_option!(:plot_style, :reference, [])
@try_ studio_option!(:plot_style, :markers, (:circle, :rect))
@try_ studio_option!(:plot_style, :line_styles, [:solid, (:dash, :dense)])
@try_ studio_option!(:labels, :title, "My title")
@try_ studio_option!(:labels, :title, "default")
@try_ studio_option!(:export, :save_formats, ("png", "pdf"))
@try_ studio_option!(:export, :save_formats, ["png"])
@try_ studio_option!(:plot_style, :levels, 10)
@try_ studio_option!(:plot_style, :method_index, 2)
@try_ studio_option!(:plot_style, :method_index, 1)
println("--- C: failed redraw status")
@try_ studio_option!(:plot_style, :line_styles, [:nope])
@show studio_state().status
@try_ studio_option!(:plot_style, :line_styles, [:solid, :dash, :dot, (:dash, :dense), (:dot, :dense)])
@show studio_state().status
@try_ studio_option!(:x_axis_1d, :tick_format, "{:nope")
@show studio_state().status
@try_ studio_option!(:x_axis_1d, :tick_format, "default")
@show studio_state().status
@try_ studio_set!(:t => 0.3)
@show studio_state().status
println("--- D: camera validation")
@try_ studio_zoom!(2; plot = true)
@try_ studio_view!(plot = false, xlims = (0, 1))
@try_ studio_zoom!(2; dims = :z)
@show st()
@try_ studio_view!(azimuth = NaN)
@try_ studio_view!(elevation = Inf)
@try_ studio_rotate!(NaN)
@try_ studio_zoom!(2; center = (NaN, 0.0))
@try_ studio_pan!(NaN)
@show st()
@try_ studio_pan!(Inf)
@show st()
studio_reset_view!()
@try_ studio_zoom!(2; dims = (:x, :z))
@show st()
studio_reset_view!()
println("--- E: non-PNG")
@try_ studio_snapshot(joinpath(P, "h02_x.jpg"))
@try_ studio_snapshot(joinpath(P, "h02_x.PNG"))
@try_ studio_snapshot(joinpath(P, "h02_noext"))
println("--- F: default names")
fs = [studio_snapshot() for _ in 1:3]; @show fs length(unique(fs))
