# ---- Bonito application ----------------------------------------------------------------------

const CSS = """
body { margin: 0; background: #f9f9f7; color: #0b0b0b; font: 14px/1.4 -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif; }
.smf { max-width: 1680px; margin: 0 auto; padding: 14px 18px 22px; }
.smf h1 { font-size: 20px; font-weight: 600; margin: 0; }
.smf .sub { color: #52514e; margin: 2px 0 10px; }
.smf .bar { display: flex; flex-wrap: wrap; gap: 8px 18px; align-items: center; padding: 8px 12px; background: #fcfcfb;
            border: 1px solid #e1e0d9; border-radius: 8px; margin-bottom: 10px; }
.smf .bar label { color: #52514e; font-size: 13px; display: flex; align-items: center; gap: 6px; }
.smf select, .smf input[type=number], .smf button { font: inherit; font-size: 13px; padding: 3px 6px; border: 1px solid #c3c2b7;
            border-radius: 5px; background: #fff; color: #0b0b0b; }
.smf input[type=number] { width: 72px; }
.smf button { cursor: pointer; min-width: 58px; }
.smf .step { flex: 1 1 320px; }
.smf .step input { flex: 1; }
.smf .wrap { position: relative; display: flex; align-items: stretch; background: #fff; border: 1px solid #e1e0d9; border-radius: 8px; overflow: hidden; }
.smf .left { flex: 0 0 168px; padding: 14px 0 0 14px; }
.smf .right { flex: 1 1 auto; min-width: 0; position: relative; padding-bottom: 30px; }
.smf .legend { font-size: 12px; font-variant-numeric: tabular-nums; }
.smf .legend .ttl { font-weight: 600; margin-bottom: 14px; max-width: 150px; }
.smf .legend .row { display: flex; align-items: flex-start; height: 22px; }
.smf .legend .sw { width: 30px; height: 22px; box-sizing: border-box; border: 1px solid rgba(0,0,0,0.55); border-top-width: 0; }
.smf .legend .row:first-of-type .sw { border-top-width: 1px; }
.smf .legend .lab { margin-left: 7px; transform: translateY(-8px); color: #0b0b0b; }
.smf .legend .last { height: 0; }
.smf .legend .note { color: #52514e; margin-top: 12px; }
.smf .legend .hd { color: #0b0b0b; margin-top: 16px; font-weight: 600; }
.smf .info { position: absolute; left: 8px; bottom: 8px; font-size: 12.5px; font-variant-numeric: tabular-nums; }
.smf .info b { font-weight: 600; }
.smf .bar.view button { min-width: 0; padding: 3px 8px; }
.smf .bar button.on { background: #0b0b0b; color: #fff; border-color: #0b0b0b; }
.smf .bar button:disabled { opacity: 0.45; cursor: default; }
.smf .bar .grp { display: flex; gap: 4px; align-items: center; }
.smf .bar .grp > span { color: #52514e; font-size: 13px; margin-right: 2px; }
.smf .hint { flex-basis: 100%; color: #52514e; font-size: 12px; margin-top: -2px; }
.smf .boxsel { position: fixed; border: 1.5px dashed #0b0b0b; background: rgba(11,11,11,0.06); pointer-events: none; z-index: 20; display: none; }
"""

const DEFAULT_VIEW_LABELS = Dict(:px => "+x", :mx => "−x", :py => "+y", :my => "−y", :pz => "+z", :mz => "−z")

"a JavaScript array literal whose elements are interpolated one by one (Makie plots cannot be serialized inside a Vector)"
function _jsarray(objs)
    src = Union{Bonito.JSString,Any}[Bonito.JSString("[")]
    for (i, o) in enumerate(objs)
        i > 1 && push!(src, Bonito.JSString(", "))
        push!(src, o)
    end
    push!(src, Bonito.JSString("]"))
    return Bonito.JSCode(src)
end

