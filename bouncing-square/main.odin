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
import "core:math"
import "core:math/linalg/glsl"
import "core:time"
import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

vertices :: []Vertex {
	{{-0.5, -0.5}, {1, 0, 0}, {1, 0}},
	{{0.5, -0.5}, {0, 1, 0}, {0, 0}},
	{{0.5, 0.5}, {0, 0, 1}, {0, 1}},
	{{-0.5, 0.5}, {1, 1, 1}, {1, 1}},
}

indices :: []u32{0, 1, 2, 2, 3, 0}

main :: proc() {
	state := setup_renderer()
	defer cleanup_renderer(state)

	start_time := time.now()._nsec

	// main loop
	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
		current_time := time.now()._nsec
		time: f32 = cast(f32)((current_time - start_time) * 15 / 1_000_000_000)
		pos := glsl.vec2{math.sin(time) / 5, math.cos(time) / 5}
		draw_frame(&state, pos)
	}
	vk.DeviceWaitIdle(state.device)
}
