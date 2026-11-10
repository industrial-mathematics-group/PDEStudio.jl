include(joinpath(@__DIR__, "fixtures.jl"))
const M = PDEStudio.manager
set_stat_preset!("hyperbolic")
reset_plotter!()
launch_plotter(test_particles_2d())
println("mode ", M.mode[], " style ", studio_state().style)
println("widgets present: ", [k => haskey(M.widgets, k) for k in (keys(PDEStudio._MENU_LABELS)..., keys(PDEStudio._NUMBER_LABELS)...)])
println("controls: ", [c.name for c in studio_controls()])
for n in (:x, :y, :t, :dt, :param_1, :u_axis, :z_axis)
    @probe "check $n" (PDEStudio._check_control_name(n); "ok")
end
@probe "hint" only(c for c in studio_controls() if c.name === :u_axis).label
@probe "x_axis label" only(c for c in studio_controls() if c.name === :x_axis).label
@probe "to lines + slider x" (r = studio_set!(:plot_style => :lines, :x_axis => :t, :u_axis => :l1error, :x => 0.0); (r.status, studio_state().axes))
@probe "to lines + slider y" (r = studio_set!(:y => 0.0); r.status)
println("controls after: ", [c.name for c in studio_controls()])
reset_plotter!()
