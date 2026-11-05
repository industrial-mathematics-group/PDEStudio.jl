# GUI probes of the UI area (GLMakie on the Xvfb display), in the style of test/runtests.jl
using PDEStudio, GLMakie, Test, StaticArrays
import PDEStudio: manager, show_tab!, show_editor_page!, preset_dir, sim_preset_dir
PDEStudioCore.set_target_module!(@__MODULE__)

function advection_solver_1d(params::ParamDict)
    N = params[:N]; cfl = get(params, :cfl, 0.5); dx = 2π / N; dt = cfl * dx
    Nt = ceil(Int, 2.0 / dt) + 1
    x = collect(range(0.0, step = dx, length = N)); t = collect(range(0.0, step = dt, length = Nt))
    u = fill(SVector{1, Float64}(0.0), N, Nt)
    for i in 1:N; u[i, 1] = SVector(sin(x[i]) + 2.0); end
    for n in 1:Nt-1, i in 1:N
        im1 = i == 1 ? N : i - 1
        u[i, n+1] = SVector(u[i, n][1] - cfl * (u[i, n][1] - u[im1, n][1]))
    end
    return create_sim_data(x, u, t, params; time_dim = :t, dims = :x)
end

set_save_path!(mktempdir())
reset_manager!()
set_mode!(:eulerian)
GLMakie.activate!()
click_button!(k) = (manager.widgets[k].clicks[] += 1; yield())
w() = manager.widgets
status() = replace(w()[:status][], '\n' => ' ')

shared = create_param_dict(:cfl => 0.5, :N => 20, :sim_func_name => :advection_solver_1d)
methods = create_method_dict(:upwind => create_param_dict(:scheme => "upwind"))
cfg = SimulationConfig(shared, methods, [:upwind])
fig = launch_plotter(); display(fig)
set_sim_config!(cfg)
click_button!(:run_button)

@testset "GUI probes" begin

@testset "probe: ◀ ▶ pages in the Files tab (preset file, preset list)" begin
    @test save_plot_preset("many_rows")
    click_button!(:tab_files)
    click_button!(:look_presets_button)
    i = findfirst(isequal(:many_rows), manager.editor_row_keys)
    w()[Symbol("method_row_", i, "_b")].clicks[] += 1   # Edit ›
    t1 = w()[:editor_title][]
    @show t1 length(manager.preset_file_rows)
    @test occursin("(1/", t1)
    @test w()[:editor_next].blockscene.visible[]          # the pager is shown ...
    keys1 = copy(manager.editor_row_keys)
    click_button!(:editor_next)
    @show w()[:editor_title][]
    @test occursin("(2/", w()[:editor_title][])            # ... but turning the page does nothing?
    @test manager.editor_row_keys != keys1

    # the list of presets: more than EDITOR_ROWS simulation presets
    for k in 1:PDEStudio.EDITOR_ROWS + 2
        save_sim_preset("p$(lpad(k, 2, '0'))")
    end
    click_button!(:editor_back)
    click_button!(:sim_presets_button)
    @show w()[:editor_title][]
    click_button!(:editor_next)
    @test occursin("(2/", w()[:editor_title][])
end

@testset "probe: ↺ on a display name restores the built-in name" begin
    show_editor_page!(:ui, :methods)
    i = findfirst(isequal(:upwind), manager.editor_row_keys)
    tb = w()[Symbol("editor_row_", i, "_text")]
    tb.stored_string[] = "Upwind scheme"; yield()
    @test manager.labels[:upwind] == "Upwind scheme"
    w()[Symbol("editor_row_", i, "_button")].clicks[] += 1; yield()
    @show manager.labels[:upwind]
    @test manager.labels[:upwind] == "Upwind"
end

@testset "probe: built-in :heatmap preset sets the axis variant of the plot it switches to" begin
    show_tab!(:plot)
    PDEStudio.set_plot_preset!()      # defaults; 1D lines active
    yield()
    @test manager.active_plot_type === :lines_1d
    y1d_pad = manager.ui[:y_axis_1d][:padding]
    set_plot_preset!(:heatmap)
    yield()
    @show manager.active_plot_type w()[:plot_style].selection[] manager.layout_cache[:plot_style]
    @show manager.ui[:x_axis_nd][:label_offset] manager.ui[:x_axis_1d][:label_offset] manager.ui[:y_axis_1d][:padding]
    @test manager.ui[:x_axis_nd][:label_offset] == 10.0    # what the heatmap reads
    @test manager.ui[:y_axis_1d][:padding] == y1d_pad      # the 1D settings are untouched
end

@testset "probe: renaming a variable relabels the axis menus" begin
    PDEStudio.set_plot_preset!(); yield()
    click_button!(:run_button)
    show_editor_page!(:ui, :variables)
    i = findfirst(isequal(:x), manager.editor_row_keys)
    w()[Symbol("editor_row_", i, "_text")].stored_string[] = "Space"; yield()
    @show w()[:x_axis].options[]
    @test any(o -> o[1] == "Space", w()[:x_axis].options[])
end

@testset "probe: Play Anim with 0 FPS / 0 s" begin
    show_tab!(:plot)
    manager.ui[:export][:animation_FPS] = 0
    ok = try
        click_button!(:play_anim_button); true
    catch e
        @show e; false
    end
    @show ok manager.is_animating[] status()
    manager.is_animating[] && click_button!(:play_anim_button)
    manager.ui[:export][:animation_FPS] = 30
    @test ok
end

@testset "probe: a second, different upload of a Julia file with the same name runs without the warning" begin
    code(N) = """SimulationConfig(create_param_dict(:N => $N, :cfl => 0.5, :sim_func_name => :advection_solver_1d),
                    create_method_dict(:upwind => create_param_dict(:scheme => "upwind")), [:upwind])\n"""
    PDEStudio.receive_upload!(["config.jl" => Vector{UInt8}(code(24))])
    @test occursin("click Load again", status()) && manager.active_config.shared[:N] == 20
    PDEStudio.receive_upload!(["config.jl" => Vector{UInt8}(code(33))])   # other content, same name
    @show status() manager.active_config.shared[:N]
    @test manager.active_config.shared[:N] != 33     # FAILS if the new code ran without a warning
end

end
