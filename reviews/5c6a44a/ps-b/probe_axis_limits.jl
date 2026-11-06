# Probe: 1D axis limits for a (numerically) constant Float32 field (no window).
#   julia -t 2 --project=test <scratch>/probe_axis_limits.jl
using PDEStudio, Test
const P = PDEStudio
using PDEStudio: CairoMakie
using PDEStudio.CairoMakie: Figure, Axis, lines!, Makie
@testset "axis limits of a constant Float32 field" begin
    x = collect(range(0.0, 1.0, length = 50))
    u = Float64.(1.4f0 .+ Float32.(1e-7 .* sin.(10 .* x)))      # Float32 noise around 1.4, plotted as Float64
    lims = P.calculate_padded_axis_range(P._safe_extrema([u]), 0.05, false)
    println("raw extrema: ", P._safe_extrema([u]), "  padded y limits: ", lims, "  width: ", lims[2] - lims[1])
    fig = Figure(); ax = Axis(fig[1, 1]); lines!(ax, x, u)
    P.set_axis_limits_manager!(ax, [x], [u])
    img = Makie.colorbuffer(fig; backend = CairoMakie)
    CairoMakie.save(joinpath(@__DIR__, "axis_limits_const.png"), fig; backend = CairoMakie)
    fl = ax.finallimits[]
    println("final y limits: ", fl.origin[2], " .. ", fl.origin[2] + fl.widths[2])
    @test lims[2] - lims[1] > 1e-6
end
