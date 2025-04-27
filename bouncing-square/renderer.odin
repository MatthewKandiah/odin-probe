package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

RendererState :: struct {
	command_buffer:                 vk.CommandBuffer,
	command_pool:                   vk.CommandPool,
	device:                         vk.Device,
	graphics_pipeline:              vk.Pipeline,
	graphics_queue:                 vk.Queue,
	graphics_queue_family_index:    u32,
	instance:                       vk.Instance,
	physical_device:                vk.PhysicalDevice,
	pipeline_layout:                vk.PipelineLayout,
	present_mode:                   vk.PresentModeKHR,
	present_queue:                  vk.Queue,
	present_queue_family_index:     u32,
	render_pass:                    vk.RenderPass,
	shader_module_fragment:         vk.ShaderModule,
	shader_module_vertex:           vk.ShaderModule,
	surface:                        vk.SurfaceKHR,
	surface_capabilities:           vk.SurfaceCapabilitiesKHR,
	swapchain:                      vk.SwapchainKHR,
	swapchain_extent:               vk.Extent2D,
	swapchain_format:               vk.SurfaceFormatKHR,
	swapchain_framebuffers:         []vk.Framebuffer,
	swapchain_image_index:          u32,
	swapchain_image_views:          []vk.ImageView,
	swapchain_images:               []vk.Image,
	sync_fence_in_flight:           vk.Fence,
	sync_semaphore_image_available: vk.Semaphore,
	sync_semaphore_render_finished: vk.Semaphore,
	window:                         glfw.WindowHandle,
}

draw_frame :: proc(state: ^RendererState) {
	vk.WaitForFences(state.device, 1, &state.sync_fence_in_flight, true, max(u64))
	vk.ResetFences(state.device, 1, &state.sync_fence_in_flight)
	vk.AcquireNextImageKHR(
		state.device,
		state.swapchain,
		max(u64),
		state.sync_semaphore_image_available,
		0,
		&state.swapchain_image_index,
	)
	vk.ResetCommandBuffer(state.command_buffer, {})
	record_command_buffer(state)
	wait_stages := []vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &state.sync_semaphore_image_available,
		pWaitDstStageMask    = raw_data(wait_stages),
		commandBufferCount   = 1,
		pCommandBuffers      = &state.command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &state.sync_semaphore_render_finished,
	}
	if res := vk.QueueSubmit(state.graphics_queue, 1, &submit_info, state.sync_fence_in_flight);
	   res != .SUCCESS {
		panic("failed to submit draw command buffer")
	}
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &state.sync_semaphore_render_finished,
		swapchainCount     = 1,
		pSwapchains        = &state.swapchain,
		pImageIndices      = &state.swapchain_image_index,
	}
	if res := vk.QueuePresentKHR(state.present_queue, &present_info); res != .SUCCESS {
		panic("failed to present swapchain image")
	}
}

record_command_buffer :: proc(using state: ^RendererState) {
	command_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	if res := vk.BeginCommandBuffer(command_buffer, &command_buffer_begin_info); res != .SUCCESS {
		panic("failed to begin recording command buffer")
	}
	clear_colour := vk.ClearValue {
		color = {float32 = {0, 0, 0, 1}},
	}
	render_pass_begin_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = render_pass,
		framebuffer = swapchain_framebuffers[swapchain_image_index],
		renderArea = vk.Rect2D{offset = {0, 0}, extent = swapchain_extent},
		clearValueCount = 1,
		pClearValues = &clear_colour,
	}
	vk.CmdBeginRenderPass(command_buffer, &render_pass_begin_info, .INLINE)
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, graphics_pipeline)
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = cast(f32)swapchain_extent.width,
		height   = cast(f32)swapchain_extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = swapchain_extent,
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)
	vk.CmdDraw(command_buffer, 3, 1, 0, 0)
	vk.CmdEndRenderPass(command_buffer)
	if res := vk.EndCommandBuffer(command_buffer); res != .SUCCESS {
		panic("failed to record command buffer")
	}
}

check_validation_layer_support :: proc() -> bool {
	count: u32
	vk.EnumerateInstanceLayerProperties(&count, nil)
	available_layers := make([]vk.LayerProperties, count)
	defer delete(available_layers)
	if vk.EnumerateInstanceLayerProperties(&count, raw_data(available_layers)) !=
	   vk.Result.SUCCESS {
		panic("enumerate instance layer properties failed")
	}
	for required_layer_name in REQUIRED_LAYER_NAMES {
		found := false
		for &available_layer in available_layers {
			available_layer_name := cast(cstring)&available_layer.layerName[0]
			if required_layer_name == available_layer_name {
				found = true
			}
		}
		if !found {return false}
	}
	return true
}

check_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)
	extension_properties := make([]vk.ExtensionProperties, count)
	defer delete(extension_properties)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(extension_properties))
	for required_extension_name in REQUIRED_EXTENSION_NAMES {
		found := false
		for available_extension_properties in extension_properties {
			available_extension_name := available_extension_properties.extensionName
			if cast(cstring)&available_extension_name[0] == required_extension_name {
				found = true
			}
		}
		if !found {
			return false
		}
	}
	return true
}

get_physical_devices :: proc(instance: vk.Instance) -> []vk.PhysicalDevice {
	count: u32
	vk.EnumeratePhysicalDevices(instance, &count, nil)
	if count == 0 {
		panic("failed to find a Vulkan compatible device")
	}
	physical_devices := make([]vk.PhysicalDevice, count)
	if vk.EnumeratePhysicalDevices(instance, &count, raw_data(physical_devices)) !=
	   vk.Result.SUCCESS {
		panic("enumerate physical devices failed")
	}
	return physical_devices
}

get_queue_family_properties :: proc(
	physical_device: vk.PhysicalDevice,
) -> []vk.QueueFamilyProperties {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, nil)
	queue_family_properties := make([]vk.QueueFamilyProperties, count)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&count,
		raw_data(queue_family_properties),
	)
	return queue_family_properties
}

get_physical_device_surface_formats :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> []vk.SurfaceFormatKHR {
	count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, nil)
	if count == 0 {
		panic("found no physical device surface formats")
	}
	supported_surface_formats := make([]vk.SurfaceFormatKHR, count)
	if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device,
		surface,
		&count,
		raw_data(supported_surface_formats),
	); res != vk.Result.SUCCESS {
		panic("get physical device surface formats failed")
	}
	return supported_surface_formats
}

get_physical_device_surface_present_modes :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> []vk.PresentModeKHR {
	count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, nil)
	if count == 0 {
		panic("found no physical device surface present modes")
	}
	supported_surface_present_modes := make([]vk.PresentModeKHR, count)
	if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&count,
		raw_data(supported_surface_present_modes),
	); res != vk.Result.SUCCESS {
		panic("get physical device surface present modes failed")
	}
	return supported_surface_present_modes
}

get_swapchain_images :: proc(device: vk.Device, swapchain: vk.SwapchainKHR) -> []vk.Image {
	count: u32
	vk.GetSwapchainImagesKHR(device, swapchain, &count, nil)
	swapchain_images := make([]vk.Image, count)
	vk.GetSwapchainImagesKHR(device, swapchain, &count, raw_data(swapchain_images))
	return swapchain_images
}
