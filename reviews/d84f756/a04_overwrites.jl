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

mark("A: a look preset whose tick format can't be drawn, applied from the Files tab")
studio_option!(:x_axis_1d, :tick_format, "{:nope"); @show stat()
save_plot_preset(:bad)
studio_option!(:x_axis_1d, :tick_format, "default"); @show stat()
m.preset_kind = :visual
m.editor_row_keys = Any[:bad]
@try_ PDEStudio._preset_row_action!(1, :a)
@show stat() m.ui[:x_axis_1d][:tick_format]
studio_option!(:x_axis_1d, :tick_format, "default"); @show stat()

mark("B: switch to a particle style (mode switch) while the tick format is broken")
studio_option!(:x_axis_1d, :tick_format, "{:nope"); @show stat()
@try_ studio_set!(:plot_style => :particles_1d)
@show stat() studio_state().style
@try_ studio_set!(:plot_style => :lines_1d)
@show stat() studio_state().style
studio_option!(:x_axis_1d, :tick_format, "default"); @show stat()
mark("END")
