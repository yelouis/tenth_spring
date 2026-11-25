// time_of_day.gdshader — Phase 4 Day/Dawn/Dusk/Night screen-space lighting (Item 74, Decision 79 F79)
// Pure procedural shader (no ROM pixels, identical with and without ROM).
// Day (07:15-18:45): alpha = 0.0 (100% untouched).
// Dawn (05:15-06:45): rgb(245, 195, 165) @ 0.14.
// Dusk (19:15-20:45): rgb(220, 145, 120) @ 0.24.
// Night (21:15-04:45): dims 62% toward rgb(22, 30, 62) outside Emerald 4.5-tile Flash circle (4.0..5.0 world tiles)
// plus 3.5-tile warm glow pools around visible waypost lamps.
shader_type canvas_item;

uniform float minute_of_day = 720.0;
uniform vec2 cam_center_tiles = vec2(0.0, 0.0);
uniform vec2 view_size_tiles = vec2(15.0, 10.0);
uniform vec2 player_world_tiles = vec2(0.0, 0.0);
uniform float has_player = 0.0;
uniform int lamp_count = 0;
uniform vec2 lamp_world_tiles[16];

const vec3 DAWN_COL = vec3(245.0, 195.0, 165.0) / 255.0;
const float DAWN_ALPHA = 0.14;
const vec3 DUSK_COL = vec3(220.0, 145.0, 120.0) / 255.0;
const float DUSK_ALPHA = 0.24;
const vec3 NIGHT_COL = vec3(22.0, 30.0, 62.0) / 255.0;
const float NIGHT_ALPHA = 0.62;
const vec3 LAMP_COL = vec3(255.0, 224.0, 150.0) / 255.0;
const float LAMP_GLOW_ALPHA = 0.12;

void fragment() {
    float m = mod(mod(minute_of_day, 1440.0) + 1440.0, 1440.0);

    // Smooth 15-min transitions across band boundaries (04:45-05:15, 06:45-07:15, 18:45-19:15, 20:45-21:15)
    float t_n_to_dawn = smoothstep(285.0, 315.0, m);
    float t_dawn_to_day = smoothstep(405.0, 435.0, m);
    float t_day_to_dusk = smoothstep(1125.0, 1155.0, m);
    float t_dusk_to_n = smoothstep(1245.0, 1275.0, m);

    float w_dawn = t_n_to_dawn * (1.0 - t_dawn_to_day);
    float w_dusk = t_day_to_dusk * (1.0 - t_dusk_to_n);
    float w_night = (1.0 - t_n_to_dawn) + t_dusk_to_n;

    if (w_dawn + w_dusk + w_night <= 0.0001) {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0);
    } else {
        vec2 world_tile = cam_center_tiles + (UV - vec2(0.5)) * view_size_tiles;

        // Emerald Flash level-1 circle: fully lit <= 4.0 world tiles, smooth across 4.0..5.0, dimmed >= 5.0
        float dark_factor = 1.0;
        if (has_player > 0.5) {
            float d_player = length(world_tile - player_world_tiles);
            dark_factor = smoothstep(4.0, 5.0, d_player);
        }

        // Waypost lamp warm 3.5-tile glow pools
        float lamp_reduction = 0.0;
        for (int i = 0; i < 16; i++) {
            if (i >= lamp_count) {
                break;
            }
            float d_lamp = length(world_tile - lamp_world_tiles[i]);
            float lit = 1.0 - smoothstep(1.0, 3.5, d_lamp);
            lamp_reduction = max(lamp_reduction, lit);
        }

        float effective_dark = dark_factor * (1.0 - 0.85 * lamp_reduction);
        float a_dawn = w_dawn * DAWN_ALPHA;
        float a_dusk = w_dusk * DUSK_ALPHA;
        float a_night = w_night * NIGHT_ALPHA * effective_dark;
        float a_lamp = w_night * LAMP_GLOW_ALPHA * lamp_reduction;

        float a_out = clamp(a_dawn + a_dusk + a_night + a_lamp, 0.0, 1.0);
        vec3 c_num = DAWN_COL * a_dawn + DUSK_COL * a_dusk + NIGHT_COL * a_night + LAMP_COL * a_lamp;
        vec3 rgb_out = (a_out > 0.0001) ? (c_num / a_out) : vec3(0.0);
        COLOR = vec4(rgb_out, a_out);
    }
}
