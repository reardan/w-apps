# Images are decoded in loader processes, then uploaded on the rendering thread.
import graphics.image.png
import graphics.image.jpeg
import graphics.ui.render
import libs.extras.html.html

const int WIN_IMAGE_INPUT_LIMIT = 4194304
const int WIN_IMAGE_RGBA_LIMIT = 16777216

struct win_image:
	html_node* node
	int width
	int height
	int length
	char* pixels
	ui_image* texture
	int failed

win_image* win_image_find(list[win_image*] images, html_node* node):
	for i in range(images.length):
		if (images[i].node == node): return images[i]
	return 0

void win_images_free(list[win_image*] images):
	for i in range(images.length):
		win_image* image = images[i]
		if (image.texture != 0): ui_image_release(image.texture)
		if (image.pixels != 0): free(image.pixels)
		free(image)
	__w_list_free(cast(__w_list*, images))

void win_image_draw(ui_renderer* renderer, win_image* image, ui_rect rect):
	if (image == 0 || image.failed || image.width == 0): return
	if (image.texture == 0 && image.pixels != 0):
		image.texture = ui_image_create(renderer, image.width, image.height, image.pixels, image.length)
		free(image.pixels)
		image.pixels = 0
	if (image.texture != 0): ui_draw_image(renderer, image.texture, rect, 1.0)

wresult[rgba_image*]* win_image_decode(char* source, int length):
	image_limits limits
	limits.input_bytes = WIN_IMAGE_INPUT_LIMIT
	limits.width = 4096
	limits.height = 4096
	limits.rgba_bytes = WIN_IMAGE_RGBA_LIMIT
	if (length >= 8 && (source[0] & 255) == 137): return png_decode_n(source, length, &limits)
	if (length >= 2 && (source[0] & 255) == 255 && (source[1] & 255) == 216): return jpeg_decode_n(source, length, &limits)
	return result_new_error[rgba_image*](IMAGE_UNSUPPORTED)

# Fixed-width binary dimensions avoid ambiguous delimiters in pixel data.
int win_image_receive(win_image* image, char* source, int length):
	if (length < 8): return 0
	int width = load_be32(source)
	int height = load_be32(source + 4)
	if (width < 1 || height < 1 || width > 4096 || height > 4096): return 0
	if (height > WIN_IMAGE_RGBA_LIMIT / 4 / width || length - 8 != width * height * 4): return 0
	image.width = width
	image.height = height
	image.length = length - 8
	image.pixels = cast(char*, malloc(image.length))
	for i in range(image.length): image.pixels[i] = source[i + 8]
	return 1
