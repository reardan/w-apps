# Linux x64 persistent content transport. Process separation, not a sandbox.
# One request outstanding; every poll moves at most 64 KiB in each direction.
import lib.process
import lib.net
import lib.utf8
import structures.string
import win.frame_surface
import win.execution
import win.sandbox
import win.interactive_input

const int WIN_INTERACTIVE_LIMIT = 8388608
const int WIN_INTERACTIVE_HEADER = 24

struct win_interactive_worker:
	process* child
	string_builder* incoming
	string_builder* outgoing
	int sent
	int busy
	int sequence
	int started
	int timeout_ms
	int limit
	int status
	char* error
	char* html
	char* address
	char* title
	int script_failures
	int resource_failures
	int generation
	int viewport_width
	int viewport_height
	int document_generation
	int focus_node
	int selection_start
	int selection_end
	int selection_direction
	int scroll_y
	int input_mouse_x
	int input_mouse_y
	int input_mods
	int input_present
	list[win_interactive_input*] input_queue
	int stage
	int frame_count
	int frame_index
	int frame_bytes
	int[8] frame_nodes
	win_frame_decoder* decoder
	win_frame_receiver* receiver
	list[win_frame_surface*] surfaces
	list[win_frame_surface*] pending_surfaces

void win_interactive_fail(win_interactive_worker* worker, int status, char* error):
	worker.status = status
	worker.error = error
	worker.busy = 0
	worker.html = 0
	worker.address = 0
	worker.title = 0
	if (worker.child != 0):
		process_free(worker.child)
		worker.child = 0

# Socketpair avoids SIGPIPE without changing the parent's signal dispositions.
# Both directions are nonblocking; MSG_NOSIGNAL also covers peer death races.
win_interactive_worker* win_interactive_start_config(char* executable, char* address, char* home, int timeout_ms, int max_bytes, int generation, int width, int height, int budget):
	win_interactive_worker* worker = new win_interactive_worker()
	worker.incoming = string_new()
	worker.outgoing = string_new()
	worker.timeout_ms = timeout_ms
	worker.limit = max_bytes
	worker.started = process_monotonic_ms()
	worker.busy = 1
	worker.generation = generation
	worker.viewport_width = width
	worker.viewport_height = height
	worker.surfaces = new list[win_frame_surface*]
	worker.pending_surfaces = new list[win_frame_surface*]
	worker.input_queue = new list[win_interactive_input*]
	if (generation > 0):
		worker.receiver = win_frame_receiver_new(generation)
		worker.decoder = win_frame_decoder_new(WIN_INTERACTIVE_PIXELS)
	if (generation < 0 || generation > 2147483647 || width < 1 || width > 4096 || height < 1 || height > 4096 || budget < 1 || budget > WIN_EXECUTION_MAX):
		win_interactive_fail(worker, 7, c"Invalid interactive graphics configuration")
		return worker
	if (timeout_ms <= 0 || timeout_ms > 120000 || max_bytes < 40 || max_bytes > WIN_INTERACTIVE_LIMIT):
		win_interactive_fail(worker, 7, c"Invalid interactive worker limits")
		return worker
	char[8] pair
	if (syscall7(53, 1, 1 | 524288, 0, cast(int, &pair[0]), 0, 0) < 0):
		win_interactive_fail(worker, 7, c"Cannot create interactive socket")
		return worker
	int parent_fd = load_int32(&pair[0])
	int child_fd = load_int32(&pair[4])
	string_builder* limit = string_new()
	string_append_int(limit, max_bytes)
	string_builder* parent = string_new()
	string_append_int(parent, getpid())
	char** environment = 0
	if (win_sandbox_requested()): environment = win_sandbox_environment(getpid())
	else: environment = env_copy_with(env_current(), c"WIN_SCRIPT_WORKER_PARENT", parent.data)
	string_builder* config = string_new()
	string_append_int(config, generation)
	string_append_char(config, 0)
	int width_at = config.length
	string_append_int(config, width)
	string_append_char(config, 0)
	int height_at = config.length
	string_append_int(config, height)
	string_append_char(config, 0)
	int budget_at = config.length
	string_append_int(config, budget)
	char*[19] argv
	argv[0] = executable
	argv[1] = c"--interactive-worker"
	argv[2] = c"--page"
	argv[3] = address
	argv[4] = c"--home"
	argv[5] = home
	argv[6] = c"--worker-limit"
	argv[7] = limit.data
	argv[8] = c"--worker-generation"
	argv[9] = config.data
	argv[10] = c"--worker-width"
	argv[11] = config.data + width_at
	argv[12] = c"--worker-height"
	argv[13] = config.data + height_at
	argv[14] = c"--execution-budget"
	argv[15] = config.data + budget_at
	argv[16] = 0
	if (win_sandbox_requested()):
		argv[16] = c"--sandbox-root"
		argv[17] = win_sandbox_root
		argv[18] = 0
	int pid = fork()
	if (pid == 0):
		setpgid(0, 0)
		close(parent_fd)
		process_redirect(child_fd, 0)
		process_redirect_null(1, 1)
		process_redirect_null(2, 1)
		process_close_from(3)
		execve(executable, &argv[0], environment)
		exit(127)
	close(child_fd)
	if (win_sandbox_requested()): win_sandbox_environment_free(environment)
	else:
		for i in range(env_vector_count(environment)):
			char* entry = env_entry_at(environment, i)
			if (env_match_name(entry, c"WIN_SCRIPT_WORKER_PARENT") >= 0): free(entry)
		free(cast(void*, environment))
	string_free(parent)
	string_free(limit)
	string_free(config)
	if (pid < 0):
		close(parent_fd)
		win_interactive_fail(worker, 7, c"Cannot start interactive worker")
		return worker
	setpgid(pid, pid)
	worker.child = new process()
	worker.child.pid = pid
	worker.child.stdin_fd = -1
	worker.child.stdout_fd = parent_fd
	worker.child.stderr_fd = -1
	if (socket_set_nonblocking(parent_fd) < 0): win_interactive_fail(worker, 7, c"Cannot configure interactive socket")
	return worker

