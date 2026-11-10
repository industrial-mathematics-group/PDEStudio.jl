using PDEStudio
const P = @__DIR__
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
m = PDEStudio.manager
println("--- UI tab path (_apply_editor_input!, as typing into the Plot style / axis page)")
ok = PDEStudio._apply_editor_input!(:ui, :x_axis_1d, :tick_format, m.ui[:x_axis_1d], "\"{:nope\"", nothing)
@show ok studio_state().status
ok = PDEStudio._apply_editor_input!(:ui, :x_axis_1d, :tick_format, m.ui[:x_axis_1d], "\"default\"", nothing)
println("--- UI tab path, a value the type check now rejects for the API: line_width typed as 2 then 2.5")
PDEStudio._apply_editor_input!(:ui, :plot_style, :line_width, m.ui[:plot_style], "2", nothing)
@show m.ui[:plot_style][:line_width]
PDEStudio._apply_editor_input!(:ui, :plot_style, :line_width, m.ui[:plot_style], "2.5", nothing)
@show m.ui[:plot_style][:line_width]
println("--- UI tab: plain text for a Symbol option (line_direction)")
PDEStudio._apply_editor_input!(:ui, :plot_style, :line_direction, m.ui[:plot_style], "vertical", nothing)
@show m.ui[:plot_style][:line_direction] studio_state().status
println("--- API: line_direction \"vertical\" then does it draw vertically?")
studio_option!(:plot_style, :line_direction, "vertical")
@show studio_state().status
println("--- Update Plot press after a failing option (the press handler's own status?)")
studio_option!(:x_axis_1d, :tick_format, "{:nope")
@show studio_press!(:update_plot)
@show studio_state().status
studio_set!(:t => 0.4)
@show studio_state().status
