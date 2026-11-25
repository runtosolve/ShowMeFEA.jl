# ---- Makie scene (shared by the page and the still images) ----------------------------------

"""
    draw_model!(ax, v, k, fd; scale, cmax, palette = :abaqus, edges = true, parts = trues, ssao = false, mode = 0)

Draw frame `k` (or buckling `mode`) into the 3D scene `ax`; returns the plots (`mesh`, `edges`, `feature`, `ghost`,
`overlays`) that the page updates in the browser.
"""
function draw_model!(ax, v::VizData, k::Int, fd::FieldDef; scale, cmax, palette = :abaqus, edges = true,
                     parts::AbstractVector{Bool} = [p.visible for p in v.parts], edge_width = 0.6, feature_width = 1.6, ssao = false, mode::Int = 0)
    pos = surface_positions(v, k, scale; mode)
    faces = [GLTriangleFace(f...) for f in v.faces[_select(parts, v.face_part)]]
    msh = mesh!(ax, pos, faces; color = surface_colors(v, k, fd, cmax; mode), colormap = band_colormap(palette), colorrange = (0, 2NBANDS + 1),
                nan_color = RGBf(0.80, 0.80, 0.78), shading = true, backlight = 1.0f0, specular = 0.12f0, shininess = 24.0f0,
                diffuse = 0.55f0, interpolate = false, ssao)
    ed = linesegments!(ax, segment_points(pos, v.edges[_select(parts, v.edge_part)]); color = RGBAf(0.05, 0.05, 0.05, 0.38), linewidth = edge_width,
                       visible = edges, depth_shift = -1.0f-4)
    ft = linesegments!(ax, segment_points(pos, v.feature[_select(parts, v.feature_part)]); color = RGBf(0.04, 0.04, 0.04), linewidth = feature_width,
                       depth_shift = -3.0f-4)
    pos0 = surface_positions(v, 1, 0.0)
    gh = linesegments!(ax, segment_points(pos0, v.feature); color = RGBAf(0.35, 0.35, 0.33, 0.6), linewidth = 0.8, visible = false)
    ovs = []
    for o in v.overlays
        pts = overlay_points(v, o, k, scale)
        vis = o.visible && (o.requires == 0 || parts[o.requires]) && (mode == 0 || o.in_modes)
        col = length(o.color) == 1 ? o.color[1] : o.color
        if o.kind == :segments
            push!(ovs, linesegments!(ax, pts; color = col, linewidth = o.linewidth, overdraw = true, visible = vis))
        else
            R, H = o.marker
            push!(ovs, meshscatter!(ax, pts; marker = GeometryBasics.Cylinder(Point3f(0, 0, 0), Point3f(0, 0, 1), 1.0f0),
                                    markersize = Vec3f(R, R, H), color = col, shading = true, specular = 0.3f0, ssao, visible = vis))
        end
    end
    return (; mesh = msh, edges = ed, feature = ft, ghost = gh, overlays = ovs)
end

"view direction (camera minus target, unit) and up vector for the model's vertical axis"
function _view_dir(up::Symbol, azimuth, elevation)
    up == :y ? (Vec3f(cos(elevation) * cos(azimuth), sin(elevation), cos(elevation) * sin(azimuth)), Vec3f(0, 1, 0)) :
               (Vec3f(cos(elevation) * cos(azimuth), cos(elevation) * sin(azimuth), sin(elevation)), Vec3f(0, 0, 1))
end

"camera distance along `d` at which the undeformed bounding box fills a view of `fov` degrees and width/height `aspect`"
function fit_distance(v::VizData, d, up; fov = 28.0, aspect = 1.6, margin = 1.06)
    f = -Vec3f(d); r = normalize(cross(f, Vec3f(up))); u = normalize(cross(r, f))
    tv = tan(deg2rad(fov) / 2); th = tv * aspect
    lo = vec(minimum(v.x, dims = 1)); hi = vec(maximum(v.x, dims = 1)); c = Vec3f(v.center...)
    need = 0.0
    for m in 0:7
        p = Vec3f(m & 1 != 0 ? hi[1] : lo[1], m & 2 != 0 ? hi[2] : lo[2], m & 4 != 0 ? hi[3] : lo[3]) - c; dz = dot(p, f)
        need = max(need, abs(dot(p, u)) / tv + dz, abs(dot(p, r)) / th + dz)
    end
    return margin * need
end

"""
    set_camera!(lscene, v; azimuth = -0.95, elevation = 0.42, zoom = :fit, aspect = 1.6)

Look at the model centre from the direction (`azimuth`, `elevation`) about the model's vertical axis. `zoom = :fit`
places the camera so that the model fills the view of the given width/height `aspect`; a number zooms relative to
a fixed distance of 1.65 × model size.
"""
function set_camera!(lscene, v::VizData; azimuth = -0.95, elevation = 0.42, zoom = :fit, aspect = 1.6)
    c = Vec3f(v.center...)
    d, up = _view_dir(v.up, azimuth, elevation)
    cam = cameracontrols(lscene.scene)
    cam.settings.center[] = false          # plots added later (colour bar, labels) must not re-centre the camera
    cam.fov[] = 28.0f0
    dist = zoom === :fit ? fit_distance(v, d, up; aspect) : 1.65 * v.size / zoom
    update_cam!(lscene.scene, c + Float32(dist) * d, c, up)
    return lscene
end

_lights(up::Symbol) = [AmbientLight(RGBf(0.80, 0.80, 0.80)),
                       DirectionalLight(RGBf(0.36, 0.36, 0.36), up == :y ? Vec3f(-0.35, -1.0, 0.45) : Vec3f(-0.35, 0.45, -1.0), true)]

