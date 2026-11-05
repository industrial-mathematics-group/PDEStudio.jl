# Probe: style values the editor accepts but the renderer can't draw (window on the Xvfb display).
#   DISPLAY=:99 julia -t 4 --project=test <scratch>/probe_style_values.jl
include(joinpath(@__DIR__, "probe_setup.jl"))
using Logging
w() = manager.widgets
function errors_during(f)
    logger = Test.TestLogger(min_level = Logging.Warn)
    err = nothing
    with_logger(logger) do
        try f() catch e; err = e end
    end
    msgs = [string(r.level, ": ", first(split(string(r.message), '\n'))) *
            (haskey(r.kwargs, :exception) ? " [" * sprint(showerror, first(r.kwargs[:exception])) * "]" : "")
            for r in logger.logs if r.level >= Logging.Warn]
    return msgs, err
end
@testset "Degenerate style values" begin
    click_menu!(w()[:plot_style], :lines_1d)
    click_menu!(w()[:x_axis], :x); click_menu!(w()[:y_axis], :none); click_menu!(w()[:z_axis], :none)
    click_button!(:layout_apply)
    for (key, val, style) in ((:colors, Any[], :lines_1d), (:color_range, Any[1.0], :heatmap_flat), (:levels, 1, :contour_f))
        println("editor accepts $key = $(repr(val)): ", PDEStudio._valid_ui_value(key, val))
        old = manager.ui[:plot_style][key]
        manager.ui[:plot_style][key] = val
        if style !== :lines_1d
            click_menu!(w()[:plot_style], style)
            click_menu!(w()[:x_axis], :x); click_menu!(w()[:y_axis], :t); click_menu!(w()[:z_axis], :none)
        end
        msgs, err = errors_during(() -> click_button!(:layout_apply))
        println("  $key = $(repr(val)) with $style: thrown = ", isnothing(err) ? "nothing" : sprint(showerror, err))
        foreach(m -> println("    ", first(m, 200)), unique(msgs))
        @test isnothing(err) && isempty(filter(m -> startswith(m, "Error"), msgs))
        manager.ui[:plot_style][key] = old
    end
end
reset_plotter!()