# Wire header: WINT0001, payload bytes, sequence, kind, revision (int32).
# Legacy callers keep text snapshots and do not require an X display.
win_interactive_worker* win_interactive_start(char* executable, char* address, char* home, int timeout_ms, int max_bytes):
	return win_interactive_start_config(executable, address, home, timeout_ms, max_bytes, 0, 800, 600, WIN_EXECUTION_DEFAULT)

void win_interactive_header(string_builder* buffer, int sequence, int kind):
	string_clear(buffer)
	string_append(buffer, c"WINT0001")
	for i in range(16): string_append_char(buffer, 0)
	save_int32(buffer.data + 12, sequence)
	save_int32(buffer.data + 16, kind)

# Kinds: 1 tick, 2 click, 3 input(value), 4 submit. Node IDs are snapshot-local.
# Busy refusal bounds the queue; the UI must retain/retry an event if desired.
int win_interactive_request(win_interactive_worker* worker, int kind, int node_id, char* value):
	if (worker == 0 || worker.child == 0 || worker.busy || kind < 1 || kind > 4 || node_id < 0): return 0
	int prefix = 4
	if (worker.generation > 0): prefix = 12
	int length = strlen(value)
	if (length > 65536 || length + 24 + prefix > worker.limit || utf8_validate_bytes(value, length) == 0): return 0
	if (worker.sequence >= 2147483646): return 0
	worker.sequence = worker.sequence + 1
	win_interactive_header(worker.outgoing, worker.sequence, kind)
	for i in range(prefix): string_append_char(worker.outgoing, 0)
	save_int32(worker.outgoing.data + 24, node_id)
	if (worker.generation > 0):
		save_int32(worker.outgoing.data + 20, 1)
		save_int32(worker.outgoing.data + 28, worker.viewport_width)
		save_int32(worker.outgoing.data + 32, worker.viewport_height)
	string_append_bytes(worker.outgoing, value, length)
	save_int32(worker.outgoing.data + 8, length + prefix)
	string_clear(worker.incoming)
	worker.html = 0
	worker.title = 0
	worker.address = 0
	worker.sent = 0
	worker.busy = 1
	worker.started = process_monotonic_ms()
	worker.status = 0
	worker.stage = 0
	worker.frame_count = 0
	worker.frame_index = 0
	worker.frame_bytes = 0
	if (worker.decoder != 0): worker.decoder.limit = WIN_INTERACTIVE_PIXELS
	return 1

