# 13b3dfd: cost of loading grid data with more stored snapshots than the time resolution (50), per (re)load
using PDEStudio, StaticArrays
const P = PDEStudio
function big_2d(params::ParamDict)
    N, nt = params[:N], params[:nt]
    x = collect(range(0.0, step = 2π / N, length = N))
    t = collect(range(0.0, 2.0, length = nt))
    return create_sim_data((x, x), [SVector(sin(xi + yi - ti) + 2.0) for xi in x, yi in x, ti in t], t, params; dims = (:x, :y))
end
set_save_path!(mktempdir()); reset_manager!()
println("conversion cache enabled: ", PDEStudioCore._ENABLE_CONV_CACHE[])
for nt in (40, 401)
    cfg = SimulationConfig(create_param_dict(:N => 256, :nt => nt, :sim_func_name => :big_2d),
                           create_method_dict(:num => create_param_dict()), [:num])
    run_all_simulations(cfg)
    params = PDEStudioCore.generate_tasks(cfg)[1]
    path = get_file_name(params)
    println("nt = $nt: file size ", round(filesize(path) / 2^20, digits = 1), " MiB")
    dom = P._get_template_domain(cfg)
    for rep in 1:3
        GC.gc()
        st = @timed P._load_for_display(params, dom, Val(:eulerian))
        println("  studio load #$rep: ", round(st.time, digits = 3), " s, ", round(st.bytes / 2^20, digits = 1), " MiB allocated, size ", size(st.value.u))
    end
    # what the time-resampled Core path cost (cached conversion), for comparison
    res = (200, 200, 50)
    for rep in 1:2
        GC.gc()
        st = @timed load_sim_data(params, Val(:eulerian), res)
        println("  Core :eulerian $res #$rep: ", round(st.time, digits = 3), " s, ", round(st.bytes / 2^20, digits = 1), " MiB")
    end
    # suggested alternative: space-resampled full time axis (cached by Core), then select snapshots
    for rep in 1:2
        GC.gc()
        st = @timed begin
            full = load_sim_data(params, Val(:eulerian), (200, 200, nt))
            nt > 50 ? P._select_snapshots(full, unique(round.(Int, range(1, nt, length = 50)))) : full
        end
        println("  alt: Core (200,200,$nt) cached + select #$rep: ", round(st.time, digits = 3), " s, ", round(st.bytes / 2^20, digits = 1), " MiB, size ", size(st.value.u))
    end
end
