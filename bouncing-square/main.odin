/*
  goal - have a cpu-based program updating the position and/or size of a textured quad and draw it using the gpu
*/
/*
  TODO-Matt
  - cpu positioning logic - bounce the square off the edges of the screen without ever leaving the screen
  - cpu responding to input - reverse direction on pressing space
  - read https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/main/docs/best_practices.md might be useful to enable in next project!
*/
package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math/linalg/glsl"
import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

vertices :: []Vertex {
	{{-0.5, -0.5}, {1, 0, 0}, {1, 0}}, // top left
	{{0.5, -0.5}, {0, 1, 0}, {0, 0}}, // top right
	{{0.5, 0.5}, {0, 0, 1}, {0, 1}}, // bottom right
	{{-0.5, 0.5}, {1, 1, 1}, {1, 1}}, // bottom left
}

indices :: []u32{0, 1, 2, 2, 3, 0}

main :: proc() {
  state := setup_renderer()
  defer cleanup_renderer(state)

	// main loop
	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
		draw_frame(&state)
	}
	vk.DeviceWaitIdle(state.device)
}
