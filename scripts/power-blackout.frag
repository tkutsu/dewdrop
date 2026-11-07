#version 300 es
precision mediump float;
layout(location = 0) out vec4 fragColor;

// Hold the CRT's final black independently of desktop clients.
void main() {
    fragColor = vec4(0.0, 0.0, 0.0, 1.0);
}
