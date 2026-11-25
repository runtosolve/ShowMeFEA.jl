# ---- model description ---------------------------------------------------------------------

"""
    ShellPart(name, conn; thickness, fy = Inf, normals = nothing, toggle = false, visible = true)

A group of shell elements (triangles or quadrilaterals) drawn with one checkbox and one yield stress.

  * `conn`: element connectivities, each 3 or 4 global node ids (tuples or vectors).
  * `thickness`: one value or one per element.
  * `fy`: yield stress; with `FieldDef(...; yield = true)` values at or above it are drawn gray. `Inf` disables it.
  * `normals`: optional unit normal per element (the `+normal` side is the "top" surface). Computed from the element
    geometry (right-hand rule of the node order) when not given.
  * `toggle`: give the part a visibility checkbox on the page.
"""
struct ShellPart
    name::String
    conn::Vector{Vector{Int32}}
    thickness::Vector{Float64}
    fy::Float64
    normals::Union{Nothing,Vector{NTuple{3,Float64}}}
    toggle::Bool
    visible::Bool
end
function ShellPart(name::AbstractString, conn; thickness, fy::Real = Inf, normals = nothing, toggle::Bool = false, visible::Bool = true)
    cv = [Int32.(collect(c)) for c in conn]
    all(c -> length(c) in (3, 4), cv) || throw(ArgumentError("elements must have 3 or 4 nodes"))
    tv = thickness isa Real ? fill(Float64(thickness), length(cv)) : Float64.(collect(thickness))
    length(tv) == length(cv) || throw(ArgumentError("one thickness per element expected ($(length(cv)) elements, $(length(tv)) thicknesses)"))
    nv = normals === nothing ? nothing : [NTuple{3,Float64}(Tuple(Float64.(collect(n)))) for n in normals]
    nv === nothing || length(nv) == length(cv) || throw(ArgumentError("one normal per element expected"))
    return ShellPart(String(name), cv, tv, Float64(fy), nv, toggle, visible)
end

"""
    ShellModel(x, parts; up = :z)

Node coordinates `x` (an `nn × 3` matrix or a vector of 3-component points) and the [`ShellPart`](@ref)s. `up` (`:y`
or `:z`) is the vertical axis of the camera. With Ferrite loaded, `ShellModel(grid::Ferrite.Grid; thickness, ...)`
builds the model from a grid of `Triangle`/`Quadrilateral` cells.
"""
struct ShellModel
    x::Matrix{Float64}
    parts::Vector{ShellPart}
    up::Symbol
end
function ShellModel(x, parts; up::Symbol = :z)
    X = x isa AbstractMatrix ? Matrix{Float64}(x) : Matrix{Float64}(reduce(vcat, [permutedims(Float64.(collect(p))) for p in x]))
    size(X, 2) == 3 || throw(ArgumentError("node coordinates must be nn × 3"))
    up in (:y, :z) || throw(ArgumentError("up must be :y or :z"))
    ps = collect(ShellPart, parts)
    for p in ps, c in p.conn
        all(1 .<= c .<= size(X, 1)) || throw(ArgumentError("part $(p.name): node id out of range"))
    end
    return ShellModel(X, ps, up)
end
nnodes(m::ShellModel) = size(m.x, 1)
nelements(m::ShellModel) = sum(length(p.conn) for p in m.parts)

"""
    FieldDef(key, label; unit = "", kind = :seq, top = key, bot = top, max = NaN, yield = false)

A contour field of the page. `top`/`bot` name the frame field arrays drawn on the `+normal` and `−normal` surfaces
(the same array for both by default; e.g. `top = :vm_top, bot = :vm_bot` for the two surfaces of a shell). `kind` is
`:seq` (0 … max, magnitudes) or `:div` (−max … max, signed). `max` is the default contour limit (automatic when
`NaN`: the yield stress of the model for `yield = true` fields, else a round number above the largest value).
"""
struct FieldDef
    key::Symbol
    label::String
    unit::String
    kind::Symbol
    top::Symbol
    bot::Symbol
    max::Float64
    yield::Bool
end
function FieldDef(key::Symbol, label::AbstractString; unit::AbstractString = "", kind::Symbol = :seq, top::Symbol = key, bot::Symbol = top,
                  max::Real = NaN, yield::Bool = false)
    kind in (:seq, :div) || throw(ArgumentError("kind must be :seq or :div"))
    return FieldDef(key, String(label), String(unit), kind, top, bot, Float64(max), yield)
