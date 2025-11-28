#version 330 core

in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D u_texture;

void main()
{
    // Flip Y to convert from OpenGL texture coords to screen coords
    vec2 flipped_coord = vec2(TexCoord.x, 1.0 - TexCoord.y);
    FragColor = texture(u_texture, flipped_coord);
}
