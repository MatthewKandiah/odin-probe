/*
  goal - have a cpu-based program updating the position and/or size of a textured quad and draw it using the gpu
*/
/*
  TODO-Matt
  - read https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/main/docs/best_practices.md might be useful to enable in next project!
*/
package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "core:os"
import "core:time"
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

	pos := glsl.vec2{0, 0}
	vel := glsl.vec2 {
		rand.float32_range(0.0000005, 0.000003),
		rand.float32_range(0.0000005, 0.000003),
	}

	// main loop
	start_time := get_current_micros()
	frame_start_time := start_time
	frame_end_time := start_time

	for !glfw.WindowShouldClose(state.window) {
		delta_t := cast(f32)(frame_end_time - frame_start_time)
		frame_start_time = frame_end_time

		glfw.PollEvents()
		pos, vel = get_next_pos_and_vel(pos, vel, delta_t)
		draw_frame(&state, pos)

		frame_end_time = get_current_micros()
	}
	vk.DeviceWaitIdle(state.device)
}

get_current_micros :: proc() -> f64 {
	return cast(f64)(time.time_to_unix_nano(time.now())) / 1_000
}

turnaround :: 0.55
get_next_pos_and_vel :: proc(
	old_pos: glsl.vec2,
	old_vel: glsl.vec2,
	delta_t: f32,
) -> (
	new_pos: glsl.vec2,
	new_vel: glsl.vec2,
) {
	disp := glsl.vec2{delta_t * old_vel.x, delta_t * old_vel.y}
	new_pos = old_pos + disp
	if new_pos.x > -turnaround &&
	   new_pos.x < turnaround &&
	   new_pos.y > -turnaround &&
	   new_pos.y < turnaround {
		new_vel = old_vel
	} else if new_pos.x <= -turnaround || new_pos.x >= turnaround {
		new_vel = glsl.vec2{-old_vel.x, old_vel.y}
	} else if new_pos.y <= -turnaround || new_pos.y >= turnaround {
		new_vel = glsl.vec2{old_vel.x, -old_vel.y}
	} else {
		panic("unreachable")
	}

  if new_vel.x == 0 || new_vel.y == 0 {fmt.println("whoops hit the bug! seen the face get stuck moving along an edge once, haven't worked out how")}
	if new_vel.x == 0 {new_vel.x = rand.float32_range(0.0000005, 0.000003)}
  if new_vel.y == 0 {new_vel.y = rand.float32_range(0.0000005, 0.000003)}

	return
}
