import lib.args
import lib.assert
import win.interactive_worker

int storage_fake_child(char* mode):
	int sequence = 1
	while (1):
		string_builder* wire = string_new()
		win_storage_wire_header(wire, sequence, WIN_STORAGE_REQUEST)
		for i in range(24): string_append_char(wire, 0)
		store_le32(wire.data + 8, 24)
		store_le32(wire.data + 36, -1)
		if (strcmp(mode, c"generation") == 0): store_le32(wire.data + 24, 1)
		if (strcmp(mode, c"sequence") == 0): store_le32(wire.data + 12, 2)
		if (strcmp(mode, c"oversized") == 0): store_le32(wire.data + 8, 2147483647)
		if (strcmp(mode, c"selector") == 0): store_le32(wire.data + 28, 2)
		if (strcmp(mode, c"operation") == 0): store_le32(wire.data + 32, 6)
		if (strcmp(mode, c"nul") == 0 || strcmp(mode, c"utf8") == 0):
			store_le32(wire.data + 8, 25)
			store_le32(wire.data + 40, 1)
			string_append_char(wire, 0)
			if (strcmp(mode, c"utf8") == 0): wire.data[48] = cast(char, 255)
		for i in range(wire.length):
			if (win_storage_send_exact(0, wire.data + i, 1) == 0):
				string_free(wire)
				return 0
		string_free(wire)
		char[44] reply
		if (win_storage_read_exact(0, &reply[0], 44) == 0): return 0
		if (load_le32(&reply[16]) != 201 || load_le32(&reply[12]) != sequence || load_le32(&reply[28]) != 0 || load_le32(&reply[32]) != 1): return 2
		if (strcmp(mode, c"deadline") != 0): break
		sequence = sequence + 1
	string_builder* snapshot = string_new()
	win_interactive_header(snapshot, 0, 100)
	for i in range(8): string_append_char(snapshot, 0)
	string_append(snapshot, c"http://example.test/")
	string_append_char(snapshot, 0)
	string_append(snapshot, c"stored")
	string_append_char(snapshot, 0)
	string_append(snapshot, c"<title>stored</title>")
	string_append_char(snapshot, 0)
	store_le32(snapshot.data + 8, snapshot.length - 24)
	int ok = win_storage_send_exact(0, snapshot.data, snapshot.length)
	string_free(snapshot)
	char[1] end
	read(0, &end[0], 1) # remain live until the parent tears down the worker
	return ok == 0

int main(int argc, int argv):
	# Initialization must not depend on fresh/zeroed stack storage.
	win_storage_bridge bridge
	bridge.generation = -71
	bridge.sequence = 2147483647
	bridge.failed = 1
	win_storage_bridge_init(&bridge, 19)
	assert_equal(19, bridge.generation)
	assert_equal(0, bridge.sequence)
	assert_equal(0, bridge.failed)
	args_init(argc, argv)
	args_declare_bool(c"interactive-worker")
	if (args_has_flag(c"interactive-worker")): return storage_fake_child(args_value(c"page"))
	char*[10] modes
	modes[0] = c"fragmented"
	modes[1] = c"generation"
	modes[2] = c"sequence"
	modes[3] = c"oversized"
	modes[4] = c"selector"
	modes[5] = c"operation"
	modes[6] = c"nul"
	modes[7] = c"utf8"
	modes[8] = c"deadline"
	modes[9] = c"unowned"
	for i in range(10):
		win_storage_context* local_store = win_storage_new()
		win_storage_context* session_store = win_storage_new()
		win_interactive_worker* worker = 0
		int timeout = 2000
		if (i == 8): timeout = 150
		if (i == 9): worker = win_interactive_start_config(args_program(), modes[i], c"", timeout, WIN_INTERACTIVE_LIMIT, 0, 200, 160, WIN_EXECUTION_DEFAULT)
		else: worker = win_interactive_start_owned(args_program(), modes[i], c"", timeout, WIN_INTERACTIVE_LIMIT, 0, 200, 160, WIN_EXECUTION_DEFAULT, local_store, session_store)
		# The fake child address is just its mode; set the trusted test capability.
		free(worker.storage_origin)
		worker.storage_origin = strclone(c"http://example.test:80")
		int started = process_monotonic_ms()
		while (worker.busy && worker.child != 0):
			win_interactive_poll(worker)
			assert1(process_monotonic_ms() - started < 3000)
			sleep_ms(1)
		if (i == 0):
			assert_equal(1, worker.status)
			assert_strings_equal(c"stored", worker.title)
		else if (i == 8):
			assert_equal(2, worker.status)
			assert1(worker.storage_sequence > 1)
		else: assert_equal(4, worker.status)
		win_interactive_free(worker)
		win_storage_free(local_store)
		win_storage_free(session_store)
	println(c"storage RPC real fragmented sockets, malformed requests and total deadline: OK")
	return 0
