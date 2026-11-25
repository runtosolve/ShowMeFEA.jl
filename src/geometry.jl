# ---- per-frame arrays (the JavaScript in `viewer_app` mirrors these) --------------------------

"surface vertex positions of frame `k` (or of mode `mode`) at deformation `scale`"
function surface_positions(v::VizData, k::Int, scale::Real; mode::Int = 0)
    out = Vector{Point3f}(undef, length(v.sv_pv))
    U = mode > 0 ? v.modes[mode].disp : view(v.disp, :, :, k)
    for i in eachindex(v.sv_pv)
        s = v.sv_pv[i]; n = v.pv_node[s]; sg = v.sv_side[i]
        out[i] = Point3f(v.x[n, 1] + scale * U[1, n] + sg * v.pv_off[s, 1],
                         v.x[n, 2] + scale * U[2, n] + sg * v.pv_off[s, 2],
                         v.x[n, 3] + scale * U[3, n] + sg * v.pv_off[s, 3])
    end
    return out
end

# band coordinate in [0, 2 NBANDS + 1): sequential fields use the first NBANDS colors, then one gray band
# (yielded), diverging fields the last NBANDS; NaN = no value
function surface_colors(v::VizData, k::Int, fd::FieldDef, cmax::Real; mode::Int = 0)
    out = Vector{Float32}(undef, length(v.sv_pv))
    if mode > 0
        U = v.modes[mode].disp
        for i in eachindex(v.sv_pv)
            n = v.pv_node[v.sv_pv[i]]
            out[i] = NBANDS * clamp(hypot(U[1, n], U[2, n], U[3, n]), 0.0, 1 - 1e-6)
        end
        return out
    end
    lo, hi = fd.kind == :seq ? (0.0, float(cmax)) : (-float(cmax), float(cmax))
    base = fd.kind == :seq ? 0.0 : float(NBANDS + 1)
    for i in eachindex(v.sv_pv)
        key = v.sv_side[i] > 0 ? fd.top : fd.bot
        q = v.stored[key][v.sv_pv[i], k]
        if q == QNAN
            out[i] = NaN32
        else
            r = v.range[key]
            val = r[1] + q / 65534 * (r[2] - r[1])
            out[i] = fd.yield && val >= YIELD_TOL * v.pv_fy[v.sv_pv[i]] ? NBANDS + 0.5f0 :
                     base + NBANDS * clamp((val - lo) / (hi - lo), 0.0, 1 - 1e-6)
        end
    end
    return out
end

segment_points(pos, segs) = Point3f[pos[i] for s in segs for i in s]

"points of an overlay for frame `k` at deformation `scale`: anchored node position plus the frame offset"
function overlay_points(v::VizData, o::Overlay, k::Int, scale::Real)
    kk = size(o.offset, 3) == 1 ? 1 : k
    return [begin
                a = o.anchor[i]
                a == 0 ? Point3f(o.offset[1, i, kk], o.offset[2, i, kk], o.offset[3, i, kk]) :
                         Point3f(v.x[a, 1] + scale * v.disp[1, a, k] + o.offset[1, i, kk],
                                 v.x[a, 2] + scale * v.disp[2, a, k] + o.offset[2, i, kk],
                                 v.x[a, 3] + scale * v.disp[3, a, k] + o.offset[3, i, kk])
            end for i in 1:npoints(o)]
end

"indices of the faces/edges of the visible parts"
_select(parts_vis::AbstractVector{Bool}, part::Vector{Int32}) = findall(i -> parts_vis[part[i]], eachindex(part))
