using Documenter
using PDEStudio

makedocs(
    sitename = "PDEStudio.jl",
    modules = [PDEStudio],
    checkdocs = :exports,
    # PDEStudioCore names are reexported; their docstrings live in the PDEStudioCore documentation.
    warnonly = [:missing_docs, :cross_references],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://industrial-mathematics-group.github.io/PDEStudio.jl/",
        # The sidebar logo needs no entry here: Documenter shows docs/src/assets/logo.svg (and logo-dark.svg for the
        # dark themes) automatically. `assets` only takes CSS/JS files and favicons.
        assets = [asset("assets/favicon.png", class = :ico, islocal = true)],
        sidebar_sitename = true,
    ),
    pages = [
        "Home" => "index.md",
        "Control Panel" => "overview.md",
        "File Operations" => "file_ops.md",
        "Presets" => "presets.md",
        "Editors" => "editors.md",
        "Rendering" => [
            "Plot & Layout Options" => "rendering.md",
            "Lines" => "render/lines.md",
            "Scatter" => "render/scatter.md",
            "Contour" => "render/contour.md",
            "Heatmap" => "render/heatmap.md",
            "Volume" => "render/volume.md",
        ],
        "Exploration" => "sliders.md",
        "Scripting & AI Agents" => "agents.md",
        "API Reference" => "api.md",
    ],
)

deploydocs(
    repo = "github.com/industrial-mathematics-group/PDEStudio.jl.git",
    devbranch = "main",
    push_preview = true,
)