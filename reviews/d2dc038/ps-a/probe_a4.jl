include(joinpath(@__DIR__, "common.jl"))
@testset "ps-a probe 4" begin
    fig = open_studio()
    w = manager.widgets
    @testset "Advanced sweep: an empty vector" begin
        show_editor_page!(:advanced, :sweep)
        ok = try
            type_into!(:cfl, "[]"); true
        catch e
            @info "typing [] into the sweep threw out of the handler" exception = e
            false
        end
        @test ok
        @info "sweep now" manager.active_config.varied status()
        ok2 = try
            click_button!(:run_button); true
        catch e
            @info "Run threw" exception = e
            false
        end
        @test ok2
        @info "after run" status()
    end
    @testset "Advanced: a sweep with one value / a method named like a sentinel" begin
        show_editor_page!(:advanced, PDEStudio.ADV_METHODS)
        w[:method_add_name].stored_string[] = "#order"
        ok = try
            click_button!(:method_add_button); true
        catch e
            @info "adding #order threw" exception = e
            false
        end
        @info "methods" collect(keys(manager.active_config.methods)) w[:editor_title][]
        manager.method_filter = :all
        show_editor_page!(:methods)
        i = findfirst(isequal(Symbol("#order")), manager.editor_row_keys)
        if !isnothing(i)
            w[Symbol("method_row_", i, "_b")].clicks[] += 1; yield()   # Edit ›
            @info "Edit › of #order shows" w[:editor_title][]
            @test w[:editor_title][] != "Drawing order (top first)"
        end
    end
end
