// known_tint.gdshader — known = 40% desaturated and dimmed (design_art_direction.md §3)
shader_type canvas_item;

void fragment() {
    vec4 c = texture(TEXTURE, UV) * COLOR;
    float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    COLOR = vec4(mix(vec3(g), c.rgb, 0.6) * 0.82, c.a);
}
