#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <X11/Xlib.h>

bool quitted = true;

void on_delete(Display *display, Window window) {
  XDestroyWindow(display, window);
  quitted = true;
}

int main(int argc, char *argv[]) {
  Display *display = XOpenDisplay(NULL);
  if (NULL == display) {
    fprintf(stderr, "Failed to init display");
    return EXIT_FAILURE;
  }

  Window root = DefaultRootWindow(display);
  if (None == root) {
    fprintf(stderr, "No root window found");
    XCloseDisplay(display);
    return EXIT_FAILURE;
  }

  Window window = XCreateSimpleWindow(display, root, 0,0,800,600,0,0,0xffffffff);
  if (None == window) {
    fprintf(stderr, "Failed to create window");
    XCloseDisplay(display);
    return EXIT_FAILURE;
  }

  XMapWindow(display, window);

  Atom wm_delete_window = XInternAtom(display, "WM_DELETE_WINDOW", False);
  XSetWMProtocols(display, window, &wm_delete_window, 1);
  
  XEvent event;
  while(!quitted) {
    XNextEvent(display, &event);

    switch(event.type) {
      case ClientMessage:
        if(event.xclient.data.l[0] == wm_delete_window) {
          on_delete(event.xclient.display, event.xclient.window);
        }
      break;
    }
  }

  XCloseDisplay(display);

  return 0;
}
