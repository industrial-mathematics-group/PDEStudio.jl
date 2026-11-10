include(joinpath(@__DIR__, "fixtures.jl"))
set_stat_preset!("hyperbolic")
reset_plotter!()
launch_plotter(adv_config(); style = :lines)
@probe "scalar err" studio_set!(:u_axis => :spacetime_relative_mass)
@probe "scalar follow" begin
    studio_set!(:x_axis => :cfl, :u_axis => :spacetime_relative_mass)
    s = studio_state(); (s.axes, s.plots[1].title, studio_data(1).methods[:upwind].u)
end
# contour (2D) style: the hint
studio_set!(:x_axis => :x, :u_axis => :Solution)
studio_set!(:plot_style => :contour, :x_axis => :x, :y_axis => :t)
@probe "contour hint" only(c for c in studio_controls() if c.name === :u_axis).label
@probe "contour, x=cfl y=tag (stat over two params?)" begin
    studio_set!(:x_axis => :cfl, :y_axis => :tag)
    only(c for c in studio_controls() if c.name === :u_axis).choices
end