# Queued input is owned by this worker generation. Eight whole UI batches
# bound memory and latency; overflow terminates visibly rather than losing UP.
int win_interactive_enqueue(win_interactive_worker* worker, win_interactive_input* batch):
	if (worker == 0 || worker.child == 0 || batch == 0): return 0
	if (batch.generation != worker.generation || batch.document != worker.document_generation || win_interactive_input_valid(batch) == 0): return 0
	if (worker.input_queue.length):
		win_interactive_input* last = worker.input_queue[worker.input_queue.length - 1]
		if (last.document == batch.document && last.width == batch.width && last.height == batch.height):
			# Motion already comes from a coalesced backend snapshot. Retain its
			# latest value while blocked; never coalesce across a button/key edge.
			if (last.native.count == 0 && batch.native.count == 0):
				last.mouse_x = batch.mouse_x
				last.mouse_y = batch.mouse_y
				last.mods = batch.mods
				free(batch)
				return 1
			# Adjacent text/key frames at one pointer position share one packet.
			# This keeps fast typing bounded by records rather than frame rate.
			int text_only = 1
			for i in range(last.native.count):
				int kind = last.native.events[i].kind
				if ((kind >= GFX_EVENT_MOUSE_DOWN && kind <= GFX_EVENT_SCROLL) || kind == GFX_EVENT_SCROLL_PIXELS || kind == GFX_EVENT_POINTER_CANCEL): text_only = 0
			for i in range(batch.native.count):
				int kind = batch.native.events[i].kind
				if ((kind >= GFX_EVENT_MOUSE_DOWN && kind <= GFX_EVENT_SCROLL) || kind == GFX_EVENT_SCROLL_PIXELS || kind == GFX_EVENT_POINTER_CANCEL): text_only = 0
			if (text_only && last.mouse_x == batch.mouse_x && last.mouse_y == batch.mouse_y && last.mods == batch.mods && last.native.count + batch.native.count <= 64):
				for i in range(batch.native.count): win_native_push(&last.native, &batch.native.events[i])
				free(batch)
				return 1
	if (worker.input_queue.length >= WIN_INPUT_BATCHES):
		win_interactive_fail(worker, 5, c"Isolated input queue overflow; content stopped")
		return 0
	worker.input_queue.push(batch)
	return 1

int win_interactive_send_input(win_interactive_worker* worker):
	if (worker == 0 || worker.child == 0 || worker.busy || worker.input_queue.length == 0): return 0
	win_interactive_input* batch = worker.input_queue[0]
	for i in range(1, worker.input_queue.length): worker.input_queue[i - 1] = worker.input_queue[i]
	worker.input_queue.pop()
	if (batch.document != worker.document_generation):
		free(batch)
		return -1
	string_builder* payload = win_interactive_input_encode(batch)
	free(batch)
	if (payload == 0 || payload.length > worker.limit - 24):
		string_free(payload)
		win_interactive_fail(worker, 5, c"Invalid isolated input batch")
		return 0
	# Reuse the single outstanding request and ACK state machine.
	if (win_interactive_request(worker, 1, 0, c"") == 0):
		string_free(payload)
		return 0
	win_interactive_header(worker.outgoing, worker.sequence, 5)
	save_int32(worker.outgoing.data + 20, 2)
	save_int32(worker.outgoing.data + 8, payload.length)
	string_append_bytes(worker.outgoing, payload.data, payload.length)
	string_free(payload)
	return 1