end

"""
    Frame(disp; fields = Dict(), label = "", info = "")

One load step: `disp` the nodal translations (`3 × nn` or `nn × 3`), `fields` the named value arrays (one value
per element over all parts in order, or one per node; `NaN` = no value), `label` the short step name shown next to
the slider and `info` an HTML line shown under the model (e.g. the load level).
"""
struct Frame
    disp::Matrix{Float32}
    fields::Dict{Symbol,Vector{Float64}}
    label::String
    info::String
end
function Frame(disp; fields = Dict{Symbol,Any}(), label::AbstractString = "", info::AbstractString = "")
    d = disp isa AbstractMatrix ? disp : reduce(hcat, [Float32.(collect(p)) for p in disp])
    D = size(d, 1) == 3 ? Matrix{Float32}(d) : size(d, 2) == 3 ? Matrix{Float32}(permutedims(d)) : throw(ArgumentError("disp must be 3 × nn or nn × 3"))
    return Frame(D, Dict{Symbol,Vector{Float64}}(Symbol(k) => Float64.(collect(v)) for (k, v) in fields), String(label), String(info))
end

"""
    Overlay(name, kind, anchor, offset; color, linewidth = 3, marker = (0.3, 0.18), toggle = true, visible = true,
            requires = 0, notes = String[], in_modes = false)

Line segments (`kind = :segments`, consecutive point pairs) or cylinder markers (`kind = :markers`) drawn with the
model. Point `i` is at `x[anchor[i]] + scale * disp[anchor[i]] + offset[:, i, frame]` (`anchor[i] = 0`: the offset
alone, a fixed point), so loads follow the deformed model and arrow lengths can change per frame. `offset` is
`3 × npts × nframes`, or `3 × npts` for the same geometry in every frame. `color` is one color or one per point
(segments). `requires` is the index of a part that must be visible for the overlay to show, `notes` optional
HTML lines per frame listed in the legend while the overlay is shown, `in_modes` whether it is drawn with
buckling modes. Helpers: [`arrow_points`](@ref), [`arc_points`](@ref).
"""
struct Overlay
    name::String
    kind::Symbol
    anchor::Vector{Int32}
    offset::Array{Float32,3}
    color::Vector{RGBAf}
    linewidth::Float64
    marker::NTuple{2,Float64}
    toggle::Bool
    visible::Bool
    requires::Int
    notes::Vector{String}
    in_modes::Bool
end
function Overlay(name::AbstractString, kind::Symbol, anchor, offset; color = RGBAf(0.75, 0.05, 0.55, 1), linewidth::Real = 3.0,
                 marker = (0.3, 0.18), toggle::Bool = true, visible::Bool = true, requires::Int = 0, notes = String[], in_modes::Bool = false)
    kind in (:segments, :markers) || throw(ArgumentError("kind must be :segments or :markers"))
    a = Int32.(collect(anchor)); np = length(a)
    off = ndims(offset) == 2 ? reshape(Float32.(offset), 3, np, 1) : Array{Float32,3}(Float32.(offset))
    size(off, 1) == 3 && size(off, 2) == np || throw(ArgumentError("offset must be 3 × npts (× nframes)"))
    kind == :segments && isodd(np) && throw(ArgumentError("segments need an even number of points"))
    cols = color isa AbstractVector ? RGBAf.(to_color.(color)) : [RGBAf(to_color(color))]
    length(cols) in (1, np) || throw(ArgumentError("one color, or one per point"))
    return Overlay(String(name), kind, a, off, cols, Float64(linewidth), (Float64(marker[1]), Float64(marker[2])), toggle, visible, requires,
                   String.(collect(notes)), in_modes)
end
npoints(o::Overlay) = length(o.anchor)

