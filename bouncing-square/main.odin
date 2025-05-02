/*
  goal - have a cpu-based program updating the position and/or size of a textured quad and draw it using the gpu
*/
/*
  TODO-Matt
  - texture sampling - draw an image on our square
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
import "vendor:stb/image"
import vk "vendor:vulkan"

WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600

vertices :: []Vertex {
	{{-0.5, -0.5}, {1, 0, 0}, {1, 0}}, // top left
	{{0.5, -0.5}, {0, 1, 0}, {0, 0}}, // top right
	{{0.5, 0.5}, {0, 0, 1}, {0, 1}}, // bottom right
	{{-0.5, 0.5}, {1, 1, 1}, {1, 1}}, // bottom left
}

indices :: []u32{0, 1, 2, 2, 3, 0}

main :: proc() {
	state: RendererState

	{ 	// set up window
		if !glfw.Init() {
			panic("glfwInit failed")
		}

		error_callback :: proc "c" (error: i32, description: cstring) {
			context = runtime.default_context()
			fmt.eprintln("ERROR", error, description)
			panic("glfw error")
		}
		glfw.SetErrorCallback(error_callback)

		// create window
		glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
		glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
		state.window = glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "bouncing ball", nil, nil)
		if state.window == nil {panic("glfw create window failed")}

		// handle window resizes
		glfw.SetWindowUserPointer(state.window, &state)
		framebuffer_resize_callback :: proc "c" (
			window: glfw.WindowHandle,
			width: i32,
			height: i32,
		) {
			state := cast(^RendererState)glfw.GetWindowUserPointer(window)
			state.frame_buffer_resized = true
		}
		glfw.SetFramebufferSizeCallback(state.window, framebuffer_resize_callback)
	}
	defer glfw.Terminate()
	defer glfw.DestroyWindow(state.window)

	{ 	// initialise Vulkan instance
		context.user_ptr = &state
		get_proc_address :: proc(p: rawptr, name: cstring) {
			state := cast(^RendererState)context.user_ptr
			(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(state.instance, name)
		}
		vk.load_proc_addresses(get_proc_address)
		application_info := vk.ApplicationInfo {
			sType              = .APPLICATION_INFO,
			pApplicationName   = "bouncing ball",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName        = "magic",
			engineVersion      = vk.MAKE_VERSION(1, 0, 0),
			apiVersion         = vk.API_VERSION_1_0,
		}
		glfw_extensions := glfw.GetRequiredInstanceExtensions()
		if !check_validation_layer_support() {
			fmt.eprintln("validation layers not supported")
			panic("validation layers not supported")
		}
		instance_create_info := vk.InstanceCreateInfo {
			sType                   = .INSTANCE_CREATE_INFO,
			pApplicationInfo        = &application_info,
			enabledExtensionCount   = cast(u32)len(glfw_extensions),
			ppEnabledExtensionNames = raw_data(glfw_extensions),
			enabledLayerCount       = cast(u32)len(REQUIRED_LAYER_NAMES),
			ppEnabledLayerNames     = raw_data(REQUIRED_LAYER_NAMES),
		}
		if vk.CreateInstance(&instance_create_info, nil, &state.instance) != .SUCCESS {
			panic("create instance failed")
		}
	}
	defer vk.DestroyInstance(state.instance, nil)

	{ 	// create vulkan window surface
		if glfw.CreateWindowSurface(state.instance, state.window, nil, &state.surface) !=
		   vk.Result.SUCCESS {
			panic("create window surface failed")
		}
	}
	defer vk.DestroySurfaceKHR(state.instance, state.surface, nil)

	{ 	// get physical device
		physical_devices := get_physical_devices(state.instance)
		for physical_device in physical_devices {
			properties: vk.PhysicalDeviceProperties
			if !check_extension_support(physical_device) {
				continue
			}
			if !check_feature_support(physical_device) {
				continue
			}
			vk.GetPhysicalDeviceProperties(physical_device, &properties)
			if properties.deviceType == .DISCRETE_GPU {
				state.physical_device = physical_device
				break
			} else if properties.deviceType == .INTEGRATED_GPU {
				state.physical_device = physical_device
			}
		}
		if state.physical_device == nil {
			panic("failed to get physical device")
		}
		delete(physical_devices)
	}

	{ 	// create logical device
		queue_family_properties := get_queue_family_properties(state.physical_device)
		graphics_index_found: bool = false
		present_index_found: bool = false
		for i: u32 = 0; i < cast(u32)len(queue_family_properties); i += 1 {
			queue_family_properties := queue_family_properties[i]
			if vk.QueueFlag.GRAPHICS in queue_family_properties.queueFlags {
				state.graphics_queue_family_index = i
				graphics_index_found = true
			}
			present_supported: b32
			if res := vk.GetPhysicalDeviceSurfaceSupportKHR(
				state.physical_device,
				i,
				state.surface,
				&present_supported,
			); res != vk.Result.SUCCESS {
				panic("failed to check surface presentation support")
			}
			if present_supported {
				state.present_queue_family_index = i
				present_index_found = true
			}
			// seems simplest to just use one queue family if possible? Not sure what's actually best to do here
			if present_index_found &&
			   graphics_index_found &&
			   state.graphics_queue_family_index == state.present_queue_family_index {
				break
			}
		}
		delete(queue_family_properties)
		if !graphics_index_found {
			panic("failed to find graphics queue family index")
		}
		if !present_index_found {
			panic("failed to find present queue family index")
		}
		if state.graphics_queue_family_index != state.present_queue_family_index {
			panic(
				"assumed from here that graphics and present queues are using the same queue family index",
			)
		}
		queue_priority: f32 = 1
		device_queue_create_info := vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = state.graphics_queue_family_index,
			queueCount       = 1,
			pQueuePriorities = &queue_priority,
		}
		queue_create_infos: []vk.DeviceQueueCreateInfo = {device_queue_create_info}
		required_device_features := vk.PhysicalDeviceFeatures {
			samplerAnisotropy = true,
		}
		device_create_info := vk.DeviceCreateInfo {
			sType                   = .DEVICE_CREATE_INFO,
			pQueueCreateInfos       = raw_data(queue_create_infos),
			queueCreateInfoCount    = cast(u32)len(queue_create_infos),
			ppEnabledExtensionNames = raw_data(REQUIRED_EXTENSION_NAMES),
			enabledExtensionCount   = cast(u32)len(REQUIRED_EXTENSION_NAMES),
			pEnabledFeatures        = &required_device_features,
		}
		if res := vk.CreateDevice(state.physical_device, &device_create_info, nil, &state.device);
		   res != vk.Result.SUCCESS {
			panic("create logical device failed")
		}
		// we are only grabbing one queue per queue family
		vk.GetDeviceQueue(
			state.device,
			state.graphics_queue_family_index,
			0,
			&state.graphics_queue,
		)
		vk.GetDeviceQueue(state.device, state.present_queue_family_index, 0, &state.present_queue)
	}
	defer vk.DestroyDevice(state.device, nil)

	{ 	// select physical device surface format
		supported_surface_formats := get_physical_device_surface_formats(
			state.physical_device,
			state.surface,
		)
		format_selected := false
		for available_format in supported_surface_formats {
			// select preferred format if it's supported, else just take the first supported format
			if available_format.format == vk.Format.B8G8R8A8_SRGB &&
			   available_format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
				state.swapchain_format = available_format
				format_selected = true
				break
			}
		}
		if !format_selected {
			state.swapchain_format = supported_surface_formats[0]
		}
		delete(supported_surface_formats)

	}

	{ 	// select physical device surface present mode
		supported_surface_present_modes := get_physical_device_surface_present_modes(
			state.physical_device,
			state.surface,
		)
		mode_selected := false
		for available_mode in supported_surface_present_modes {
			// select preferred present mode if it's supported, else just take FIFO because it's guaranteed to be supported
			if available_mode == vk.PresentModeKHR.MAILBOX {
				state.present_mode = available_mode
				mode_selected = true
				break
			}
		}
		if !mode_selected {
			state.present_mode = vk.PresentModeKHR.FIFO
		}
		delete(supported_surface_present_modes)
	}

	set_swapchain_extent(&state)
	setup_new_swapchain(&state)

	{ 	// create shader modules
		shader_code_vertex, vert_shader_read_ok := os.read_entire_file("vert.spv")
		if !vert_shader_read_ok {
			panic("read vertex shader code failed")
		}
		shader_code_fragment, frag_shader_read_ok := os.read_entire_file("frag.spv")
		if !frag_shader_read_ok {
			panic("read fragment shader code failed")
		}
		create_info_vertex := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			pCode    = cast(^u32)raw_data(shader_code_vertex),
			codeSize = len(shader_code_vertex),
		}
		create_info_fragment := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			pCode    = cast(^u32)raw_data(shader_code_fragment),
			codeSize = len(shader_code_fragment),
		}
		if res := vk.CreateShaderModule(
			state.device,
			&create_info_vertex,
			nil,
			&state.shader_module_vertex,
		); res != vk.Result.SUCCESS {
			panic("failed to create vertex shader module")
		}
		if res := vk.CreateShaderModule(
			state.device,
			&create_info_fragment,
			nil,
			&state.shader_module_fragment,
		); res != vk.Result.SUCCESS {
			panic("failed to create fragment shader module")
		}
	}

	{ 	// create descriptor sets for uniform buffer object and combined image sampler
		descriptor_set_layout_binding_ubo := vk.DescriptorSetLayoutBinding {
			binding         = 0,
			descriptorType  = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags      = {.VERTEX},
		}
		descriptor_set_layout_binding_sampler := vk.DescriptorSetLayoutBinding {
			binding            = 1,
			descriptorType     = .COMBINED_IMAGE_SAMPLER,
			descriptorCount    = 1,
			pImmutableSamplers = nil,
			stageFlags         = {.FRAGMENT},
		}
		descriptor_set_bindings := []vk.DescriptorSetLayoutBinding {
			descriptor_set_layout_binding_ubo,
			descriptor_set_layout_binding_sampler,
		}
		descriptor_set_layout_create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = cast(u32)len(descriptor_set_bindings),
			pBindings    = raw_data(descriptor_set_bindings),
		}
		if res := vk.CreateDescriptorSetLayout(
			state.device,
			&descriptor_set_layout_create_info,
			nil,
			&state.descriptor_set_layout,
		); res != .SUCCESS {
			panic("failed to create descriptor set layout")
		}
	}
	defer vk.DestroyDescriptorSetLayout(state.device, state.descriptor_set_layout, nil)

	{ 	// create graphics pipeline
		vertex_shader_stage_create_info := vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = state.shader_module_vertex,
			pName  = "main",
		}
		fragment_shader_stage_create_info := vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = state.shader_module_fragment,
			pName  = "main",
		}
		shader_stage_create_infos := []vk.PipelineShaderStageCreateInfo {
			vertex_shader_stage_create_info,
			fragment_shader_stage_create_info,
		}
		dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
		dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
			sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = cast(u32)len(dynamic_states),
			pDynamicStates    = raw_data(dynamic_states),
		}
		vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
			sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			vertexBindingDescriptionCount   = 1,
			pVertexBindingDescriptions      = &vertex_input_binding_description,
			vertexAttributeDescriptionCount = len(vertex_input_attribute_descriptions),
			pVertexAttributeDescriptions    = &vertex_input_attribute_descriptions[0],
		}
		input_assembly_state_create_info := vk.PipelineInputAssemblyStateCreateInfo {
			sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology               = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		}
		viewport := vk.Viewport {
			x        = 0,
			y        = 0,
			width    = cast(f32)state.swapchain_extent.width,
			height   = cast(f32)state.swapchain_extent.height,
			minDepth = 0,
			maxDepth = 1,
		}
		scissor := vk.Rect2D {
			offset = {0, 0},
			extent = state.swapchain_extent,
		}
		pipeline_viewport_state_create_info := vk.PipelineViewportStateCreateInfo {
			sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			viewportCount = 1,
			scissorCount  = 1,
		}
		pipeline_rasterization_state_create_info := vk.PipelineRasterizationStateCreateInfo {
			sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			depthClampEnable        = false,
			rasterizerDiscardEnable = false,
			polygonMode             = .FILL,
			lineWidth               = 1,
			cullMode                = {.BACK},
			frontFace               = .CLOCKWISE,
			depthBiasEnable         = false,
		}
		pipeline_multisample_state_create_info := vk.PipelineMultisampleStateCreateInfo {
			sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			sampleShadingEnable  = false,
			rasterizationSamples = {._1},
		}
		pipeline_color_blend_attachment_state := vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable    = false,
		}
		pipeline_color_blend_state_create_info := vk.PipelineColorBlendStateCreateInfo {
			sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			logicOpEnable   = false,
			attachmentCount = 1,
			pAttachments    = &pipeline_color_blend_attachment_state,
		}
		pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
			sType          = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount = 1,
			pSetLayouts    = &state.descriptor_set_layout,
		}
		if res := vk.CreatePipelineLayout(
			state.device,
			&pipeline_layout_create_info,
			nil,
			&state.pipeline_layout,
		); res != vk.Result.SUCCESS {
			panic("create pipeline layout failed")
		}
		color_attachment_description := vk.AttachmentDescription {
			format         = state.swapchain_format.format,
			samples        = {._1},
			loadOp         = .CLEAR,
			storeOp        = .STORE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .UNDEFINED,
			finalLayout    = .PRESENT_SRC_KHR,
		}
		color_attachment_ref := vk.AttachmentReference {
			attachment = 0, // this matches the (location = 0) in our fragment shader output
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}
		subpass_description := vk.SubpassDescription {
			colorAttachmentCount = 1,
			pColorAttachments    = &color_attachment_ref,
		}
		subpass_dependency := vk.SubpassDependency {
			srcSubpass    = vk.SUBPASS_EXTERNAL,
			dstSubpass    = 0,
			srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {},
			dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		}
		render_pass_create_info := vk.RenderPassCreateInfo {
			sType           = .RENDER_PASS_CREATE_INFO,
			attachmentCount = 1,
			pAttachments    = &color_attachment_description,
			subpassCount    = 1,
			pSubpasses      = &subpass_description,
			dependencyCount = 1,
			pDependencies   = &subpass_dependency,
		}
		if res := vk.CreateRenderPass(
			state.device,
			&render_pass_create_info,
			nil,
			&state.render_pass,
		); res != vk.Result.SUCCESS {
			panic("create render pass failed")
		}
		graphics_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
			sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
			stageCount          = 2,
			pStages             = raw_data(shader_stage_create_infos),
			pVertexInputState   = &vertex_input_state_create_info,
			pInputAssemblyState = &input_assembly_state_create_info,
			pViewportState      = &pipeline_viewport_state_create_info,
			pRasterizationState = &pipeline_rasterization_state_create_info,
			pMultisampleState   = &pipeline_multisample_state_create_info,
			pDepthStencilState  = nil,
			pColorBlendState    = &pipeline_color_blend_state_create_info,
			pDynamicState       = &dynamic_state_create_info,
			layout              = state.pipeline_layout,
			renderPass          = state.render_pass,
			subpass             = 0,
		}
		if res := vk.CreateGraphicsPipelines(
			state.device,
			0,
			1,
			&graphics_pipeline_create_info,
			nil,
			&state.graphics_pipeline,
		); res != .SUCCESS {
			panic("create graphics pipeline failed")
		}
		vk.DestroyShaderModule(state.device, state.shader_module_vertex, nil)
		vk.DestroyShaderModule(state.device, state.shader_module_fragment, nil)
		state.shader_module_vertex = 0
		state.shader_module_fragment = 0
	}
	defer {
		vk.DestroyPipeline(state.device, state.graphics_pipeline, nil)
		vk.DestroyPipelineLayout(state.device, state.pipeline_layout, nil)
		vk.DestroyRenderPass(state.device, state.render_pass, nil)
	}

	setup_new_framebuffers(&state)
	defer clean_up_swapchain(&state)

	{ 	// create command pool
		command_pool_create_info := vk.CommandPoolCreateInfo {
			sType            = .COMMAND_POOL_CREATE_INFO,
			flags            = {.RESET_COMMAND_BUFFER},
			queueFamilyIndex = state.graphics_queue_family_index,
		}
		if res := vk.CreateCommandPool(
			state.device,
			&command_pool_create_info,
			nil,
			&state.command_pool,
		); res != .SUCCESS {
			panic("create command pool failed")
		}
	}
	defer vk.DestroyCommandPool(state.device, state.command_pool, nil)

	{ 	// create texture image
		width, height, channel_count: i32
		pixels := image.load("./smiley.png", &width, &height, &channel_count, 0)
		if channel_count != 4 {
			panic("ASSERT - I've assumed 4 channel input images")
		}
		image_size := cast(vk.DeviceSize)(width * height * 4)
		staging_buffer, staging_buffer_memory := create_buffer(
			&state,
			image_size,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		defer {
			vk.DestroyBuffer(state.device, staging_buffer, nil)
			vk.FreeMemory(state.device, staging_buffer_memory, nil)
		}
		staging_buffer_data: rawptr
		vk.MapMemory(state.device, staging_buffer_memory, 0, image_size, {}, &staging_buffer_data)
		intrinsics.mem_copy_non_overlapping(staging_buffer_data, pixels, image_size)
		vk.UnmapMemory(state.device, staging_buffer_memory)
		texture_image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			extent = {width = cast(u32)width, height = cast(u32)height, depth = 1},
			mipLevels = 1,
			arrayLayers = 1,
			format = .R8G8B8A8_SRGB,
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = {.TRANSFER_DST, .SAMPLED},
			sharingMode = .EXCLUSIVE,
			samples = {._1},
		}
		if res := vk.CreateImage(
			state.device,
			&texture_image_create_info,
			nil,
			&state.texture_image,
		); res != .SUCCESS {
			panic("failed to create texture image")
		}
		image_memory_requirements: vk.MemoryRequirements
		vk.GetImageMemoryRequirements(
			state.device,
			state.texture_image,
			&image_memory_requirements,
		)
		image_allocate_info := vk.MemoryAllocateInfo {
			sType           = .MEMORY_ALLOCATE_INFO,
			allocationSize  = image_memory_requirements.size,
			memoryTypeIndex = find_memory_type(
				&state,
				image_memory_requirements.memoryTypeBits,
				{.DEVICE_LOCAL},
			),
		}
		if res := vk.AllocateMemory(
			state.device,
			&image_allocate_info,
			nil,
			&state.texture_image_memory,
		); res != .SUCCESS {
			panic("failed to allocate image memory")
		}
		vk.BindImageMemory(state.device, state.texture_image, state.texture_image_memory, 0)
		transition_image_layout(
			&state,
			state.texture_image,
			.R8G8B8A8_SRGB,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
		)
		copy_buffer_to_image(
			&state,
			staging_buffer,
			state.texture_image,
			cast(u32)width,
			cast(u32)height,
		)
		transition_image_layout(
			&state,
			state.texture_image,
			.R8G8B8A8_SRGB,
			.TRANSFER_DST_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
		)
	}
	defer {
		vk.DestroyImage(state.device, state.texture_image, nil)
		vk.FreeMemory(state.device, state.texture_image_memory, nil)
	}

	{ 	// create texture image view
		image_view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = state.texture_image,
			viewType = .D2,
			format = .R8G8B8A8_SRGB,
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
			&state.texture_image_view,
		); res != .SUCCESS {
			panic("failed to create texture image view")
		}
	}
	defer vk.DestroyImageView(state.device, state.texture_image_view, nil)

	{ 	// create texture sampler
		physical_device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(state.physical_device, &physical_device_properties)
		sampler_create_info := vk.SamplerCreateInfo {
			sType                   = .SAMPLER_CREATE_INFO,
			magFilter               = .LINEAR,
			minFilter               = .LINEAR,
			addressModeU            = .REPEAT,
			addressModeV            = .REPEAT,
			addressModeW            = .REPEAT,
			anisotropyEnable        = true,
			maxAnisotropy           = physical_device_properties.limits.maxSamplerAnisotropy,
			borderColor             = .INT_OPAQUE_BLACK,
			unnormalizedCoordinates = false,
			compareEnable           = false,
			compareOp               = .ALWAYS,
			mipmapMode              = .LINEAR,
			mipLodBias              = 0,
			minLod                  = 0,
			maxLod                  = 0,
		}
		if res := vk.CreateSampler(
			state.device,
			&sampler_create_info,
			nil,
			&state.texture_sampler,
		); res != .SUCCESS {
			panic("failed to create texture sampler")
		}
	}
	defer vk.DestroySampler(state.device, state.texture_sampler, nil)

	{ 	// create vertex buffer, allocate memory for it, and bind buffer to memory
		buffer_size := cast(vk.DeviceSize)(size_of(vertices[0]) * len(vertices))

		staging_buffer, staging_buffer_memory := create_buffer(
			&state,
			buffer_size,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		defer {
			vk.DestroyBuffer(state.device, staging_buffer, nil)
			vk.FreeMemory(state.device, staging_buffer_memory, nil)
		}

		state.vertex_buffer, state.vertex_buffer_memory = create_buffer(
			&state,
			buffer_size,
			{.VERTEX_BUFFER, .TRANSFER_DST},
			{.DEVICE_LOCAL},
		)

		staging_buffer_data: rawptr
		vk.MapMemory(state.device, staging_buffer_memory, 0, buffer_size, {}, &staging_buffer_data)
		intrinsics.mem_copy_non_overlapping(staging_buffer_data, raw_data(vertices), buffer_size)
		vk.UnmapMemory(state.device, staging_buffer_memory)
		copy_buffer(&state, staging_buffer, state.vertex_buffer, buffer_size)
	}
	defer {
		vk.DestroyBuffer(state.device, state.vertex_buffer, nil)
		vk.FreeMemory(state.device, state.vertex_buffer_memory, nil)
	}

	{ 	// create index buffer, allocate memory for it, and bind buffer to memory
		buffer_size := cast(vk.DeviceSize)(size_of(indices[0]) * len(indices))

		staging_buffer, staging_buffer_memory := create_buffer(
			&state,
			buffer_size,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		defer {
			vk.DestroyBuffer(state.device, staging_buffer, nil)
			vk.FreeMemory(state.device, staging_buffer_memory, nil)
		}

		state.index_buffer, state.index_buffer_memory = create_buffer(
			&state,
			buffer_size,
			{.INDEX_BUFFER, .TRANSFER_DST},
			{.DEVICE_LOCAL},
		)

		staging_buffer_data: rawptr
		vk.MapMemory(state.device, staging_buffer_memory, 0, buffer_size, {}, &staging_buffer_data)
		intrinsics.mem_copy_non_overlapping(staging_buffer_data, raw_data(indices), buffer_size)
		vk.UnmapMemory(state.device, staging_buffer_memory)
		copy_buffer(&state, staging_buffer, state.index_buffer, buffer_size)
	}
	defer {
		vk.DestroyBuffer(state.device, state.index_buffer, nil)
		vk.FreeMemory(state.device, state.index_buffer_memory, nil)
	}

	{ 	// create uniform buffers
		buffer_size := cast(vk.DeviceSize)size_of(UniformBufferObject)

		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			state.uniform_buffers[i], state.uniform_buffers_memory[i] = create_buffer(
				&state,
				buffer_size,
				{.UNIFORM_BUFFER},
				{.HOST_VISIBLE, .HOST_COHERENT},
			)
			vk.MapMemory(
				state.device,
				state.uniform_buffers_memory[i],
				0,
				buffer_size,
				{},
				&state.uniform_buffers_mapped[i],
			)
		}
	}
	defer {
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			vk.DestroyBuffer(state.device, state.uniform_buffers[i], nil)
			vk.FreeMemory(state.device, state.uniform_buffers_memory[i], nil)
		}
	}

	{ 	// create descriptor pool
		descriptor_pool_size_ubo := vk.DescriptorPoolSize {
			type            = .UNIFORM_BUFFER,
			descriptorCount = MAX_FRAMES_IN_FLIGHT,
		}
		descriptor_pool_size_sampler := vk.DescriptorPoolSize {
			type            = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = MAX_FRAMES_IN_FLIGHT,
		}
		pool_sizes := []vk.DescriptorPoolSize {
			descriptor_pool_size_ubo,
			descriptor_pool_size_sampler,
		}
		descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			poolSizeCount = cast(u32)len(pool_sizes),
			pPoolSizes    = raw_data(pool_sizes),
			maxSets       = MAX_FRAMES_IN_FLIGHT,
		}
		if res := vk.CreateDescriptorPool(
			state.device,
			&descriptor_pool_create_info,
			nil,
			&state.descriptor_pool,
		); res != .SUCCESS {
			panic("failed to create descriptor pool")
		}
	}
	defer vk.DestroyDescriptorPool(state.device, state.descriptor_pool, nil)

	{ 	// allocate and configure descriptor sets
		layouts := [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout {
			state.descriptor_set_layout,
			state.descriptor_set_layout,
		}
		allocate_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = state.descriptor_pool,
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
			pSetLayouts        = &layouts[0],
		}
		if res := vk.AllocateDescriptorSets(
			state.device,
			&allocate_info,
			&state.descriptor_sets[0],
		); res != .SUCCESS {
			panic("failed to allocate descriptor sets")
		}

		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			descriptor_buffer_info := vk.DescriptorBufferInfo {
				buffer = state.uniform_buffers[i],
				offset = 0,
				range  = size_of(UniformBufferObject),
			}
			descriptor_image_info := vk.DescriptorImageInfo {
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				imageView   = state.texture_image_view,
				sampler     = state.texture_sampler,
			}
			descriptor_write_buffer := vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = state.descriptor_sets[i],
				dstBinding      = 0,
				dstArrayElement = 0,
				descriptorType  = .UNIFORM_BUFFER,
				descriptorCount = 1,
				pBufferInfo     = &descriptor_buffer_info,
			}
			descriptor_write_sampler := vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = state.descriptor_sets[i],
				dstBinding      = 1,
				dstArrayElement = 0,
				descriptorType  = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				pImageInfo      = &descriptor_image_info,
			}
			descriptor_writes := []vk.WriteDescriptorSet {
				descriptor_write_buffer,
				descriptor_write_sampler,
			}
			vk.UpdateDescriptorSets(state.device, cast(u32)len(descriptor_writes), raw_data(descriptor_writes), 0, nil)
		}
	}

	{ 	// create command buffers
		command_buffer_allocate_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = state.command_pool,
			level              = .PRIMARY,
			commandBufferCount = len(state.command_buffers),
		}
		if res := vk.AllocateCommandBuffers(
			state.device,
			&command_buffer_allocate_info,
			&state.command_buffers[0],
		); res != .SUCCESS {
			panic("allocate command buffers failed")
		}
	}

	{ 	// create sync objects
		semaphore_create_info := vk.SemaphoreCreateInfo {
			sType = .SEMAPHORE_CREATE_INFO,
		}
		fence_create_info := vk.FenceCreateInfo {
			sType = .FENCE_CREATE_INFO,
			flags = {.SIGNALED},
		}
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			if res := vk.CreateSemaphore(
				state.device,
				&semaphore_create_info,
				nil,
				&state.sync_semaphores_image_available[i],
			); res != .SUCCESS {
				panic("create image available semaphore failed")
			}
			if res := vk.CreateSemaphore(
				state.device,
				&semaphore_create_info,
				nil,
				&state.sync_semaphores_render_finished[i],
			); res != .SUCCESS {
				panic("create render finished semaphore failed")
			}
			if res := vk.CreateFence(
				state.device,
				&fence_create_info,
				nil,
				&state.sync_fences_in_flight[i],
			); res != .SUCCESS {
				panic("create in-flight fence failed")
			}
		}
	}
	defer {
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			vk.DestroySemaphore(state.device, state.sync_semaphores_image_available[i], nil)
			vk.DestroySemaphore(state.device, state.sync_semaphores_render_finished[i], nil)
			vk.DestroyFence(state.device, state.sync_fences_in_flight[i], nil)
		}
	}

	// main loop
	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
		draw_frame(&state)
	}
	vk.DeviceWaitIdle(state.device)
}
