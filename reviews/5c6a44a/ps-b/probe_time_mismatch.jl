# Probe: times shown for the numerical method and the reference in one 1D plot at the same slider position.
#   DISPLAY=:99 julia -t 4 --project=test <scratch>/probe_time_mismatch.jl
include(joinpath(@__DIR__, "probe_setup.jl"))
@testset "Numerical and reference curves are drawn at the same time" begin
    click_menu!(manager.widgets[:plot_style], :lines_1d)
    click_menu!(manager.widgets[:x_axis], :x); click_menu!(manager.widgets[:y_axis], :none); click_menu!(manager.widgets[:z_axis], :none)
    click_button!(:layout_apply)
    set_close_to!(manager.widgets[manager.reverse_map[:cfl]], 0.2); yield()
    pdn = manager.plot_data[][:upwind]; pdr = manager.plot_data[][:analytical_solution]
    k = findfirst(==(0.2), pdn.active_param_values[1])
    dn, dr = pdn.data[k], pdr.data[k]
    # the original (unresampled) snapshot times of the upwind run
    params = assemble_params(config.shared, config.methods, :upwind); params[:cfl] = 0.2
    orig = load_sim_data(params, Val(:raw))
    t_orig = orig.axes[2]
    worst = 0.0; worst_at = NaN
    rng = manager.widgets[:t].range[]
    for ts in rng
        tn = dn.axes[2][findmin(v -> abs(v - ts), dn.axes[2])[2]]          # resampled numeric axis value picked
        tsnap = t_orig[findmin(v -> abs(v - tn), t_orig)[2]]                # the snapshot that value holds (nearest)
        tr = dr.axes[2][findmin(v -> abs(v - ts), dr.axes[2])[2]]          # reference time picked
        d = abs(tsnap - tr)
        d > worst && (worst = d; worst_at = ts)
    end
    println("numeric display t-grid: $(length(dn.axes[2])) pts, reference t-grid: $(length(dr.axes[2])) pts, slider: $(length(rng)) pts")
    println("original upwind dt = $(t_orig[2]-t_orig[1]), Nt = $(length(t_orig))")
    println("max |t(numeric snapshot) - t(reference)| over slider positions: $worst (at slider t = $worst_at)")
    # the error that time offset alone puts between exact solutions: max_x |u(x, t1) - u(x, t2)| = |sin| shift ~ c*dt
    println("=> apparent error from the offset alone (c = 1, amplitude 1): ~", round(2 * sin(worst / 2), sigdigits = 3))
    # the true upwind error at the snapshot vs the plotted difference
    set_close_to!(manager.widgets[:t], worst_at); yield()
    cu = manager.caches[1][:upwind].obs_u[]; ca = manager.caches[1][:analytical_solution].obs_u[]
    xs = manager.caches[1][:upwind].obs_x[]
    tn = dn.axes[2][findmin(v -> abs(v - worst_at), dn.axes[2])[2]]
    tsnap = t_orig[findmin(v -> abs(v - tn), t_orig)[2]]
    true_err = maximum(abs.(cu .- (sin.(xs .- tsnap) .+ 2)))
    tr = dr.axes[2][findmin(v -> abs(v - worst_at), dr.axes[2])[2]]
    shown_err = maximum(abs.(cu .- (sin.(xs .- tr) .+ 2)))
    println("t slider $worst_at: upwind snapshot t = $tsnap, reference drawn at t = $tr")
    println("max |upwind - exact| as drawn (exact at the reference time) = $shown_err; true error at the snapshot time = $true_err")
    println("title: ", manager.plot_titles[1])
    @test worst < 1e-8
end
reset_plotter!()
