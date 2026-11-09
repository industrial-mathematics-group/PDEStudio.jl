# Titles: line breaks, layout size, narrow widths, " | " in values, compare, Axis3 (headless CairoMakie)
using PDEStudio; using PDEStudio.Makie: Axis, Axis3
studio_headless!()
set_save_path!(mktempdir())
const M = PDEStudio.manager
out = joinpath(@__DIR__, "img"); mkpath(out)
axes_() = [b for b in M.master_fig.content if b isa Axis || b isa Axis3]
figsize() = Tuple(M.master_fig.scene.viewport[].widths)
info(tag) = (ax = first(axes_()); println(rpad(tag, 34), "fig=", figsize(), " axvp=", Tuple(round.(Int, ax.scene.viewport[].widths)),
             " lines=", count(==('\n'), ax.title[]) + 1, " title=", repr(ax.title[])))

cfg = SimulationConfig(create_param_dict(:N => 100, :c => 1.0, :T => 1.0, :cfl => 0.5, :scheme => "upwind",
                                         :tag => "a", :sim_func_name => :solve_advection_1d),
                       create_method_dict(:fd => create_param_dict()), [:fd];
                       varied = create_varied_dict(:scheme => ["upwind", "lax_friedrichs", "lax_wendroff"],
                                                   :tag => ["a | b", "c"]))
launch_plotter(cfg)
info("default 500")
f = first(axes_())
for w in (500, 450, 420, 400, 380, 350)
    studio_set!(:plot_width => w)
    info("width $w")
end
# find a width where scheme changes the line count
for w in 300:10:600
    studio_set!(:plot_width => w)
    studio_set!(:scheme => "upwind"); n1 = count(==('\n'), first(axes_()).title[])
    studio_set!(:scheme => "lax_friedrichs"); n2 = count(==('\n'), first(axes_()).title[])
    if n1 != n2
        println("width $w: upwind -> $(n1+1) lines, lax_friedrichs -> $(n2+1) lines")
        studio_set!(:scheme => "upwind"); info("  upwind");  studio_snapshot(joinpath(out, "t_w$(w)_upwind.png"); area = :window)
        studio_set!(:scheme => "lax_friedrichs"); info("  lax_friedrichs"); studio_snapshot(joinpath(out, "t_w$(w)_lf.png"); area = :window)
        break
    end
end
println("== tag value with ' | ' inside")
studio_set!(:plot_width => 500, :scheme => "upwind", :tag => "a | b")
info("tag 'a | b' w500")
studio_set!(:plot_width => 200)
info("tag 'a | b' w200")
println("state: ", studio_state().plots[1].title)
println("== very narrow / single long part")
studio_set!(:plot_width => 50)
info("width 50")
studio_snapshot(joinpath(out, "t_w50.png"); area = :window)
studio_set!(:plot_width => 500)
println("== compare time")
studio_set!(:compare_target => :time)
for ax in axes_(); println("  compare title: ", repr(ax.title[])); end
studio_snapshot(joinpath(out, "t_compare.png"); area = :window)
studio_set!(:compare_target => :none)
println("== Axis3 (heatmap_surface)")
studio_set!(:plot_style => :heatmap_surface)
info("surface")
studio_snapshot(joinpath(out, "t_surface.png"); area = :window)
println("== custom title with ' | '")
studio_option!(:labels, :title, "Run A | long custom title that does not fit at all into the plot width")
info("custom")
studio_option!(:labels, :title, "default")
println("== title size option bigger")
studio_set!(:plot_style => :lines_1d)
studio_option!(:axis_general, :title_size, 40)
info("title_size 40")
studio_snapshot(joinpath(out, "t_size40.png"); area = :window)
println(sprint(describe_studio))
