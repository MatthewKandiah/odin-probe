package main

import "core:fmt"
import "core:strings"
import "vendor:glfw"
import vk "vendor:vulkan"

required_layer_names := []cstring{"VK_LAYER_KHRONOS_validation"}

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
	for i: u32 = 0; i < cast(u32)len(queue_family_properties); i += 1 {
		queue_family_properties := queue_family_properties[i]
		if vk.QueueFlag.GRAPHICS in queue_family_properties.queueFlags {
			state.graphics_queue_family_index = i
			graphics_index_found = true
			break
		}

		// TODO-Matt: create a KHR surface, then we'll need to get a queue family index for a present queue compatible with that surface
	}
  if !graphics_index_found {
    panic("failed to find graphics queue family index")
  }

	queue_priority: f32 = 1
	graphics_queue_create_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = state.graphics_queue_family_index,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}

	queue_create_infos: []vk.DeviceQueueCreateInfo = {graphics_queue_create_info}
	device_create_info := vk.DeviceCreateInfo {
		sType                = .DEVICE_CREATE_INFO,
		pQueueCreateInfos    = raw_data(queue_create_infos),
		queueCreateInfoCount = cast(u32)len(queue_create_infos),
	}

	return(
		vk.CreateDevice(state.physical_device, &device_create_info, nil, &state.device) ==
		vk.Result.SUCCESS \
	)
}

get_queue_handle :: proc(state: ^State) -> (success: bool) {
	if state.device == nil {
		panic("cannot get queue handle before creating logical device")
	}
	// assumes we are only grabbing one queue per queue family
	vk.GetDeviceQueue(state.device, state.graphics_queue_family_index, 0, &state.graphics_queue)

	return true
}
