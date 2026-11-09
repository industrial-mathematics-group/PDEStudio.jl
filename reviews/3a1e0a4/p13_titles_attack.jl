# Titles: datasets with other axis ends per sweep value, cost per slider move with a long sweep, cache size,
# NaN in an axis (headless)
using PDEStudio; using PDEStudio.Makie: Axis
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
ax() = only(b for b in M.master_fig.content if b isa Axis)
lines_(t) = count(==('\n'), t) + 1
vp() = Tuple(round.(Int, ax().scene.viewport[].origin)), Tuple(M.master_fig.scene.viewport[].widths)

println("== 1: T swept (the time axis ends differ per dataset)")
cfg = SimulationConfig(create_param_dict(:N => 40, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                         :sim_func_name => :solve_advection_1d),
                       create_method_dict(:fd => create_param_dict()), [:fd];
                       varied = create_varied_dict(:T => [1.0, 10.0], :scheme => ["upwind", "lax_wendroff"]))
launch_plotter(cfg; style = :lines)
found = false
for w in 250:5:700
    studio_set!(:plot_width => w)
    studio_set!(:T => 1.0); a = ax().title[]; va = vp()
    studio_set!(:T => 10.0); b = ax().title[]; vb = vp()
    if lines_(a) != lines_(b)
        println("width $w: T=1 -> ", repr(a), " ", va, "\n          T=10 -> ", repr(b), " ", vb)
        global found = true
        break
    end
end
found || println("no width where T changes the line count")
studio_set!(:T => 1.0); println("T=1 others of the time part: ", last(M.plot_title_parts[1][end]))
studio_set!(:T => 10.0); println("T=10 others of the time part: ", last(M.plot_title_parts[1][end]))

println("== 2: cost of a slider move, 3 vs 400 swept values")
for n in (3, 400)
    reset_plotter!()
    c = SimulationConfig(create_param_dict(:N => 8, :c => 1.0, :T => 0.05, :cfl => 0.5, :scheme => "upwind",
                                           :sim_func_name => :solve_advection_1d),
                         create_method_dict(:fd => create_param_dict()), [:fd];
                         varied = create_varied_dict(:cfl => collect(range(0.1, 0.9, length = n))))
    launch_plotter(c; style = :lines)
    vals = c.varied[:cfl]
    studio_set!(:cfl => vals[2]); studio_set!(:cfl => vals[1])
    parts = M.plot_title_parts[1]
    tp = @elapsed for k in 1:50; PDEStudio._title_values(1, true, :cfl, nothing); end
    tf = @elapsed for k in 1:50; PDEStudio._fit_title(parts, ax()); end
    ts = @elapsed for k in 1:10; studio_set!(:cfl => vals[mod1(k, n)]); end
    println("n=$n: _title_values $(round(1000tp/50, digits = 3)) ms, _fit_title $(round(1000tf/50, digits = 3)) ms, studio_set! $(round(1000ts/10, digits = 1)) ms; cache size ", length(PDEStudio._TEXT_WIDTHS))
end

println("== 3: _title_values with NaN / empty axes")
struct FakeData end
println(PDEStudio._fmt_value(NaN), " ", PDEStudio._fit_title(Tuple{String, Vector{String}}[], ax()) |> repr)
println("parts with NaN others: ", repr(PDEStudio._fit_title([("A = NaN", ["A = NaN"]), ("B = 1", String[])], ax())))
