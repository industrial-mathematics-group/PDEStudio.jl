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
const m = PDEStudio.manager
mark(s) = (println("#### ", s); println(stderr, "#### ", s); flush(stdout); flush(stderr))
stat() = (studio_state().status, m.render_failures)
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())

mark("A: broken tick_format, zoom, then studio_press! that releases the view")
studio_zoom!(4; center = (0.3, 0.5)); @show stat()
studio_option!(:x_axis_1d, :tick_format, "{:nope"); @show stat()
@try_ studio_set!(:x_axis => :t; apply = false)
@try_ studio_press!(:update_plot)
@show stat() studio_state().camera_locked

mark("B: same with studio_set! (apply = true), which keeps a reported failure")
studio_option!(:x_axis_1d, :tick_format, "default"); studio_set!(:x_axis => :x); studio_zoom!(4; center = (0.3, 0.5)); studio_option!(:x_axis_1d, :tick_format, "{:nope"); @show stat()
@try_ studio_set!(:x_axis => :t)
@show stat()

mark("C: a plain Update Plot press with a broken option (no release)")
@try_ studio_press!(:update_plot); @show stat()

mark("D: studio_reset_view! with a broken option")
studio_option!(:x_axis_1d, :tick_format, "default"); studio_zoom!(2); studio_option!(:x_axis_1d, :tick_format, "{:nope")
@try_ studio_reset_view!(); @show stat()

mark("E: toggle path (_editor_row_action! :toggle) while broken")
r = PDEStudio._editor_row_action!(:ui, :x_axis_1d, :grid_visibility, m.ui[:x_axis_1d], nothing); @show stat()

mark("F: UI tab reset (default) of a different key while broken")
PDEStudio._apply_editor_input!(:ui, :x_axis_1d, :padding, m.ui[:x_axis_1d], "default", nothing); @show stat()

mark("G: repair through the tab")
PDEStudio._apply_editor_input!(:ui, :x_axis_1d, :tick_format, m.ui[:x_axis_1d], "default", nothing); @show stat()
studio_set!(:x_axis => :x); studio_reset_view!()

mark("H: Drawing failed (plot step) status text")
studio_option!(:plot_style, :line_styles, [:nope]); @show stat()
studio_option!(:plot_style, :line_styles, PDEStudio.MASTER_UI_DICT[:plot_style][:line_styles]); @show stat()

mark("I: colour tuple directly for :colors")
@try_ studio_option!(:plot_style, :colors, (:red, 0.5)); @show m.ui[:plot_style][:colors] stat()
studio_snapshot(joinpath(P, "a02_colors_tuple.png"))
PDEStudio._apply_editor_input!(:ui, :plot_style, :colors, m.ui[:plot_style], "(:red, 0.5)", nothing)
@show m.ui[:plot_style][:colors] stat()
studio_snapshot(joinpath(P, "a02_colors_tuple_tab.png"))
@try_ studio_option!(:plot_style, :colors, :red); @show m.ui[:plot_style][:colors] stat()
studio_option!(:plot_style, :colors, PDEStudio.MASTER_UI_DICT[:plot_style][:colors])
@try_ studio_option!(:hud, :color, (:blue, 0.5)); @show m.ui[:hud][:color]
mark("Z: a camera call while the tick format is broken")
studio_reset_view!(); studio_option!(:x_axis_1d, :tick_format, "{:nope")
@try_ studio_zoom!(2)
@show stat() studio_state().camera_locked PDEStudio._api_view_locked()
mark("END")
