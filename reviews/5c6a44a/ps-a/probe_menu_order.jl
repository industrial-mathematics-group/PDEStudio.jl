# update_menu_safe! sorts every menu by its label: the component menu with >= 10 components or custom labels
using PDEStudio, Test
const P = PDEStudio
@testset "probe: component menu order" begin
    fig = P.Figure()
    m = P.Menu(fig[1, 1], options = Any[("Component 1", 1)])
    opts = Any[("Component $i", i) for i in 1:11]
    P.update_menu_safe!(m, opts; fallbacks = [1])
    @show [o[2] for o in m.options[]]
    @test [o[2] for o in m.options[]] == 1:11              # component order expected
    P.update_menu_safe!(m, Any[("Density", 1), ("Momentum", 2), ("Energy", 3)]; fallbacks = [1])
    @show [o[1] for o in m.options[]]
    @test [o[2] for o in m.options[]] == 1:3
end
