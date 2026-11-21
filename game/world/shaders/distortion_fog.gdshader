// distortion_fog.gdshader — Decision 72 Option C drifting Distortion fog & route mist
// Pure procedural shader (no ROM pixels, identical with and without ROM).
shader_type canvas_item;

uniform vec2 rect_origin_tiles = vec2(0.0, 0.0);
uniform vec2 rect_size_tiles = vec2(32.0, 32.0);
uniform sampler2D cell_reveal_tex : filter_nearest, repeat_disable;
uniform vec2 cell_grid_origin = vec2(-32.0, -32.0);
uniform vec2 cell_grid_size = vec2(64.0, 64.0);
uniform int town_rect_count = 0;
uniform vec4 town_rects[32];
uniform float time_override = -1.0;
uniform float zoom_scale = 1.0;

const vec3 MIST_COL = vec3(206.0, 210.0, 220.0) / 255.0;
const vec3 BANK_DARK = vec3(92.0, 96.0, 110.0) / 255.0;
const vec3 BANK_LIGHT = vec3(168.0, 172.0, 184.0) / 255.0;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p, float seed) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i + vec2(seed, seed * 1.37));
    float b = hash21(i + vec2(1.0, 0.0) + vec2(seed, seed * 1.37));
    float c = hash21(i + vec2(0.0, 1.0) + vec2(seed, seed * 1.37));
    float d = hash21(i + vec2(1.0, 1.0) + vec2(seed, seed * 1.37));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm3(vec2 p, vec2 cell_sz, float seed) {
    vec2 q = p / cell_sz;
    float v = 0.0;
    v += 1.0 * value_noise(q, seed);
    v += 0.5 * value_noise(q * 2.0, seed + 3.1);
    v += 0.25 * value_noise(q * 4.0, seed + 6.7);
    v /= 1.75;
    return clamp((v - 0.25) / 0.5, 0.0, 1.0);
}

vec4 sample_cell(vec2 sc) {
    vec2 rel = sc - cell_grid_origin;
    if (rel.x < 0.0 || rel.y < 0.0 || rel.x >= cell_grid_size.x || rel.y >= cell_grid_size.y) {
        return vec4(0.0);
    }
    return texture(cell_reveal_tex, (rel + vec2(0.5)) / cell_grid_size);
}

void fragment() {
    vec2 st = rect_origin_tiles + UV * rect_size_tiles;
    float t = (time_override >= 0.0) ? time_override : TIME;
    // Drift sideways at 1 tile every 3 seconds in world tile units
    vec2 drift = vec2(-t / 3.0, 0.0);

    float bank_scale = max(1.0, 0.25 / max(zoom_scale, 0.02));
    float n = fbm3(st + drift, vec2(6.0, 2.2) * bank_scale, 11.0);
    float n2 = fbm3(st + drift, vec2(10.0, 4.0) * bank_scale, 18.0);

    vec2 sc = floor(st / 32.0);
    vec2 loc = st - sc * 32.0;
    vec4 here = sample_cell(sc);

    vec3 bank = mix(BANK_DARK, BANK_LIGHT, n2);
    if (here.r < 0.5) {
        COLOR = vec4(bank, 1.0);
    } else {
        float d_edge = 100.0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) {
                    continue;
                }
                vec4 nb = sample_cell(sc + vec2(float(dx), float(dy)));
                if (nb.r < 0.5) {
                    float ex = (dx < 0) ? loc.x : ((dx > 0) ? (32.0 - loc.x) : 0.0);
                    float ey = (dy < 0) ? loc.y : ((dy > 0) ? (32.0 - loc.y) : 0.0);
                    d_edge = min(d_edge, length(vec2(ex, ey)));
                }
            }
        }
        float edge_t = 1.0 - smoothstep(0.0, 9.0, d_edge);
        float a_edge = pow(edge_t, 1.4) * mix(0.55, 1.0, n);
        a_edge = max(a_edge, 1.0 - smoothstep(0.0, 1.5, d_edge));

        float a_mist = 0.0;
        if (here.g > 0.5) {
            float d_town = 100.0;
            for (int i = 0; i < 32; i++) {
                if (i >= town_rect_count) {
                    break;
                }
                vec4 r = town_rects[i];
                vec2 dv = max(max(r.xy - st, st - r.zw), vec2(0.0));
                d_town = min(d_town, length(dv));
            }
            a_mist = 0.34 * mix(0.30, 1.0, n) * smoothstep(0.0, 5.0, d_town);
        }

        float alpha = 1.0 - (1.0 - a_edge) * (1.0 - a_mist);
        vec3 fog_col = mix(bank, MIST_COL, smoothstep(0.0, 2.5, d_edge));
        COLOR = vec4(fog_col, alpha);
    }
}
