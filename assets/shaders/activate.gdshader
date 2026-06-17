shader_type canvas_item;

// Godot uses 'uniform' but with a slightly different syntax. 
// 'TIME' is built-in, so we don't need a time uniform, but we'll map resolution/mouse.
uniform vec2 mouse;

// Godot doesn't allow overriding functions easily, so we keep your custom texture math
const float PI = 3.14159265;

float tex(vec2 pos) {
    float upper = length(vec2(cos(PI / 3.0), sin(PI / 11.0)) * length(pos) - pos);
    return min(pow(upper, 0.2), pow(1.0 - length(pos), 0.88));
}

void fragment() {
    // 1. Get the resolution of the texture/control node automatically
    // SCREEN_PIXEL_SIZE or local texture size can be used. For a ColorRect, we use 1.0 / SCREEN_PIXEL_SIZE or custom uniform.
    // To mimic screen-space resolution seamlessly, we can use the UV and the node's size:
    vec2 resolution = 1.0 / TEXTURE_PIXEL_SIZE; 
    
    // 2. Map gl_FragCoord equivalent. In Godot 2D, FRAGCOORD gives screen space, 
    // but UV * resolution gives local pixel coordinates.
    vec2 pixel_coord = UV * resolution;

    vec2 position = (pixel_coord / min(resolution.x, resolution.y)) - vec2(1.0, 0.5);
    position *= 2.0;

    float color = 0.0;
    vec2 circleDistor = position;
    circleDistor /= (sqrt(5.0) - length(circleDistor));
    float modab = 1.0;
    
    // TIME is a built-in global variable in Godot
    float off = mod(TIME, 1.0) * modab; 
    
    circleDistor = normalize(circleDistor) * mod(length(circleDistor) - off, modab);
    float ang = asin(circleDistor.y / length(circleDistor));
    
    if (circleDistor.x < 0.0) { 
        ang = PI - ang;
    }
    
    ang = mod(ang, PI / 3.0);
    circleDistor = vec2(cos(ang), sin(ang)) * length(circleDistor);
    vec4 col = mix(vec4(0.5), vec4(0.0), tex(circleDistor));

    // 3. Set the final output color using COLOR instead of gl_FragColor
    COLOR = col;
}