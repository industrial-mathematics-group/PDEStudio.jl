# f3ed3a2: fine_labels in the real window (both axes, scale_offset and tick_format, log scale untouched)
using Test, PDEStudio, GLMakie, StaticArrays
const P = PDEStudio
import PDEStudio: manager
PDEStudioCore.set_target_module!(@__MODULE__)
OUT = joinpath(@__DIR__, "fine_png"); mkpath(OUT)
# static 1-D data: x = 1 + 1e-9 k (tiny x extent), u = 1 + 1e-9 sin
function tiny(params::ParamDict)
    x = collect(1.0 .+ 1e-9 .* (0:49)); u = [SVector(1.0 + 1e-9 * sin(2π * k / 49)) for k in 0:49]
    create_sim_data(x, u, params; dims = :x)
end
set_save_path!(mktempdir()); reset_plotter!(); set_mode!(:eulerian)
fig = launch_plotter(); display(fig)
set_sim_config!(SimulationConfig(create_param_dict(:N => 50, :sim_func_name => :tiny), create_method_dict(:num => create_param_dict()), [:num]))
manager.widgets[:run_button].clicks[] += 1; yield()
P._choose_plot_style!(:lines_1d); manager.widgets[:layout_apply].clicks[] += 1; yield()
ax() = first(c for c in fig.content if c isa Axis && !isempty(c.scene.plots))
function lims(tag)
    manager.widgets[:plot_button].clicks[] += 1; yield()
    manager.widgets[:layout_apply].clicks[] += 1; yield()
    l = ax().targetlimits[]; xw, yw = l.widths
    save(joinpath(OUT, tag * ".png"), fig)
    println(rpad(tag, 34), " x width = ", xw, "  y width = ", yw, "  yticklabels = ", ax().yticklabelsvisible[])
    return xw, yw
end
uix, uiy = P._axis_ui(:x_axis), P._axis_ui(:y_axis)
@testset "fine labels" begin
    xw, yw = lims("default")
    @test xw > 1e-4 && yw > 1e-4                         # flat (padded to 1e-3 relative)
    uiy[:scale_offset] = 1.0
    xw, yw = lims("y scale_offset")
    @test yw < 1e-8 && xw > 1e-4
    uix[:scale_offset] = 1.0
    xw, yw = lims("x and y scale_offset")
    @test yw < 1e-8 && xw < 1e-7
    uiy[:scale_offset] = 0.0; uix[:scale_offset] = 0.0
    uiy[:tick_format] = "{:.12f}"
    xw, yw = lims("y tick_format {:.12f}")
    @test yw < 1e-8
    uiy[:tick_format] = "{:.2f}"
    xw, yw = lims("y tick_format {:.2f} (coarse)")
    uiy[:tick_format] = "default"; uiy[:log_scale] = true; uiy[:scale_offset] = 1.0
    xw, yw = lims("y log + scale_offset")
    uiy[:log_scale] = false; uiy[:scale_offset] = 0.0
end
