# Probe: reading hand-edited CSV variants (BOM, CRLF, extra columns, column order, blank lines)
using PDEStudio, Test
f(s) = (p = joinpath(mktempdir(), "x.csv"); write(p, s); p)
@testset "csv read variants" begin
    for (name, s) in (("BOM+CRLF", "﻿Category,Scope,Parameter,Value\r\nSimulation,Shared,N,40\r\n"),
                      ("extra column", "Category,Scope,Parameter,Value,Note\nSimulation,Shared,N,40,hi\n"),
                      ("reordered", "Value,Category,Scope,Parameter\n40,Simulation,Shared,N\n"),
                      ("blank line", "Category,Scope,Parameter,Value\n\nSimulation,Shared,N,40\n"),
                      ("quoted header", "\"Category\",\"Scope\",\"Parameter\",\"Value\"\nSimulation,Shared,N,40\n"),
                      ("only header", "Category,Scope,Parameter,Value\n"),
                      ("tab after comma", "Category,\tScope,\tParameter,\tValue\nSimulation,\tShared,\tN,\t40\n"))
        @testset "$name" begin
            r = try PDEStudio._read_csv(f(s)) catch e; e end
            r isa Exception && println("  $name -> ", sprint(showerror, r))
            @test !(r isa Exception)
            r isa Exception || name == "only header" || (println("  $name -> ", r[1]); @test r[1]["Simulation"]["Shared"]["N"] == 40)
        end
    end
end
