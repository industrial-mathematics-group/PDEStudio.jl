    # --- particles_lines joins the particles along the axis, not in storage order ---
    reset_plotter!()
    launch_plotter(SimulationConfig(create_param_dict(:n => 12, :sim_func_name => :shuffled_particle_solver),
                                    create_method_dict(:a => create_param_dict()), [:a]); style = :particles_lines)
    pts = first(values(studio_data(1).methods)).points
    @test length(pts) == 12 && issorted(first.(pts))
    studio_set!(:t => 1.0)
    @test issorted(first.(first(values(studio_data(1).methods)).points))
    @test PDEStudio._by_position([3.0, 1.0, 2.0], [30, 10, 20]) == ([1.0, 2.0, 3.0], [10, 20, 30])

    # --- statistics: dependent fields over the dimensions they keep or swept parameters; the controls say how ---
    set_stat_preset!("hyperbolic")   # (statistics over time: the errors, the mass, ...)
    reset_plotter!()
    launch_plotter(config; style = :lines)
    @test occursin("studio_set!(:x_axis => :t, :u_axis => :l1error)", only(c for c in studio_controls() if c.name === :u_axis).label)
    err = try studio_set!(:u_axis => :l1error); "" catch e; sprint(showerror, e) end
    @test occursin("u_axis has no option :l1error", err) && occursin("The statistic :l1error: plotted over :t", err)
    # (one call, in any order: the axes first, then the dependent field they offer)
    studio_set!(:u_axis => :l1error, :x_axis => :t)
    s = studio_state()
    @test s.axes.x === :t && s.axes.u === :l1error && s.plots[1].ylabel == "L1Error"
    studio_set!(:u_axis => :l1error, :x_axis => :cfl)   # (over the swept parameter, at the time of the slider)
    @test studio_state().axes.x === :cfl && length(first(values(studio_data(1).methods)).x) == 4
    studio_set!(:x_axis => :x, :u_axis => :Solution)
    # (particle styles point to the grid styles)
    reset_plotter!()
    launch_plotter(test_particles_2d())
    @test occursin("in a grid style", only(c for c in studio_controls() if c.name === :u_axis).label)

    # --- a slider the comparison held can be set in the same call that ends the comparison ---
    reset_plotter!()
    launch_plotter(config)
    studio_set!(:compare_target => :cfl)
    r = studio_set!(:cfl => 0.75, :compare_target => :none)
    @test r.values[:cfl] == 0.75 && studio_state().compare.target === :none

    # --- names and numbers: tuple entries, capitals as written, small values ---
    @test PDEStudio.frontend_key.((:Grid_Ns__1, :PDE_tau, :Ns__all, :l1error, :cfl)) ==
          ("Grid Ns[1]", "PDE Tau", "Ns (all)", "L1Error", "Cfl")
    @test PDEStudio._fmt_value.((1e-5, 0.25, 0.0, 2.5e6, 3)) == ("1e-05", "0.250", "0.000", "2.5e+06", "3")

    # --- long method names in the titles of compared methods are broken into lines to fit the plot ---
    long = SimulationConfig(create_param_dict(:N => 32, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
                            create_method_dict(:upwind_first_order_scheme_without_limiter => create_param_dict(:scheme => "upwind"),
                                               :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")))
    reset_plotter!()
    launch_plotter(long; style = :lines)
    studio_set!(:compare_target => :methods, :plot_width => 300)
    drawn = [b.title[] for b in manager.master_fig.content if b isa Axis]
    @test "upwind_first_order_scheme_without_limiter" in [p.title for p in studio_state().plots]   # (the API: one line)
    @test any(t -> occursin("\n", t) && replace(t, "\n" => "") == "upwind_first_order_scheme_without_limiter", drawn)
    @test PDEStudio._fit_label("x" ^ 200, first(b for b in manager.master_fig.content if b isa Axis))[end] == '…'
    studio_set!(:plot_width => 500)

