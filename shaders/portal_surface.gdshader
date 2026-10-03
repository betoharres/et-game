shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D portal_texture : filter_linear;
uniform vec3 frame_center;
uniform vec3 frame_right;
uniform vec3 frame_up;
uniform vec2 frame_size = vec2(1.0);
uniform bool restrict_view = false;
uniform vec3 view_position;
uniform bool flip_x = false;
varying vec2 portal_uv;

void vertex() {
    vec3 offset = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - frame_center;
    portal_uv = vec2(dot(offset, frame_right), dot(offset, frame_up)) / frame_size + vec2(0.5);
    portal_uv.y = 1.0 - portal_uv.y;
    if (flip_x) {
        portal_uv.x = 1.0 - portal_uv.x;
    }
}

void fragment() {
    if (restrict_view && distance(CAMERA_POSITION_WORLD, view_position) > 0.001) { discard; }
    ALBEDO = texture(portal_texture, portal_uv).rgb;
}
