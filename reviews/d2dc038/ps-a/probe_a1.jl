include(joinpath(@__DIR__, "common.jl"))

nlist(o) = length(o.listeners)

@testset "ps-a probe 1" begin
    fig = open_studio()
    w = manager.widgets

    @testset "N1: a failed export leaves the export figure's render listeners attached" begin
        click_button!(:layout_apply)
        base = Dict(k => nlist(manager.triggers[k]) for k in (:Plot, :Slider, :PlotData, :UI))
        @info "listeners before" base
        # a good static export first: the count must come back to the same numbers
        w[:export_text].stored_string[] = joinpath(mktempdir(), "ok_export")
        manager.ui[:export][:save_formats] = ["png"]
        click_button!(:export_button)
        good = Dict(k => nlist(manager.triggers[k]) for k in keys(base))
        @info "after a good export" good status()
        @test good == base
        # an animation export that fails inside the try block (animation_FPS = NaN, typed as `NaN` in the editor)
        manager.ui[:export][:animation_FPS] = NaN
        w[:anim_target].i_selected[] = findfirst(o -> o[2] === :t, w[:anim_target].options[])
        w[:export_text].stored_string[] = "anim_fail.mp4"
        click_button!(:export_button)
        bad = Dict(k => nlist(manager.triggers[k]) for k in keys(base))
        @info "after a failed export" bad status()
        @test occursin("Export failed", status())
        @test bad == base     # expected to FAIL: the export figure's listeners stay
        manager.ui[:export][:animation_FPS] = 30
        # the leaked handlers keep running: count plot-trigger handler runs
        n_before = manager.triggers[:Plot].listeners |> length
        click_button!(:plot_button)
        @test isempty(PDEStudio.manager.caches) == false
    end

    @testset "N1b: can NaN be typed into animation_FPS through the editor?" begin
        show_tab!(:files)
        click_button!(:export_settings_button)
        type_into!(:animation_FPS, "NaN")
        @info "animation_FPS after typing NaN" manager.ui[:export][:animation_FPS] status()
        @test !(manager.ui[:export][:animation_FPS] isa Float64 && isnan(manager.ui[:export][:animation_FPS]))
        manager.ui[:export][:animation_FPS] = 30
        click_button!(:editor_back)
    end

    @testset "N2: renaming a variable or component flags Apply Layout / Update Plot" begin
        show_tab!(:plot)
        click_button!(:layout_apply)
        click_button!(:plot_button)
        @test !manager.flags[:Layout][] && !manager.flags[:Plot][]
        show_editor_page!(:ui, :variables)
        type_into!(:cfl, "CFL number")
        @info "after renaming :cfl" manager.flags[:Layout][] manager.flags[:Plot][] [o[1] for o in w[:compare_target].options[]] [o[1] for o in w[:anim_target].options[]]
        @test any(o -> o[1] == "CFL number", w[:anim_target].options[])
        @test !manager.flags[:Layout][]     # expected to FAIL if the relabel flags a rebuild
        @test !manager.flags[:Plot][]
        show_tab!(:plot); click_button!(:layout_apply); click_button!(:plot_button)
        show_editor_page!(:ui, :components)
        type_into!(:component_1, "Density")
        @info "after renaming component_1" manager.flags[:Layout][] manager.flags[:Plot][] w[:component].options[]
        @test !manager.flags[:Plot][]
    end

    @testset "N3: compact3d writes the 3D label offsets into the 1D axis variants while a 1D plot is shown" begin
        show_tab!(:plot)
        @test manager.active_plot_type === :lines_1d
        x1d = manager.ui[:x_axis_1d][:label_offset]; xnd = manager.ui[:x_axis_nd][:label_offset]
        set_plot_preset!(:compact3d); yield()
        @info "label offsets" manager.ui[:x_axis_1d][:label_offset] manager.ui[:x_axis_nd][:label_offset] manager.ui[:z_axis_3d][:label_offset]
        @test manager.ui[:x_axis_nd][:label_offset] == 5.0   # expected to FAIL
        @test manager.ui[:x_axis_1d][:label_offset] == x1d   # expected to FAIL
        @test haskey(manager.ui[:axis_general], :legend_pos)  # a key nothing reads
    end
end
