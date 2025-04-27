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
	swapchain_image_count:          u32,
	swapchain_image_index:          u32,
	swapchain_image_views:          []vk.ImageView,
	swapchain_images:               []vk.Image,
	sync_fence_in_flight:           vk.Fence,
	sync_semaphore_image_available: vk.Semaphore,
	sync_semaphore_render_finished: vk.Semaphore,
	window:                         glfw.WindowHandle,
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
	physical_device_count: u32
	vk.EnumeratePhysicalDevices(instance, &physical_device_count, nil)
	if physical_device_count == 0 {
		panic("failed to find a Vulkan compatible device")
	}
	physical_devices := make([]vk.PhysicalDevice, physical_device_count)
	if vk.EnumeratePhysicalDevices(instance, &physical_device_count, raw_data(physical_devices)) !=
	   vk.Result.SUCCESS {
		panic("enumerate physical devices failed")
	}
	return physical_devices
}

get_queue_family_properties :: proc(
	physical_device: vk.PhysicalDevice,
) -> []vk.QueueFamilyProperties {
	queue_family_properties_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_properties_count, nil)
	queue_family_properties := make([]vk.QueueFamilyProperties, queue_family_properties_count)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&queue_family_properties_count,
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

