# Probe: cost of a Lagrangian 2-D reference evaluated at every saved time (test_particles_2d-like, dt = 0.01, T = 2)
using PDEStudio, StaticArrays
PDEStudioCore.set_target_module!(Main)
set_save_path!(mktempdir()); reset_manager!()
fac(p) = (xyt -> SVector(hypot(xyt[1], xyt[2])))
for nt in (21, 201, 1001)
    t = collect(range(0.0, 2.0, length = nt))
    grid = range(-1.0, 1.0, length = 10)
    x = [vec([SVector(a, b) for a in grid, b in grid]) for _ in t]
    u = [[SVector(1.0) for _ in x[1]] for _ in t]
    num = create_sim_data(x, u, t, create_param_dict(:K => 10); dims = (:x, :y), time_dim = :t)
    PDEStudio._make_reference(fac, num.params, num.domain, Val(:lagrangian), PDEStudio._time_axis(num))  # compile
    GC.gc()
    stats = @timed PDEStudio._make_reference(fac, num.params, num.domain, Val(:lagrangian), PDEStudio._time_axis(num))
    r = stats.value
    println("nt = $nt: reference with $(length(r.x[1])) particles x $(length(r.t)) times, ",
            round(stats.bytes / 2^20, digits = 1), " MiB allocated, ", round(stats.time, digits = 2), " s")
end
# before the fix: the time resolution of the references (resolution_ref[:t] = 100), independent of the data
println("resolution_ref = ", PDEStudio.manager.resolution_ref)
