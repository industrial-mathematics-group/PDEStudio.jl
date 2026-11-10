# The new tests of 8a544e3, one testset per block (run with the env of either src)
using PDEStudio, StaticArrays, Test
import PDEStudio: manager
PDEStudioCore.set_target_module!(@__MODULE__)
studio_headless!()
set_save_path!(mktempdir())
function advection_solver_1d(params::ParamDict)
    N = params[:N]; scheme = get(params, :scheme, "upwind"); cfl = get(params, :cfl, 0.5)
    dx = 2π / N; dt = cfl * dx; Nt = ceil(Int, 2.0 / dt) + 1
    x = collect(range(0.0, step = dx, length = N)); t = collect(range(0.0, step = dt, length = Nt))
    u = fill(SVector{1, Float64}(0.0), N, Nt)
    for i in 1:N; u[i, 1] = SVector(sin(x[i]) + 2.0); end
    for n in 1:Nt-1, i in 1:N
        im1 = i == 1 ? N : i - 1; ip1 = i == N ? 1 : i + 1
        val = scheme == "upwind" ? u[i, n][1] - cfl * (u[i, n][1] - u[im1, n][1]) :
              0.5 * (u[ip1, n][1] + u[im1, n][1]) - 0.5 * cfl * (u[ip1, n][1] - u[im1, n][1])
        u[i, n+1] = SVector(val)
    end
    return create_sim_data(x, u, t, params; time_dim = :t, dims = :x)
end
exact_advection_factory(params) = (st -> SVector(sin(st[1] - st[2]) + 2.0))
function shuffled_particle_solver(params::ParamDict)
    x0 = collect(range(0.0, 1.0, length = 12))
    perm = [7, 2, 11, 1, 9, 4, 12, 3, 6, 10, 5, 8]
    t = [0.0, 1.0]
    return create_sim_data([[SVector(x0[i] + 0.1 * tn) for i in perm] for tn in t],
                           [[SVector(sin(2π * x0[i])) for i in perm] for _ in t], t, params)
end
config = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :tag => "a", :sim_func_name => :advection_solver_1d),
                          create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                             :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
                          [:upwind, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.25, 0.5, 0.75, 1.0],
                                                                                  :tag => ["a", "b"]),
                          reference = :exact_advection_factory)
@testset "new tests" begin
@testset "1 particles" begin
    reset_plotter!()
    launch_plotter(SimulationConfig(create_param_dict(:n => 12, :sim_func_name => :shuffled_particle_solver),
                                    create_method_dict(:a => create_param_dict()), [:a]); style = :particles_lines)
    pts = first(values(studio_data(1).methods)).points
    @test length(pts) == 12 && issorted(first.(pts))
    studio_set!(:t => 1.0)
    @test issorted(first.(first(values(studio_data(1).methods)).points))
end
@testset "1b _by_position" begin
    @test PDEStudio._by_position([3.0, 1.0, 2.0], [30, 10, 20]) == ([1.0, 2.0, 3.0], [10, 20, 30])
end
@testset "2 stats hint" begin
    set_stat_preset!("hyperbolic")
    reset_plotter!()
    launch_plotter(config; style = :lines)
    @test occursin("studio_set!(:x_axis => :t, :u_axis => :l1error)", only(c for c in studio_controls() if c.name === :u_axis).label)
    err = try studio_set!(:u_axis => :l1error); "" catch e; sprint(showerror, e) end
    @test occursin("u_axis has no option :l1error", err) && occursin("The statistic :l1error: plotted over :t", err)
end
@testset "2b stats order" begin
    reset_plotter!()
    launch_plotter(config; style = :lines)
    studio_set!(:u_axis => :l1error, :x_axis => :t)
    s = studio_state()
    @test s.axes.x === :t && s.axes.u === :l1error && s.plots[1].ylabel == "L1Error"
end
@testset "2c stats param" begin
    studio_set!(:x_axis => :x, :u_axis => :Solution)
    studio_set!(:u_axis => :l1error, :x_axis => :cfl)
    @test studio_state().axes.x === :cfl && length(first(values(studio_data(1).methods)).x) == 4
    studio_set!(:x_axis => :x, :u_axis => :Solution)
end
@testset "2d particle hint" begin
    reset_plotter!()
    launch_plotter(test_particles_2d())
    @test occursin("in a grid style", only(c for c in studio_controls() if c.name === :u_axis).label)
end
@testset "3 slider order" begin
    reset_plotter!()
    launch_plotter(config)
    studio_set!(:compare_target => :cfl)
    r = studio_set!(:cfl => 0.75, :compare_target => :none)
    @test r.values[:cfl] == 0.75 && studio_state().compare.target === :none
end
@testset "3b reported order" begin
    reset_plotter!()
    launch_plotter(config)
    studio_set!(:compare_target => :cfl)
    r = studio_set!(:compare_target => :none, :cfl => 0.75)
    @test r.values[:cfl] == 0.75 && studio_state().compare.target === :none
end
@testset "4 names" begin
    @test PDEStudio.frontend_key.((:Grid_Ns__1, :PDE_tau, :Ns__all, :l1error, :cfl)) ==
          ("Grid Ns[1]", "PDE Tau", "Ns (all)", "L1Error", "Cfl")
    @test PDEStudio._fmt_value.((1e-5, 0.25, 0.0, 2.5e6, 3)) == ("1e-05", "0.250", "0.000", "2.5e+06", "3")
end
@testset "5 titles" begin
    long = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
                            create_method_dict(:upwind_first_order_scheme_without_limiter => create_param_dict(:scheme => "upwind"),
                                               :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")))
    reset_plotter!()
    launch_plotter(long; style = :lines)
    studio_set!(:compare_target => :methods, :plot_width => 300)
    drawn = [b.title[] for b in manager.master_fig.content if b isa Axis]
    @test "upwind_first_order_scheme_without_limiter" in [p.title for p in studio_state().plots]
    @test any(t -> occursin("\n", t) && replace(t, "\n" => "") == "upwind_first_order_scheme_without_limiter", drawn)
end
end
# Behaviour of calls that might differ between the two versions
macro probe(name, ex)
    quote
        local r = try $(esc(ex)) catch e "THROWS: " * first(sprint(showerror, e), 300) end
        println("[", $(esc(name)), "] ", r isa AbstractString ? r : repr(r))
    end
end
reset_plotter!()
launch_plotter(config; style = :lines)
@probe "slider then x_axis=t" (studio_set!(:t => 1.0, :x_axis => :t); studio_state().axes.x)
studio_set!(:x_axis => :x)
@probe "slider then compare its param" (studio_set!(:cfl => 1.0, :compare_target => :cfl); studio_state().compare.target)
studio_set!(:compare_target => :none)
@probe "typo after x_axis" studio_set!(:x_axis => :t, :cfll => 0.5)
@probe "typo: flags/axes" (manager.flags[:Plot][], studio_state().axes.x)
