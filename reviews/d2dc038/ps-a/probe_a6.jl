include(joinpath(@__DIR__, "common.jl"))
@testset "ps-a probe 6: <empty> on the label pages and nested empty text" begin
    fig = open_studio()
    show_editor_page!(:ui, :methods)
    type_into!(:upwind, "<empty>")
    @info "label after typing <empty>" repr(manager.labels[:upwind]) editor_row(:upwind).text.displayed_string[]
    @test manager.labels[:upwind] == ""          # docs: `<empty>` stands for the empty string
    # Advanced tab: a vector with an empty text is shown as String[<empty>, "a"]; Enter on the unchanged row is refused
    manager.active_config.shared[:tags] = ["", "a"]
    show_editor_page!(:advanced, :shared)
    shown = editor_row(:tags).text.displayed_string[]
    type_into!(:tags, shown)
    @info "nested empty text" shown status() manager.active_config.shared[:tags]
    @test !occursin("no literal", status())
end
