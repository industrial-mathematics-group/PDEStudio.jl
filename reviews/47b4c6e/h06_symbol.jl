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
launch_plotter(test_heat_2d(); style = :heatmap)
@try_ studio_set!(:plot_style => :lines_2d)
@show studio_state().style studio_state().status
@try_ studio_option!(:plot_style, :line_direction, :vertical)
@show studio_state().status
@try_ studio_option!(:plot_style, :line_direction, "horizontal")
@show studio_state().status
@try_ studio_option!(:plot_style, :line_direction, :horizontal)
@show studio_state().status
studio_snapshot(joinpath(P, "h06_lines2d.png"))
