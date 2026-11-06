# f3ed3a2: bundled sources in all cases ("an export runs as it was exported")
using Test, PDEStudio
const P = PDEStudio
set_save_path!(mktempdir())
N() = P.manager.active_config.shared[:N]
src_of(cfg) = P.manager.active_config.sources
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
function load!(csv)
    reset_manager!()
    P.load_and_apply_csv!(csv)
    return (N = isnothing(P.manager.active_config) ? nothing : get(P.manager.active_config.shared, :N, nothing),
            note = hasproperty(P.manager, :source_note) ? P.manager.source_note : "(old code)", failures = copy(P.manager.source_failures),
            sources = isnothing(P.manager.active_config) ? String[] : copy(P.manager.active_config.sources))
end
cfgtext(n; listed = true, extra = "") = """
    include("helper.jl")
    $extra
    SimulationConfig(create_param_dict(:N => helper_N() + $n, :sim_func_name => :advection_solver_1d),
                     create_method_dict(:m => create_param_dict()), [:m];
                     sources = $(listed ? "[joinpath(@__DIR__, \"helper.jl\")]" : "String[]"))
    """

@testset verbose = true "bundle cases" begin
@testset "A: 9fa97ea probe_reexport_helper (edited included helper)" begin
    orig = mktempdir(); out1, out2 = mktempdir(), mktempdir()
    write(joinpath(orig, "helper.jl"), "helper_N() = 24\n"); write(joinpath(orig, "config.jl"), cfgtext(0))
    P.load_config_file!(joinpath(orig, "config.jl")); @test exp!("exp", out1)
    write(joinpath(orig, "helper.jl"), "helper_N() = 25\n")
    r = load!(joinpath(out1, "exp.csv")); println("A load1: ", r)
    @test r.N == 24
    @test exp!("exp2", out2)
    rows = P.parse_csv_to_dict(joinpath(out2, "exp2.csv"))
    println("A export2 N = ", rows["Simulation"]["Shared"]["N"], " bundled helper: ", strip(read(joinpath(out2, "exp2_sources", "helper.jl"), String)))
    @test occursin("24", read(joinpath(out2, "exp2_sources", "helper.jl"), String))
    rm(orig; recursive = true)
    r = load!(joinpath(out2, "exp2.csv")); println("A load2 (originals gone): ", r)
    @test r.N == 24 && isempty(r.failures)
end

@testset "B: 03e98ab probe_reexport_origin (edited top-level file)" begin
    dir, out1, out2 = mktempdir(), mktempdir(), mktempdir()
    src = joinpath(dir, "cfg.jl")
    write(src, "ic_v(x) = x\nSimulationConfig(create_param_dict(:N => 16, :version => 1, :ic => ic_v, :sim_func_name => :advection_solver_1d), create_method_dict(:m => create_param_dict()), [:m])\n")
    P.load_config_file!(src); @test exp!("exp", out1)
    write(src, replace(read(src, String), ":version => 1" => ":version => 2"))
    r = load!(joinpath(out1, "exp.csv")); println("B load1: ", r)
    @test P.manager.active_config.shared[:version] == 1
    @test exp!("exp2", out2)
    @test occursin(":version => 1", read(joinpath(out2, "exp2_sources", "cfg.jl"), String))
    # unchanged afterwards: export 2's origins are export 1's copies
    r = load!(joinpath(out2, "exp2.csv")); println("B load export2: ", r)
    @test P.manager.active_config.shared[:version] == 1 && isempty(r.note)
    # third generation from export 2, export 1 folder deleted
    out3 = mktempdir(); @test exp!("exp3", out3)
    rm(out1; recursive = true)
    r = load!(joinpath(out2, "exp2.csv")); println("B load export2 (export1 gone): ", r)
    @test P.manager.active_config.shared[:version] == 1 && isempty(r.failures)
    r = load!(joinpath(out3, "exp3.csv")); println("B load export3 (export1 gone): ", r)
    @test P.manager.active_config.shared[:version] == 1 && isempty(r.failures)
end

