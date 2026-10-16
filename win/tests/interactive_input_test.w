import lib.assert
import win.interactive_worker

int main():
	win_interactive_input input
	input.generation = 7
	input.document = 3
	input.width = 390
	input.height = 720
	input.mouse_x = -12
	input.mouse_y = 150
	input.mods = GFX_MOD_SHIFT
	win_native_clear(&input.native)
	gfx_event event
	event.kind = GFX_EVENT_CHAR
	event.code = 128578
	event.x = 0
	event.y = 0
	event.mods = 0
	win_native_push(&input.native, &event)
	string_builder* bytes = win_interactive_input_encode(&input)
	assert1(bytes != 0)
	win_interactive_input* decoded = win_interactive_input_decode(bytes.data, bytes.length, 7, 3)
	assert1(decoded != 0)
	assert_equal(128578, decoded.native.events[0].code)
	assert_equal(-12, decoded.mouse_x)
	free(decoded)
	assert1(win_interactive_input_decode(bytes.data, bytes.length, 8, 3) == 0)
	assert1(win_interactive_input_decode(bytes.data, bytes.length, 7, 4) == 0)
	assert1(win_interactive_input_decode(bytes.data, bytes.length - 1, 7, 3) == 0)
	save_int32(bytes.data + 16, 2147483647)
	assert1(win_interactive_input_decode(bytes.data, bytes.length, 7, 3) == 0)
	save_int32(bytes.data + 16, 1)
	save_int32(bytes.data + WIN_INPUT_PREFIX + 4, 55296)
	assert1(win_interactive_input_decode(bytes.data, bytes.length, 7, 3) == 0)
	save_int32(bytes.data + WIN_INPUT_PREFIX + 4, 65)
	save_int32(bytes.data + WIN_INPUT_PREFIX, 99)
	assert1(win_interactive_input_decode(bytes.data, bytes.length, 7, 3) == 0)
	save_int32(bytes.data + WIN_INPUT_PREFIX, GFX_EVENT_NAV)
	save_int32(bytes.data + WIN_INPUT_PREFIX + 4, 10)
	assert1(win_interactive_input_decode(bytes.data, bytes.length, 7, 3) == 0)
	save_int32(bytes.data + WIN_INPUT_PREFIX + 4, GFX_NAV_LEFT)
	save_int32(bytes.data + 32, 1)
	assert1(win_interactive_input_decode(bytes.data, bytes.length, 7, 3) == 0)
	string_free(bytes)
	# A harmless process handle exercises queue ownership without spawning.
	win_interactive_worker* worker = new win_interactive_worker()
	worker.child = new process()
	worker.child.stdin_fd = -1
	worker.child.stdout_fd = -1
	worker.child.stderr_fd = -1
	worker.child.reaped = 1
	worker.generation = 7
	worker.document_generation = 3
	worker.input_queue = new list[win_interactive_input*]
	for i in range(3):
		win_interactive_input* motion = new win_interactive_input()
		motion[0] = input
		motion.native.count = 0
		motion.mouse_x = 20 + i
		assert1(win_interactive_enqueue(worker, motion))
	assert_equal(1, worker.input_queue.length)
	assert_equal(22, worker.input_queue[0].mouse_x)
	free(worker.input_queue.pop())
	for i in range(3):
		win_interactive_input* text = new win_interactive_input()
		text[0] = input
		text.native.events[0].code = 'a' + i
		assert1(win_interactive_enqueue(worker, text))
	assert_equal(1, worker.input_queue.length)
	assert_equal(3, worker.input_queue[0].native.count)
	assert_equal('c', worker.input_queue[0].native.events[2].code)
	free(worker.input_queue.pop())
	for i in range(8):
		win_interactive_input* batch = new win_interactive_input()
		batch[0] = input
		batch.native.events[0].kind = GFX_EVENT_MOUSE_DOWN
		batch.native.events[0].code = 1
		assert1(win_interactive_enqueue(worker, batch))
	assert_equal(8, worker.input_queue.length)
	win_interactive_input* overflow = new win_interactive_input()
	overflow[0] = input
	overflow.native.events[0].kind = GFX_EVENT_MOUSE_UP
	overflow.native.events[0].code = 1
	assert_equal(0, win_interactive_enqueue(worker, overflow))
	assert_equal(5, worker.status)
	assert1(worker.child == 0)
	assert_equal(8, worker.input_queue.length)
	free(overflow)
	for win_interactive_input* queued in worker.input_queue: free(queued)
	__w_list_free(cast(__w_list*, worker.input_queue))
	free(worker)
	println(c"Win complete raw input validation and document/worker generations: OK")
	return 0
