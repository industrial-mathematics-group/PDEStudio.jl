using PDEStudio
const P = @__DIR__
studio_headless!()
set_save_path!(mktempdir())
w() = PDEStudio.manager.widgets
show_state(tag) = (s = studio_state(); println(tag, ": axes=", s.axes, " sliders=", [(x.name, x.value) for x in s.sliders], " nplots=", length(s.plots), " compare=", s.compare.target))
launch_plotter(test_heat_2d(); style = :heatmap)
show_state("launch")
println("--- GUI way: widgets only")
m = w()[:compare_target]; m.i_selected[] = findfirst(o -> o[2] === :methods, m.options[]); w()[:layout_apply].clicks[] += 1
show_state("GUI compare methods")
m = w()[:compare_link]; m.i_selected[] = findfirst(o -> o[2] === :decoupled, m.options[]); w()[:layout_apply].clicks[] += 1
show_state("GUI decoupled")
m = w()[:compare_target]; m.i_selected[] = findfirst(o -> o[2] === :none, m.options[]); w()[:layout_apply].clicks[] += 1
show_state("GUI compare none")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
show_state("launch2")
studio_set!(:compare_target => :methods); show_state("API compare methods")
studio_set!(:compare_link => :decoupled); show_state("API decoupled")
studio_set!(:compare_target => :none); show_state("API none")
reset_plotter!()
launch_plotter(test_heat_2d(); style = :heatmap)
show_state("launch3")
m = w()[:compare_target]; m.i_selected[] = findfirst(o -> o[2] === :methods, m.options[])
m = w()[:compare_link]; m.i_selected[] = findfirst(o -> o[2] === :decoupled, m.options[]); w()[:layout_apply].clicks[] += 1
show_state("GUI methods+decoupled in one apply")