@testset "C: helper included but NOT listed in sources" begin
    orig = mktempdir(); out1 = mktempdir()
    write(joinpath(orig, "helper.jl"), "helper_N() = 24\n"); write(joinpath(orig, "config.jl"), cfgtext(0; listed = false))
    P.load_config_file!(joinpath(orig, "config.jl")); @test exp!("exp", out1)
    r = load!(joinpath(out1, "exp.csv")); println("C unchanged: ", r)
    @test r.N == 24 && isempty(r.failures)
    # the user edits the configuration file (+1): before f3ed3a2 the copy ran as the original (N = 24, helper found)
    write(joinpath(orig, "config.jl"), cfgtext(1; listed = false))
    r = load!(joinpath(out1, "exp.csv")); println("C config edited: ", r)
    @test isempty(r.failures)
    # unlisted helper edited, config unchanged: the edited helper runs silently
    write(joinpath(orig, "config.jl"), cfgtext(0; listed = false)); write(joinpath(orig, "helper.jl"), "helper_N() = 30\n")
    r = load!(joinpath(out1, "exp.csv")); println("C unlisted helper edited: ", r)
end

@testset "D: data file read relative to @__DIR__ (docs: rule 4)" begin
    orig = mktempdir(); out1 = mktempdir()
    write(joinpath(orig, "n.txt"), "24")
    body(v) = """
        n0 = parse(Int, read(joinpath(@__DIR__, "n.txt"), String))
        SimulationConfig(create_param_dict(:N => n0, :version => $v, :sim_func_name => :advection_solver_1d),
                         create_method_dict(:m => create_param_dict()), [:m])
        """
    write(joinpath(orig, "cfg.jl"), body(1))
    P.load_config_file!(joinpath(orig, "cfg.jl")); @test exp!("exp", out1)
    r = load!(joinpath(out1, "exp.csv")); println("D unchanged: ", r); @test isempty(r.failures)
    write(joinpath(orig, "cfg.jl"), body(2))
    r = load!(joinpath(out1, "exp.csv")); println("D cfg edited: ", r)
    @test isempty(r.failures)
end

@testset "E: originals moved (folder renamed) / deleted file, folder kept" begin
    root = mktempdir(); orig = joinpath(root, "orig"); mkpath(orig); out1 = mktempdir()
    write(joinpath(orig, "helper.jl"), "helper_N() = 24\n"); write(joinpath(orig, "config.jl"), cfgtext(0))
    P.load_config_file!(joinpath(orig, "config.jl")); @test exp!("exp", out1)
    mv(orig, joinpath(root, "moved"))
    r = load!(joinpath(out1, "exp.csv")); println("E moved: ", r)
    @test r.N == 24 && isempty(r.failures) && occursin("gone", r.note)
    mv(joinpath(root, "moved"), orig)
    rm(joinpath(orig, "helper.jl"))
    r = load!(joinpath(out1, "exp.csv")); println("E helper original deleted, folder kept: ", r)
    @test r.N == 24 && isempty(r.failures)
end

@testset "F: mixed: config copy missing, helper original edited" begin
    orig = mktempdir(); out1 = mktempdir()
    write(joinpath(orig, "helper.jl"), "helper_N() = 24\n"); write(joinpath(orig, "config.jl"), cfgtext(0))
    P.load_config_file!(joinpath(orig, "config.jl")); @test exp!("exp", out1)
    rm(joinpath(out1, "exp_sources", "config.jl"))
    write(joinpath(orig, "helper.jl"), "helper_N() = 25\n")
    r = load!(joinpath(out1, "exp.csv")); println("F: ", r)
    # the config original runs as itself: its include("helper.jl") runs the edited original helper (25), the note
    # says the exported helper ran
end

@testset "G: config ending with a function, edited original" begin
    orig = mktempdir(); out1, out2 = mktempdir(), mktempdir()
    write(joinpath(orig, "helper.jl"), "helper_N() = 24\n")
    fn(n) = """
        include("helper.jl")
        () -> SimulationConfig(create_param_dict(:N => helper_N() + $n, :sim_func_name => :advection_solver_1d),
                               create_method_dict(:m => create_param_dict()), [:m]; sources = [joinpath(@__DIR__, "helper.jl")])
        """
    write(joinpath(orig, "cfg.jl"), fn(0))
    P.load_config_file!(joinpath(orig, "cfg.jl")); @test exp!("exp", out1)
    write(joinpath(orig, "cfg.jl"), fn(5)); write(joinpath(orig, "helper.jl"), "helper_N() = 99\n")
    r = load!(joinpath(out1, "exp.csv")); println("G: ", r)
    @test r.N == 24 && all(s -> startswith(s, realpath(out1)) || startswith(s, out1), r.sources)
    @test exp!("exp2", out2); rm(orig; recursive = true); rm(out1; recursive = true)
    r = load!(joinpath(out2, "exp2.csv")); println("G gen2 alone: ", r)
    @test r.N == 24 && isempty(r.failures)
