include(joinpath(@__DIR__, "fixtures.jl"))
set_stat_preset!("hyperbolic")
reset_plotter!()
launch_plotter(adv_config(); style = :lines)
for tq in (1.0, 2.0)
    studio_set!(:x_axis => :cfl, :u_axis => :l1error, :t => tq)
    d = studio_data(1).methods[:upwind]
    println("[err vs cfl at t=$tq] x=", d.x, " u=", round.(Float64.(vec(d.u)), sigdigits = 4), " title=", studio_state().plots[1].title)
    studio_set!(:x_axis => :t, :u_axis => :l1error)
    for c in (0.25, 0.5, 0.75, 1.0)
        studio_set!(:cfl => c)
        e = studio_data(1).methods[:upwind]
        ts = Float64.(vec(e.x)); us = Float64.(vec(e.u))
        i = argmin(abs.(ts .- tq)); j = searchsortedlast(ts, tq)
        println("   cfl=$c: nearest t=", round(ts[i], digits = 4), " err=", round(us[i], sigdigits = 4),
                "  floor t=", round(ts[max(j,1)], digits = 4), " err=", round(us[max(j,1)], sigdigits = 4), "  t_end=", round(ts[end], digits = 4))
    end
end
# particle values follow positions
reset_plotter!()
launch_plotter(SimulationConfig(create_param_dict(:n => 12, :mode => "plain", :sim_func_name => :shuffled_particle_solver),
    create_method_dict(:a => create_param_dict()), [:a]); style = :particles_lines)
studio_set!(:t => 0.5)
d = first(values(studio_data(1).methods))
xs = first.(d.points); us = first.(vec(d.u))
@probe "u follows x" maximum(abs.(us .- sin.(2π .* (xs .- 0.05))))
