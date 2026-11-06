# d302bc6: `_origin_of` keeps a recorded origin only while the copy keeps its content (digest = Base.hash(read(copy))).
# Base.hash of a Vector{UInt8} with >= 32768 elements samples ~log(N) elements, so same-length edits of a large copy
# usually keep the digest.
using Test, PDEStudio, Random
const P = PDEStudio
include(joinpath(@__DIR__, "old", "solver.jl"))
set_save_path!(mktempdir())
exp!(name, dir) = P.save_params_to_csv(name, dir, Dict("Save Type" => "test"))
for pad in (0, 40_000)
    A = mktempdir(); E = mktempdir()
    body(n) = """
        SimulationConfig(create_param_dict(:N => $n, :sim_func_name => :advection_solver_1d),
                         create_method_dict(:m => create_param_dict()), [:m])
        """ * join("# " * String(rand(Random.Xoshiro(1), collect("abcdefgh ijk"), 60)) * "\n" for _ in 1:(pad ÷ 63))
    write(joinpath(A, "cfg.jl"), body(11))
    reset_manager!(); P.load_config_file!(joinpath(A, "cfg.jl")); exp!("exp", E)
    write(joinpath(A, "cfg.jl"), body(12))                  # edited original: the copy becomes the source
    reset_manager!(); P.load_and_apply_csv!(joinpath(E, "exp.csv"))
    copy = joinpath(E, "exp_sources", "cfg.jl")
    o0 = P._origin_of(copy)
    # the user edits the copy (same length: a digit), or another export of the same length overwrites it
    n_hit = 0
    for k in 10:19
        write(copy, body(k + 3))  # 13..22: same length as 11
        n_hit += !isnothing(P._origin_of(copy))
    end
    println("file size $(filesize(copy)) B: origin before edit = $(o0 !== nothing); origin kept after 10 different same-length edits: $n_hit/10")
    # consequence: the next export records the original of the old content
    write(copy, body(19))
    P.load_config_file!(copy)
    E2 = mktempdir(); exp!("exp", E2)
    println("   export of the edited copy (loaded as .jl) records origin: ",
            P.parse_csv_to_dict(joinpath(E2, "exp.csv"))["Metadata"]["General"]["source_origins"])
end
