// distortion_fog.gdshader — the Distortion's slow shimmer
shader_type canvas_item;

void fragment() {
    vec4 c = texture(TEXTURE, UV) * COLOR;
    float s = sin(TIME * 0.6 + FRAGCOORD.y * 0.05) * 0.5 + 0.5;
    COLOR = vec4(c.rgb * (0.96 + 0.08 * s), c.a);
}
