package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"
import "core:os"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

REQUIRED_LAYER_NAMES := []cstring{"VK_LAYER_KHRONOS_validation"}
REQUIRED_EXTENSION_NAMES := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
MAX_FRAMES_IN_FLIGHT :: 2

Vertex :: struct {
	pos:   glsl.vec2,
	color: glsl.vec3,
}

UniformBufferObject :: struct {
	translation: glsl.vec2,
}

vertex_input_binding_description := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

vertex_input_attribute_descriptions := [2]vk.VertexInputAttributeDescription {
	{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = cast(u32)offset_of(Vertex, pos)},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, color),
	},
}

RendererState :: struct {
	command_buffers:                 [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	command_pool:                    vk.CommandPool,
	descriptor_pool:                 vk.DescriptorPool,
	descriptor_sets:                 [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	descriptor_set_layout:           vk.DescriptorSetLayout,
	device:                          vk.Device,
	frame_buffer_resized:            bool,
	frame_index:                     u32,
	graphics_pipeline:               vk.Pipeline,
	graphics_queue:                  vk.Queue,
	graphics_queue_family_index:     u32,
	index_buffer:                    vk.Buffer,
	index_buffer_memory:             vk.DeviceMemory,
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
	uniform_buffers:                 [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	uniform_buffers_memory:          [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	uniform_buffers_mapped:          [MAX_FRAMES_IN_FLIGHT]rawptr,
	window:                          glfw.WindowHandle,
	vertex_buffer:                   vk.Buffer,
	vertex_buffer_memory:            vk.DeviceMemory,
}

set_swapchain_extent :: proc(state: ^RendererState) {
	if res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		state.physical_device,
		state.surface,
		&state.surface_capabilities,
	); res != vk.Result.SUCCESS {
		panic("get physical device surface capabilities failed")
	}
	// special value, indicates size will be determined by extent of a swapchain targeting the surface
	if state.surface_capabilities.currentExtent.width == max(u32) {
		width, height := glfw.GetFramebufferSize(state.window)
		extent: vk.Extent2D = {
			width  = clamp(
				cast(u32)width,
				state.surface_capabilities.minImageExtent.width,
				state.surface_capabilities.maxImageExtent.width,
			),
			height = clamp(
				cast(u32)height,
				state.surface_capabilities.minImageExtent.height,
				state.surface_capabilities.maxImageExtent.height,
			),
		}
		state.swapchain_extent = extent
	} else {
		// default case, set swapchain extent to match the screens current extent
		state.swapchain_extent = state.surface_capabilities.currentExtent
	}
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
	// handle minimization
	width, height := glfw.GetFramebufferSize(state.window)
	for width == 0 || height == 0 {
		width, height = glfw.GetFramebufferSize(state.window)
		glfw.WaitEvents()
	}

	vk.DeviceWaitIdle(state.device)
	clean_up_swapchain(state)
	set_swapchain_extent(state)
	setup_new_swapchain(state)
	setup_new_framebuffers(state)
}

start_time := time.now()._nsec

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
	current_time := time.now()._nsec
	time: f32 = cast(f32)((current_time - start_time) * 15 / 1_000_000_000)
	ubo := UniformBufferObject {
		translation = {math.sin(time) / 5, 0},
	}
	// TODO-Matt: look up `push constants` as an alternative way to do the same thing
	intrinsics.mem_copy_non_overlapping(uniform_buffers_mapped[frame_index], &ubo, size_of(ubo))
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
	if queue_submit_res != .SUCCESS {
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
	present_res := vk.QueuePresentKHR(present_queue, &present_info)
	if present_res == .ERROR_OUT_OF_DATE_KHR ||
	   present_res == .SUBOPTIMAL_KHR ||
	   frame_buffer_resized {
		frame_buffer_resized = false
		recreate_swapchain(state)
	} else if present_res != .SUCCESS {
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
	vertex_buffers := []vk.Buffer{vertex_buffer}
	offsets := []vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(
		command_buffers[frame_index],
		0,
		1,
		raw_data(vertex_buffers),
		raw_data(offsets),
	)
	vk.CmdBindIndexBuffer(command_buffers[frame_index], state.index_buffer, 0, .UINT32)
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = cast(f32)swapchain_extent.width,
		height   = cast(f32)swapchain_extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdBindDescriptorSets(
		command_buffers[frame_index],
		.GRAPHICS,
		state.pipeline_layout,
		0,
		1,
		&state.descriptor_sets[frame_index],
		0,
		nil,
	)
	vk.CmdSetViewport(command_buffers[frame_index], 0, 1, &viewport)
	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = swapchain_extent,
	}
	vk.CmdSetScissor(command_buffers[frame_index], 0, 1, &scissor)
	vk.CmdDrawIndexed(command_buffers[frame_index], cast(u32)len(indices), 1, 0, 0, 0)
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

find_memory_type :: proc(
	state: ^RendererState,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(state.physical_device, &physical_device_memory_properties)
	for i in 0 ..< physical_device_memory_properties.memoryTypeCount {
		if type_filter & (1 << i) != 0 &&
		   physical_device_memory_properties.memoryTypes[i].propertyFlags >= properties {
			return i
		}
	}
	panic("failed to find suitable memory type")
}

create_buffer :: proc(
	state: ^RendererState,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_properties: vk.MemoryPropertyFlags,
) -> (
	buffer: vk.Buffer,
	buffer_memory: vk.DeviceMemory,
) {
	// create buffer
	buffer_create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	if res := vk.CreateBuffer(state.device, &buffer_create_info, nil, &buffer); res != .SUCCESS {
		panic("create buffer failed")
	}
	// allocate and bind memory
	buffer_memory_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(state.device, buffer, &buffer_memory_requirements)
	buffer_allocate_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = buffer_memory_requirements.size,
		memoryTypeIndex = find_memory_type(
			state,
			buffer_memory_requirements.memoryTypeBits,
			memory_properties,
		),
	}
	if res := vk.AllocateMemory(state.device, &buffer_allocate_info, nil, &buffer_memory);
	   res != .SUCCESS {
		panic("failed to allocate buffer memory")
	}
	vk.BindBufferMemory(state.device, buffer, buffer_memory, 0)

	return buffer, buffer_memory
}

copy_buffer :: proc(state: ^RendererState, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) {
	command_buffer_allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = state.command_pool,
		commandBufferCount = 1,
	}
	temp_command_buffer: vk.CommandBuffer
	if res := vk.AllocateCommandBuffers(
		state.device,
		&command_buffer_allocate_info,
		&temp_command_buffer,
	); res != .SUCCESS {
		panic("failed to allocate temporary command buffer for copy")
	}
	command_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if res := vk.BeginCommandBuffer(temp_command_buffer, &command_buffer_begin_info);
	   res != .SUCCESS {
		panic("failed to begin temporary command buffer for copy")
	}
	buffer_copy_info := vk.BufferCopy {
		size = size,
	}
	vk.CmdCopyBuffer(temp_command_buffer, src, dst, 1, &buffer_copy_info)
	vk.EndCommandBuffer(temp_command_buffer)
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &temp_command_buffer,
	}
	vk.QueueSubmit(state.graphics_queue, 1, &submit_info, 0)
	vk.QueueWaitIdle(state.graphics_queue)
	vk.FreeCommandBuffers(state.device, state.command_pool, 1, &temp_command_buffer)
}
