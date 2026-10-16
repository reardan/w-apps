import lib.assert
import lib.args
import win.interactive_worker

int frame_test_read(char* data, int length):
	int at = 0
	while (at < length):
		int count = read(0, data + at, length - at)
		if (count <= 0): return 0
		at = at + count
	return 1

void frame_test_snapshot(char* mode, int sequence, int count):
	string_builder* snapshot = string_new()
	win_interactive_header(snapshot, sequence, 101)
	for i in range(16): string_append_char(snapshot, 0)
	save_int32(snapshot.data + 32, count)
	save_int32(snapshot.data + 36, 1)
	if (strcmp(mode, c"manifest") == 0): save_int32(snapshot.data + 36, 20001)
	if (count == 2):
		for i in range(4): string_append_char(snapshot, 0)
		save_int32(snapshot.data + 40, 2)
		if (strcmp(mode, c"duplicate") == 0): save_int32(snapshot.data + 40, 1)
	string_append(snapshot, c"local")
	string_append_char(snapshot, 0)
	string_append(snapshot, c"pixels")
	string_append_char(snapshot, 0)
	string_append(snapshot, c"<canvas data-win-node='1' width='2' height='2'></canvas><canvas data-win-node='2' width='2' height='2'></canvas>")
	string_append_char(snapshot, 0)
	save_int32(snapshot.data + 8, snapshot.length - 24)
	# Force fragmentation across both protocol headers.
	for i in range(snapshot.length): socket_send(0, snapshot.data + i, 1, 16384)
	string_free(snapshot)

int frame_test_child(char* mode):
	int count = 1
	if (strcmp(mode, c"duplicate") == 0): count = 2
	frame_test_snapshot(mode, 0, count)
	char[16] pixels
	for i in range(16): pixels[i] = i
	win_frame_sender* sender = win_frame_sender_new(7, WIN_INTERACTIVE_PIXELS)
	win_frame_sender_submit(sender, 2, 2, 8, &pixels[0], 16)
	if (strcmp(mode, c"stale") == 0): win_frame_u32_write(sender.outgoing.data + 12, 6)
	if (strcmp(mode, c"sequence") == 0): win_frame_u32_write(sender.outgoing.data + 16, 2)
	if (strcmp(mode, c"oversize") == 0): win_frame_u32_write(sender.outgoing.data + 36, WIN_INTERACTIVE_PIXELS + 1)
	if (strcmp(mode, c"stride") == 0): win_frame_u32_write(sender.outgoing.data + 32, 12)
	int length = sender.outgoing.length
	if (strcmp(mode, c"partial") == 0 || strcmp(mode, c"hang") == 0): length = 50
	for i in range(length):
		socket_send(0, sender.outgoing.data + i, 1, 16384)
		win_frame_sender_advance(sender, 1)
	if (strcmp(mode, c"partial") == 0): close(0)
	if (strcmp(mode, c"good") != 0 && strcmp(mode, c"atomic") != 0):
		process_sleep_ms(5000)
		win_frame_sender_free(sender)
		return 0
	char[48] ack
	assert1(frame_test_read(&ack[0], 48))
	win_frame_header h
	assert1(win_frame_header_read(&ack[0], &h, 4))
	assert1(win_frame_sender_ack(sender, h))
	assert1(sender.outgoing == 0)
	# The next request forwards viewport dimensions, without another frame queued.
	char[36] request
	assert1(frame_test_read(&request[0], 36))
	assert_equal(1, load_int32(&request[20]))
	assert_equal(320, load_int32(&request[28]))
	assert_equal(240, load_int32(&request[32]))
	if (strcmp(mode, c"atomic") == 0):
		frame_test_snapshot(mode, 1, 2)
		win_frame_sender_submit(sender, 2, 2, 8, &pixels[0], 16)
		socket_send(0, sender.outgoing.data, sender.outgoing.length, 16384)
		win_frame_sender_advance(sender, sender.outgoing.length)
		assert1(frame_test_read(&ack[0], 48))
		assert1(win_frame_header_read(&ack[0], &h, 4))
		assert1(win_frame_sender_ack(sender, h))
		win_frame_sender_submit(sender, 2, 2, 8, &pixels[0], 16)
		win_frame_u32_write(sender.outgoing.data + 12, 6)
		socket_send(0, sender.outgoing.data, sender.outgoing.length, 16384)
	win_frame_sender_free(sender)
	process_sleep_ms(5000)
	return 0

