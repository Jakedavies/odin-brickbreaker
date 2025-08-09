#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

uniform float iTime;
uniform vec2 iResolution;

// Hash function for pseudorandom values
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Noise function
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fractal brownian motion for nebula effect
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    
    for(int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Star field
float stars(vec2 uv, float density) {
    vec2 id = floor(uv * density);
    vec2 gv = fract(uv * density) - 0.5;
    
    float n = hash(id);
    if(n < 0.05) {
        float size = fract(n * 100.0) * 0.4 + 0.1;
        float twinkle = sin(iTime * 10.0 * fract(n * 10.0)) * 0.5 + 0.5;
        float star = 1.0 - smoothstep(0.0, size, length(gv));
        return star * twinkle;
    }
    return 0.0;
}

void main() {
    vec2 uv = gl_FragCoord.xy / iResolution.xy;
    vec2 p = (gl_FragCoord.xy - 0.5 * iResolution.xy) / min(iResolution.x, iResolution.y);
    
    // Deep space background
    vec3 col = vec3(0.02, 0.01, 0.05);
    
    // Nebula layers
    vec2 drift1 = vec2(iTime * 0.01, iTime * 0.005);
    vec2 drift2 = vec2(iTime * -0.005, iTime * 0.01);
    
    float nebula1 = fbm(p * 2.0 + drift1);
    float nebula2 = fbm(p * 3.0 + drift2);
    
    // Purple/blue nebula
    col += vec3(0.3, 0.1, 0.6) * nebula1 * 0.6;
    // Cyan/teal nebula
    col += vec3(0.1, 0.4, 0.5) * nebula2 * 0.4;
    
    // Add some bright spots
    float brightSpots = pow(fbm(p * 1.5 + drift1 * 2.0), 3.0);
    col += vec3(0.8, 0.6, 1.0) * brightSpots * 0.3;
    
    // Star layers
    float starLayer1 = stars(uv, 100.0);
    float starLayer2 = stars(uv + vec2(0.5), 150.0);
    float starLayer3 = stars(uv + vec2(0.25, 0.75), 200.0);
    
    col += vec3(1.0) * starLayer1;
    col += vec3(0.9, 0.9, 1.0) * starLayer2 * 0.8;
    col += vec3(1.0, 0.8, 0.8) * starLayer3 * 0.6;
    
    // Vignette effect
    float vignette = 1.0 - length(p) * 0.3;
    col *= vignette;
    
    // Subtle color grading
    col = pow(col, vec3(0.9));
    col = clamp(col, 0.0, 1.0);
    
    finalColor = vec4(col, 1.0);
}