const SERIES = RGBf(_hex("#2a78d6")); const ACCENT = RGBf(_hex("#b3261e"))
_col(c, default) = c === nothing ? default : to_color(c)

"draw the charts of `v` into the grid layout `gl`; returns the marker plots (one per chart, `nothing` without marker)"
function charts!(gl, v::VizData, k::Int)
    ink = RGBf(0.32, 0.32, 0.31); grid = RGBf(0.88, 0.88, 0.85)
    kw = (; xgridcolor = grid, ygridcolor = grid, topspinevisible = false, rightspinevisible = false, titlealign = :left,
          titlesize = 14, titlefont = :regular, xlabelsize = 12, ylabelsize = 12, xticklabelsize = 11, yticklabelsize = 11,
          xlabelcolor = ink, ylabelcolor = ink, xticklabelcolor = ink, yticklabelcolor = ink)
    markers = []
    for (i, c) in enumerate(v.charts)
        ax = Axis(gl[i, 1]; title = c.title, xlabel = c.xlabel, ylabel = c.ylabel, kw...)
        for h in c.hlines
            hlines!(ax, [h.y]; color = _col(h.color, ACCENT), linewidth = h.linewidth, linestyle = h.linestyle, label = h.label)
        end
        for h in c.vlines
            vlines!(ax, [h.x]; color = _col(h.color, ACCENT), linewidth = h.linewidth, linestyle = h.linestyle, label = h.label)
        end
        for cv in c.curves
            lines!(ax, cv.x, cv.y; color = _col(cv.color, SERIES), linewidth = cv.linewidth, linestyle = cv.linestyle, label = cv.label)
        end
        if c.marker === nothing
            push!(markers, nothing)
        else
            push!(markers, scatter!(ax, [Point2f(c.marker.x[k], c.marker.y[k])]; color = SERIES, strokecolor = :white, strokewidth = 2, markersize = 13))
        end
        labelled = any(x -> x.label !== nothing, c.curves) || any(x -> x.label !== nothing, c.hlines) || any(x -> x.label !== nothing, c.vlines)
        labelled && c.legend != :none && axislegend(ax; position = c.legend, framevisible = false, labelsize = 11, patchsize = (18, 10), rowgap = 0, padding = (4, 4, 2, 2))
    end
    return markers
end

_strip(html) = replace(replace(html, r"<[^>]*>" => ""), "&nbsp;" => " ")

"""
    render_image(path, v, frame = last; field = first, scale = auto, cmax = auto, palette = :abaqus, size = (1600, 1000),
                 px_per_unit = 2, ssao = true, edges = true, parts = default, azimuth = -0.95, elevation = 0.42, zoom = :fit,
                 title = "", charts = false, mode = 0)

Write a PNG of frame `frame` (index into the kept frames) with GLMakie: banded contours with a colour bar, element
edges, screen-space ambient occlusion and anti-aliasing at `px_per_unit` supersampling. `mode > 0` draws that
buckling mode instead.
"""
function render_image(path::AbstractString, v::VizData, frame::Int = nframes(v); field::Symbol = v.fields[1].key, scale = v.default_scale,
                      cmax = nothing, palette::Symbol = :abaqus, size = (1600, 1000), px_per_unit = 2, ssao::Bool = true, edges::Bool = true,
                      parts = [p.visible for p in v.parts], azimuth = -0.95, elevation = 0.42, zoom = :fit, title::AbstractString = "",
                      charts::Bool = false, mode::Int = 0)
    GLMakie.activate!(; ssao, fxaa = true, px_per_unit, visible = false)
    fd = v.fields[fieldindex(v, field)]
    cm = cmax === nothing ? fd.max : float(cmax)
    fig = Figure(; size, backgroundcolor = :white, figure_padding = 14)
    ls = LScene(fig[1, 1]; show_axis = false, scenekw = (; lights = _lights(v.up), backgroundcolor = RGBf(0.96, 0.96, 0.95), clear = true))
    draw_model!(ls, v, frame, fd; scale, cmax = cm, palette, edges, parts = collect(Bool, parts), ssao, mode)
    set_camera!(ls, v; azimuth, elevation, zoom, aspect = (size[1] - (charts && !isempty(v.charts) ? 560 : 130)) / size[2])
    if mode > 0
        Colorbar(fig[1, 2]; colormap = cgrad(sequential_bands(palette), NBANDS; categorical = true), limits = (0, 1),
                 label = "normalised translation", width = 22, ticklabelsize = 13, labelsize = 14, height = Relative(0.6), tellheight = false)
        info = _strip(v.modes[mode].info) * "    mode shape ×" * fmt(scale)
    else
        bands = fd.kind == :seq ? sequential_bands(palette) : diverging_bands(palette)
        lo = fd.kind == :seq ? 0.0 : -cm
        ticks = collect(range(lo, cm; length = NBANDS + 1))
        Colorbar(fig[1, 2]; colormap = cgrad(bands, NBANDS; categorical = true), limits = (lo, cm), ticks = (ticks, fmt.(ticks)),
                 label = isempty(fd.unit) ? fd.label : "$(fd.label) ($(fd.unit))", width = 22, ticklabelsize = 13, labelsize = 14,
                 height = Relative(0.6), tellheight = false, (fd.yield ? (; highclip = YIELD_GRAY) : (;))...)
        info = v.labels[frame] * "    " * _strip(v.info[frame]) * "    deformation ×" * fmt(scale)
    end
    Label(fig[0, 1:2], isempty(title) ? info : title * "\n" * info; halign = :left, fontsize = 15, justification = :left)
    if charts && !isempty(v.charts)
        gl = GridLayout(fig[1, 3]); charts!(gl, v, frame); colsize!(fig.layout, 3, Fixed(430))
    end
    save(path, fig; px_per_unit)
    WGLMakie.activate!()
    return path
end
