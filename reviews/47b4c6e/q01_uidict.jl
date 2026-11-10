using PDEStudio
D = PDEStudio.MASTER_UI_DICT
for s in sort!(collect(keys(D))), k in sort!(collect(keys(D[s])))
    v = D[s][k]
    println(rpad("$s.$k", 40), rpad(string(typeof(v)), 28), repr(v))
end
