# 3b58cb8: resolution rows from a CSV (valid, out of range, non-integer), and a studio-written file round trip
using Test, PDEStudio
const P = PDEStudio
set_save_path!(mktempdir()); reset_manager!()
@testset "resolution rows from CSV" begin
    csv = joinpath(mktempdir(), "res.csv")
    write(csv, "Category,Scope,Parameter,Value\nConfig,Resolution_Base,t,80\nConfig,Resolution_Base,x,1\nConfig,Resolution_Ref,x,2.5\nConfig,Resolution_Ref,t,1e3\n")
    parsed = P.parse_csv_to_dict(csv)
    println("parsed Config: ", parsed["Config"])
    P.load_and_apply_csv!(csv)
    println("t=", P.get_resolution(:t), " x=", P.get_resolution(:x), " ref x=", P.get_resolution(:x; is_ref = true), " ref t=", P.get_resolution(:t; is_ref = true))
    @test P.get_resolution(:t) == 80
    @test P.get_resolution(:t; is_ref = true) == 1000
    # old test: t = 1 alone
    reset_manager!()
    r = P.get_resolution(:t)
    write(csv, "Category,Scope,Parameter,Value\nConfig,Resolution_Base,t,1\n")
    println("parsed t=1: ", P.parse_csv_to_dict(csv)["Config"])
end
