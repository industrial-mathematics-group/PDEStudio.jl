# 59da74c: does git_dirty see an untracked file?
using PDEStudio
root = mktempdir(); repo = joinpath(root, "Demo.jl"); mkpath(repo)
write(joinpath(repo, "a.txt"), "1")
git(args...) = run(`git -C $repo -c user.name=t -c user.email=t@e -c commit.gpgsign=false $args`)
git("init", "-q"); git("add", "a.txt"); git("commit", "-q", "-m", "first")
write(joinpath(repo, "new_helper.jl"), "x = 1")
println("untracked file only: git_dirty = ", PDEStudio.get_all_git_infos(root)["Demo.jl"]["git_dirty"])
