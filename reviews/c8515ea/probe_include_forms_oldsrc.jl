# c8515ea: which version runs for each include form, after the listed originals were edited (1 -> 2)?
# "copy" = the exported version ran (the rule), "ORIGINAL" = the edited original ran, "FAIL" = the load failed.
using Test, PDEStudio
const P = PDEStudio
set_save_path!(mktempdir())
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
cfgend(expr; listed) = """
    SimulationConfig(create_param_dict(:N => $expr, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m];
                     sources = [$(join(["joinpath(@__DIR__, $(repr(l)))" for l in listed], ", "))])
    """
# files: name => text with VAL as the version; cfg: the config body (before the SimulationConfig)
function run_case(tag; files, body, expr, listed, after = nothing, gone = false)
    dir = mktempdir(); out = mktempdir()
    write_all(v) = for (n, t) in files
        mkpath(dirname(joinpath(dir, n)))
        write(joinpath(dir, n), replace(t, "VAL" => string(v)))
    end
    write_all(1)
    write(joinpath(dir, "cfg.jl"), body * cfgend(expr; listed))
    reset_manager!()
    ok0 = try P.load_config_file!(joinpath(dir, "cfg.jl")); true catch e; println(rpad(tag, 44), "LOAD OF THE ORIGINAL FAILED: ", sprint(showerror, e)[1:min(end, 150)]); false end
    ok0 || return
    n0 = P.manager.active_config.shared[:N]
    exp!("exp", out)
    write_all(2)
    gone && rm(dir; recursive = true)
    reset_manager!()
    P.load_and_apply_csv!(joinpath(out, "exp.csv"))
    f = copy(P.manager.source_failures)
    n = isnothing(P.manager.active_config) || !isempty(f) ? nothing : P.manager.active_config.shared[:N]
    verdict = !isempty(f) ? "FAIL" : n == n0 ? "copy" : "ORIGINAL"
    println(rpad(tag, 44), rpad(verdict, 9), " N0 = $n0, N = $n, note = $(repr((hasproperty(P.manager, :source_note) ? P.manager.source_note : "")))", isempty(f) ? "" : "  failures = $(first(f, 1))")
    isnothing(after) || after()
    return verdict
end
h(name) = "$(name)() = VAL\n"

r = Dict{String, Any}()
r["plain"] = run_case("include(\"h.jl\")"; files = ["h.jl" => h("hA")], body = "include(\"h.jl\")\n", expr = "hA()", listed = ["h.jl"])
r["joinpath"] = run_case("include(joinpath(@__DIR__, \"h.jl\"))"; files = ["h.jl" => h("hB")],
    body = "include(joinpath(@__DIR__, \"h.jl\"))\n", expr = "hB()", listed = ["h.jl"])
r["module"] = run_case("module M ... include ... end"; files = ["h.jl" => h("hC")],
    body = "module MC\ninclude(\"h.jl\")\nend\n", expr = "MC.hC()", listed = ["h.jl"])
r["function"] = run_case("include in a function body"; files = ["h.jl" => h("hD")],
    body = "loadD() = include(\"h.jl\")\nloadD()\n", expr = "Base.invokelatest(hD)", listed = ["h.jl"],
    after = () -> try Base.invokelatest(Main.loadD); println("   ... loadD() called later -> hD() = ", Base.invokelatest(Main.hD)) catch e; println("   ... loadD() called later fails: ", sprint(showerror, e)[1:80]) end)
r["mapexpr"] = run_case("include(identity, \"h.jl\")"; files = ["h.jl" => h("hE")],
    body = "include(identity, \"h.jl\")\n", expr = "hE()", listed = ["h.jl"])
r["Base.include"] = run_case("Base.include(@__MODULE__, \"h.jl\")"; files = ["h.jl" => h("hF")],
    body = "Base.include(@__MODULE__, \"h.jl\")\n", expr = "hF()", listed = ["h.jl"])