"""
    arrow_points(tail, tip, a, b; show = true) -> 10 points (5 segments)

Segments of an arrow from `tail` to `tip` with a four-blade head in the directions `±a`, `±b` (unit vectors
normal to the shaft). With `show = false` all points collapse onto `tip` (hidden, same point count).
"""
function arrow_points(tail, tip, a, b; show::Bool = true)
    T = Vec3f(tip...); show || return fill(Point3f(T), 10)
    d = T - Vec3f(tail...); len = sqrt(sum(abs2, d)); hl = 0.28f0 * len; u = d / max(len, 1f-30)
    out = Point3f[Point3f(tail...), Point3f(T)]
    for w in (Vec3f(a...), -Vec3f(a...), Vec3f(b...), -Vec3f(b...))
        push!(out, Point3f(T), Point3f(T - hl * u + 0.35f0 * hl * w))
    end
    return out
end

"""
    arc_points(center, r, e1, e2, φ0, φ1; n = 18, head = true, show = true) -> 2n (+4) points

Segments of a circular arc `center + r (cos φ e1 + sin φ e2)` from `φ0` to `φ1` with an arrow head at `φ1`
(moment symbol). With `show = false` all points collapse onto `center`.
"""
function arc_points(center, r, e1, e2, φ0, φ1; n::Int = 18, head::Bool = true, show::Bool = true)
    c = Vec3f(center...); u = Vec3f(e1...); v = Vec3f(e2...); R = Float32(r)
    p(φ) = Point3f(c + R * (cos(Float32(φ)) * u + sin(Float32(φ)) * v))
    out = Point3f[]
    for i in 0:n-1
        φa = φ0 + (φ1 - φ0) * i / n; φb = φ0 + (φ1 - φ0) * (i + 1) / n
        append!(out, show ? (p(φa), p(φb)) : (Point3f(c), Point3f(c)))
    end
    if head
        tip = p(φ1); sg = sign(φ1 - φ0)
        t = Vec3f(sg * (-sin(Float32(φ1)) * u + cos(Float32(φ1)) * v)); rr = Vec3f(cos(Float32(φ1)) * u + sin(Float32(φ1)) * v); hl = 0.45f0 * R
        for w in (rr, -rr)
            append!(out, show ? (tip, Point3f(tip - hl * t + 0.4f0 * hl * w)) : (Point3f(c), Point3f(c)))
        end
    end
    return out
end

"""
    Chart(title; xlabel = "", ylabel = "", curves = [], hlines = [], vlines = [], marker = nothing, legend = :rb)

A 2D chart next to the model: `curves` from [`curve`](@ref), reference lines from [`hline`](@ref)/[`vline`](@ref),
and `marker = (x = ..., y = ...)` the point of the current frame (one value per frame of the analysis).
"""
struct Chart
    title::String
    xlabel::String
    ylabel::String
    curves::Vector{NamedTuple}
    hlines::Vector{NamedTuple}
    vlines::Vector{NamedTuple}
    marker::Union{Nothing,NamedTuple{(:x, :y),Tuple{Vector{Float64},Vector{Float64}}}}
    legend::Symbol
end
Chart(title::AbstractString; xlabel = "", ylabel = "", curves = [], hlines = [], vlines = [], marker = nothing, legend::Symbol = :rb) =
    Chart(String(title), String(xlabel), String(ylabel), collect(NamedTuple, curves), collect(NamedTuple, hlines), collect(NamedTuple, vlines),
          marker === nothing ? nothing : (x = Float64.(collect(marker.x)), y = Float64.(collect(marker.y))), legend)
"a chart curve; `color = nothing` uses the model color (blue)"
curve(x, y; color = nothing, linestyle = :solid, linewidth = 2.2, label = nothing) =
    (; x = Float64.(collect(x)), y = Float64.(collect(y)), color, linestyle, linewidth, label)
hline(y; color = nothing, linestyle = :dash, linewidth = 1.6, label = nothing) = (; y = Float64(y), color, linestyle, linewidth, label)
vline(x; color = nothing, linestyle = :dot, linewidth = 1.0, label = nothing) = (; x = Float64(x), color, linestyle, linewidth, label)

"""
    Mode(label, disp; info = "")

An alternative displacement set, e.g. an elastic buckling mode (`3 × nn` or `nn × 3`), listed in the model
selector; drawn with the colour of its normalised translation magnitude.
"""
struct Mode
    label::String
    disp::Matrix{Float32}
    info::String
end
Mode(label::AbstractString, disp; info::AbstractString = "") = Mode(String(label), Frame(disp).disp, String(info))

# ---- precomputed data ----------------------------------------------------------------------

