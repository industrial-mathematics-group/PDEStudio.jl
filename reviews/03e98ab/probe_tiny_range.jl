# 134a6c7: axis limits of Float64 data with relative variations just above 100 eps (e.g. conserved mass with round-off)
using PDEStudio
const CairoMakie = PDEStudio.CairoMakie
using .CairoMakie
const P = PDEStudio
fig = Figure(size = (900, 300))
for (i, a) in enumerate((1e-6, 1e-7, 1e-8))
    v = 1 .+ a .* sin.(range(0, 2π, length = 50))
    lo, hi = P.calculate_padded_axis_range(P._safe_extrema([v]), 0.05, false; precision = Float64)
    ax = Axis(fig[1, i], title = "a = $a")
    lines!(ax, 1:50, v)
    limits!(ax, 1, 50, lo, hi)
    println("a = $a: limits ", (lo, hi), " width ", hi - lo)
end
save(joinpath(@__DIR__, "tiny_range2.png"), fig)
