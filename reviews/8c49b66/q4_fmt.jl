using PDEStudio
f = PDEStudio._fmt_value
for v in (0.001, 0.0015, 0.0095, 0.0099, 0.00999, 0.01, 0.0100, 0.0105, 0.011, 0.0125, 0.013, 0.0135, 0.05, 0.0995, 0.099, 0.1, 0.1255, 0.126, -0.005, -0.05)
    println(rpad(v, 8), " -> ", f(v))
end
# a time slider 0:0.0005:0.05 (101 values): how many distinct labels below / above 0.01?
t = collect(range(0.0, 0.05, length = 101))
lo = filter(<(0.01), t); hi = filter(>=(0.01), t)
println("t < 0.01: ", length(lo), " values, ", length(unique(f.(lo))), " labels; t >= 0.01: ", length(hi), " values, ", length(unique(f.(hi))), " labels")
println("sample labels: ", join(f.(t[17:26]), ", "))
# a sweep tau = 0.005, 0.0075, 0.01, 0.0125, 0.015
println("sweep: ", join(f.([0.005, 0.0075, 0.01, 0.0125, 0.015]), ", "))
println("sweep2: ", join(f.([0.01, 0.0125, 0.015, 0.0175, 0.02]), ", "), " | ", join(f.([0.001, 0.00125, 0.0015, 0.00175, 0.002]), ", "))
