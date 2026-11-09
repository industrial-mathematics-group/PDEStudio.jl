using PDEStudio
const P = @__DIR__
const m = PDEStudio.manager
res = Tuple{String, String, String}[]
function try_opt(scope, key, val)
    s = "studio_option!(:$scope, :$key, $(repr(val)))"
    try
        studio_option!(scope, key, val)
        st = studio_state().status
        println(rpad("OK", 5), s, "  -> stored ", repr(m.ui[scope][key]), "  [", st.level, "]")
        st.level === :error && println("        status: ", st.text)
    catch e
        println(rpad("ERR", 5), s, "  -> ", first(sprint(showerror, e), 160))
    end
end
tab(scope, key, txt) = (ok = PDEStudio._apply_editor_input!(:ui, scope, key, m.ui[scope], txt, nothing);
    println(rpad(ok ? "TAB+" : "TAB-", 5), ":$scope.$key <- ", repr(txt), "  -> stored ", repr(m.ui[scope][key]), "  [", studio_state().status.level, "]"))
reset(scope, key) = (m.ui[scope][key] = deepcopy(PDEStudio.MASTER_UI_DICT[scope in PDEStudio.UI_AXIS_SCOPES ? scope : scope][key]); studio_option!(scope, key, m.ui[scope][key]))
studio_headless!()
set_save_path!(mktempdir())
launch_plotter(test_advection_1d())
println("=== numbers")
for (sc, k, vals) in ((:plot_style, :line_width, (2, 2.5, 3.0, Inf, true)), (:x_axis_1d, :padding, (0, 0.1, 0.0)),
                      (:axis_general, :font_size, (20.5, 24)), (:x_axis_1d, :scale_offset, (1, 0.0)),
                      (:x_axis_1d, :label_offset, (10, 15.0)), (:outliers_extrema, :outlier_threshold, (2, 1.5)),
                      (:hud, :line_width, (2, 3.0)), (:hud, :marker_size, (10, 15.0)),
                      (:x_axis_1d, :tick_count, (5, 5.0, 0)), (:plot_style, :levels, (10, 10.0, 15)),
                      (:plot_style, :bottom_margin, (20.5, 60)), (:plot_style, :method_index, (2, 2.0, 0, 1)))
    for v in vals; try_opt(sc, k, v); end
end
println("=== lists")
for (sc, k, vals) in ((:plot_style, :color_range, ((0, 1), [0.0, 0.5], (1,), [])),
                      (:x_axis_1d, :lims, ((0.2, 0.8), [0, 1], (nothing, 1), [])),
                      (:y_axis_1d, :lims, ((0.0, 2.0), [])),
                      (:plot_style, :reference, ([1, 2], (1,), 2, [])),
                      (:plot_style, :markers, ((:circle, :rect), [:circle], PDEStudio.MASTER_UI_DICT[:plot_style][:markers])),
                      (:plot_style, :line_styles, ([(:dash, :dense)], PDEStudio.MASTER_UI_DICT[:plot_style][:line_styles])),
                      (:hud, :points, ([(0.2, 0.0), (0.8, 0.5)], ((0.2, 0.0), (0.8, 0.5)), [])))
    for v in vals; try_opt(sc, k, v); end
end
println("=== text / names")
for (sc, k, vals) in ((:x_axis_1d, :tick_format, ("{:.2f}", x -> string.(round.(x; digits = 1)), :default, "default")),
                      (:labels, :title, ("T", PDEStudio.Makie.LaTeXString("\$u(x)\$"), PDEStudio.Makie.rich("a", color = :red), "default")),
                      (:labels, :legend_label, ("M", "Methods")),
                      (:hud, :mode, ("scatter", :scatter, "lines")),
                      (:hud, :line_style, (:dot, (:dash, :dense), "dash", :dash)),
                      (:plot_style, :line_direction, (:vertical, "vertical", :horizontal)),
                      (:plot_style, :color_map, (:plasma, "plasma", PDEStudio.Makie.Reverse(:viridis), :viridis)))
    for v in vals; try_opt(sc, k, v); end
end
println("=== bools")
for (sc, k, vals) in ((:hud, :visible, (true, 1, false)), (:axis_general, :sort_legend, (false, true)))
    for v in vals; try_opt(sc, k, v); end
end
println("=== the UI tab with the same values")
tab(:hud, :line_style, "(:dash, :dense)"); tab(:hud, :line_style, ":dash")
tab(:x_axis_1d, :tick_count, "5.0"); tab(:x_axis_1d, :tick_count, "0")
tab(:plot_style, :bottom_margin, "20.5"); tab(:plot_style, :bottom_margin, "60")
tab(:plot_style, :method_index, "9"); tab(:plot_style, :method_index, "1")
tab(:hud, :mode, ":scatter"); tab(:hud, :mode, "lines")
println("=== HUD drawn with a tuple line style (the tab accepts it)")
studio_option!(:hud, :points, [(0.1, 0.1), (0.9, 0.9)]); studio_option!(:hud, :visible, true)
tab(:hud, :line_style, "(:dash, :dense)")
studio_snapshot(joinpath(P, "a03_hud_tuple_style.png"))
println("END")