# Snapshot payload: script/resource failures (int32), then address, title,
# HTML as three NUL-terminated UTF-8 strings. No raw pointers cross IPC.
int win_interactive_validate(win_interactive_worker* worker):
	char* data = worker.incoming.data
	int size = worker.incoming.length
	if (size < 35): return 0
	int scripts = load_int32(data + 24)
	int resources = load_int32(data + 28)
	if (scripts < 0 || scripts > 100000 || resources < 0 || resources > 100000): return 0
	int text_at = 32
	int kind = load_int32(data + 16)
	if (kind == 101 || kind == 102):
		if (worker.generation == 0 || size < 39): return 0
		int count = load_int32(data + 32)
		if (count < 0 || count > WIN_INTERACTIVE_CANVASES || size < 39 + count * 4): return 0
		worker.frame_count = count
		text_at = 36 + count * 4
		for i in range(count):
			int id = load_int32(data + 36 + i * 4)
			if (id < 1 || id > 20000): return 0
			for j in range(i):
				if (worker.frame_nodes[j] == id): return 0
			worker.frame_nodes[i] = id
	else if (kind != 100 || worker.generation > 0): return 0
	if (kind == 102):
		if (size < text_at + 39 || load_int32(data + 20) != 2): return 0
		int generation = load_int32(data + text_at)
		int document = load_int32(data + text_at + 4)
		int focus = load_int32(data + text_at + 8)
		int first_unit = load_int32(data + text_at + 12)
		int last_unit = load_int32(data + text_at + 16)
		int direction = load_int32(data + text_at + 20)
		int scroll = load_int32(data + text_at + 24)
		int width = load_int32(data + text_at + 28)
		int height = load_int32(data + text_at + 32)
		if (generation != worker.generation || document < 1 || focus < 0 || focus > 20000 || first_unit < 0 || last_unit < first_unit || last_unit > 65536 || direction < 0 || direction > 2 || scroll < 0 || scroll > 16777216 || width < 1 || width > 4096 || height < 1 || height > 4096): return 0
		worker.document_generation = document
		worker.focus_node = focus
		worker.selection_start = first_unit
		worker.selection_end = last_unit
		worker.selection_direction = direction
		worker.scroll_y = scroll
		text_at = text_at + 36
	int first = -1
	int second = -1
	int last = -1
	for i in range(text_at, size):
		if (data[i] == 0):
			if (first < 0): first = i
			else if (second < 0): second = i
			else if (last < 0): last = i
			else: return 0
	if (first < 0 || second < 0 || last != size - 1): return 0
	if (utf8_validate_bytes(data + text_at, first - text_at) == 0 || utf8_validate_bytes(data + first + 1, second - first - 1) == 0 || utf8_validate_bytes(data + second + 1, last - second - 1) == 0): return 0
	worker.address = data + text_at
	worker.title = data + first + 1
	worker.html = data + second + 1
	worker.script_failures = scripts
	worker.resource_failures = resources
	return 1

# ACKs share the request socket, but only one writer/state is active at a time.
int win_interactive_poll_frames(win_interactive_worker* worker):
	if (worker.sent != worker.outgoing.length): return 0
	char[8192] chunk
	win_frame_decoder* decoder = worker.decoder
	for i in range(8):
		int wanted = WIN_FRAME_HEADER - decoder.header_count
		if (wanted == 0): wanted = decoder.header.length - decoder.pixel_count
		if (wanted > 8192): wanted = 8192
		int count = read(worker.child.stdout_fd, &chunk[0], wanted)
		if (count == -11 || count == -4): return 0
		if (count <= 0):
			win_interactive_fail(worker, 4, c"Truncated interactive frame")
			return -1
		int consumed = win_frame_decoder_feed(decoder, &chunk[0], count)
		if (consumed != count || decoder.status < 0):
			win_interactive_fail(worker, 4, c"Invalid interactive frame")
			return -1
		if (decoder.header_count == WIN_FRAME_HEADER):
			win_frame_header h = decoder.header
			if (h.kind != WIN_FRAME_PIXELS || h.generation != worker.generation || h.sequence != worker.receiver.sequence + 1 || h.width > 4096 || h.height > 4096 || h.stride != h.width * 4):
				win_interactive_fail(worker, 4, c"Invalid interactive frame identity or dimensions")
				return -1
		if (decoder.status == 1):
			if (win_frame_receiver_take(worker.receiver, decoder) == 0):
				win_interactive_fail(worker, 4, c"Stale interactive frame")
				return -1
			win_frame_surface* surface = new win_frame_surface()
			surface.node_id = worker.frame_nodes[worker.frame_index]
			surface.width = worker.receiver.header.width
			surface.height = worker.receiver.header.height
			surface.pixels = worker.receiver.pixels
			worker.receiver.pixels = 0
			worker.frame_bytes = worker.frame_bytes + worker.receiver.header.length
			worker.pending_surfaces.push(surface)
			string_free(worker.outgoing)
			worker.outgoing = win_frame_receiver_release(worker.receiver)
			worker.sent = 0
			worker.frame_index = worker.frame_index + 1
			if (worker.frame_index == worker.frame_count): worker.stage = 2
			else if (WIN_INTERACTIVE_PIXELS - worker.frame_bytes < 4):
				win_interactive_fail(worker, 5, c"Interactive canvas aggregate exceeds limit")
				return -1
			else: decoder.limit = WIN_INTERACTIVE_PIXELS - worker.frame_bytes
			return 0
	return 0

