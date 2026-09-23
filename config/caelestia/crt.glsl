#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

void main() {
    vec4 c = texture(tex, v_texcoord);

    // Scanlines every 3px
    float scan = mod(gl_FragCoord.y, 3.0) < 1.0 ? 0.90 : 1.0;

    // Faint 48px grid
    vec2 g = mod(gl_FragCoord.xy, 48.0);
    float grid = (g.x < 1.0 || g.y < 1.0) ? 0.95 : 1.0;

    // Slight warm gold cast (YoRHa accent 8f7c4a)
    vec3 gold = vec3(0.561, 0.486, 0.290);
    c.rgb = mix(c.rgb, c.rgb * gold * 1.7, 0.08);

    // Vignette toward the edges
    float vig = 1.0 - smoothstep(0.35, 0.85, length(v_texcoord - 0.5)) * 0.35;

    c.rgb *= scan * grid * vig;
    fragColor = c;
}
