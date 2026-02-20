shader_type canvas_item;

// Tile shake and glitch shader for webcore horror
uniform float shake_intensity : hint_range(0.0, 10.0) = 1.0;
uniform float glitch_intensity : hint_range(0.0, 5.0) = 0.5;
uniform float scan_line_speed : hint_range(0.0, 5.0) = 1.0;
uniform vec4 glitch_color : source_color = vec4(1.0, 0.0, 0.0, 0.3);

void fragment() {
	vec2 uv = UV;
	
	// Shake offset
	float shake_x = sin(TIME * 20.0 + VERTEX.y * 0.1) * shake_intensity * 0.01;
	float shake_y = cos(TIME * 15.0 + VERTEX.x * 0.1) * shake_intensity * 0.01;
	uv += vec2(shake_x, shake_y);
	
	// Glitch offset (random horizontal displacement)
	float glitch_line = floor(UV.y * 50.0);
	float glitch_offset = sin(glitch_line * 12.5893 + TIME * 5.0) * glitch_intensity * 0.02;
	
	if (mod(glitch_line, 7.0) < 1.0) {
		uv.x += glitch_offset;
	}
	
	// Get base color
	vec4 color = texture(TEXTURE, uv);
	
	// Scan line effect
	float scan_line = sin((UV.y + TIME * scan_line_speed) * 100.0) * 0.1;
	color.rgb -= vec3(scan_line);
	
	// Random color corruption
	if (mod(floor(UV.y * 100.0 + TIME * 10.0), 13.0) < 1.0) {
		color.rgb += glitch_color.rgb * glitch_intensity * 0.3;
	}
	
	COLOR = color;
}
