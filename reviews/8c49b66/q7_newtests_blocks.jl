# The new tests of 8c49b66, one testset per block (run with the env of either src)
include(joinpath(@__DIR__, "fixtures.jl"))
import PDEStudio: manager
using PDEStudio.Makie: Axis, Axis3
set_stat_preset!("hyperbolic")
config = adv_config()
function fresh(style = nothing)
    reset_plotter!(); isnothing(style) ? launch_plotter(config) : launch_plotter(config; style = style)
end
@testset "new tests" begin
@testset "A hint heatmap" begin
    fresh(:lines); studio_set!(:plot_style => :heatmap)
    hint = only(c for c in studio_controls() if c.name === :u_axis).label
    @test occursin("studio_set!(:plot_style => :lines, :x_axis => :t, :u_axis => :l1error)", hint)
end
@testset "C F2 compare" begin
    fresh(); r = studio_set!(:cfl => 1.0, :compare_target => :cfl)
    @test studio_state().compare.target === :cfl && occursin("not set: :cfl", r.status)
end
@testset "D F2 axis" begin
    fresh(); r = studio_set!(:t => 1.0, :plot_style => :heatmap, :x_axis => :x, :y_axis => :t)
    @test studio_state().axes.y === :t && occursin("not set: :t", r.status)
end
@testset "E F1 methods+typo" begin
    fresh(); active = copy(manager.active_config.defaults)
    @test_throws ArgumentError studio_set!(:methods => [:upwind], :cfll => 1.0)
    @test manager.active_config.defaults == active
end
@testset "F F1 x_axis+typo" begin
    fresh(); plot_flag = manager.flags[:Plot][]
    @test_throws ArgumentError studio_set!(:x_axis => :t, :bogus => 1)
    @test studio_state().axes.x === :x && manager.flags[:Plot][] == plot_flag
end
@testset "G fmt" begin
    @test PDEStudio._fmt_value.((1e-5, 0.0015, 0.002, 0.25, 0.0, 2.5e6, 3)) == ("1e-05", "0.0015", "0.002", "0.250", "0.000", "2.5e+06", "3")
end
long = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
                        create_method_dict(:upwind_first_order_scheme_without_limiter => create_param_dict(:scheme => "upwind"),
                                           :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")))
reset_plotter!(); launch_plotter(long; style = :lines)
studio_set!(:compare_target => :methods, :plot_width => 300)
ax1 = first(b for b in manager.master_fig.content if b isa Axis)
@testset "H fit_label one word" begin
    @test PDEStudio._fit_label("x" ^ 200, ax1)[end] == '…' && !occursin("\n", PDEStudio._fit_label("x" ^ 200, ax1))
end
@testset "I two-line cap" begin
    studio_set!(:plot_width => 60)
    @test count(==('\n'), PDEStudio._fit_label("upwind_first_order_scheme_without_limiter", ax1)) <= 1
end
@testset "J Axis3 one line" begin
    studio_set!(:plot_style => :heatmap_surface, :plot_width => 300)
    drawn3 = [b.title[] for b in manager.master_fig.content if b isa Axis3]
    @test length(drawn3) == 2 && !any(t -> occursin("\n", t), drawn3) && any(t -> endswith(t, "…"), drawn3)
end
@testset "K custom title" begin
    studio_set!(:plot_style => :lines, :plot_width => 500, :compare_target => :none)
    studio_option!(:labels, :title, "a\nb")
    @test studio_state().plots[1].title == "a | b"
    studio_option!(:labels, :title, "default")
end
end
