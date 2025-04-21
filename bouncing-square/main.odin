/*
  goal - have a cpu-based program updating the position and/or size of a textured quad and draw it using the gpu
*/
package main

import "base:runtime"
import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

State :: struct {
	vk_instance:     vk.Instance,
	physical_device: vk.PhysicalDevice,
	window:          glfw.WindowHandle,
}

main :: proc() {
	state: State

	if !glfw.Init() {
		panic("glfwInit failed")
	}
	defer glfw.Terminate()

	error_callback :: proc "c" (error: i32, description: cstring) {
		context = runtime.default_context()
		fmt.eprintln("ERROR", error, description)
		panic("glfw error")
	}
	glfw.SetErrorCallback(error_callback)

	if !create_window(&state) {
		panic("create_window failed")
	}
	defer glfw.DestroyWindow(state.window)

	if !init_vulkan(&state) {
		panic("init_vulkan failed")
	}
	defer vk.DestroyInstance(state.vk_instance, nil)

	if !get_physical_gpu(&state) {
		panic("get physical gpu failed")
	}

	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
	}

	// pick a physical device - integrated gpu with most memory?
	// create logical device and graphics queue and presentation queue
	// create surface
	// create swap chain (including its image views)
	// create graphics pipeline (including its framebuffers wrapping needed image views)
	// create command pool and command buffer
	// synchronise host and gpu actions and present frame when it is ready
}