end

@testset "H: older export (<export>_source_<i>.jl next to the CSV, with source_origins)" begin
    orig = mktempdir(); out1 = mktempdir()
    write(joinpath(orig, "helper.jl"), "helper_N() = 24\n"); write(joinpath(orig, "config.jl"), cfgtext(0))
    P.load_config_file!(joinpath(orig, "config.jl")); @test exp!("exp", out1)
    csv = joinpath(out1, "exp.csv"); txt = read(csv, String)
    println("H bundled row: ", filter(l -> occursin("bundled_sources", l), split(txt, '\n')))
    mv(joinpath(out1, "exp_sources", "helper.jl"), joinpath(out1, "exp_source_1.jl"))
    mv(joinpath(out1, "exp_sources", "config.jl"), joinpath(out1, "exp_source_2.jl"))
    txt = replace(txt, "exp_sources/helper.jl" => "exp_source_1.jl", "exp_sources/config.jl" => "exp_source_2.jl")
    write(csv, txt)
    r = load!(csv); println("H unchanged: ", r); @test r.N == 24 && isempty(r.failures)
    write(joinpath(orig, "helper.jl"), "helper_N() = 25\n")
    r = load!(csv); println("H helper edited: ", r)
    @test isempty(r.failures)
    # without origins (the oldest format): runs from next to the CSV, as before
    txt2 = join(filter(l -> !occursin("source_origins", l), split(txt, '\n')), '\n'); write(csv, txt2)
    r = load!(csv); println("H no origins: ", r)
end

@testset "I: symlinked original" begin
    real = mktempdir(); link = mktempdir(); out1 = mktempdir()
    write(joinpath(real, "helper.jl"), "helper_N() = 24\n"); write(joinpath(real, "config.jl"), cfgtext(0))
    symlink(joinpath(real, "config.jl"), joinpath(link, "config.jl"))
    symlink(joinpath(real, "helper.jl"), joinpath(link, "helper.jl"))
    P.load_config_file!(joinpath(link, "config.jl")); @test exp!("exp", out1)
    println("I bundled config is a symlink: ", islink(joinpath(out1, "exp_sources", "config.jl")))
    write(joinpath(real, "helper.jl"), "helper_N() = 25\n")
    r = load!(joinpath(out1, "exp.csv")); println("I helper edited (via link): ", r)
    @test r.N == 24
end

@testset "J: CRLF" begin
    orig = mktempdir(); out1 = mktempdir()
    write(joinpath(orig, "helper.jl"), "helper_N() = 24\n"); write(joinpath(orig, "config.jl"), cfgtext(0))
    P.load_config_file!(joinpath(orig, "config.jl")); @test exp!("exp", out1)
    write(joinpath(orig, "config.jl"), replace(cfgtext(0), "\n" => "\r\n"))
    r = load!(joinpath(out1, "exp.csv")); println("J original converted to CRLF: ", r)
end

@testset "K: absolute source path in the config, edited helper" begin
    orig = mktempdir(); out1, out2 = mktempdir(), mktempdir()
    h = joinpath(orig, "helper.jl")
    write(h, "helper_N() = 24\n")
    write(joinpath(orig, "config.jl"), replace(cfgtext(0), "joinpath(@__DIR__, \"helper.jl\")" => repr(h)))
    P.load_config_file!(joinpath(orig, "config.jl")); @test exp!("exp", out1)
    write(h, "helper_N() = 25\n")
    r = load!(joinpath(out1, "exp.csv")); println("K: ", r)
    @test exp!("exp2", out2); println("K export2 files: ", readdir(joinpath(out2, "exp2_sources")))
end
end
