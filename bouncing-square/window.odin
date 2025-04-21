package main

import "vendor:glfw"

window_width :: 800
window_height :: 600

create_window :: proc(state: ^State) -> (success: bool) {
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	window := glfw.CreateWindow(window_width, window_height, "bouncing ball", nil, nil)
	if window == nil {return false}
	state.window = window
	return true
}
