import lib.assert
import win.images
import tests.images.gif_fixtures

int main():
	wresult[rgba_image*]* decoded = win_image_decode(gif_fixture_offset(), gif_fixture_offset_length)
	assert_equal(1, decoded.ok)
	rgba_image* rgba = decoded.value
	assert_equal(3, rgba.width)
	assert_equal(3, rgba.height)
	for i in range(rgba.length): assert_equal(gif_golden_offset()[i] & 255, rgba.pixels[i] & 255)
	win_image image
	image.node = 0
	image.width = rgba.width
	image.height = rgba.height
	image.length = rgba.length
	image.pixels = rgba.pixels
	image.texture = 0
	image.failed = 0
	rgba.pixels = 0
	rgba_image_free(rgba)
	free(decoded)
	ui_renderer renderer
	ui_render_init_headless(&renderer)
	ui_render_begin(&renderer, 100, 100)
	win_image_draw(&renderer, &image, ui_rect_new(0.0, 0.0, 30.0, 30.0))
	assert_equal(1, renderer.commands.length)
	asserts(c"GIF uploaded to native renderer", image.texture != 0 && image.pixels == 0)
	for i in range(image.length): assert_equal(gif_golden_offset()[i] & 255, image.texture.pixels[i] & 255)
	ui_image_release(image.texture)
	ui_render_destroy(&renderer)
	decoded = win_image_decode(gif_bad_bad_code(), gif_bad_bad_code_length)
	assert_equal(IMAGE_COMPRESSED_DATA, decoded.code)
	free(decoded)
	decoded = win_image_decode(0, 20)
	assert_equal(IMAGE_BAD_FORMAT, decoded.code)
	free(decoded)
	println(c"GIF browser decode and texture upload: OK")
	return 0
