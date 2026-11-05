# Probe: Lagrangian reference evaluated at the times of non-uniformly saved particle data
using PDEStudio, Test, StaticArrays
PDEStudioCore.set_target_module!(Main)
set_save_path!(mktempdir()); reset_manager!()
t = [0.0, 0.1, 0.2, 1.0]                      # e.g. adaptive steps / output times
x0 = collect(range(0.0, 1.0, length = 5))
xs = [[SVector{1, Float64}(p + ti) for p in x0] for ti in t]
us = [[SVector{1, Float64}(1.0) for _ in x0] for _ in t]
params = create_param_dict(:N => 5)
num = create_sim_data(xs, us, t, params; time_dim = :t)
fac(p) = (x -> SVector(x[end]))                 # u_exact(x, t) = t: shows the time it was evaluated at
@testset "lagrangian reference times" begin
    ref = PDEStudio._make_reference(fac, params, num.domain, Val(:lagrangian), PDEStudio._time_axis(num))
    @show ref.t num.t
    @test ref.t == num.t                          # docstring: evaluated at exactly these times
    # what a time slider at 0.2 draws: the nearest snapshot of each dataset
    nearest(a, v) = a[findmin(x -> abs(x - v), a)[2]]
    @show nearest(ref.t, 0.2) nearest(num.t, 0.2)
    @test nearest(ref.t, 0.2) == nearest(num.t, 0.2)
end
