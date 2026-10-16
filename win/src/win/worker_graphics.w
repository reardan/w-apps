# Worker-only unmapped X11 drawable. Never maps a window or requests focus.
# The child owns this connection/context and every canvas context it creates.
import win.canvas

struct win_worker_graphics:
	int display
	int drawable
	int context
	int colormap

c_lib "libX11.so.6"
extern int XFreeColormap(int display, int colormap)

void win_worker_graphics_free(win_worker_graphics* graphics):
	if (graphics == 0): return
	glXMakeCurrent(graphics.display, 0, 0)
	if (graphics.context): glXDestroyContext(graphics.display, graphics.context)
	if (graphics.drawable): XDestroyWindow(graphics.display, graphics.drawable)
	if (graphics.colormap): XFreeColormap(graphics.display, graphics.colormap)
	XCloseDisplay(graphics.display)
	free(graphics)

win_worker_graphics* win_worker_graphics_new():
	int display = XOpenDisplay(0)
	if (display == 0): return 0
	win_worker_graphics* graphics = new win_worker_graphics()
	graphics.display = display
	int32[5] attributes
	attributes[0] = GLX_RGBA
	attributes[1] = GLX_DOUBLEBUFFER
	attributes[2] = GLX_DEPTH_SIZE
	attributes[3] = 16
	attributes[4] = 0
	int screen = XDefaultScreen(display)
	x_visual_info* visual = glXChooseVisual(display, screen, &attributes[0])
	if (visual == 0):
		win_worker_graphics_free(graphics)
		return 0
	int root = XRootWindow(display, screen)
	x_set_window_attributes settings
	settings.colormap = XCreateColormap(display, root, visual.visual, 0)
	settings.border_pixel = 0
	settings.event_mask = 0
	graphics.colormap = settings.colormap
	graphics.drawable = XCreateWindow(display, root, 0, 0, 1, 1, 0, visual.depth, InputOutput, visual.visual, CWBorderPixel | CWEventMask | CWColormap, &settings)
	graphics.context = glXCreateContext(display, visual, 0, 1)
	XFree(cast(int, visual))
	if (graphics.context == 0 || glXMakeCurrent(display, graphics.drawable, graphics.context) == 0):
		win_worker_graphics_free(graphics)
		return 0
	return graphics

# Snapshot into the canvas-owned CPU buffer, tightly packed top-left RGBA8.
int win_worker_canvas_capture(win_canvas* canvas):
	if (canvas.width <= 0 || canvas.height <= 0 || win_canvas_enter(canvas) == 0): return 0
	glPixelStorei(0x0D05, 1)
	glReadPixels(0, 0, canvas.width, canvas.height, GL_RGBA, GL_UNSIGNED_BYTE, canvas.pixels)
	glPixelStorei(0x0D05, canvas.pack_alignment)
	win_canvas_leave(canvas)
	int stride = canvas.width * 4
	for y in range(canvas.height / 2):
		for x in range(stride):
			int top = y * stride + x
			int bottom = (canvas.height - y - 1) * stride + x
			char saved = canvas.pixels[top]
			canvas.pixels[top] = canvas.pixels[bottom]
			canvas.pixels[bottom] = saved
	return 1
