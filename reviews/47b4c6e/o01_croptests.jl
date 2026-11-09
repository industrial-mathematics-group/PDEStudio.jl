# The new snapshot tests of the agent group, run with either src (env_old = 691bed7's src).
using PDEStudio, Test, StaticArrays
include(joinpath(@__DIR__, "o01_simfuncs.jl"))
studio_headless!()
set_save_path!(mktempdir()); snapdir = mktempdir()
config = SimulationConfig(create_param_dict(:N => 64, :cfl => 0.5, :tag => "a", :sim_func_name => :advection_solver_1d),
                          create_method_dict(:upwind => create_param_dict(:scheme => "upwind"),
                                             :lax_friedrichs => create_param_dict(:scheme => "lax_friedrichs")),
                          [:upwind, :lax_friedrichs]; varied = create_varied_dict(:cfl => [0.25, 0.5, 0.75, 1.0], :tag => ["a", "b"]),
                          reference = :exact_advection_factory)
launch_plotter(config)
f_plots = studio_snapshot(joinpath(snapdir, "plots.png"))
f_window = studio_snapshot(joinpath(snapdir, "window.png"); area = :window)
img_p, img_w = (PDEStudio.Makie.FileIO.load(f) for f in (f_plots, f_window))
box = PDEStudio._plot_layout().layoutobservables.computedbbox[]
r_top = size(img_w, 1) - round(Int, box.origin[2] + box.widths[2]); c_left = round(Int, box.origin[1])
hits = [(r, c) for r in max(1, r_top - 12):(r_top + 12), c in max(1, c_left - 40):(c_left + 12)
        if r + size(img_p, 1) - 1 <= size(img_w, 1) && c + size(img_p, 2) - 1 <= size(img_w, 2) &&
           img_w[r:r + size(img_p, 1) - 1, c:c + size(img_p, 2) - 1] == img_p]
println("crop content hits: ", length(hits), " r_top=", r_top, " c_left=", c_left, " sizes ", size(img_p), size(img_w)); for r in 1:size(img_w,1)-size(img_p,1)+1, c in 1:size(img_w,2)-size(img_p,2)+1; img_w[r,c] == img_p[1,1] && img_w[r:r+size(img_p,1)-1, c:c+size(img_p,2)-1] == img_p && (println("found at ", (r,c)); break); end
studio_set!(:compare_target => :methods, :compare_columns => 2)
studio_set!(:compare_link => :decoupled)
studio_set!(:plot_style => :heatmap_flat); studio_set!(:y_axis => :t)
f1 = studio_snapshot(joinpath(@__DIR__, "o01_decoupled1_$(ARGS[1]).png"); plot = 1)
sub1 = PDEStudio.Makie.FileIO.load(f1)
cmap = count(p -> abs(p.r - p.g) + abs(p.g - p.b) > 0.3, sub1[:, end - 120:end])
println("decoupled1 size ", size(sub1), " cmap = ", cmap, "  (test: > 200)")