r["unlisted->listed"] = run_case("unlisted u.jl includes listed h.jl"; files = ["h.jl" => h("hG"), "u.jl" => "include(\"h.jl\")\n"],
    body = "include(\"u.jl\")\n", expr = "hG()", listed = ["h.jl"])
r["nested"] = run_case("listed a.jl includes listed h.jl"; files = ["h.jl" => h("hH"), "a.jl" => "include(\"h.jl\")\naH() = VAL\n"],
    body = "include(\"a.jl\")\n", expr = "hH() + 10aH()", listed = ["h.jl", "a.jl"])
r["nested-sub"] = run_case("sub/a.jl includes ../lib/h.jl (listed)"; files = ["lib/h.jl" => h("hI"), "sub/a.jl" => "include(\"../lib/h.jl\")\n"],
    body = "include(\"sub/a.jl\")\n", expr = "hI()", listed = ["lib/h.jl", "sub/a.jl"])
r["@__FILE__"] = run_case("@__FILE__ in an included file"; files = ["h.jl" => "hJ() = VAL\nhJfile() = @__FILE__\n"],
    body = "include(\"h.jl\")\n", expr = "hJ()", listed = ["h.jl"],
    after = () -> println("   ... @__FILE__ of the included copy = ", Base.invokelatest(Main.hJfile)))
r["@time"] = run_case("@time include(\"h.jl\")"; files = ["h.jl" => h("hK")], body = "@time include(\"h.jl\")\n", expr = "hK()", listed = ["h.jl"])
r["@static"] = run_case("@static if true include end"; files = ["h.jl" => h("hL")], body = "@static if true\n include(\"h.jl\")\nend\n", expr = "hL()", listed = ["h.jl"])
r["foreach"] = run_case("foreach(include, [\"h.jl\"])"; files = ["h.jl" => h("hM")], body = "foreach(include, [\"h.jl\"])\n", expr = "hM()", listed = ["h.jl"])
r["broadcast"] = run_case("include.([\"h.jl\"])"; files = ["h.jl" => h("hN")], body = "include.([\"h.jl\"])\n", expr = "hN()", listed = ["h.jl"])
r["baremodule"] = run_case("baremodule with its own include(p) = ..."; files = ["h.jl" => h("hO")],
    body = "baremodule BO\nusing Base\ninclude(p) = Base.include(BO, p)\ninclude(\"h.jl\")\nend\n", expr = "BO.hO()", listed = ["h.jl"])
# (not a valid definition in Main either) r["method"] = run_case("include(s::Symbol) = include(\"\$s.jl\")"; files = ["h.jl" => h("hP")],
#     body = "include(s::Symbol) = include(string(s, \".jl\"))\ninclude(:h)\n", expr = "hP()", listed = ["h.jl"])
r["sub-gone"] = run_case("include(\"lib/h.jl\"), originals deleted"; files = ["lib/h.jl" => h("hQ")],
    body = "include(\"lib/h.jl\")\n", expr = "hQ()", listed = ["lib/h.jl"], gone = true)
r["plain-gone"] = run_case("include(\"h.jl\"), originals deleted"; files = ["h.jl" => h("hR")],
    body = "include(\"h.jl\")\n", expr = "hR()", listed = ["h.jl"], gone = true)
r["samebase-gone"] = run_case("a/u.jl + b/u.jl (same name), deleted"; files = ["a/u.jl" => h("hS"), "b/u.jl" => h("hT")],
    body = "include(joinpath(@__DIR__, \"a\", \"u.jl\"))\ninclude(joinpath(@__DIR__, \"b\", \"u.jl\"))\n", expr = "hS() + 10hT()",
    listed = ["a/u.jl", "b/u.jl"], gone = true)
r["samebase"] = run_case("a/u.jl + b/u.jl (same name), edited"; files = ["a/u.jl" => h("hU"), "b/u.jl" => h("hV")],
    body = "include(\"a/u.jl\")\ninclude(\"b/u.jl\")\n", expr = "hU() + 10hV()", listed = ["a/u.jl", "b/u.jl"])
println(r)
