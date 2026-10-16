# Display-only ownership of validated worker pixels; never a JS/GL handle.
import win.frame_transport
import graphics.ui.render

const int WIN_INTERACTIVE_CANVASES = 8
const int WIN_INTERACTIVE_PIXELS = 16777216

struct win_frame_surface:
	int node_id
	int width
	int height
	char* pixels
	ui_image* image

void win_frame_surfaces_clear(list[win_frame_surface*] surfaces):
	for win_frame_surface* surface in surfaces:
		free(surface.pixels)
		if (surface.image != 0): ui_image_release(surface.image)
		free(surface)
	while (surfaces.length > 0): surfaces.pop()

void win_frame_surface_draw(win_frame_surface* surface, ui_renderer* renderer, ui_rect rect):
	if (renderer.gl_ready == 0): return
	if (surface.pixels != 0):
		surface.image = ui_image_create(renderer, surface.width, surface.height, surface.pixels, surface.width * surface.height * 4)
		free(surface.pixels)
		surface.pixels = 0
	if (surface.image != 0): ui_draw_image(renderer, surface.image, rect, 1.0)
