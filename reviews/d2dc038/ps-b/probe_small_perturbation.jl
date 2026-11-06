# Probe: 1-D axis limits / colour range of a Float64 field with a small (but resolved) relative variation
using PDEStudio, Test
@testset "small Float64 perturbation stays visible" begin
    x = range(0, 2π, length = 200)
    for amp in (1e-4, 1e-5, 1e-6, 1e-8)
        u = 1.0 .+ amp .* sin.(x)              # e.g. a linear acoustic wave on a unit background (Float64)
        lo, hi = PDEStudio.calculate_padded_axis_range(PDEStudio._safe_extrema([collect(u)]), 0.1, false)
        frac = (maximum(u) - minimum(u)) / (hi - lo)     # fraction of the axis height the curve spans
        cr = PDEStudio.get_colorrange(Dict{Symbol, Any}(:color_range => Any[]), collect(u))[]
        println("amp = $amp: axis ($lo, $hi), curve spans $(round(100frac, digits = 3)) % of the axis; colour range $cr")
        @test frac > 0.5
    end
end
