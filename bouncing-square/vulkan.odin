package main

import "vendor:glfw"
import vk "vendor:vulkan"

init_vulkan :: proc(state: ^State) -> (success: bool) {
	application_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "bouncing ball",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "magic",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_4,
	}

	glfw_extensions := glfw.GetRequiredInstanceExtensions()

	instance_create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &application_info,
		enabledExtensionCount   = cast(u32)len(glfw_extensions),
		ppEnabledExtensionNames = &glfw_extensions[0],
		enabledLayerCount       = 0,
	}

	context.user_ptr = state
	load_vulkan_dispatch_table()
	return vk.CreateInstance(&instance_create_info, nil, &state.vk_instance) == vk.Result.SUCCESS
}

load_vulkan_dispatch_table :: proc() {
	get_proc_address :: proc(p: rawptr, name: cstring) {
		state := cast(^State)context.user_ptr
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(state.vk_instance, name)
	}
	vk.load_proc_addresses(get_proc_address)
}
