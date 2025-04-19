package main

import "core:fmt"
import "vendor:x11/xlib"

quitted := false

main :: proc() {
	display := xlib.OpenDisplay("")
	if display == nil {
		fmt.println("main_display == nil")
	} else {
		fmt.println("main_display init successful")
	}

	root_window := xlib.DefaultRootWindow(display)
	if root_window == 0 {
		fmt.println("root_window == 0")
	} else {
		fmt.println("root_window init successful", root_window)
	}

	window := xlib.CreateSimpleWindow(display, root_window, 0, 0, 800, 600, 0, 0, 0xffffffff)
	if window == 0 {
		fmt.println("window == 0")
	} else {
		fmt.println("window creation successful", window)
	}

	xlib.MapWindow(display, window)

	onDelete :: proc(display: ^xlib.Display, window: xlib.Window) {
		xlib.DestroyWindow(display, window)
		quitted = true
	}

	wm_delete_window := xlib.InternAtom(display, "WM_DELETE_WINDOW", false)
	xlib.SetWMProtocols(display, window, &wm_delete_window, 1)

	event: xlib.XEvent
	for !quitted {
		xlib.NextEvent(display, &event)

		#partial switch event.type {
		case xlib.EventType.ClientMessage:
			if (event.xclient.data.l[0] == cast(int)wm_delete_window) {
				onDelete(event.xclient.display, event.xclient.window)
			}
		}
	}

	xlib.CloseDisplay(display)
}
