# b27de21: particle data drawn with a grid style, 1-D and 2-D, uneven times, both paths (nt <= res, nt > res),
# references, statistics over time, static particle data, Float32
using Test, PDEStudio, StaticArrays
const P = PDEStudio
times(n) = n == 4 ? [0.0, 0.1, 0.2, 1.0] : collect(range(0.0, 1.0, length = n)) .^ 2
function parts_2d(params::ParamDict)
    T = params[:f32] ? Float32 : Float64
    t = T.(times(params[:nt]))
    g = range(T(0), T(1), length = 8)
    pts = [SVector(a, b) for a in g for b in g]
    create_sim_data([pts for _ in t], [[SVector(ti) for _ in pts] for ti in t], t, params; time_dim = :t)
end
function parts_1d(params::ParamDict)
    t = times(params[:nt])
    x0 = collect(range(0.0, 1.0, length = 40))
    create_sim_data([[SVector(p) for p in x0] for _ in t], [[SVector(ti) for _ in x0] for ti in t], t, params; time_dim = :t)
end
function parts_static(params::ParamDict)
    x0 = collect(range(0.0, 1.0, length = 40))
    create_sim_data([SVector(p) for p in x0], [SVector(p^2) for p in x0], params; dims = :x)
end
tfac(params) = (xt -> SVector(xt[end]))       # u = t
set_save_path!(mktempdir()); reset_manager!(); set_stat_preset!("hyperbolic")
for (fn, nts) in ((:parts_1d, (4, 30, 80, 400)), (:parts_2d, (4, 50, 51, 120)))
    for nt in nts, f32 in (false, true)
        fn === :parts_1d && f32 && continue
        @testset "$fn nt=$nt f32=$f32" begin
            cfg = SimulationConfig(create_param_dict(:nt => nt, :f32 => f32, :sim_func_name => fn),
                                   create_method_dict(:num => create_param_dict(), :analytical_solution => create_param_dict()),
                                   [:num, :analytical_solution]; reference = :tfac)
            run_all_simulations(cfg; calculate_stats = true)
            pd = P.update_plot_data_collection!(Dict{Symbol, P.AbstractPlotData}(), cfg, [:num, :analytical_solution])
            d, r = pd[:num].data[1], pd[:analytical_solution].data[1]
            D = ndims(d.u)
            stored = load_sim_data(PDEStudioCore.generate_tasks(cfg)[1], Val(:raw)).t
            ta = d.axes[D]
            @test d isa ESimData
            @test length(ta) == min(nt, 50) && issubset(ta, stored) && first(ta) == first(stored) && last(ta) == last(stored)
            @test all(k -> all(v -> v[1] ≈ ta[k], selectdim(d.u, D, k)), eachindex(ta))
            @test r.axes[D] == ta
            @test all(k -> all(v -> v[1] ≈ ta[k], selectdim(r.u, D, k)), eachindex(ta))
            m = d.stats[:mass]
            @test length(m) == length(ta)
            # the mass of u = t over a fixed area: proportional to the time of the snapshot shown
            ks = findall(>(0), ta)
            @test all(k -> isapprox(m[k] / ta[k], m[ks[end]] / ta[ks[end]]; rtol = 1e-4), ks)
            @test eltype(ta) == (f32 ? Float32 : Float64)
        end
    end
end
@testset "static particles" begin
    cfg = SimulationConfig(create_param_dict(:sim_func_name => :parts_static), create_method_dict(:num => create_param_dict()), [:num])
    run_all_simulations(cfg)
    d = P.update_plot_data_collection!(Dict{Symbol, P.AbstractPlotData}(), cfg, [:num])[:num].data[1]
    @test d isa ESimData && ndims(d.u) == 1
    println("static: ", size(d.u), " domain time_dim = ", d.domain.time_dim)
end
