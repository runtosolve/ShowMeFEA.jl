# ---- banded palettes -----------------------------------------------------------------------

_hex(s) = parse(RGBf, s)
function _ramp(stops::Vector{RGBf}, n)
    out = RGBf[]
    for i in 1:n
        x = (i - 0.5) / n * (length(stops) - 1)
        k = clamp(floor(Int, x), 0, length(stops) - 2)
        f = Float32(x - k)
        a = stops[k+1]; b = stops[k+2]
        push!(out, RGBf(a.r + f * (b.r - a.r), a.g + f * (b.g - a.g), a.b + f * (b.b - a.b)))
    end
    return out
end

"`NBANDS` colors for magnitudes: `:abaqus` (blue–green–red spectrum, default), `:viridis`, `:blue` (single hue)"
function sequential_bands(palette::Symbol)
    palette == :abaqus && return [RGBf(HSV(240 * (1 - (i - 1) / (NBANDS - 1)), 0.82, 0.96)) for i in 1:NBANDS]
    palette == :blue && return _ramp(_hex.(["#e4effd", "#9ec5f4", "#3987e5", "#184f95", "#0a2a55"]), NBANDS)
    palette == :viridis && return [RGBf(c) for c in Makie.to_colormap(cgrad(:viridis, NBANDS; categorical = true))]
    throw(ArgumentError("palette must be :viridis, :abaqus or :blue"))
end
"`NBANDS` colors for signed values (blue – neutral – orange); `:abaqus` keeps the spectrum"
diverging_bands(palette::Symbol) = palette == :abaqus ? sequential_bands(:abaqus) :
                                   _ramp(_hex.(["#0b3168", "#3987e5", "#f0efec", "#eb6834", "#7c2c0a"]), NBANDS)

"the categorical colormap of the mesh: sequential bands, the yield band, diverging bands"
band_colormap(palette) = cgrad(vcat(sequential_bands(palette), YIELD_GRAY, diverging_bands(palette)), 2NBANDS + 1; categorical = true)

tohex(c) = "#" * hex(RGB{Colors.N0f8}(clamp(c.r, 0, 1), clamp(c.g, 0, 1), clamp(c.b, 0, 1)))
tohexa(c::RGBAf) = @sprintf("rgba(%d,%d,%d,%.3f)", round(Int, 255clamp(c.r, 0, 1)), round(Int, 255clamp(c.g, 0, 1)), round(Int, 255clamp(c.b, 0, 1)), clamp(c.alpha, 0, 1))

"a round number at or above `v` for contour limits"
function _nice(v)
    (isfinite(v) && v > 0) || return 1.0
    e = 10.0^floor(log10(v)); f = v / e
    return (f <= 1 ? 1.0 : f <= 1.2 ? 1.2 : f <= 1.5 ? 1.5 : f <= 2 ? 2.0 : f <= 2.5 ? 2.5 : f <= 3 ? 3.0 : f <= 4 ? 4.0 :
            f <= 5 ? 5.0 : f <= 6 ? 6.0 : f <= 8 ? 8.0 : 10.0) * e
end

fmt(x) = abs(x) >= 100 ? @sprintf("%.0f", x) : abs(x) >= 10 ? @sprintf("%.1f", x) : abs(x) >= 1 ? @sprintf("%.2f", x) :
         x == 0 ? "0" : @sprintf("%.3g", x)