"""
    VizData(model, frames; fields, overlays = [], charts = [], modes = [], notes = [], max_frames = 40,
            keep = Int[], thickness_scale = 1, crease = 8)

Everything the viewer draws, precomputed once: thick-shell surfaces, quantized fields, thinned frames. At most
`max_frames` frames are kept (evenly spaced, plus the first, the last and the indices in `keep`); the charts use
every frame. `thickness_scale` exaggerates the drawn thickness; element edges whose normals differ by more than
`crease` degrees are drawn as feature lines (as are free edges and part boundaries).
"""
struct VizData
    x::Matrix{Float32}                 # nn × 3
    pv_node::Vector{Int32}             # value slots: one per (part, node)
    pv_part::Vector{Int32}
    pv_off::Matrix{Float32}            # npv × 3 half-thickness offset (+normal)
    pv_fy::Vector{Float32}             # yield stress of the slot's part (1f30: none)
    sv_pv::Vector{Int32}               # surface vertices → slot
    sv_side::Vector{Int8}              # +1 top face, −1 bottom face
    faces::Vector{NTuple{3,Int32}}
    face_part::Vector{Int32}
    edges::Vector{NTuple{2,Int32}}
    edge_part::Vector{Int32}
    feature::Vector{NTuple{2,Int32}}
    feature_part::Vector{Int32}
    disp::Array{Float32,3}             # 3 × nn × nframes
    stored::Dict{Symbol,Matrix{UInt16}}
    range::Dict{Symbol,NTuple{2,Float64}}
    fields::Vector{FieldDef}
    labels::Vector{String}
    info::Vector{String}
    keep::Vector{Int}                  # kept frame indices of the analysis
    overlays::Vector{Overlay}          # offsets thinned to the kept frames
    charts::Vector{Chart}              # markers thinned to the kept frames
    modes::Vector{Mode}
    notes::Vector{String}
    parts::Vector{ShellPart}
    up::Symbol
    center::Vector{Float64}; size::Float64; default_scale::Float64
end

nframes(v::VizData) = length(v.labels)
function fieldindex(v::VizData, key::Symbol)
    i = findfirst(f -> f.key == key, v.fields)
    i === nothing && throw(ArgumentError("no field $key"))
    return i
end

function _element_normals(x, p::ShellPart)
    p.normals === nothing || return p.normals
    out = NTuple{3,Float64}[]
    for c in p.conn
        a = x[c[1], :]; b = x[c[2], :]; cc = x[c[3], :]
        n = length(c) == 3 ? cross(b - a, cc - a) : cross(cc - a, x[c[4], :] - b)
        l = norm(n); push!(out, l > 0 ? Tuple(n ./ l) : (0.0, 0.0, 1.0))
    end
    return out
end

