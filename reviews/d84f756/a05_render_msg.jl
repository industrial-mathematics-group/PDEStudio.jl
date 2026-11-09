using PDEStudio
const P = @__DIR__
macro try_(ex)
    s = string(ex)
    quote
        try
            r = $(esc(ex)); println("OK   ", $s, " => ", r)
        catch e
            println("ERR  ", $s, " => ", typeof(e), ": ", first(sprint(showerror, e), 600))
        end
    end
end
const m = PDEStudio.manager
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
println("--- an option that only fails when CairoMakie draws (no backend switch at all)")
@try_ studio_option!(:plot_style, :line_styles, [:nope])
@show studio_state().status m.render_failures
@try_ studio_snapshot(joinpath(P, "a05_nope.png"))
@try_ studio_snapshot(joinpath(P, "a05_nope_window.png"); area = :window)
studio_option!(:plot_style, :line_styles, PDEStudio.MASTER_UI_DICT[:plot_style][:line_styles])
@try_ studio_snapshot(joinpath(P, "a05_ok.png"))
println("--- HUD with a String colour list / marker")
@try_ studio_option!(:plot_style, :markers, [:nope])
@try_ studio_set!(:plot_style => :scatter_1d)
@show studio_state().status
@try_ studio_snapshot(joinpath(P, "a05_marker.png"))
println("END")
