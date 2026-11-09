using Documenter, PDEStudio
makedocs(root = "/home/agent/.claude/jobs/d2d299f1/tmp/review-agent/repo/docs", build = mktempdir(), remotes = nothing,
    sitename = "PDEStudio.jl", modules = [PDEStudio], checkdocs = :exports,
    warnonly = [:missing_docs, :cross_references],
    format = Documenter.HTML(prettyurls = false),
    pages = ["Scripting & AI Agents" => "agents.md", "API Reference" => "api.md"], pagesonly = true)
