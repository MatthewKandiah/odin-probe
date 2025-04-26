/*
  goal - have a cpu-based program updating the position and/or size of a textured quad and draw it using the gpu
*/
package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

State :: struct {
	command_buffer:                  vk.CommandBuffer,
	command_pool:                    vk.CommandPool,
	device:                          vk.Device,
	graphics_pipeline:               vk.Pipeline,
	graphics_queue:                  vk.Queue,
	graphics_queue_family_index:     u32,
	instance:                        vk.Instance,
	physical_device:                 vk.PhysicalDevice,
	pipeline_layout:                 vk.PipelineLayout,
	present_mode:                    vk.PresentModeKHR,
	present_queue:                   vk.Queue,
	present_queue_family_index:      u32,
	render_pass:                     vk.RenderPass,
	shader_code_fragment:            []byte,
	shader_code_vertex:              []byte,
	shader_module_fragment:          vk.ShaderModule,
	shader_module_vertex:            vk.ShaderModule,
	supported_surface_formats:       []vk.SurfaceFormatKHR,
	supported_surface_present_modes: []vk.PresentModeKHR,
	surface:                         vk.SurfaceKHR,
	surface_capabilities:            vk.SurfaceCapabilitiesKHR,
	swapchain:                       vk.SwapchainKHR,
	swapchain_extent:                vk.Extent2D,
	swapchain_format:                vk.SurfaceFormatKHR,
	swapchain_framebuffers:          []vk.Framebuffer,
	swapchain_image_count:           u32,
	swapchain_image_index:           u32,
	swapchain_image_views:           []vk.ImageView,
	swapchain_images:                []vk.Image,
	sync_fence_in_flight:            vk.Fence,
	sync_semaphore_image_available:  vk.Semaphore,
	sync_semaphore_render_finished:  vk.Semaphore,
	window:                          glfw.WindowHandle,
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

	if !get_physical_device_surface_formats(&state) {
		panic("get supported formats failed")
	}
	defer delete(state.supported_surface_formats)

	if !get_physical_device_surface_present_modes(&state) {
		panic("get supported present modes failed")
	}
	defer delete(state.supported_surface_present_modes)

	if !get_swap_exent(&state) {
		panic("get swap extent failed")
	}

	if !create_swapchain(&state) {
		panic("create swapchain failed")
	}
	defer vk.DestroySwapchainKHR(state.device, state.swapchain, nil)

	get_swapchain_images(&state)
	defer delete(state.swapchain_images)

	if !create_swapchain_image_views(&state) {
		panic("create swapchain image views failed")
	}
	defer {
		for image_view in state.swapchain_image_views {
			vk.DestroyImageView(state.device, image_view, nil)
		}
		delete(state.swapchain_image_views)
	}

	if !create_shader_modules(&state) {
		panic("create shader modules failed")
	}

	if !create_graphics_pipeline(&state) {
		panic("create graphics pipeline failed")
	}
	vk.DestroyShaderModule(state.device, state.shader_module_vertex, nil)
	vk.DestroyShaderModule(state.device, state.shader_module_fragment, nil)
	state.shader_module_vertex = 0
	state.shader_module_fragment = 0
	defer {
		vk.DestroyPipeline(state.device, state.graphics_pipeline, nil)
		vk.DestroyPipelineLayout(state.device, state.pipeline_layout, nil)
		vk.DestroyRenderPass(state.device, state.render_pass, nil)
	}

	if !create_framebuffers(&state) {
		panic("create framebuffers failed")
	}
	defer {
		for framebuffer in state.swapchain_framebuffers {
			vk.DestroyFramebuffer(state.device, framebuffer, nil)
		}
		delete(state.swapchain_framebuffers)
	}

	if !create_command_pool(&state) {
		panic("create command pool failed")
	}
	defer {
		vk.DestroyCommandPool(state.device, state.command_pool, nil)
	}

	if !create_command_buffer(&state) {
		panic("create command buffer failed")
	}

  if !create_sync_objects(&state) {
    panic("create sync objects failed")
  }
  defer{
    vk.DestroySemaphore(state.device, state.sync_semaphore_image_available, nil)
    vk.DestroySemaphore(state.device, state.sync_semaphore_render_finished, nil)
    vk.DestroyFence(state.device, state.sync_fence_in_flight, nil)
}

	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
		draw_frame(&state)
	}

	// synchronise host and gpu actions and present frame when it is ready
}
