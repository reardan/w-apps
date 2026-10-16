import lib.assert
import win.worker_graphics

int main():
	win_worker_graphics* graphics = win_worker_graphics_new()
	if (graphics == 0):
		println(c"SKIP worker capture test: no GLX display")
		return 0
	win_canvas* canvas = win_canvas_new(0, 2, 2, 1)
	assert1(canvas != 0 && canvas.context != 0)
	assert1(win_canvas_enter(canvas))
	glClearColor(1.0, 0.0, 0.0, 1.0)
	glClear(GL_COLOR_BUFFER_BIT)
	# A preexisting script error must remain observable without spoiling a
	# valid internal readback.
	glEnable(0)
	win_canvas_leave(canvas)
	assert1(win_worker_canvas_capture(canvas))
	assert_equal(0x500, canvas.error)
	for i in range(4):
		assert_equal(255, canvas.pixels[i * 4] & 255)
		assert_equal(0, canvas.pixels[i * 4 + 1])
		assert_equal(0, canvas.pixels[i * 4 + 2])
		assert_equal(255, canvas.pixels[i * 4 + 3] & 255)
	assert1(win_canvas_enter(canvas))
	int32 framebuffer = 0
	glGenFramebuffers(1, &framebuffer)
	glBindFramebuffer(0x8D40, framebuffer)
	win_canvas_leave(canvas)
	canvas.error = 0
	for i in range(16): canvas.pixels[i] = 123
	assert_equal(0, win_worker_canvas_capture(canvas))
	assert_equal(0x506, canvas.error)
	for i in range(16): assert_equal(0, canvas.pixels[i])
	win_canvas_free(canvas)
	win_worker_graphics_free(graphics)
	println(c"Worker capture: valid pixels, preserved WebGL error, zeroed failed readback: OK")
	return 0
