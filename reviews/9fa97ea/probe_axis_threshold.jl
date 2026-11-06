# 0bcebe1: axis limits with the 1e-6 relative threshold, rendered (default tick labels, and the studio's scale_offset format)
using PDEStudio, Printf
const CairoMakie = PDEStudio.CairoMakie
using .CairoMakie
const P = PDEStudio
offset_fmt(y_off) = t -> map(v -> "$(round(y_off, sigdigits=3)) $(v - y_off < 0 ? "-" : "+") $(@sprintf("%.1e", abs(v - y_off)))", t)
cases = [
    ("F64 1+1e-6 sin (w 2e-6)", Float64, 1 .+ 1e-6 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F64 1+6e-7 sin (w 1.2e-6)", Float64, 1 .+ 6e-7 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F64 1+4e-7 sin (w 8e-7)", Float64, 1 .+ 4e-7 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F64 1+1e-12 sin", Float64, 1 .+ 1e-12 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F64 -1+1e-6 sin", Float64, -1 .+ 1e-6 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F64 1e5+0.2 sin (w 4e-6)", Float64, 1e5 .+ 0.2 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F64 1e-9 sin (around 0)", Float64, 1e-9 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F64 1e-8+1e-14 sin", Float64, 1e-8 .+ 1e-14 .* sin.(range(0, 2π, length = 50)), nothing),
    ("F32 1+1e-5 sin (w 2e-5)", Float32, Float32.(1 .+ 1e-5 .* sin.(range(0, 2π, length = 50))), nothing),
    ("F32 1+5e-6 sin (w 1e-5)", Float32, Float32.(1 .+ 5e-6 .* sin.(range(0, 2π, length = 50))), nothing),
    ("F64 1+1e-9 sin, scale_offset 1", Float64, 1 .+ 1e-9 .* sin.(range(0, 2π, length = 50)), 1.0),
    ("same, axis fitted to data", Float64, 1 .+ 1e-9 .* sin.(range(0, 2π, length = 50)), -1.0),
]
fig = Figure(size = (1400, 900))
for (i, (title, T, v, off)) in enumerate(cases)
    lo, hi = P.calculate_padded_axis_range(P._safe_extrema([v]), 0.05, false; precision = T)
    if off == -1.0
        w = maximum(v) - minimum(v); lo, hi = minimum(v) - 0.025w, maximum(v) + 0.025w; off = 1.0
    end
    ax = Axis(fig[fld1(i, 4), mod1(i, 4)], title = title, titlesize = 12)
    isnothing(off) || (ax.ytickformat = offset_fmt(off))
    lines!(ax, 1:50, Float64.(v))
    limits!(ax, 1, 50, lo, hi)
    filled = (maximum(v) - minimum(v)) / (hi - lo)
    @printf("%-32s limits (%.12g, %.12g)  data/axis = %.3g\n", title, lo, hi, filled)
end
save(joinpath(@__DIR__, "axis_threshold.png"), fig)
