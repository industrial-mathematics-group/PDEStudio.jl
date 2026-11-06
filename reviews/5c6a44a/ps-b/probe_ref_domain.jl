# Probe: reference solutions in a sweep that changes the domain (final time T_end swept).
#   DISPLAY=:99 julia -t 4 --project=test <scratch>/probe_ref_domain.jl
include(joinpath(@__DIR__, "probe_setup.jl"))
function adv_T(params::ParamDict)
    N = params[:N]; cfl = params[:cfl]; Tend = params[:T_end]
    dx = 2π / N; dt = cfl * dx; Nt = ceil(Int, Tend / dt) + 1
    x = collect(range(0.0, step = dx, length = N)); t = collect(range(0.0, step = dt, length = Nt))
    u = [SVector{1, Float64}(sin(xi - ti) + 2.0) for xi in x, ti in t]      # exact transport (no scheme error)
    return create_sim_data(x, u, t, params; time_dim = :t, dims = :x)
end
w() = manager.widgets
@testset "Reference follows the domain of each sweep point" begin
    cfg = SimulationConfig(create_param_dict(:cfl => 0.5, :N => 40, :T_end => 1.0, :sim_func_name => :adv_T),
        create_method_dict(:analytical_solution => create_param_dict(), :transport => create_param_dict()),
        [:transport, :analytical_solution]; varied = create_varied_dict(:T_end => [1.0, 2.0]),
        reference = :exact_advection_factory)
    set_sim_config!(cfg); force_simulation()
    click_menu!(w()[:plot_style], :lines_1d)
    click_menu!(w()[:x_axis], :x); click_menu!(w()[:y_axis], :none); click_menu!(w()[:z_axis], :none)
    click_button!(:layout_apply)
    set_close_to!(w()[manager.reverse_map[:T_end]], 2.0); yield()
    set_close_to!(w()[:t], last(w()[:t].range[])); yield()
    k = 2
    dn = manager.plot_data[][:transport].data[k]; dr = manager.plot_data[][:analytical_solution].data[k]
    println("T_end = 2.0: numeric t-range ", extrema(dn.axes[2]), ", reference t-range ", extrema(dr.axes[2]))
    cu = manager.caches[1][:transport].obs_u[]; ca = manager.caches[1][:analytical_solution].obs_u[]
    println("t slider = ", w()[:t].value[], "; max |numeric - reference| as drawn: ", maximum(abs.(extrema(cu) .- extrema(ca))),
            " (the numeric data IS the exact solution)")
    save(joinpath(@__DIR__, "ref_domain.png"), fig)
    @test extrema(dr.axes[2])[2] ≈ extrema(dn.axes[2])[2] atol = 0.1
end
reset_plotter!()
