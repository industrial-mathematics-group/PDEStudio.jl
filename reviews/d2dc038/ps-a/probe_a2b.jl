include(joinpath(@__DIR__, "common.jl"))

rootscene(s) = isnothing(s.parent) ? s : rootscene(s.parent)
function cache_plots_in(fig)
    ps = [p for (_, d) in manager.caches for (_, pc) in d for p in values(pc.primitives) if p isa Makie.AbstractPlot]
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
        ax = first(c for c in fig.content if c isa Axis); lp = first(p for p in ax.scene.plots if p isa Lines); y0 = copy(lp[1][]); @info "main lines before" length(y0)
        set_close_to!(w[:t], w[:t].range[][end]); yield()
        @info "slider moved" cache_plots_in(fig) (lp[1][] != y0)
        @test lp[1][] != y0
        # a second failed export stacks another set
        w[:export_text].stored_string[] = "anim_fail2.mp4"
        manager.ui[:export][:animation_FPS] = NaN
        click_button!(:export_button)
        manager.ui[:export][:animation_FPS] = 30
        @info "listeners after 2 failed exports" length(manager.triggers[:Plot].listeners)
        @test length(manager.triggers[:Plot].listeners) == 1
    end

    end
