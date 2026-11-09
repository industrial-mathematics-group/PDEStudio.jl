# Mutation check: patches one PDEStudio function in memory (the repo is not edited), then runs the agent test group.
using PDEStudio
const MUT = ARGS[1]
if MUT == "crop_none"
    @eval PDEStudio _crop(img, box, fig, left_limit = -Inf) = img
elseif MUT == "crop_flipped"
    @eval PDEStudio function _crop(img, box, fig, left_limit = -Inf)
        h, w = size(img); s = w / fig.scene.viewport[].widths[1]; margin = 6
        x0 = clamp(max(floor(Int, (box.origin[1] - margin) * s), isfinite(left_limit) ? ceil(Int, left_limit * s) + 2 : 0) + 1, 1, w)
        x1 = clamp(ceil(Int, (box.origin[1] + box.widths[1] + margin) * s), x0, w)
        # rows counted from the bottom (wrong: images count from the top)
        r0 = clamp(floor(Int, (box.origin[2] - margin) * s) + 1, 1, h)
        r1 = clamp(ceil(Int, (box.origin[2] + box.widths[2] + margin) * s), r0, h)
        return img[r0:r1, x0:x1]
    end
elseif MUT == "no_lock"
    @eval PDEStudio _lock_view!(msg::AbstractString) = (_status!(msg, :info); nothing)
elseif MUT == "no_apply"
    @eval PDEStudio _apply_steps!(steps) = nothing
elseif MUT == "reset_no_trigger"
    @eval PDEStudio function studio_reset_view!()
        axes = _plot_axes(); manager.camera_locked[] = false; manager.camera_cache = Dict{Symbol, Any}()
        for ax in axes
            ax isa Axis3 || continue
            ax.azimuth[], ax.elevation[] = _DEFAULT_AZIMUTH, _DEFAULT_ELEVATION
            ax.limits[] = (nothing, nothing, nothing); reset_limits!(ax)
        end
        _status!("View reset: the plots follow the data.", :info)
        return isempty(axes) ? NamedTuple[] : _view_summary()
    end
end
ENV["PDESTUDIO_TEST_GROUP"] = "agent"
try
    include(joinpath(ARGS[2], "test", "runtests.jl"))
    println("MUTATION $MUT: tests PASSED (mutation not caught)")
catch e
    println("MUTATION $MUT: tests FAILED (caught)")
end
