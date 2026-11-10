# Attacks on 3a1e0a4's _title_values (slider range) and the slot-remap cache drop (headless).
using PDEStudio; using PDEStudio.Makie: Axis, Axis3
studio_headless!()
sp = mktempdir(); set_save_path!(sp)
const M = PDEStudio.manager
w() = M.widgets
axs() = [b for b in M.master_fig.content if b isa Axis || b isa Axis3]
nl(t) = count(==('\n'), t) + 1
tsweep(Ts = [1.0, 10.0]) = SimulationConfig(create_param_dict(:N => 40, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                                  :sim_func_name => :solve_advection_1d),
                                create_method_dict(:fd => create_param_dict()), [:fd]; varied = create_varied_dict(:T => Ts, :cfl => [0.25, 0.5]))
tw(str) = PDEStudio._text_width(str, axs()[1].titlefont[], Float64(M.ui[:axis_general][:title_size]))
sl() = [(x.name, x.value) for x in studio_state().sliders]
others() = [last(p) for p in M.plot_title_parts[1]]

println("== T1: first draw after binding a T sweep into an open window of another setup (t range reset to [0.0])")
launch_plotter(test_heat_2d(); style = :lines)
cfg = tsweep()
crit = round(Int, (tw("T = 10.000 | cfl = 0.250 | Time (T) = 1.000") + tw("T = 10.000 | cfl = 0.250 | Time (T) = 10.000")) / 2)
studio_set!(:plot_width => crit)
set_sim_config!(cfg); force_simulation()
a = axs()[1].title[]; oa = others(); ra = w()[:t].range[]
studio_set!(:T => 10.0); b = axs()[1].title[]
studio_set!(:T => 1.0); c = axs()[1].title[]
println("width $crit: after run ", repr(a), " (lines ", nl(a), ") t range ends ", (first(ra), last(ra)), "\n   others ", oa)
println("   T=10 ", repr(b), " (", nl(b), "); back to T=1 ", repr(c), " (", nl(c), ")")

println("== T2: T not swept, changed in the editor from 1 to 10, Run (stale t range at the Plot tier)")
reset_plotter!()
cfg2 = tsweep(); delete!(cfg2.varied, :T); cfg2.varied[:N] = [40, 41]
launch_plotter(cfg2; style = :lines)
crit2 = round(Int, (tw("N = 40 | cfl = 0.250 | Time (T) = 1.000") + tw("N = 40 | cfl = 0.250 | Time (T) = 10.000")) / 2)
studio_set!(:plot_width => crit2)
println("T=1 run: ", repr(axs()[1].title[]))
M.active_config.shared[:T] = 10.0; M.flags[:Simulation][] = true
w()[:run_button].clicks[] += 1
a = axs()[1].title[]; oa = others()
studio_set!(:cfl => 0.5); b = axs()[1].title[]
println("T=10 after Run: ", repr(a), " (", nl(a), ") others ", oa, "\n   after a slider move: ", repr(b), " (", nl(b), ")")

println("== T3: x leaves the x axis (x slider [0.0] until the slider step): first draw vs after a move")
reset_plotter!()
cfg3 = SimulationConfig(create_param_dict(:N => 40, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                          :sim_func_name => :solve_advection_1d),
                        create_method_dict(:fd => create_param_dict()), [:fd]; varied = create_varied_dict(:cfl => [0.25, 0.5]))
launch_plotter(cfg3; style = :lines)
studio_set!(:x_axis => :t)
a = axs()[1].title[]; oa = others(); rx = w()[:x].range[]
studio_set!(:cfl => 0.5); b = axs()[1].title[]
println("x-axis t: ", repr(a), " others ", oa, " x range ", (first(rx), last(rx), length(rx)), "\n   after move: ", repr(b))

println("== T4: compare by cfl with a T sweep: subplot titles (labels) and stored parts")
reset_plotter!()
launch_plotter(tsweep(); style = :lines)
studio_set!(:compare_target => :cfl)
println("compare titles: ", [repr(ax.title[]) for ax in axs()], " parts others: ", [last.(p) for p in M.plot_title_parts])
studio_set!(:compare_target => :time)
println("compare time titles: ", [repr(ax.title[]) for ax in axs()][1:2], " t range ", w()[:t].range[])

println("== T5: Lagrangian (particles), dt sweep: titles and the t slider")
reset_plotter!()
launch_plotter(test_particles_2d(); style = :particles)
println("title ", repr(axs()[1].title[]), " others ", others(), " t range ends ", (first(w()[:t].range[]), last(w()[:t].range[])))
studio_set!(:dt => 0.01); println("dt=0.01 title ", repr(axs()[1].title[]))

println("== S1: two-step sweep edit: remove the last parameter, then add another that sorts last")
reset_plotter!()
c4 = tsweep()   # varied T, cfl -> param_1 = T, param_2 = cfl
launch_plotter(c4; style = :lines)
studio_set!(:cfl => 0.5)
println("start ", sl(), " cache ", filter(p -> startswith(string(p[1]), "param"), M.slider_cache), " map ", M.param_map)
delete!(M.active_config.varied, :cfl); PDEStudio._after_raw_change!(:sweep, "cfl removed")
w()[:run_button].clicks[] += 1
println("cfl removed + Run ", sl(), " cache ", filter(p -> startswith(string(p[1]), "param"), M.slider_cache), " map ", M.param_map)
M.active_config.varied[:scheme] = ["upwind", "lax_friedrichs", "lax_wendroff"]; PDEStudio._after_raw_change!(:sweep, "scheme added")
w()[:run_button].clicks[] += 1
println("scheme added + Run ", sl(), " (a fresh window starts at upwind)")

println("== S2: CSV of the same setup with slider positions out of range (pending), then a sweep edit")
reset_plotter!()
c5 = tsweep()
launch_plotter(c5; style = :lines)
studio_set!(:T => 10.0, :cfl => 0.5)
PDEStudio.save_params_to_csv("tview", sp, Dict("Save Type" => "probe"))
studio_set!(:T => 1.0, :cfl => 0.25)
set_sim_config!(joinpath(sp, "tview.csv"))
println("CSV loaded: cache ", filter(p -> startswith(string(p[1]), "param"), M.slider_cache), " pending ", M.pending_sliders)
w()[:run_button].clicks[] += 1
println("CSV + Run ", sl())

println("== S3: set_max_params!(1) then 2 with a 2-parameter sweep (slot 2 appears)")
reset_plotter!()
c6 = tsweep()
launch_plotter(c6; style = :lines)
studio_set!(:cfl => 0.5, :T => 10.0)
set_max_params!(1); launch_plotter(c6; style = :lines)
println("max 1: ", sl(), " map ", M.param_map)
set_max_params!(2); launch_plotter(c6; style = :lines)
println("max 2: ", sl(), " map ", M.param_map)