int frame_test_wait(win_interactive_worker* worker):
	int result = 0
	while (result == 0):
		int started = process_monotonic_ms()
		result = win_interactive_poll(worker)
		assert1(process_monotonic_ms() - started < 100)
		process_sleep_ms(1)
	return result

void frame_test_bad(char* mode, int status):
	win_interactive_worker* worker = win_interactive_start_config(args_program(), mode, c"", 500, 4096, 7, 640, 480, WIN_EXECUTION_MAX)
	int pid = worker.child.pid
	assert_equal(-1, frame_test_wait(worker))
	assert_equal(status, worker.status)
	assert_equal(0, worker.surfaces.length)
	assert_equal(-10, wait4(pid, 0, 1, 0))
	win_interactive_free(worker)

int main(int argc, int argv):
	malloc_force_debug_mode()
	args_init(argc, argv)
	args_declare_bool(c"interactive-worker")
	if (args_has_flag(c"interactive-worker")):
		assert_equal(WIN_EXECUTION_MAX, win_execution_budget_parse(args_value(c"execution-budget")))
		assert_equal(7, atoi(args_value(c"worker-generation")))
		return frame_test_child(args_value(c"page"))
	frame_test_bad(c"manifest", 4)
	frame_test_bad(c"duplicate", 4)
	frame_test_bad(c"stale", 4)
	frame_test_bad(c"sequence", 4)
	frame_test_bad(c"oversize", 4)
	frame_test_bad(c"stride", 4)
	frame_test_bad(c"partial", 4)
	frame_test_bad(c"hang", 2)
	win_interactive_worker* worker = win_interactive_start_config(args_program(), c"good", c"", 1000, 4096, 7, 640, 480, WIN_EXECUTION_MAX)
	assert_equal(1, frame_test_wait(worker))
	assert_equal(1, worker.surfaces.length)
	assert_equal(1, worker.surfaces[0].node_id)
	assert_equal(2, worker.surfaces[0].width)
	assert_equal(15, worker.surfaces[0].pixels[15])
	worker.viewport_width = 320
	worker.viewport_height = 240
	assert1(win_interactive_request(worker, 1, 0, c""))
	assert_equal(0, win_interactive_request(worker, 1, 0, c""))
	assert_equal(1, worker.surfaces.length)
	assert_equal(15, worker.surfaces[0].pixels[15])
	win_interactive_poll(worker)
	process_sleep_ms(5)
	int pid = worker.child.pid
	win_interactive_free(worker)
	assert_equal(-10, wait4(pid, 0, 1, 0))
	worker = win_interactive_start_config(args_program(), c"atomic", c"", 1000, 4096, 7, 640, 480, WIN_EXECUTION_MAX)
	assert_equal(1, frame_test_wait(worker))
	worker.viewport_width = 320
	worker.viewport_height = 240
	assert1(win_interactive_request(worker, 1, 0, c""))
	assert_equal(-1, frame_test_wait(worker))
	assert_equal(4, worker.status)
	assert_equal(1, worker.surfaces.length)
	assert_equal(15, worker.surfaces[0].pixels[15])
	assert_equal(1, worker.pending_surfaces.length)
	win_interactive_free(worker)
	worker = win_interactive_start_config(args_program(), c"", c"", 1000, 4096, 1, 4097, 480, 1)
	assert_equal(7, worker.status)
	win_interactive_free(worker)
	__w_list_free(cast(__w_list*, args_bool_names))
	args_bool_names = 0
	assert_equal(0, debug_alloc_report_leaks())
	println(c"Interactive WFRM fragmentation, identity, limits, ACK, resize, cancellation: OK")
	return 0
