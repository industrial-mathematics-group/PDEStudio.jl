include(joinpath(@__DIR__, "fixtures.jl"))
const M = PDEStudio.manager
reset_plotter!()
launch_plotter(adv_config(); style = :lines)
sl(n) = only(s for s in studio_state().sliders if s.name === n).value
presses = Ref(0)

# 1. the reported case
studio_set!(:compare_target => :cfl)
@probe "end compare + slider" (studio_set!(:compare_target => :none, :cfl => 0.75).values, studio_state().compare.target)
# 2. apply = false
studio_set!(:compare_target => :cfl)
@probe "apply=false" studio_set!(:compare_target => :none, :cfl => 0.25; apply = false)
@probe "apply=false state" (studio_state().compare.target, M.flags[:Plot][], M.flags[:Layout][])
studio_press!(:apply_layout)
@probe "after press" studio_state().compare.target

# 3. a typo after a change: what happened before the error?
studio_set!(:x_axis => :x)
@probe "typo" studio_set!(:x_axis => :t, :cfll => 0.5)
@probe "typo: state" (studio_state().axes.x, M.flags[:Plot][], studio_state().status.text)

# 4. bad slider value after methods (runs the simulation first?)
runs_before = studio_state().status.text
@probe "methods + bad slider" studio_set!(:methods => [:upwind], :cfl => 7.0)
@probe "methods + bad slider: state" (studio_state().config.active_methods, M.flags[:Simulation][], studio_state().status.text)
studio_set!(:methods => [:upwind, :lax_friedrichs])

# 5. methods + slider in one call
@probe "methods + slider" begin
    r = studio_set!(:methods => [:upwind], :cfl => 0.5, :tag => "b")
    (r.values, studio_state().config.active_methods, r.status)
end
studio_set!(:methods => [:upwind, :lax_friedrichs])

# 6. slider then axis that consumes it
studio_set!(:x_axis => :x)
@probe "slider + x_axis=t" studio_set!(:t => 1.0, :x_axis => :t)
studio_set!(:x_axis => :x)
@probe "x_axis back + slider t" studio_set!(:x_axis => :x, :t => 1.0)
@probe "t" sl(:t)
# 7. param slider via :param_1 key
@probe "param_1 key" studio_set!(:param_1 => 0.5)
# 8. stat message with only sliders: status
@probe "only slider" studio_set!(:cfl => 0.25).status
@probe "mixed status" studio_set!(:plot_width => 450, :cfl => 0.5).status
studio_set!(:plot_width => 500)
# 9. compare_target => :cfl and :cfl slider in same call
@probe "compare + its slider" studio_set!(:cfl => 1.0, :compare_target => :cfl)
studio_set!(:compare_target => :none)
