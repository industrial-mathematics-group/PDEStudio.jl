# d302bc6: include forms and code that names `include`, at the load and at Run (`_run_simulations`).
# The listed helper h.jl (form_val() = 1) is edited to 2 after the export; "copy" = 1 (the exported version), "ORIGINAL" = 2.
using Test, PDEStudio
const P = PDEStudio
include(joinpath(@__DIR__, "old", "solver.jl"))
set_save_path!(mktempdir())
println("Core skips sources: ", P._CORE_SKIPS_SOURCES)
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
cfgend(; listed = ["h.jl"]) = """
    SimulationConfig(create_param_dict(:N => 20, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m];
                     sources = [$(join(["joinpath(@__DIR__, $(repr(l)))" for l in listed], ", "))])
    """
val() = try Base.invokelatest(Main.form_val) catch; missing end
verdict(v) = v === 1 ? "copy" : v === 2 ? "ORIGINAL" : string(v)
function form(tag, body; edit_cfg = false)
    A = mktempdir(); E = mktempdir()
    write(joinpath(A, "h.jl"), "form_val() = 1\n")
    write(joinpath(A, "cfg.jl"), body * "\n" * cfgend())
    reset_manager!()
    ok = try P.load_config_file!(joinpath(A, "cfg.jl")); true catch e
        println(rpad(tag, 52), "the .jl itself fails: ", first(split(sprint(showerror, e), '\n'))[1:min(end, 80)]); false end
    ok || return
    exp!("exp", E)
    write(joinpath(A, "h.jl"), "form_val() = 2\n")
    edit_cfg && write(joinpath(A, "cfg.jl"), "# edited\n" * read(joinpath(A, "cfg.jl"), String))
    reset_manager!()
    Main.eval(:(form_val() = 0))
    P.load_and_apply_csv!(joinpath(E, "exp.csv"))
    f = P.manager.source_failures
    load = isempty(f) ? verdict(val()) : "FAIL " * first(f)[1:min(end, 90)]
    Main.eval(:(form_val() = 0))
    run = try
        P._run_simulations(P.manager.active_config; force_overwrite = false); verdict(val())
    catch e
        "FAIL " * first(split(sprint(showerror, e isa LoadError ? e.error : e), '\n'))[1:min(end, 90)]
    end
    println(rpad(tag, 52), "load: ", rpad(load, 10), " Run: ", run, "   note: ", P.manager.source_note)
end
forms = [
    "include(\"h.jl\")" => "include(\"h.jl\")",
    "include(identity, \"h.jl\")" => "include(identity, \"h.jl\")",
    "Base.include(@__MODULE__, \"h.jl\")" => "Base.include(@__MODULE__, \"h.jl\")",
    "foreach(include, [\"h.jl\"])" => "foreach(include, [\"h.jl\"])",
    "include.([\"h.jl\"])" => "include.([\"h.jl\"])",
    "map(f -> include(f), [\"h.jl\"]) (do-free closure)" => "map(f -> include(f), [\"h.jl\"])",
    "map([\"h.jl\"]) do f include(f) end" => "map([\"h.jl\"]) do f\n include(f)\nend",
    "@eval include(\"h.jl\")" => "@eval include(\"h.jl\")",
    "Main.include(\"h.jl\")" => "Main.include(\"h.jl\")",
    "eval(quote include(\"h.jl\") end)" => "eval(quote include(\"h.jl\") end)",
    "evalfile(joinpath(@__DIR__, \"h.jl\"))" => "evalfile(joinpath(@__DIR__, \"h.jl\"))",
    "import Base: include; include(\"h.jl\")" => "import Base: include\ninclude(\"h.jl\")",
    "module M ... include ... end; form_val() = M.form_val()" => "module FormM\ninclude(\"h.jl\")\nend\nform_val() = FormM.form_val()",
    # code that names `include` without meaning Base's
    "kwarg: f(; include = true) = include ? ... " => "pick(; include::Bool = true) = include ? \"h.jl\" : \"x.jl\"\ninclude(pick())",
    "local variable: let include = \"h.jl\"; Base.include(Main, include) end" => "let inc = \"h.jl\", include = inc\n Base.include(@__MODULE__, joinpath(@__DIR__, include))\nend",
    "for include in [\"h.jl\"] ... end" => "for include in [\"h.jl\"]\n Base.include(@__MODULE__, joinpath(@__DIR__, include))\nend",
    "named tuple (; include) shorthand" => "include_flag = let include = true; (; include) end\ninclude(\"h.jl\")",
    "struct field include::Bool" => "struct FormOpt; include::Bool; end\nFormOpt(true).include && include(\"h.jl\")",
    "@NamedTuple{include::Bool}" => "const FormNT = @NamedTuple{include::Bool}\ninclude(\"h.jl\")",
]
for (tag, body) in forms
    form(tag, body)
end
println("-- with cfg.jl edited too (cfg.jl then runs from its copy)")
for (tag, body) in forms[[1, 4, 9, 14, 15]]
    form(tag, body; edit_cfg = true)
end
