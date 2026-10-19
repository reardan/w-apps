# Parent-owned policy and asynchronous jobs. The worker supplies no origin,
# cookie jar, file path capability, proxy, executable, or environment variables.
import win.loader

struct win_broker_job:
	int id
	win_load* load

struct win_broker:
	win_broker_wire* wire
	char* executable
	int sequence
	int messages
	int bytes
	list[win_broker_job*] jobs

win_broker* win_broker_new(int fd, char* executable):
	win_broker* broker = new win_broker()
	broker.wire = win_broker_wire_new(fd)
	broker.executable = strclone(executable)
	broker.jobs = new list[win_broker_job*]
	return broker

void win_broker_remove(win_broker* broker, int index):
	win_broker_job* job = broker.jobs[index]
	win_load_free(job.load)
	free(job)
	broker.jobs[index] = broker.jobs[broker.jobs.length - 1]
	broker.jobs.pop()

void win_broker_free(win_broker* broker):
	if (broker == 0): return
	while (broker.jobs.length): win_broker_remove(broker, 0)
	list_free[win_broker_job*](broker.jobs)
	win_broker_wire_free(broker.wire)
	free(broker.executable)
	free(broker)

int win_broker_request_valid(char* data, int length):
	if (length < 48 || length > 71856 || load_int32(data + 16) != 1): return 0
	int kind = load_int32(data + 24)
	int address = load_int32(data + 28)
	int method = load_int32(data + 32)
	int type_length = load_int32(data + 36)
	int accept = load_int32(data + 40)
	int body = load_int32(data + 44)
	if (kind < 1 || kind > 5 || address < 1 || address > WIN_ADDRESS_LIMIT || method < 1 || method > 32 || type_length < 0 || type_length > 1024 || accept < 0 || accept > 1024 || body < 0 || body > WIN_FETCH_REQUEST_LIMIT || length != 48 + address + method + type_length + accept + body): return 0
	for i in range(48, 48 + address + method):
		if ((data[i] & 255) < 32 || (data[i] & 255) >= 127): return 0
	int headers = 48 + address + method
	return win_fetch_header_value(data + headers, type_length) && win_fetch_header_value(data + headers + type_length, accept)

void win_broker_poll(win_broker* broker):
	if (broker == 0 || broker.wire.failed): return
	win_broker_pump(broker.wire)
	if (broker.wire.input.length >= 24 && load_int32(broker.wire.input.data + 8) > 71856 - 24): broker.wire.failed = 1
	if (broker.wire.failed): return
	if (win_broker_complete(broker.wire)):
		broker.messages = broker.messages + 1
		if (broker.messages > WIN_BROKER_REQUESTS * 2):
			broker.wire.failed = 1
			return
		char* data = broker.wire.input.data
		int id = load_int32(data + 12)
		int kind = load_int32(data + 16)
		if (kind == 2 && broker.wire.input.length == 24 && id <= broker.sequence):
			for i in range(broker.jobs.length):
				if (broker.jobs[i].id == id):
					win_broker_remove(broker, i)
					break
		else if (kind == 1 && id == broker.sequence + 1 && broker.jobs.length < 16 && win_broker_request_valid(data, broker.wire.input.length)):
			broker.sequence = id
			int resource_kind = load_int32(data + 24)
			int at = 48
			int count = load_int32(data + 28)
			char* address = str_copy_range(data, at, at + count)
			at = at + count
			count = load_int32(data + 32)
			char* method = str_copy_range(data, at, at + count)
			at = at + count
			count = load_int32(data + 36)
			char* content_type = str_copy_range(data, at, at + count)
			at = at + count
			count = load_int32(data + 40)
			char* accept = str_copy_range(data, at, at + count)
			at = at + count
			int body_length = load_int32(data + 44)
			# Non-Fetch resources can only GET; document forms can POST.
			int allowed = win_fetch_method(method) && win_fetch_header_value(content_type, strlen(content_type)) && win_fetch_header_value(accept, strlen(accept))
			if (resource_kind != 5 && strcmp(method, c"GET") != 0 && (resource_kind != 1 || strcmp(method, c"POST") != 0)): allowed = 0
			if ((win_net_equal(method, c"GET") || win_net_equal(method, c"HEAD")) && body_length): allowed = 0
			if (resource_kind != 5):
				for i in range(body_length):
					if (data[at + i] == 0): allowed = 0
			if (allowed):
				win_broker_job* job = new win_broker_job()
				job.id = id
				job.load = win_load_start_network_bytes(broker.executable, address, win_broker_kind_name(resource_kind), method, data + at, body_length, content_type, accept, win_sandbox_origin)
				broker.jobs.push(job)
			else: broker.wire.failed = 1
			free(address)
			free(method)
			free(content_type)
			free(accept)
		else: broker.wire.failed = 1
		string_clear(broker.wire.input)
	if (broker.wire.failed): return
	# Watchdogs remain active even while a slow reader blocks result delivery.
	for win_broker_job* pending in broker.jobs:
		if (pending.load.finished == 0 && time_monotonic_ms() - pending.load.started > 12000):
			win_load_fail(pending.load, c"Sandbox broker loader timed out")
	# Output backpressure bounds retained completed resources as well as memory.
	if (broker.wire.output.length != broker.wire.sent): return
	for i in range(broker.jobs.length):
		win_broker_job* job = broker.jobs[i]
		if (win_load_poll(job.load) == 0): continue
		win_load* load = job.load
		if (load.length > WIN_BROKER_TOTAL - broker.bytes):
			broker.wire.failed = 1
			return
		broker.bytes = broker.bytes + load.length
		string_builder* reply = win_broker_packet(job.id, 3)
		for j in range(16): string_append_char(reply, 0)
		save_int32(reply.data + 24, load.error != 0)
		save_int32(reply.data + 28, load.status)
		save_int32(reply.data + 32, load.wasm_mime)
		if (load.error == 0):
			save_int32(reply.data + 36, strlen(load.address))
			string_append(reply, load.address)
			string_append_bytes(reply, load.source, load.length)
		win_broker_queue(broker.wire, reply)
		string_free(reply)
		win_broker_remove(broker, i)
		break
