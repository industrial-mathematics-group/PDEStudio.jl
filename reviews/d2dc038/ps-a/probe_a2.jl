include(joinpath(@__DIR__, "common.jl"))

rootscene(s) = isnothing(s.parent) ? s : rootscene(s.parent)
function cache_plots_in(fig)
    ps = [p for c in manager.caches for (_, pc) in c for p in values(pc.primitives) if p isa Makie.AbstractPlot]
    isempty(ps) && return missing
    return all(p -> rootscene(Makie.parent_scene(p)) === fig.scene, ps)
end

@testset "ps-a probe 2" begin
    fig = open_studio()
    w = manager.widgets

    @testset "N1 (impact): after a failed export the plot caches belong to the export figure" begin
        click_button!(:layout_apply)
        @test cache_plots_in(fig) === true
        manager.ui[:export][:animation_FPS] = NaN
        w[:anim_target].i_selected[] = findfirst(o -> o[2] === :t, w[:anim_target].options[])
        w[:export_text].stored_string[] = "anim_fail.mp4"
        click_button!(:export_button)
        manager.ui[:export][:animation_FPS] = 30
        @info "after the failed export (before any update)" cache_plots_in(fig)
        click_button!(:plot_button)
        @info "after Update Plot" cache_plots_in(fig)
        @test cache_plots_in(fig) === true
        # slider move: does the main window's plot change?
        main_plot = first(p for c in manager.caches for (_, pc) in c for p in values(pc.primitives) if p isa Makie.AbstractPlot)
        set_close_to!(w[:t], w[:t].range[][end]); yield()
        @info "slider moved" cache_plots_in(fig)
        # a second failed export stacks another set
        w[:export_text].stored_string[] = "anim_fail2.mp4"
        manager.ui[:export][:animation_FPS] = NaN
        click_button!(:export_button)
        manager.ui[:export][:animation_FPS] = 30
        @info "listeners after 2 failed exports" length(manager.triggers[:Plot].listeners)
        @test length(manager.triggers[:Plot].listeners) == 1
    end

    @testset "N4: a hand-written preset that isn't in the 4-column layout breaks the preset file page" begin
        mkpath(PDEStudio.sim_preset_dir())
        # a valid studio CSV for _read_csv? (spaces after commas are accepted by the loader)
        write(joinpath(PDEStudio.sim_preset_dir(), "spaced.csv"),
              "Category, Scope, Parameter, Value\nMetadata, Preset, description, spaced header\nSimulation, Shared, N, 40\n")
        show_tab!(:files)
        click_button!(:sim_presets_button)
        @test :spaced in manager.editor_row_keys
        ok = try
            press_preset!(:spaced, :b); true
        catch e
            @info "Edit › of 'spaced' threw" exception = e
            false
        end
        @test ok
        @info "editor title / rows" w[:editor_title][] manager.preset_file_rows
        # Apply works for it (the loader accepts the spaces)
        try
            click_button!(:editor_back)
        catch e
            @info "Back threw" exception = e
        end
        ok2 = try
            show_editor_page!(:files, PDEStudio.PRESET_LIST); press_preset!(:spaced, :a); true
        catch e
            @info "Apply of 'spaced' threw" exception = e
            false
        end
        @test ok2
        @info "after apply" manager.active_config.shared[:N] status()
        # a malformed preset: Apply throws out of the click handler (no status message)
        write(joinpath(PDEStudio.sim_preset_dir(), "broken.csv"), "Category,Scope,Value\nSimulation,Shared,40\n")
        show_editor_page!(:files, PDEStudio.PRESET_LIST)
        click_button!(:sim_presets_button)
        st = status()
        ok3 = try
            press_preset!(:broken, :a); true
        catch e
            @info "Apply of 'broken' threw out of the click handler" exception = e
            false
        end
        @test ok3
        @info "status after apply of broken" status() (status() == st)
    end
end