"""
    viewer_app(v; title = "Shell model", subtitle = "", palette = :abaqus, size = (1420, 820), frame = last,
               field = first, model_label = "Analysis (steps)", view_labels = Dict()) -> Bonito.App

The viewer as a Bonito application (see [`serve_viewer`](@ref), [`export_viewer`](@ref)). `palette` is `:abaqus`
(spectrum), `:viridis` or `:blue`; signed fields use a blue–orange diverging scale except with `:abaqus`.
`view_labels` renames the preset view buttons, e.g. `Dict(:px => "Lips +x", :mz => "End z = 0")`.

The page accepts an initial state in the URL hash: `#frame=12&field=peeq&scale=5&cmax=0.02&edges=0`, `#model=m1`
(buckling mode 1), `#part2=0` / `#ov1=0` (hide part 2 / overlay 1), `#view=mz` (preset: iso, px, mx, py, my, pz, mz)
and `#persp=0` (near-orthographic projection).

View controls: left-drag rotates about the vertical axis, right-drag pans, wheel zooms; Shift + drag or the Box zoom
button zooms to a drawn box, double-click centres on a point; preset views, Fit/Reset, zoom and orbit buttons, a
perspective toggle and a PNG export are in the second bar.
"""
function viewer_app(v::VizData; title::AbstractString = "Shell model", subtitle::AbstractString = "", palette::Symbol = :abaqus,
                    size = (1420, 820), frame::Int = nframes(v), field::Symbol = v.fields[1].key, model_label::AbstractString = "Analysis (steps)",
                    view_labels = Dict{Symbol,String}())
    vl = merge(DEFAULT_VIEW_LABELS, Dict{Symbol,String}(Symbol(k) => String(s) for (k, s) in view_labels))
    return App(; title) do session
        WGLMakie.activate!()
        fd0 = v.fields[fieldindex(v, field)]
        fig = Figure(; size, backgroundcolor = :white, figure_padding = (4, 12, 8, 8))
        ls = LScene(fig[1, 1]; show_axis = false, scenekw = (; lights = _lights(v.up), backgroundcolor = RGBf(0.96, 0.96, 0.95), clear = true))
        p = draw_model!(ls, v, frame, fd0; scale = v.default_scale, cmax = fd0.max, palette)
        set_camera!(ls, v)
        markers = []
        if !isempty(v.charts)
            gl = GridLayout(fig[1, 2])
            markers = charts!(gl, v, frame)
            colsize!(fig.layout, 2, Fixed(420))
        end
        mk = [m for m in markers if m !== nothing]
        mk_chart = [i - 1 for (i, m) in enumerate(markers) if m !== nothing]

        nn = Base.size(v.x, 1); npv = length(v.pv_node)
        data = Dict(
            "nn" => nn, "npv" => npv, "nf" => nframes(v), "nbands" => NBANDS, "yield_tol" => YIELD_TOL, "gray" => tohex(YIELD_GRAY),
            "x" => vec(permutedims(v.x)), "pv_node" => Int32.(v.pv_node .- 1), "pv_off" => vec(permutedims(v.pv_off)), "pv_fy" => v.pv_fy,
            "sv_pv" => Int32.(v.sv_pv .- 1), "sv_side" => Int8.(v.sv_side),
            "faces" => UInt32[UInt32(i - 1) for f in v.faces for i in f], "face_part" => Int32.(v.face_part),
            "edges" => UInt32[UInt32(i - 1) for e in v.edges for i in e], "edge_part" => Int32.(v.edge_part),
            "feature" => UInt32[UInt32(i - 1) for e in v.feature for i in e], "feature_part" => Int32.(v.feature_part),
            "disp" => vec(v.disp),
            "stored" => Dict(String(k) => vec(a) for (k, a) in v.stored),
            "range" => Dict(String(k) => [r[1], r[2]] for (k, r) in v.range),
            "fields" => [Dict("key" => String(f.key), "label" => f.label, "unit" => f.unit, "kind" => String(f.kind), "top" => String(f.top),
                              "bot" => String(f.bot), "auto" => f.max, "yield" => f.yield) for f in v.fields],
            "seq" => tohex.(sequential_bands(palette)), "div" => tohex.(diverging_bands(palette)),
            "default_scale" => v.default_scale, "frame0" => frame - 1, "field0" => String(field), "size" => v.size, "center" => v.center,
            "up" => v.up == :y ? [0, 1, 0] : [0, 0, 1], "labels" => v.labels, "info" => v.info, "notes" => v.notes,
            "parts" => [Dict("name" => p.name, "toggle" => p.toggle, "visible" => p.visible) for p in v.parts],
            "overlays" => [Dict("name" => o.name, "kind" => String(o.kind), "npts" => npoints(o), "nfo" => Base.size(o.offset, 3),
                                "anchor" => Int32.(o.anchor .- 1), "off" => vec(o.offset), "toggle" => o.toggle, "visible" => o.visible,
                                "requires" => o.requires - 1, "notes" => o.notes, "in_modes" => o.in_modes) for o in v.overlays],
            "charts" => [Dict("xs" => c.marker === nothing ? Float64[] : c.marker.x, "ys" => c.marker === nothing ? Float64[] : c.marker.y) for c in v.charts],
            "mk_chart" => mk_chart,
            "nmodes" => length(v.modes), "modes" => [Dict("label" => m.label, "info" => m.info) for m in v.modes],
            "mode_disp" => (isempty(v.modes) ? Float32[] : reduce(vcat, [vec(m.disp) for m in v.modes])),
        )

        sel = DOM.select([DOM.option(f.label; value = String(f.key)) for f in v.fields]...)
        model = DOM.select(DOM.option(model_label; value = "c"), [DOM.option(m.label; value = "m$k") for (k, m) in enumerate(v.modes)]...)
        slider = DOM.input(; type = "range", min = "0", max = string(nframes(v) - 1), step = "1", value = string(frame - 1))
        play = DOM.button("Play")
        steplab = DOM.span(""; style = "min-width: 70px; color: #0b0b0b;")
        scale = DOM.input(; type = "number", min = "0", step = "any", value = string(v.default_scale))
        cmax = DOM.input(; type = "number", min = "0", step = "any", value = string(fd0.max))
        auto = DOM.button("Auto")
        cb(lbl, checked) = (i = DOM.input(; type = "checkbox", (checked ? (; checked = true) : (;))...); (i, DOM.label(i, lbl)))
        c_ed, l_ed = cb("Mesh edges", true)
        c_gh, l_gh = cb("Undeformed outline", false)
        tcb(lbl, checked, cls, i) = (c = DOM.input(; type = "checkbox", class = cls, value = string(i), (checked ? (; checked = true) : (;))...); (c, DOM.label(c, lbl)))
        part_cb = [p.toggle ? tcb(p.name, p.visible, "smf-part", i) : (nothing, nothing) for (i, p) in enumerate(v.parts)]
        ov_cb = [o.toggle ? tcb(o.name, o.visible, "smf-ov", i) : (nothing, nothing) for (i, o) in enumerate(v.overlays)]
        legend = DOM.div(; class = "legend"); info = DOM.div(; class = "info")
        vb(lbl, ttl = "") = DOM.button(lbl; title = ttl)
        b_reset = vb("Reset", "default view, fitted to the model"); b_fit = vb("Fit", "fit the model, keeping the view direction")
        b_iso = vb("Iso"); b_px = vb(vl[:px]); b_mx = vb(vl[:mx]); b_py = vb(vl[:py]); b_my = vb(vl[:my]); b_pz = vb(vl[:pz]); b_mz = vb(vl[:mz])
        b_box = vb("Box zoom", "drag a box over the model to zoom to it (or Shift + drag at any time); Esc cancels")
        b_zi = vb("Zoom +"); b_zo = vb("Zoom −"); b_rl = vb("⟲ 15°", "orbit left"); b_rr = vb("⟳ 15°", "orbit right")
        b_up = vb("Tilt ▲", "view more from above"); b_dn = vb("Tilt ▼", "view more from below")
        c_pp, l_pp = cb("Perspective", true)
        b_png = vb("Save PNG", "save the figure as shown")
        hint = DOM.div("Left-drag rotates, right-drag pans, wheel zooms. Shift + drag (or Box zoom) zooms to a box; double-click centres the view on a point; Esc cancels a box."; class = "hint")

        code = js"""
        (() => {
        const D = $(data);
        const el = {sel: $(sel), model: $(model), slider: $(slider), play: $(play), steplab: $(steplab), scale: $(scale), cmax: $(cmax), auto: $(auto),
                    ed: $(c_ed), gh: $(c_gh), legend: $(legend), info: $(info),
                    reset: $(b_reset), fit: $(b_fit), iso: $(b_iso), px: $(b_px), mx: $(b_mx), py: $(b_py), my: $(b_my), pz: $(b_pz), mz: $(b_mz),
                    box: $(b_box), zi: $(b_zi), zo: $(b_zo), rl: $(b_rl), rr: $(b_rr), up: $(b_up), dn: $(b_dn), pp: $(c_pp), png: $(b_png)};
        const root = el.legend.closest('.smf') || document;
        el.parts = D.parts.map(() => null); root.querySelectorAll('input.smf-part').forEach(c => el.parts[parseInt(c.value) - 1] = c);
        el.ovs = D.overlays.map(() => null); root.querySelectorAll('input.smf-ov').forEach(c => el.ovs[parseInt(c.value) - 1] = c);
        const fieldByKey = {}; D.fields.forEach(f => fieldByKey[f.key] = f);
        el.sel.value = D.field0;
        const hash = new URLSearchParams(window.location.hash.slice(1));
        if (hash.has('field') && fieldByKey[hash.get('field')]) el.sel.value = hash.get('field');
        if (hash.has('frame')) el.slider.value = Math.max(0, Math.min(D.nf - 1, parseInt(hash.get('frame'))));
        if (hash.has('model') && [...el.model.options].some(o => o.value === hash.get('model'))) { el.model.value = hash.get('model'); if (hash.get('model') !== 'c') el.scale.value = 1; }
        if (hash.has('scale')) el.scale.value = hash.get('scale');
        if (hash.has('edges')) el.ed.checked = hash.get('edges') !== '0';
        el.parts.forEach((c, i) => { if (c && hash.has('part' + (i + 1))) c.checked = hash.get('part' + (i + 1)) !== '0'; });
        el.ovs.forEach((c, i) => { if (c && hash.has('ov' + (i + 1))) c.checked = hash.get('ov' + (i + 1)) !== '0'; });
        const num = (x) => Number(Number(x).toPrecision(4));
        el.cmax.value = hash.has('cmax') ? hash.get('cmax') : num(fieldByKey[el.sel.value].auto);

        const nsv = D.sv_pv.length, NB = D.nbands;
        const pos = new Float32Array(nsv * 3), nor = new Float32Array(nsv * 3), col = new Float32Array(nsv);
        const fmt = (x) => { const a = Math.abs(x); if (x === 0) return '0';
            return a >= 100 ? x.toFixed(0) : a >= 10 ? x.toFixed(1) : a >= 1 ? x.toFixed(2) : Number(x.toPrecision(3)).toString(); };
        const modeOf = () => el.model.value === 'c' ? 0 : parseInt(el.model.value.slice(1));   // 0 = analysis, k = mode k
        const partVis = () => D.parts.map((p, i) => el.parts[i] ? el.parts[i].checked : p.visible);
        const pick = (idx, part, vis, n) => {
            if (vis.every(x => x)) return idx;
            const out = [];
            for (let i = 0; i < part.length; i++) if (vis[part[i] - 1]) for (let j = 0; j < n; j++) out.push(idx[n * i + j]);
            return new Uint32Array(out);
        };
        function positions(k, s) {
            const m = modeOf(), U = m ? D.mode_disp : D.disp, o = (m ? m - 1 : k) * D.nn * 3;
            for (let i = 0; i < nsv; i++) {
                const p = D.sv_pv[i], n = D.pv_node[p], sg = D.sv_side[i];
                pos[3*i]   = D.x[3*n]   + s * U[o + 3*n]   + sg * D.pv_off[3*p];
                pos[3*i+1] = D.x[3*n+1] + s * U[o + 3*n+1] + sg * D.pv_off[3*p+1];
                pos[3*i+2] = D.x[3*n+2] + s * U[o + 3*n+2] + sg * D.pv_off[3*p+2];
            }
        }
        function normals() {
            nor.fill(0);
            const F = D.faces;
            for (let f = 0; f < F.length; f += 3) {
                const a = 3*F[f], b = 3*F[f+1], c = 3*F[f+2];
                const ux = pos[b]-pos[a], uy = pos[b+1]-pos[a+1], uz = pos[b+2]-pos[a+2];
                const vx = pos[c]-pos[a], vy = pos[c+1]-pos[a+1], vz = pos[c+2]-pos[a+2];
                const nx = uy*vz-uz*vy, ny = uz*vx-ux*vz, nz = ux*vy-uy*vx;
                nor[a] += nx; nor[a+1] += ny; nor[a+2] += nz; nor[b] += nx; nor[b+1] += ny; nor[b+2] += nz; nor[c] += nx; nor[c+1] += ny; nor[c+2] += nz;
            }
            for (let i = 0; i < nsv; i++) {
                const l = Math.hypot(nor[3*i], nor[3*i+1], nor[3*i+2]) || 1;
                nor[3*i] /= l; nor[3*i+1] /= l; nor[3*i+2] /= l;
            }
        }
        function colors(k, f, cmax) {
            const m = modeOf();
            if (m) {   // mode: colour = normalised translation magnitude
                const U = D.mode_disp, o = (m - 1) * D.nn * 3; let vmax = 0;
                for (let i = 0; i < nsv; i++) {
                    const n = D.pv_node[D.sv_pv[i]], val = Math.hypot(U[o+3*n], U[o+3*n+1], U[o+3*n+2]);
                    if (val > vmax) vmax = val;
                    col[i] = NB * Math.max(0, Math.min(1 - 1e-6, val));
                }
                return [0, vmax];
            }
            const lo = f.kind === 'seq' ? 0 : -cmax, hi = cmax, base = f.kind === 'seq' ? 0 : NB + 1;
            const top = D.stored[f.top], bot = D.stored[f.bot], rt = D.range[f.top], rb = D.range[f.bot], o = k * D.npv;
            let vmax = -Infinity, vmin = Infinity;
            for (let i = 0; i < nsv; i++) {
                const t = D.sv_side[i] > 0, q = (t ? top : bot)[o + D.sv_pv[i]];
                if (q === 65535) { col[i] = NaN; continue; }
                const r = t ? rt : rb, val = r[0] + q / 65534 * (r[1] - r[0]);
                if (val > vmax) vmax = val; if (val < vmin) vmin = val;
                col[i] = (f.yield && val >= D.yield_tol * D.pv_fy[D.sv_pv[i]]) ? NB + 0.5 : base + NB * Math.max(0, Math.min(1 - 1e-6, (val - lo) / (hi - lo)));
            }
            return [vmin, vmax];
        }
        function segments(idx) {
            const out = new Float32Array(idx.length * 3);
            for (let i = 0; i < idx.length; i++) { const a = 3 * idx[i]; out[3*i] = pos[a]; out[3*i+1] = pos[a+1]; out[3*i+2] = pos[a+2]; }
            return out;
        }
        function overlayPoints(ov, k, s) {
            const np = ov.npts, kk = ov.nfo === 1 ? 0 : k, o = k * D.nn * 3, out = new Float32Array(np * 3);
            for (let p = 0; p < np; p++) {
                const a = ov.anchor[p], q = (kk * np + p) * 3;
                if (a < 0) { out[3*p] = ov.off[q]; out[3*p+1] = ov.off[q+1]; out[3*p+2] = ov.off[q+2]; continue; }
                out[3*p]   = D.x[3*a]   + s * D.disp[o + 3*a]   + ov.off[q];
                out[3*p+1] = D.x[3*a+1] + s * D.disp[o + 3*a+1] + ov.off[q+1];
                out[3*p+2] = D.x[3*a+2] + s * D.disp[o + 3*a+2] + ov.off[q+2];
            }
            return out;
        }
        const ovVisible = (i, vis, m) => { const ov = D.overlays[i], c = el.ovs[i];
            return (c ? c.checked : ov.visible) && (ov.requires < 0 || vis[ov.requires]) && (!m || ov.in_modes); };
        function legend(f, cmax, ext, k, m, vis) {
            const cols = (m || f.kind === 'seq') ? D.seq : D.div, lo = (m || f.kind === 'seq') ? 0 : -cmax;
            if (m) cmax = 1;
            let h = '<div class="ttl">' + (m ? 'Translation (normalised, largest component = 1)' : f.label + (f.unit ? ' (' + f.unit + ')' : '')) + '</div>';
            if (f.yield && !m) {
                const fys = Array.from(new Set(Array.from(D.pv_fy).filter(x => x < 1e29).map(x => fmt(x))));
                if (fys.length) h += '<div class="row" style="margin-bottom:12px"><div class="sw" style="border-top-width:1px;background:' + D.gray + '"></div><div class="lab" style="transform:none">yielded (≥ ' + fys.join(' / ') + ')</div></div>';
            }
            for (let b = NB - 1; b >= 0; b--)
                h += '<div class="row"><div class="sw" style="background:' + cols[b] + '"></div><div class="lab">' + fmt(lo + (b + 1) * (cmax - lo) / NB) + '</div></div>';
            h += '<div class="row last"><div style="width:30px"></div><div class="lab">' + fmt(lo) + '</div></div>';
            h += '<div class="note">this step: ' + (isFinite(ext[0]) ? fmt(ext[0]) + ' to ' + fmt(ext[1]) : 'no values') + '</div>';
            if (!m) D.overlays.forEach((ov, i) => {
                if (!ov.notes.length || !ovVisible(i, vis, m)) return;
                h += '<div class="hd">' + ov.name + '</div><div class="note" style="margin-top:4px">' + ov.notes[k] + '</div>';
            });
            if (D.notes.length) { h += '<div class="hd">Reference</div>'; D.notes.forEach((n, i) => { h += '<div class="note" style="margin-top:' + (i ? 2 : 4) + 'px">' + n + '</div>'; }); }
            el.legend.innerHTML = h;
        }

        const ovPlots = $(_jsarray(p.overlays)), mkPlots = $(_jsarray(mk));
        Promise.all([$(p.mesh), $(p.edges), $(p.feature), $(p.ghost), ...ovPlots, ...mkPlots]).then((plots) => {
            const po = (a) => a[0].plot_object || a[0];
            const mesh = po(plots[0]), edges = po(plots[1]), feature = po(plots[2]), ghost = po(plots[3]);
            const ovs = ovPlots.map((_, i) => po(plots[4 + i])), mks = mkPlots.map((_, i) => po(plots[4 + ovPlots.length + i]));
            const setbuf = (plot, names, arr) => {
                const g = plot.mesh.geometry, key = names.find(n => (n in g.attributes) || (g.interleaved_attributes && n in g.interleaved_attributes));
                if (key) plot.update([[key, arr]]); else console.warn('ShowMeFEA: none of', names, 'in', Object.keys(g.attributes));
            };
            window.__smf = {el, D, mesh, edges, feature, ghost, ovs, mks};

            // ---- 3D view controls: replace WGLMakie's orbit controls with ones about the model's vertical axis ----
            const cam = (() => {
                const scene = mesh.parent || (mesh.mesh && mesh.mesh.parent), T3 = window.THREE, WGL = window.WGL;
                if (!scene || !scene.orbitcontrols || !T3 || !WGL) { console.warn('ShowMeFEA: orbit controls not found'); return null; }
                const screen = scene.screen, canvas = screen.canvas, wcam = scene.wgl_camera, old = scene.orbitcontrols, camera = old.object;
                old.dispose();
                const UP = D.up, upAxis = UP[1] ? 1 : 2, ALT = upAxis === 1 ? [1, 0, 0] : [0, 1, 0];
                camera.up.set(...UP);
                const inScene = (e) => { const [x, y] = WGL.events2unitless(screen, e), [sx, sy, sw, sh] = scene.viewport.value; return x >= sx && x < sx + sw && y >= sy && y < sy + sh; };
                const ctl = new old.constructor(camera, canvas, () => true, inScene);
                ctl.target.copy(old.target); scene.orbitcontrols = ctl;
                const sync = () => {
                    const [w, h] = wcam.resolution.value, dd = camera.position.distanceTo(ctl.target);
                    camera.aspect = w / h; camera.near = 0.05 * dd; camera.far = dd + 4 * D.size;
                    camera.updateProjectionMatrix(); camera.updateWorldMatrix();
                    wcam.update_matrices(camera.matrixWorldInverse.elements, camera.projectionMatrix.elements, [w, h], camera.position.toArray());
                    if (wcam.original_light_direction) wcam.update_light_dir(wcam.original_light_direction);
                };
                ctl.addEventListener('change', sync);
                const FOV = 28, ORTHO_FOV = 1.5;
                const dir = () => new T3.Vector3().subVectors(camera.position, ctl.target).normalize();
                const dist = () => camera.position.distanceTo(ctl.target);
                const place = (target, d, len) => { ctl.target.copy(target); camera.position.copy(target).addScaledVector(d, len); ctl.update(); sync(); };
                const bbox = () => {
                    const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
                    for (let i = 0; i < nsv; i++) for (let j = 0; j < 3; j++) { const q = pos[3*i+j]; if (q < lo[j]) lo[j] = q; if (q > hi[j]) hi[j] = q; }
                    return [lo, hi];
                };
                const fitDist = (target, d, up) => {
                    const [lo, hi] = bbox(), f = d.clone().negate(), [w, h] = wcam.resolution.value;
                    const r = new T3.Vector3().crossVectors(f, up).normalize(), u = new T3.Vector3().crossVectors(r, f).normalize();
                    const tv = Math.tan(camera.fov * Math.PI / 360), th = tv * w / h; let need = 0;
                    for (let m = 0; m < 8; m++) {
                        const p = new T3.Vector3(m & 1 ? hi[0] : lo[0], m & 2 ? hi[1] : lo[1], m & 4 ? hi[2] : lo[2]).sub(target), dz = p.dot(f);
                        need = Math.max(need, Math.abs(p.dot(u)) / tv + dz, Math.abs(p.dot(r)) / th + dz);
                    }
                    return 1.06 * need;
                };
                const view = (d, up, fit = true) => {
                    d = new T3.Vector3(...d).normalize(); camera.up.set(...up);
                    const [lo, hi] = bbox(), c = new T3.Vector3((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2);
                    place(c, d, fit ? fitDist(c, d, camera.up) : dist());
                };
                const A = -0.95, E = 0.42;
                const ISO = upAxis === 1 ? [Math.cos(E) * Math.cos(A), Math.sin(E), Math.cos(E) * Math.sin(A)]
                                         : [Math.cos(E) * Math.cos(A), Math.cos(E) * Math.sin(A), Math.sin(E)];
                const ax = (i, sg) => { const d = [0, 0, 0]; d[i] = sg; return d; };
                const upFor = (i) => i === upAxis ? ALT : UP;
                const presets = { iso: [ISO, UP], px: [ax(0, 1), upFor(0)], mx: [ax(0, -1), upFor(0)], py: [ax(1, 1), upFor(1)], my: [ax(1, -1), upFor(1)],
                                  pz: [ax(2, 1), upFor(2)], mz: [ax(2, -1), upFor(2)] };
                const zoom = (f) => place(ctl.target.clone(), dir(), dist() * f);
                const orbit = (ang) => place(ctl.target.clone(), dir().applyAxisAngle(camera.up.clone().normalize(), ang), dist());
                const tilt = (ang) => {
                    const d = dir(), up = camera.up.clone().normalize(), axis = new T3.Vector3().crossVectors(d, up);
                    if (axis.length() < 1e-6) return;
                    const d2 = d.clone().applyAxisAngle(axis.normalize(), ang);
                    if (Math.abs(d2.dot(up)) > 0.995) return;
                    place(ctl.target.clone(), d2, dist());
                };
                const setPersp = (on) => {
                    const f0 = camera.fov, f1 = on ? FOV : ORTHO_FOV; if (f0 === f1) return;
                    const k = Math.tan(f0 * Math.PI / 360) / Math.tan(f1 * Math.PI / 360); camera.fov = f1;
                    place(ctl.target.clone(), dir(), dist() * k);
                };
                const ndcOf = (e) => { const [x, y] = WGL.events2unitless(screen, e), [sx, sy, sw, sh] = scene.viewport.value; return [2 * (x - sx) / sw - 1, 2 * (y - sy) / sh - 1]; };
                const zoomTo = (ax_, ay, bx, by, opts = {}) => {
                    const x0 = Math.min(ax_, bx), x1 = Math.max(ax_, bx), y0 = Math.min(ay, by), y1 = Math.max(ay, by);
                    camera.updateMatrixWorld();
                    const Em = new T3.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse).elements;
                    let sx = 0, sy = 0, sz = 0, n = 0;
                    for (let i = 0; i < nsv; i++) {
                        const x = pos[3*i], y = pos[3*i+1], z = pos[3*i+2], w = Em[3]*x + Em[7]*y + Em[11]*z + Em[15];
                        if (w <= 0) continue;
                        const cx = (Em[0]*x + Em[4]*y + Em[8]*z + Em[12]) / w; if (cx < x0 || cx > x1) continue;
                        const cy = (Em[1]*x + Em[5]*y + Em[9]*z + Em[13]) / w; if (cy < y0 || cy > y1) continue;
                        sx += x; sy += y; sz += z; n++;
                    }
                    if (!n && opts.requireHit) return;
                    const frac = Math.max((x1 - x0) / 2, (y1 - y0) / 2), d = dir();
                    let c;
                    if (n) c = new T3.Vector3(sx / n, sy / n, sz / n);
                    else { const zt = ctl.target.clone().project(camera).z; c = new T3.Vector3((x0 + x1) / 2, (y0 + y1) / 2, zt).unproject(camera); }
                    const depth = Math.max(1e-3, new T3.Vector3().subVectors(c, camera.position).dot(d.clone().negate()));
                    place(c, d, (opts.keep || frac < 0.01) ? dist() : Math.max(frac * depth, 0.01 * D.size));
                };
                let boxMode = false, drag = null;
                const rect = document.createElement('div'); rect.className = 'boxsel'; document.body.appendChild(rect);
                const setBox = (on) => { boxMode = on; el.box.classList.toggle('on', on); canvas.style.cursor = on ? 'crosshair' : ''; };
                const cancel = () => { rect.style.display = 'none'; drag = null; };
                canvas.addEventListener('pointerdown', (e) => {
                    if (e.button !== 0 || !(boxMode || e.shiftKey) || !inScene(e)) return;
                    e.stopImmediatePropagation(); e.preventDefault();
                    drag = { x: e.clientX, y: e.clientY, ndc: ndcOf(e) };
                    Object.assign(rect.style, { display: 'block', left: e.clientX + 'px', top: e.clientY + 'px', width: '0px', height: '0px' });
                    try { canvas.setPointerCapture(e.pointerId); } catch (_) {}
                }, true);
                canvas.addEventListener('pointermove', (e) => {
                    if (!drag) return; e.stopImmediatePropagation();
                    Object.assign(rect.style, { left: Math.min(drag.x, e.clientX) + 'px', top: Math.min(drag.y, e.clientY) + 'px',
                                                width: Math.abs(e.clientX - drag.x) + 'px', height: Math.abs(e.clientY - drag.y) + 'px' });
                }, true);
                canvas.addEventListener('pointerup', (e) => {
                    if (!drag) return; e.stopImmediatePropagation();
                    const [ax_, ay] = drag.ndc, [bx, by] = ndcOf(e); cancel(); setBox(false); zoomTo(ax_, ay, bx, by);
                }, true);
                canvas.addEventListener('pointercancel', (e) => { if (drag) { e.stopImmediatePropagation(); cancel(); setBox(false); } }, true);
                window.addEventListener('keydown', (e) => { if (e.key === 'Escape') { cancel(); setBox(false); } });
                canvas.addEventListener('dblclick', (e) => {
                    if (!inScene(e)) return; e.preventDefault();
                    const [, , sw, sh] = scene.viewport.value, [x, y] = ndcOf(e), hx = 24 / sw, hy = 24 / sh;
                    zoomTo(x - hx, y - hy, x + hx, y + hy, { keep: true, requireHit: true });
                });
                const savePNG = () => {
                    const k = parseInt(el.slider.value), m = modeOf();
                    const a = document.createElement('a');
                    a.download = document.title.replace(/[^\\w.-]+/g, '_') + '_' + (m ? 'mode' + m : 'step' + k) + '_' + el.sel.value + '.png';
                    a.href = canvas.toDataURL('image/png'); a.click();
                };
                const reset = () => { el.pp.checked = true; camera.fov = FOV; view(...presets.iso); };
                return { ctl, camera, view, presets, zoom, orbit, tilt, setPersp, setBox, boxMode: () => boxMode, zoomTo, reset, savePNG, fit: () => view(dir().toArray(), camera.up.toArray()) };
            })();
            window.__smf.cam = cam;
            let lastVis = null;
            function render() {
                const k = parseInt(el.slider.value), f = fieldByKey[el.sel.value];
                const s = parseFloat(el.scale.value) || 0, cmax = parseFloat(el.cmax.value) > 0 ? parseFloat(el.cmax.value) : f.auto;
                const vis = partVis(), m = modeOf();
                positions(k, s); normals();
                const ext = colors(k, f, cmax);
                el.slider.disabled = !!m; el.sel.disabled = !!m; el.play.disabled = !!m; el.cmax.disabled = !!m; el.auto.disabled = !!m;
                setbuf(mesh, ['positions_transformed_f32c', 'position'], pos);
                setbuf(mesh, ['normals', 'normal'], nor);
                setbuf(mesh, ['vertex_color', 'color'], col);
                const visKey = vis.join(',');
                if (lastVis !== visKey) { mesh.update([['faces', pick(D.faces, D.face_part, vis, 3)]]); lastVis = visKey; }
                edges.update([['positions_transformed_f32c', segments(pick(D.edges, D.edge_part, vis, 2))], ['visible', el.ed.checked]]);
                feature.update([['positions_transformed_f32c', segments(pick(D.feature, D.feature_part, vis, 2))]]);
                ghost.update([['visible', el.gh.checked]]);
                D.overlays.forEach((ov, i) => {
                    const pts = overlayPoints(ov, k, s), show = ovVisible(i, vis, m);
                    if (ov.kind === 'markers') { setbuf(ovs[i], ['positions_transformed_f32c', 'offset'], pts); ovs[i].update([['visible', show]]); }
                    else ovs[i].update([['positions_transformed_f32c', pts], ['visible', show]]);
                });
                mks.forEach((mk, i) => { const c = D.charts[D.mk_chart[i]];
                    setbuf(mk, ['wgl_positions', 'positions_transformed_f32c'], new Float32Array([c.xs[k], c.ys[k]])); mk.update([['visible', !m]]); });
                legend(f, cmax, ext, k, m, vis);
                el.steplab.textContent = m ? D.modes[m-1].label : D.labels[k];
                el.info.innerHTML = (m ? D.modes[m-1].info + ' &nbsp; mode shape ×' : D.info[k] + ' &nbsp; deformation ×') + fmt(s);
                window.__smf_rendered = (window.__smf_rendered || 0) + 1;
            }
            let timer = null;
            const stop = () => { if (timer) { clearInterval(timer); timer = null; el.play.textContent = 'Play'; } };
            el.play.onclick = () => {
                if (timer) return stop();
                if (parseInt(el.slider.value) >= D.nf - 1) el.slider.value = 0;
                el.play.textContent = 'Pause';
                timer = setInterval(() => { const k = parseInt(el.slider.value); if (k >= D.nf - 1) return stop(); el.slider.value = k + 1; render(); }, 200);
            };
            el.slider.oninput = render; el.scale.oninput = render; el.cmax.oninput = render;
            el.sel.onchange = () => { el.cmax.value = num(fieldByKey[el.sel.value].auto); render(); };
            el.model.onchange = () => { stop(); el.scale.value = modeOf() ? 1 : D.default_scale; render(); };
            el.auto.onclick = () => { el.cmax.value = num(fieldByKey[el.sel.value].auto); render(); };
            [el.ed, el.gh, ...el.parts, ...el.ovs].forEach(c => { if (c) c.onchange = render; });
            const viewButtons = [el.reset, el.fit, el.iso, el.px, el.mx, el.py, el.my, el.pz, el.mz, el.box, el.zi, el.zo, el.rl, el.rr, el.up, el.dn, el.png];
            if (cam) {
                el.reset.onclick = cam.reset; el.fit.onclick = cam.fit;
                for (const k of ['iso', 'px', 'mx', 'py', 'my', 'pz', 'mz']) el[k].onclick = () => cam.view(...cam.presets[k]);
                el.zi.onclick = () => cam.zoom(1 / 1.4); el.zo.onclick = () => cam.zoom(1.4);
                el.rl.onclick = () => cam.orbit(Math.PI / 12); el.rr.onclick = () => cam.orbit(-Math.PI / 12);
                el.up.onclick = () => cam.tilt(Math.PI / 12); el.dn.onclick = () => cam.tilt(-Math.PI / 12);
                el.pp.onchange = () => cam.setPersp(el.pp.checked); el.box.onclick = () => cam.setBox(!cam.boxMode()); el.png.onclick = cam.savePNG;
            } else { viewButtons.forEach(b => b.disabled = true); el.pp.disabled = true; }
            render();
            if (cam) {
                cam.reset();
                if (hash.has('view') && cam.presets[hash.get('view')]) cam.view(...cam.presets[hash.get('view')]);
                if (hash.get('persp') === '0') { el.pp.checked = false; cam.setPersp(false); }
                if (hash.has('box')) { const b = hash.get('box').split(',').map(Number); if (b.length === 4 && b.every(isFinite)) cam.zoomTo(...b); }
            }
        }).catch(e => console.error('ShowMeFEA:', e));
        })();
        """
        Bonito.onload(session, legend, js"() => { $(code) }")
        toggles = Any[l_ed, l_gh]
        append!(toggles, [l for (_, l) in part_cb if l !== nothing]); append!(toggles, [l for (_, l) in ov_cb if l !== nothing])
        bar1 = Any[DOM.label("Model ", model; style = isempty(v.modes) ? "display:none" : ""), DOM.label("Contour ", sel), DOM.label("max ", cmax, auto),
                   DOM.label(play, slider, steplab; class = "step"), DOM.label("Deformation × ", scale)]
        append!(bar1, toggles)
        return DOM.div(DOM.style(CSS),
            DOM.h1(title), DOM.div(subtitle; class = "sub"),
            DOM.div(bar1...; class = "bar"),
            DOM.div(DOM.div(DOM.span("View"), b_reset, b_fit, b_iso, b_px, b_mx, b_py, b_my, b_mz, b_pz; class = "grp"),
                    DOM.div(DOM.span("Zoom"), b_box, b_zi, b_zo; class = "grp"),
                    DOM.div(DOM.span("Orbit"), b_rl, b_rr, b_up, b_dn; class = "grp"), l_pp, b_png, hint; class = "bar view"),
            DOM.div(DOM.div(legend; class = "left"), DOM.div(fig, info; class = "right"); class = "wrap"); class = "smf")
    end
end

"""
    serve_viewer(v; port = 8642, kwargs...) -> Bonito.Server

Serve the viewer at `http://localhost:port` (keywords as [`viewer_app`](@ref)).
"""
function serve_viewer(v::VizData; port::Int = 8642, kw...)
    app = viewer_app(v; kw...)
    server = Bonito.Server(app, "127.0.0.1", port)
    println("ShowMeFEA: http://localhost:$port")
    return server
end

"""
    export_viewer(path, v; kwargs...) -> path

Write the viewer as one standalone HTML file (keywords as [`viewer_app`](@ref)). The page needs no Julia process
and no internet connection; all interaction runs in the browser. The page is written to a temporary file first and
then copied, so slow or synced destinations (cloud drives) do not time out on the stream.
"""
function export_viewer(path::AbstractString, v::VizData; kw...)
    tmp = joinpath(mktempdir(), basename(path))
    Bonito.export_static(tmp, viewer_app(v; kw...))
    mkpath(dirname(abspath(path))); cp(tmp, path; force = true); rm(tmp; force = true)
    return path
end
