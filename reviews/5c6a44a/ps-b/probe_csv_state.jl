# Probe: full-state CSV export -> reload (window on the Xvfb display).
#   DISPLAY=:99 julia -t 4 --project=test <scratch>/probe_csv_state.jl
include(joinpath(@__DIR__, "probe_setup.jl"))
import PDEStudio: save_params_to_csv, load_and_apply_csv!, parse_csv_to_dict
w() = manager.widgets
@testset "CSV state round trip" begin
    click_menu!(w()[:plot_style], :lines_1d)
    click_menu!(w()[:x_axis], :x); click_menu!(w()[:y_axis], :none); click_menu!(w()[:z_axis], :none)
    click_button!(:layout_apply)
    set_close_to!(w()[manager.reverse_map[:cfl]], 0.4); yield()
    set_close_to!(w()[:t], 1.0); yield()
    t_saved = w()[:t].value[]
    manager.ui[:plot_style][:line_width] = 5.0
    manager.ui[:labels][:title] = "1e3"
    PDEStudio.set_label!(:upwind, "Upwind (1st order)")
    dir = mktempdir()
    @test save_params_to_csv("state", dir, Dict("Save Type" => "probe"))
    path = joinpath(dir, "state.csv")
    parsed = parse_csv_to_dict(path)
    println("Scene/Plot rows: ", parsed["Scene"]["Plot"])
    println("Camera rows: ", get(parsed["Scene"], "Camera", nothing))

    @testset "reload into the same window (same data)" begin
        set_close_to!(w()[manager.reverse_map[:cfl]], 0.2); yield()
        manager.ui[:plot_style][:line_width] = 2.0
        manager.ui[:labels][:title] = "other"
        load_and_apply_csv!(path); yield()
        click_button!(:run_button); yield()
        println("same window: cfl slider = ", w()[manager.reverse_map[:cfl]].value[], ", t = ", w()[:t].value[],
                ", line_width = ", manager.ui[:plot_style][:line_width], ", title = ", repr(manager.ui[:labels][:title]),
                ", label = ", PDEStudio.frontend_key(:upwind), ", camera_locked = ", manager.camera_locked[])
        @test w()[manager.reverse_map[:cfl]].value[] == 0.4
        @test manager.ui[:plot_style][:line_width] == 5.0
        @test manager.ui[:labels][:title] == "1e3"
        @test w()[:t].value[] ≈ t_saved
    end

    @testset "reload while other data (other sweep values) is shown" begin
        other = deepcopy(config); other.varied[:cfl] = [0.1, 0.15]
        set_sim_config!(other); click_button!(:run_button); yield()
        println("other data shown: cfl range ", w()[manager.reverse_map[:cfl]].range[])
        load_and_apply_csv!(path); yield()
        println("  slider_cache after load: ", manager.slider_cache)
        click_button!(:run_button); yield()
        println("  after Run: cfl range ", w()[manager.reverse_map[:cfl]].range[], ", value ", w()[manager.reverse_map[:cfl]].value[],
                "; active cfl sweep ", manager.active_config.varied[:cfl])
        @test w()[manager.reverse_map[:cfl]].value[] == 0.4
    end
end
reset_plotter!()
