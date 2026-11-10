using PDEStudio
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
studio_headless!(); set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
m = PDEStudio.manager
@try_ studio_option!(:plot_style, :colors, (:red, 0.5))
@show m.ui[:plot_style][:colors] studio_state().status
studio_snapshot(joinpath(@__DIR__, "h08_colors_tuple.png"))
println("--- the UI tab with the same text")
PDEStudio._apply_editor_input!(:ui, :plot_style, :colors, m.ui[:plot_style], "(:red, 0.5)", nothing)
@show m.ui[:plot_style][:colors] studio_state().status
