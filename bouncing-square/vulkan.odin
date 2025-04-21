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
		apiVersion         = vk.API_VERSION_1_4,
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

	return vk.CreateInstance(&instance_create_info, nil, &state.vk_instance) == vk.Result.SUCCESS
}

load_vulkan_dispatch_table :: proc() {
	get_proc_address :: proc(p: rawptr, name: cstring) {
		state := cast(^State)context.user_ptr
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(state.vk_instance, name)
	}
	vk.load_proc_addresses(get_proc_address)
}

check_validation_layer_support :: proc() -> bool {
	count: u32
	vk.EnumerateInstanceLayerProperties(&count, nil)

	available_layers := make([]vk.LayerProperties, count)
	vk.EnumerateInstanceLayerProperties(&count, raw_data(available_layers))

	for required_layer_name in required_layer_names {
		found := false
		fmt.println("Checking for layer", required_layer_name)
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
