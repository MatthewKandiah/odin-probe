/*
  goal - have a cpu-based program updating the position and/or size of a textured quad and draw it using the gpu
*/
package main

import "base:runtime"
import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

State :: struct {
	instance:                    vk.Instance,
	physical_device:             vk.PhysicalDevice,
	device:                      vk.Device,
	graphics_queue_family_index: u32,
	graphics_queue:              vk.Queue,
	present_queue_family_index:  u32,
	present_queue:               vk.Queue,
	surface:                     vk.SurfaceKHR,
	window:                      glfw.WindowHandle,
	swapchain:                   vk.SwapchainKHR,
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
	defer vk.DestroyInstance(state.instance, nil)

	if !create_window_surface(&state) {
		panic("create window surface failed")
	}
	defer vk.DestroySurfaceKHR(state.instance, state.surface, nil)

	if !get_physical_gpu(&state) {
		panic("get physical gpu failed")
	}

	if !create_device(&state) {
		panic("create device failed")
	}
	defer vk.DestroyDevice(state.device, nil)

	if !create_swapchain(&state) {
		panic("create swapchain failed")
	}
	defer vk.DestroySwapchainKHR(state.device, state.swapchain, nil)

	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
	}

	// create vertex buffer
	// create swap chain (including its image views)
	// create graphics pipeline (including its framebuffers wrapping needed image views)
	// create command pool and command buffer
	// synchronise host and gpu actions and present frame when it is ready
}
