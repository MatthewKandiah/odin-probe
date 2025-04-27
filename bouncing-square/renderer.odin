package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "vendor:glfw"
import vk "vendor:vulkan"

MAX_FRAMES_IN_FLIGHT :: 2

RendererState :: struct {
	command_buffers:                 [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	command_pool:                    vk.CommandPool,
	device:                          vk.Device,
	frame_index:                     u32,
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
	shader_module_fragment:          vk.ShaderModule,
	shader_module_vertex:            vk.ShaderModule,
	surface:                         vk.SurfaceKHR,
	surface_capabilities:            vk.SurfaceCapabilitiesKHR,
	swapchain:                       vk.SwapchainKHR,
	swapchain_extent:                vk.Extent2D,
	swapchain_format:                vk.SurfaceFormatKHR,
	swapchain_framebuffers:          []vk.Framebuffer,
	swapchain_image_index:           u32,
	swapchain_image_views:           []vk.ImageView,
	swapchain_images:                []vk.Image,
	sync_fences_in_flight:           [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	sync_semaphores_image_available: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	sync_semaphores_render_finished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	window:                          glfw.WindowHandle,
}

setup_new_swapchain :: proc(state: ^RendererState) {
	// create swapchain
	swapchain_create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = state.surface,
		oldSwapchain     = 0, // VK_NULL_HANDLE
		imageFormat      = state.swapchain_format.format,
		imageColorSpace  = state.swapchain_format.colorSpace,
		presentMode      = state.present_mode,
		imageExtent      = state.swapchain_extent,
		minImageCount    = state.surface_capabilities.minImageCount + 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		imageArrayLayers = 1,
		imageSharingMode = .EXCLUSIVE,
		compositeAlpha   = {.OPAQUE},
		clipped          = true,
		preTransform     = state.surface_capabilities.currentTransform,
	}
	if res := vk.CreateSwapchainKHR(state.device, &swapchain_create_info, nil, &state.swapchain);
	   res != vk.Result.SUCCESS {
		panic("create swapchain failed")
	}

	// get swapchain images
	state.swapchain_images = get_swapchain_images(state.device, state.swapchain)

	// create swapchain image views
	state.swapchain_image_views = make([]vk.ImageView, len(state.swapchain_images))
	for i in 0 ..< len(state.swapchain_images) {
		image_view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = state.swapchain_images[i],
			viewType = vk.ImageViewType.D2,
			format = state.swapchain_format.format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		if res := vk.CreateImageView(
			state.device,
			&image_view_create_info,
			nil,
			&state.swapchain_image_views[i],
		); res != vk.Result.SUCCESS {
			panic("create image view failed")
		}
	}
}

setup_new_framebuffers :: proc(state: ^RendererState) {
	state.swapchain_framebuffers = make([]vk.Framebuffer, len(state.swapchain_image_views))
	for i in 0 ..< len(state.swapchain_image_views) {
		framebuffer_create_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = state.render_pass,
			attachmentCount = 1,
			pAttachments    = &state.swapchain_image_views[i],
			width           = state.swapchain_extent.width,
			height          = state.swapchain_extent.height,
			layers          = 1,
		}
		if res := vk.CreateFramebuffer(
			state.device,
			&framebuffer_create_info,
			nil,
			&state.swapchain_framebuffers[i],
		); res != .SUCCESS {
			panic("create framebuffer failed")
		}
	}
}

clean_up_swapchain :: proc(state: ^RendererState) {
	for framebuffer in state.swapchain_framebuffers {
		vk.DestroyFramebuffer(state.device, framebuffer, nil)
	}
	delete(state.swapchain_framebuffers)
	for image_view in state.swapchain_image_views {
		vk.DestroyImageView(state.device, image_view, nil)
	}
	delete(state.swapchain_image_views)
	delete(state.swapchain_images)
	vk.DestroySwapchainKHR(state.device, state.swapchain, nil)
}

recreate_swapchain :: proc(state: ^RendererState) {
	vk.DeviceWaitIdle(state.device)
	clean_up_swapchain(state)
	setup_new_swapchain(state)
	setup_new_framebuffers(state)
}

draw_frame :: proc(using state: ^RendererState) {
	vk.WaitForFences(device, 1, &sync_fences_in_flight[frame_index], true, max(u64))
	acquire_next_image_res := vk.AcquireNextImageKHR(
		device,
		swapchain,
		max(u64),
		sync_semaphores_image_available[frame_index],
		0,
		&swapchain_image_index,
	)
	if acquire_next_image_res == .ERROR_OUT_OF_DATE_KHR {
		recreate_swapchain(state)
		return
	}
	vk.ResetFences(device, 1, &sync_fences_in_flight[frame_index])
	vk.ResetCommandBuffer(command_buffers[frame_index], {})
	record_command_buffer(state)
	wait_stages := []vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &sync_semaphores_image_available[frame_index],
		pWaitDstStageMask    = raw_data(wait_stages),
		commandBufferCount   = 1,
		pCommandBuffers      = &command_buffers[frame_index],
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &sync_semaphores_render_finished[frame_index],
	}
	queue_submit_res := vk.QueueSubmit(
		graphics_queue,
		1,
		&submit_info,
		sync_fences_in_flight[frame_index],
	)
	if queue_submit_res == .ERROR_OUT_OF_DATE_KHR || queue_submit_res == .SUBOPTIMAL_KHR {
		recreate_swapchain(state)
	} else if queue_submit_res != .SUCCESS {
		panic("failed to submit draw command buffer")
	}
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &sync_semaphores_render_finished[frame_index],
		swapchainCount     = 1,
		pSwapchains        = &swapchain,
		pImageIndices      = &swapchain_image_index,
	}
	if res := vk.QueuePresentKHR(present_queue, &present_info); res != .SUCCESS {
		panic("failed to present swapchain image")
	}

	frame_index += 1
	frame_index %= MAX_FRAMES_IN_FLIGHT
}

record_command_buffer :: proc(using state: ^RendererState) {
	command_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	if res := vk.BeginCommandBuffer(command_buffers[frame_index], &command_buffer_begin_info);
	   res != .SUCCESS {
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
	vk.CmdBeginRenderPass(command_buffers[frame_index], &render_pass_begin_info, .INLINE)
	vk.CmdBindPipeline(command_buffers[frame_index], .GRAPHICS, graphics_pipeline)
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = cast(f32)swapchain_extent.width,
		height   = cast(f32)swapchain_extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(command_buffers[frame_index], 0, 1, &viewport)
	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = swapchain_extent,
	}
	vk.CmdSetScissor(command_buffers[frame_index], 0, 1, &scissor)
	vk.CmdDraw(command_buffers[frame_index], 3, 1, 0, 0)
	vk.CmdEndRenderPass(command_buffers[frame_index])
	if res := vk.EndCommandBuffer(command_buffers[frame_index]); res != .SUCCESS {
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
