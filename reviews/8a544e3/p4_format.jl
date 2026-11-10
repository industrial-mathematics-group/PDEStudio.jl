include(joinpath(@__DIR__, "fixtures.jl"))
const P = PDEStudio
for v in (1e-5, -1e-5, 1f-5, 0.0015, 0.0012, 0.002, 0.00099, 99999.9, 1e5, -2.5e6, 1e300, NaN, Inf, -0.0, 3, big"1e-7", 0.5f0, nextfloat(0.0))
    @probe "fmt $(repr(v))" P._fmt_value(v)
end
for k in (:Grid_Ns__1, :Grid_Ns__all, :Ns__xy, :Ns__x, :a__b__1, :my__param, :__private, :PDE_tau, :CFL, :dt, :xMax,
          :l1error, :l2error, :linf_error, :component_1, :rk4, :Nx, :T_end, :u_0, Symbol("l1error|t"), :_x, :x_, :a___1, :Ns__ALL, :Δt, :α_max)
    @probe "key $(repr(k))" P.frontend_key(k)
end
PDEStudio.set_label!(:Grid_Ns, "Grid N")
@probe "label base wins" P.frontend_key(:Grid_Ns__1)
PDEStudio.set_label!(:Grid_Ns__1, "first")
@probe "label entry wins" P.frontend_key(:Grid_Ns__1)
