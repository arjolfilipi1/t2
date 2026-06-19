shader_type canvas_item;

uniform vec4  glow_color : source_color = vec4(0.2, 1.0, 0.3, 1.0);
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform bool  glow_enabled = false;
uniform float pulse_speed = 1.0;
uniform float card_w = 100.0;
uniform float card_h = 145.0;

void fragment() {
    if (!glow_enabled) {
        COLOR = vec4(0.0);
    }
    
    vec2 uv = UV;
    float dx = min(uv.x, 1.0 - uv.x) * card_w;
    float dy = min(uv.y, 1.0 - uv.y) * card_h;
    float edge_dist = min(dx, dy);
    
    // Glow band: strong within 8px of edge, fading outward
    float band = 8.0;
    float alpha = clamp(1.0 - edge_dist / band, 0.0, 1.0);
    alpha = pow(alpha, 1.5) * glow_intensity;
    
    // Add slight inner glow for summonable/activatable
    float inner_glow = 0.0;
    if (glow_color.r > 0.9 && glow_color.b < 0.2) {
        // Yellow/orange - add slight inner glow
        inner_glow = 0.3 * (1.0 - edge_dist / (band * 2.0)) * glow_intensity;
    }
    
    COLOR = vec4(glow_color.rgb, alpha * glow_color.a);
}