int win_interactive_poll(win_interactive_worker* worker):
	if (worker.child == 0): return -1
	if (process_try_wait(worker.child) != process_status_running):
		win_interactive_fail(worker, 3, c"Interactive worker exited")
		return -1
	if (worker.busy == 0): return 1
	if (process_monotonic_ms() - worker.started >= worker.timeout_ms):
		win_interactive_fail(worker, 2, c"Interactive worker timed out")
		return -1
	int fd = worker.child.stdout_fd
	for i in range(8):
		int count = worker.outgoing.length - worker.sent
		if (count == 0): break
		if (count > 8192): count = 8192
		int written = socket_send(fd, worker.outgoing.data + worker.sent, count, 16384 | 64)
		if (written == -11 || written == -4): break
		if (written <= 0):
			win_interactive_fail(worker, 4, c"Interactive worker send failed")
			return -1
		worker.sent = worker.sent + written
	if (worker.stage == 2 && worker.sent == worker.outgoing.length):
		win_frame_surfaces_clear(worker.surfaces)
		list[win_frame_surface*] previous = worker.surfaces
		worker.surfaces = worker.pending_surfaces
		worker.pending_surfaces = previous
		worker.busy = 0
		worker.status = 1
		return 1
	if (worker.stage == 1): return win_interactive_poll_frames(worker)
	if (worker.stage == 2): return 0
	char[8192] chunk
	for i in range(8):
		int wanted = 24 - worker.incoming.length
		if (worker.incoming.length >= 24): wanted = load_int32(worker.incoming.data + 8) + 24 - worker.incoming.length
		if (wanted > 8192): wanted = 8192
		int count = read(fd, &chunk[0], wanted)
		if (count == -11 || count == -4): break
		if (count <= 0):
			win_interactive_fail(worker, 4, c"Interactive worker disconnected")
			return -1
		if (count > worker.limit - worker.incoming.length):
			win_interactive_fail(worker, 5, c"Interactive response exceeds limit")
			return -1
		string_append_bytes(worker.incoming, &chunk[0], count)
		if (worker.incoming.length >= 24):
			char* data = worker.incoming.data
			int length = load_int32(data + 8)
			if (length < 11 || length > worker.limit - 24):
				win_interactive_fail(worker, 5, c"Interactive declared size exceeds limit")
				return -1
			if (starts_with(data, c"WINT0001") == 0 || load_int32(data + 12) != worker.sequence || (load_int32(data + 16) != 100 && load_int32(data + 16) != 101 && load_int32(data + 16) != 102) || (load_int32(data + 20) != 0 && (load_int32(data + 16) != 102 || load_int32(data + 20) != 2)) || worker.incoming.length > length + 24):
				win_interactive_fail(worker, 4, c"Invalid interactive response")
				return -1
			if (worker.incoming.length == length + 24):
				if (worker.sent != worker.outgoing.length || win_interactive_validate(worker) == 0):
					win_interactive_fail(worker, 4, c"Invalid interactive snapshot")
					return -1
				if (worker.frame_count > 0):
					worker.stage = 1
					return 0
				worker.stage = 2
				return 0
	return 0

void win_interactive_free(win_interactive_worker* worker):
	if (worker == 0): return
	win_interactive_fail(worker, 6, c"Interactive worker cancelled")
	string_free(worker.incoming)
	string_free(worker.outgoing)
	win_frame_decoder_free(worker.decoder)
	win_frame_receiver_free(worker.receiver)
	win_frame_surfaces_clear(worker.surfaces)
	win_frame_surfaces_clear(worker.pending_surfaces)
	__w_list_free(cast(__w_list*, worker.surfaces))
	__w_list_free(cast(__w_list*, worker.pending_surfaces))
	for win_interactive_input* batch in worker.input_queue: free(batch)
	__w_list_free(cast(__w_list*, worker.input_queue))
	free(worker)