function VizData(model::ShellModel, frames::AbstractVector{Frame}; fields, overlays = Overlay[], charts = Chart[], modes = Mode[],
                 notes = String[], max_frames::Int = 40, keep = Int[], thickness_scale::Real = 1.0, crease::Real = 8.0)
    nn = nnodes(model); nf_all = length(frames)
    nf_all >= 1 || throw(ArgumentError("at least one frame"))
    kp = sort!(unique(vcat(1, nf_all, Int.(keep), round.(Int, range(1, nf_all; length = min(nf_all, max_frames))))))
    filter!(i -> 1 <= i <= nf_all, kp); nf = length(kp)
    fr = frames[kp]
    all(f -> size(f.disp, 2) == nn, frames) || throw(ArgumentError("frame displacements must have $nn nodes"))

    # value slots: one per (part, node); half-thickness offsets along the nodal normal of the part
    slot = Dict{Tuple{Int,Int},Int32}(); pv_node = Int32[]; pv_part = Int32[]; pv_t = Float64[]
    nrm = zeros(3, 0); enorm = Vector{Vector{NTuple{3,Float64}}}(undef, length(model.parts))
    for (ip, p) in enumerate(model.parts)
        enorm[ip] = _element_normals(model.x, p)
        for (e, c) in enumerate(p.conn), i in c
            get!(slot, (ip, Int(i))) do
                push!(pv_node, i); push!(pv_part, ip); push!(pv_t, p.thickness[e])
                Int32(length(pv_node))
            end
        end
    end
    npv = length(pv_node)
    nacc = zeros(npv, 3); cnt = zeros(Int, npv); tacc = zeros(npv)
    for (ip, p) in enumerate(model.parts), (e, c) in enumerate(p.conn), i in c
        s = slot[(ip, Int(i))]; nacc[s, :] .+= enorm[ip][e]; tacc[s] += p.thickness[e]; cnt[s] += 1
    end
    pv_off = zeros(Float32, npv, 3)
    for s in 1:npv
        l = norm(view(nacc, s, :)); n = l > 0 ? nacc[s, :] ./ l : [0.0, 0.0, 1.0]
        pv_off[s, :] .= thickness_scale * (tacc[s] / max(cnt[s], 1)) / 2 .* n
    end
    nparts_of = zeros(Int, nn)
    for s in 1:npv
        nparts_of[pv_node[s]] += 1
    end

    # surface vertices: top copy (1…npv), bottom copy (npv+1…2npv), then the closing strips of the free edges
    sv_pv = Int32[1:npv; 1:npv]; sv_side = Int8[fill(Int8(1), npv); fill(Int8(-1), npv)]
    faces = NTuple{3,Int32}[]; face_part = Int32[]
    epair = Dict{NTuple{2,Int32},Vector{Tuple{Int,Int}}}()    # slot edge → (part, element)
    for (ip, p) in enumerate(model.parts), (e, c) in enumerate(p.conn)
        s = [slot[(ip, Int(i))] for i in c]
        for k in (length(s) == 3 ? ((1, 2, 3),) : ((1, 2, 3), (1, 3, 4)))
            push!(faces, (s[k[1]], s[k[2]], s[k[3]])); push!(face_part, ip)
            push!(faces, (s[k[1]] + npv, s[k[3]] + npv, s[k[2]] + npv)); push!(face_part, ip)
        end
        for k in eachindex(s)
            a = s[k]; b = s[mod1(k + 1, length(s))]
            push!(get!(epair, a < b ? (a, b) : (b, a), Tuple{Int,Int}[]), (ip, e))
        end
    end
    cosc = cosd(Float64(crease))
    edges = NTuple{2,Int32}[]; edge_part = Int32[]; feature = NTuple{2,Int32}[]; feature_part = Int32[]
    for (key, els) in epair
        a, b = key; ip = els[1][1]
        push!(edges, (a, b)); push!(edges, (a + npv, b + npv)); push!(edge_part, ip); push!(edge_part, ip)
        free = length(els) == 1
        isfeat = free || (length(els) == 2 && dot(enorm[els[1][1]][els[1][2]], enorm[els[2][1]][els[2][2]]) < cosc)
        isfeat || continue
        push!(feature, (a, b)); push!(feature, (a + npv, b + npv)); push!(feature_part, ip); push!(feature_part, ip)
        free || continue
        (nparts_of[pv_node[a]] > 1 && nparts_of[pv_node[b]] > 1) && continue     # junction with another part: not a free edge
        n0 = Int32(length(sv_pv))
        append!(sv_pv, (a, b, b, a)); append!(sv_side, (1, 1, -1, -1))
        push!(faces, (n0 + 1, n0 + 2, n0 + 3)); push!(faces, (n0 + 1, n0 + 3, n0 + 4)); push!(face_part, ip); push!(face_part, ip)
    end

    # displacements and quantized fields (nodal averages per slot of element values; nodal values copied)
    disp = zeros(Float32, 3, nn, nf)
    for (k, f) in enumerate(fr)
        disp[:, :, k] .= f.disp
    end
    ne = nelements(model)
    keys_ = unique(vcat([collect(keys(f.fields)) for f in fr]...))
    raw = Dict{Symbol,Matrix{Float64}}(k => fill(NaN, npv, nf) for k in keys_)
    acc = zeros(npv); ecnt = zeros(Int, npv)
    for (k, f) in enumerate(fr), key in keys_
        haskey(f.fields, key) || continue
        v = f.fields[key]
        if length(v) == ne
            fill!(acc, 0.0); fill!(ecnt, 0); g = 0
            for (ip, p) in enumerate(model.parts), c in p.conn
                g += 1; isnan(v[g]) && continue
                for i in c
                    s = slot[(ip, Int(i))]; acc[s] += v[g]; ecnt[s] += 1
                end
            end
            for s in 1:npv
                ecnt[s] > 0 && (raw[key][s, k] = acc[s] / ecnt[s])
            end
        elseif length(v) == nn
            for s in 1:npv
                raw[key][s, k] = v[pv_node[s]]
            end
        else
            throw(ArgumentError("field $key of frame $(kp[k]) has $(length(v)) values; expected $ne (elements) or $nn (nodes)"))
        end
    end
    stored = Dict{Symbol,Matrix{UInt16}}(); rng = Dict{Symbol,NTuple{2,Float64}}()
    for (key, A) in raw
        fin = filter(isfinite, A)
        lo, hi = isempty(fin) ? (0.0, 1.0) : extrema(fin)
        hi > lo || (hi = lo + 1.0)
        rng[key] = (lo, hi)
        stored[key] = map(v -> isfinite(v) ? round(UInt16, (v - lo) / (hi - lo) * 65534) : QNAN, A)
    end
    pv_fy = Float32[isfinite(model.parts[p].fy) ? model.parts[p].fy : 1.0f30 for p in pv_part]
    fyl = filter(<(1.0f29), pv_fy)
    amax(ks...) = _nice(maximum(max(abs(rng[k][1]), abs(rng[k][2])) for k in ks; init = 0.0))
    fds = FieldDef[]
    for f in fields
        haskey(stored, f.top) && haskey(stored, f.bot) || throw(ArgumentError("field $(f.key): no frame data named $(f.top)/$(f.bot)"))
        mx = isfinite(f.max) ? f.max : (f.yield && !isempty(fyl)) ? Float64(maximum(fyl)) : amax(f.top, f.bot)
        push!(fds, FieldDef(f.key, f.label, f.unit, f.kind, f.top, f.bot, mx, f.yield))
    end
    isempty(fds) && throw(ArgumentError("at least one field"))

    lo = vec(minimum(model.x, dims = 1)); hi = vec(maximum(model.x, dims = 1))
    size_ = maximum(hi - lo)
    umax = maximum(abs, disp; init = 0.0f0)
    default_scale = umax > 0 ? clamp(round(0.04 * size_ / umax; sigdigits = 1), 1.0, 500.0) : 1.0
    labels = [isempty(f.label) ? "Step $(kp[k] - 1)" : f.label for (k, f) in enumerate(fr)]
    thin(o::Overlay) = Overlay(o.name, o.kind, o.anchor, size(o.offset, 3) == 1 ? o.offset : o.offset[:, :, kp], o.color, o.linewidth, o.marker,
                               o.toggle, o.visible, o.requires, isempty(o.notes) ? o.notes : o.notes[kp], o.in_modes)
    for o in overlays
        size(o.offset, 3) in (1, nf_all) || throw(ArgumentError("overlay $(o.name): offsets for 1 or $nf_all frames expected"))
        isempty(o.notes) || length(o.notes) == nf_all || throw(ArgumentError("overlay $(o.name): one note per frame expected"))
        all(a -> 0 <= a <= nn, o.anchor) || throw(ArgumentError("overlay $(o.name): anchor out of range"))
        0 <= o.requires <= length(model.parts) || throw(ArgumentError("overlay $(o.name): requires out of range"))
    end
    thinc(c::Chart) = c.marker === nothing ? c :
        (length(c.marker.x) == nf_all && length(c.marker.y) == nf_all) ? Chart(c.title, c.xlabel, c.ylabel, c.curves, c.hlines, c.vlines, (x = c.marker.x[kp], y = c.marker.y[kp]), c.legend) :
        throw(ArgumentError("chart \"$(c.title)\": marker needs one value per frame ($nf_all)"))
    for m in modes
        size(m.disp, 2) == nn || throw(ArgumentError("mode \"$(m.label)\": $nn nodes expected"))
    end
    return VizData(Float32.(model.x), pv_node, pv_part, pv_off, pv_fy, sv_pv, sv_side, faces, face_part, edges, edge_part, feature, feature_part,
                   disp, stored, rng, fds, labels, [f.info for f in fr], kp, thin.(collect(Overlay, overlays)), thinc.(collect(Chart, charts)),
                   collect(Mode, modes), String.(collect(notes)), model.parts, model.up, (lo + hi) / 2, size_, default_scale)
end
