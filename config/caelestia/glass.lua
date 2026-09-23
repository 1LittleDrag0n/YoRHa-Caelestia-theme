if hl.plugin and hl.plugin.hyprglass then
    -- Colours generated from the current wallpaper (same file Caelestia uses for borders)
    local scheme = require("scheme.current")

    -- Tint strength: last 2 hex digits (00 = none, 30 = strong)
    local tint = tonumber(scheme.primary .. "18", 16)

    hl.plugin.hyprglass.config({
        default_theme        = "dark",
        default_preset       = "default",
        blur_iterations      = 1,
        blur_strength        = 0.5,   -- frost
        refraction_strength  = 0.6,   -- edge bending   (was ~0.8)
    chromatic_aberration = 0.3,  -- rainbow fringe (was ~0.6)
    fresnel_strength     = 0.35,  -- edge glow
    specular_strength    = 0.4,   -- top highlight
    lens_distortion      = 0.2,   -- centre bulge
    edge_thickness       = 0.04,  -- thinner bezel
    tint_color           = tint,
    layers               = { enabled = false },
    })

    hl.window_rule({ match = { tag = "game" }, tag = "+hyprglass_disabled" })
    end

-- Glass on Caelestia bar/panels (not the wallpaper)
if hl.plugin and hl.plugin.hyprglass then
    hl.plugin.hyprglass.config({ layers = { enabled = true } })
    hl.plugin.hyprglass.layer("caelestia-drawers", { mask_threshold = 0.3 })
end

-- Glass behind the desktop widget
if hl.plugin and hl.plugin.hyprglass then
    hl.plugin.hyprglass.config({ layers = { enabled = true } })
    hl.plugin.hyprglass.layer("yorha-desk", { mask_threshold = 0.1 })
end
