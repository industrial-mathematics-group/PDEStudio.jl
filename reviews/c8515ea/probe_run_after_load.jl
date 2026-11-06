# c8515ea: Run Simulation after loading an export. PDEStudioCore's run_all_simulations re-includes config.sources
# (`_load_sources`, plain Base.include at the file's own path). The copies are the sources now, so they run again
# from `<name>_sources/`, without the as-original path and without the include redirection.
using Test, PDEStudio, GLMakie
const P = PDEStudio
include(joinpath(@__DIR__, "solver.jl"))
set_save_path!(mktempdir())
w() = P.manager.widgets
status() = replace(w()[:status][], '\n' => ' ')
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
fig = launch_plotter(); display(fig)
cfg(pre, n; sources = "String[]") = pre * """
    SimulationConfig(create_param_dict(:N => $n, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:upwind => create_param_dict()), [:upwind]; sources = $sources)
    """
function case(tag; files, pre, n, edit = _ -> nothing, src = nothing)
    dir = mktempdir(); out = mktempdir()
    for (f, t) in files; write(joinpath(dir, f), t); end
    write(joinpath(dir, "cfg.jl"), cfg(pre, n; sources = !isnothing(src) ? src : occursin("abs.jl", pre) ? "[" * repr(match(r"include\((\"[^\"]*\")", pre)[1][2:end-1]) * "]" : "String[]"))
    P.load_config_file!(joinpath(dir, "cfg.jl")); exp!("exp", out)
    edit(dir)
    P._handle_load(joinpath(out, "exp.csv"))
    loaded = (N = P.manager.active_config.shared[:N], failures = copy(P.manager.source_failures))
    err = try
        w()[:run_button].clicks[] += 1; yield(); ""
    catch e
        sprint(showerror, e isa LoadError ? e.error : e)[1:min(end, 110)] * " -- status line: " * status()[1:min(end, 50)]
    end
    println(rpad(tag, 46), "load: N = $(loaded.N), failures = $(loaded.failures)\n", " "^46, "Run: ",
            isempty(err) ? "ok, status = $(status()[1:min(end, 60)])" : "THROWS $err")
    return isempty(err)
end
@testset "all" begin
@testset "run after load" begin
    @test case("A: listed helper by name, unchanged (control)"; files = ["h.jl" => "hN() = 20\n"],
               pre = "include(\"h.jl\")\n", n = "hN()", src = "[joinpath(@__DIR__, \"h.jl\")]")
    @test case("C: unlisted helper, originals unchanged"; files = ["u.jl" => "uN() = 20\n"],
               pre = "include(\"u.jl\")\n", n = "uN()")
    @test case("D: data file via @__DIR__, originals unchanged"; files = ["n.txt" => "20"],
               pre = "n0 = parse(Int, read(joinpath(@__DIR__, \"n.txt\"), String))\n", n = "n0")
    ah = joinpath(mktempdir(), "abs.jl"); write(ah, "aN() = 20\n")
    @test case("K: listed helper by absolute path, edited"; files = String[] .=> String[],
               pre = "include($(repr(ah)))\n", n = "aN()",
               edit = d -> write(ah, "aN() = error(\"edited original ran\")\n"))
end
@testset "failed source, solvers defined some other way (docs: define them before Run)" begin
    # the unlisted helper is gone: the load reports the failure; the solver advection_solver_1d is defined (solver.jl)
    @test case("E: unlisted helper deleted after the export"; files = ["u.jl" => "uN() = 20\n"],
               pre = "include(\"u.jl\")\n", n = "20", edit = d -> rm(joinpath(d, "u.jl")))
end
end
