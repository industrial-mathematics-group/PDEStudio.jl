# The new agent-group assertions of d84f756 that come after the first abort on old src, each run on its own.
# ARGS[1]: label of the src (new / 47b4c6e / 691bed7).
using PDEStudio, Test, StaticArrays
const m = PDEStudio.manager
include(joinpath(dirname(@__DIR__), "repo", "reviews", "47b4c6e", "o01_simfuncs.jl"))
results = Pair{String, Any}[]
function check(f, name)
    r = try
        f() === true ? "pass" : "FAIL"
    catch e
        "ERROR: " * first(sprint(showerror, e), 140)
    end
    push!(results, name => r)
    println(rpad(name, 58), r)
end
studio_headless!()
set_save_path!(mktempdir()); snapdir = mktempdir()
config = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :tag => "a", :sim_func_name => :advection_solver_1d),
                          create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                             :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
                          [:upwind, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.25, 0.5, 0.75, 1.0], :tag => ["a", "b"]),
                          reference = :exact_advection_factory)
launch_plotter(config)
check("line_width 2, 2.5, 3.0 accepted") do; m.ui[:plot_style][:line_width] = 3.0
    all(w -> (try studio_option!(:plot_style, :line_width, w); catch; end; studio_options(:plot_style)[:line_width] == w), (2, 2.5, 3.0)) && (m.ui[:plot_style][:line_width] = 3.0; true)
end
check("line_direction \"vertical\" rejected") do
    try; studio_option!(:plot_style, :line_direction, "vertical"); false; catch e; e isa ArgumentError; end
end
m.ui[:plot_style][:line_direction] = :horizontal
check("levels 2.5 rejected") do
    try; studio_option!(:plot_style, :levels, 2.5); false; catch e; e isa ArgumentError; end
end
check("method_index 9 rejected") do
    try; studio_option!(:plot_style, :method_index, 9); false; catch e; e isa ArgumentError; end
end
m.ui[:plot_style][:method_index] = 1
check("colors [(:red, 0.5), :blue] keeps (:red, 0.5)") do
    studio_option!(:plot_style, :colors, [(:red, 0.5), :blue]); studio_options(:plot_style)[:colors][1] == (:red, 0.5)
end
studio_option!(:plot_style, :colors, PDEStudio.MASTER_UI_DICT[:plot_style][:colors])
check("failing tick_format -> :error") do
    studio_option!(:x_axis_1d, :tick_format, "{:nope"); studio_state().status.level === :error
end
check("... fails again -> :error") do
    studio_option!(:x_axis_1d, :grid_visibility, false); studio_state().status.level === :error
end
check("repaired -> :ok") do
    studio_option!(:x_axis_1d, :tick_format, "default"); studio_option!(:x_axis_1d, :grid_visibility, true)
    studio_state().status.level === :ok
end
check("UI tab failing tick_format -> :error") do
    PDEStudio._apply_editor_input!(:ui, :x_axis_1d, :tick_format, m.ui[:x_axis_1d], "\"{:nope\"", nothing)
    studio_state().status.level === :error
end
studio_option!(:x_axis_1d, :tick_format, "default")
studio_set!(:compare_target => :methods, :compare_columns => 2)
studio_set!(:compare_link => :decoupled)
studio_set!(:plot_style => :heatmap_flat, :y_axis => :t)
check("decoupled crop reaches its colorbar") do
    sub1 = PDEStudio.Makie.FileIO.load(studio_snapshot(joinpath(@__DIR__, "o02_decoupled1_$(ARGS[1]).png"); plot = 1))
    cb = [c.content for c in PDEStudio._plot_layout().content if c.content isa PDEStudio.Makie.Colorbar]
    ab = PDEStudio._axis_box(PDEStudio._plot_axes()[1])
    cbox = PDEStudio._axis_box(argmin(c -> abs(c.layoutobservables.computedbbox[].origin[1] - (ab.origin[1] + ab.widths[1])), cb))
    println("    width ", size(sub1, 2), " needed ", cbox.origin[1] + cbox.widths[1] - ab.origin[1] - 4)
    size(sub1, 2) >= cbox.origin[1] + cbox.widths[1] - ab.origin[1] - 4
end
studio_set!(:compare_target => :none, :plot_style => :lines_1d, :y_axis => :none)
println("--- describe_studio order (heat_2d)")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
io = IOBuffer(); describe_studio(io); t = String(take!(io))
println(filter(l -> occursin("method_index", l), split(t, '\n')))
for i in 1:3
    studio_option!(:plot_style, :method_index, i)
    println("method_index = $i -> ", collect(keys(studio_state().plots[1].value_ranges)))
end
println("SUMMARY ", ARGS[1], ": ", count(r -> last(r) == "pass", results), "/", length(results), " pass")
