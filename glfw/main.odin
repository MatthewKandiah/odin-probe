package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "vendor:glfw"
import vk "vendor:vulkan"

WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 600

State :: struct {
	vk_instance: vk.Instance,
	window:      glfw.WindowHandle,
}

main :: proc() {
	state: State

	if !glfw.Init() {
		panic("glfwInit failed")
	}
	defer glfw.Terminate()

	errorCallback :: proc "c" (error: c.int, description: cstring) {
		context = runtime.default_context()
		fmt.eprintln("ERROR", error, description)
		panic("glfw error")
	}
	glfw.SetErrorCallback(errorCallback)

	if !createWindow(&state) {
		panic("createWindow failed")
	}
	defer glfw.DestroyWindow(state.window)

	keyCallback :: proc "c" (
		window: glfw.WindowHandle,
		key: c.int,
		scancode: c.int,
		action: c.int,
		mods: c.int,
	) {
		if (key == glfw.KEY_ESCAPE && action == glfw.PRESS) {
			glfw.SetWindowShouldClose(window, glfw.TRUE)
		}
	}
	glfw.SetKeyCallback(state.window, keyCallback)

	if !initVulkan(&state) {
		panic("initVulkan failed")
	}

	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
	}
}

createWindow :: proc(state: ^State) -> (success: bool) {
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	window := glfw.CreateWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "glfw", nil, nil)
	if window == nil {
		return false
	}

	state.window = window
	return true
}

initVulkan :: proc(state: ^State) -> (success: bool) {
	application_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Hello glfw/vulkan",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "mjk",
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
	loadVulkanDispatchTable()
	if res := vk.CreateInstance(&instance_create_info, nil, &state.vk_instance);
	   res != vk.Result.SUCCESS {
		return false
	}

	return true
}

loadVulkanDispatchTable :: proc() {
	getProcAddress :: proc(p: rawptr, name: cstring) {
		state := cast(^State)context.user_ptr
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(state.vk_instance, name)
	}
	vk.load_proc_addresses(getProcAddress)
}
