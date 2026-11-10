using PDEStudio, StaticArrays, Test
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

# shuffled particles; :mode selects extras (:nan, :dup)
function shuffled_particle_solver(params::ParamDict)
    x0 = collect(range(0.0, 1.0, length = 12))
    mode = get(params, :mode, "plain")
    mode == "dup" && (x0[5] = x0[4])
    perm = [7, 2, 11, 1, 9, 4, 12, 3, 6, 10, 5, 8]
    t = [0.0, 0.5, 1.0]
    pts = [[SVector(x0[i] + 0.1 * tn) for i in perm] for tn in t]
    mode == "nan" && (pts[2][3] = SVector(NaN))
    return create_sim_data(pts, [[SVector(sin(2π * x0[i])) for i in perm] for _ in t], t, params; time_dim = :t)
end
exact_particle_factory(params) = (st -> SVector(sin(2π * st[1])))

adv_config() = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :tag => "a", :sim_func_name => :advection_solver_1d),
    create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                       :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
    [:upwind, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.25, 0.5, 0.75, 1.0], :tag => ["a", "b"]),
    reference = :exact_advection_factory)

macro probe(name, ex)
    quote
        local r = try
            $(esc(ex))
        catch e
            "THROWS: " * first(sprint(showerror, e), 600)
        end
        println("[", $(esc(name)), "] ", r isa AbstractString ? r : repr(r))
    end
end
