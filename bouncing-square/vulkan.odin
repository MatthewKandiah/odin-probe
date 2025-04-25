package main

import "core:fmt"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

required_layer_names := []cstring{"VK_LAYER_KHRONOS_validation"}

required_extension_names := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

init_vulkan :: proc(state: ^State) -> (success: bool) {
	context.user_ptr = state
	load_vulkan_dispatch_table()

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
		fmt.eprintln("required layers not supported")
		return false
	}

	instance_create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &application_info,
		enabledExtensionCount   = cast(u32)len(glfw_extensions),
		ppEnabledExtensionNames = raw_data(glfw_extensions),
		enabledLayerCount       = cast(u32)len(required_layer_names),
		ppEnabledLayerNames     = raw_data(required_layer_names),
	}

	return vk.CreateInstance(&instance_create_info, nil, &state.instance) == vk.Result.SUCCESS
}

load_vulkan_dispatch_table :: proc() {
	get_proc_address :: proc(p: rawptr, name: cstring) {
		state := cast(^State)context.user_ptr
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(state.instance, name)
	}
	vk.load_proc_addresses(get_proc_address)
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

	for required_layer_name in required_layer_names {
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

	for required_extension_name in required_extension_names {
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

get_physical_gpu :: proc(state: ^State) -> (success: bool) {
	physical_device_count: u32
	vk.EnumeratePhysicalDevices(state.instance, &physical_device_count, nil)
	if physical_device_count == 0 {
		panic("failed to find a Vulkan compatible device")
	}
	physical_devices := make([]vk.PhysicalDevice, physical_device_count)
	defer delete(physical_devices)
	if vk.EnumeratePhysicalDevices(
		   state.instance,
		   &physical_device_count,
		   raw_data(physical_devices),
	   ) !=
	   vk.Result.SUCCESS {
		panic("enumerate physical devices failed")
	}

	for physical_device in physical_devices {
		properties: vk.PhysicalDeviceProperties
		if !check_extension_support(physical_device) {
			continue
		}
		vk.GetPhysicalDeviceProperties(physical_device, &properties)
		if properties.deviceType == .DISCRETE_GPU {
			state.physical_device = physical_device
			return true
		} else if properties.deviceType == .INTEGRATED_GPU {
			state.physical_device = physical_device
		}
	}
	return state.physical_device != nil
}

create_device :: proc(state: ^State) -> (success: bool) {
	if (state.physical_device == nil) {
		panic("cannot create logical device before selecting a physical device")
	}

	queue_family_properties_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(
		state.physical_device,
		&queue_family_properties_count,
		nil,
	)
	queue_family_properties := make([]vk.QueueFamilyProperties, queue_family_properties_count)
	defer delete(queue_family_properties)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		state.physical_device,
		&queue_family_properties_count,
		raw_data(queue_family_properties),
	)

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
	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pQueueCreateInfos       = raw_data(queue_create_infos),
		queueCreateInfoCount    = cast(u32)len(queue_create_infos),
		ppEnabledExtensionNames = raw_data(required_extension_names),
		enabledExtensionCount   = cast(u32)len(required_extension_names),
	}

	if res := vk.CreateDevice(state.physical_device, &device_create_info, nil, &state.device);
	   res != vk.Result.SUCCESS {
		return false
	}

	get_queue_handles(state)
	return true
}

get_queue_handles :: proc(state: ^State) {
	if state.device == nil {
		panic("cannot get queue handle before creating logical device")
	}
	// assumes we are only grabbing one queue per queue family
	vk.GetDeviceQueue(state.device, state.graphics_queue_family_index, 0, &state.graphics_queue)
	vk.GetDeviceQueue(state.device, state.present_queue_family_index, 0, &state.present_queue)
}

create_window_surface :: proc(state: ^State) -> (success: bool) {
	return(
		glfw.CreateWindowSurface(state.instance, state.window, nil, &state.surface) ==
		vk.Result.SUCCESS \
	)
}

create_swapchain :: proc(state: ^State) -> (success: bool) {
	if state.device == nil {
		panic("cannot create swapchain before creating logical device")
	}

	if state.graphics_queue_family_index != state.present_queue_family_index {
		panic(
			"I've assumed these values will be equal, imageSharingMode exclusive will not work if they are different",
		)
	}

	swapchain_create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = state.surface,
		oldSwapchain     = 0, // VK_NULL_HANDLE
		imageFormat      = state.surface_format.format,
		imageColorSpace  = state.surface_format.colorSpace,
		presentMode      = state.present_mode,
		imageExtent      = state.extent,
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
		return false
	}

	return true
}

get_physical_device_surface_formats :: proc(state: ^State) -> (success: bool) {
	if state.physical_device == nil {
		panic("cannot query supported formats before creating physical device")
	}
	if state.surface == 0 {
		panic("cannot query supported formats before creating surface")
	}

	count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(state.physical_device, state.surface, &count, nil)
	if count == 0 {
		return false
	}

	formats := make([]vk.SurfaceFormatKHR, count)
	if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
		state.physical_device,
		state.surface,
		&count,
		raw_data(formats),
	); res != vk.Result.SUCCESS {
		return false
	}

	state.supported_surface_formats = formats

	format_selected := false
	for available_format in formats {
		// select preferred format if it's supported, else just take the first supported format
		if available_format.format == vk.Format.B8G8R8A8_SRGB &&
		   available_format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
			state.surface_format = available_format
			format_selected = true
			break
		}
	}
	if !format_selected {
		state.surface_format = formats[0]
	}
	return true
}

get_physical_device_surface_present_modes :: proc(state: ^State) -> (success: bool) {
	if state.physical_device == nil {
		panic("cannot query supported present modes before creating physical device")
	}
	if state.surface == 0 {
		panic("cannot query supported present modes before creating surface")
	}

	count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(state.physical_device, state.surface, &count, nil)
	if count == 0 {
		return false
	}

	modes := make([]vk.PresentModeKHR, count)
	if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
		state.physical_device,
		state.surface,
		&count,
		raw_data(modes),
	); res != vk.Result.SUCCESS {
		return false
	}

	state.supported_surface_present_modes = modes

	mode_selected := false
	for available_mode in modes {
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

	return true
}

get_swap_exent :: proc(state: ^State) -> (success: bool) {
	if res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		state.physical_device,
		state.surface,
		&state.surface_capabilities,
	); res != vk.Result.SUCCESS {
		return false
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
		state.extent = extent
	} else {
		// default case, set swapchain extent to match the screens current extent
		state.extent = state.surface_capabilities.currentExtent
	}

	return true
}
