# Dedicated connected AF_UNIX byte transport, never an Internet socket.
# Each pump moves at most 64 KiB in each direction. One bounded input frame.
import lib.net
import lib.process
import structures.string

const int WIN_BROKER_FRAME = 16785408
const int WIN_BROKER_QUEUE = 33570816
const int WIN_BROKER_REQUESTS = 4096
const int WIN_BROKER_TOTAL = 268435456

struct win_broker_wire:
	int fd
	int failed
	int sent
	string_builder* input
	string_builder* output

win_broker_wire* win_broker_wire_new(int fd):
	win_broker_wire* wire = new win_broker_wire()
	wire.fd = fd
	wire.input = string_new()
	wire.output = string_new()
	if (socket_set_nonblocking(fd) < 0): wire.failed = 1
	return wire

void win_broker_wire_free(win_broker_wire* wire):
	if (wire == 0): return
	close(wire.fd)
	string_free(wire.input)
	string_free(wire.output)
	free(wire)

string_builder* win_broker_packet(int id, int kind):
	string_builder* data = string_from(c"WBRO0001")
	for i in range(16): string_append_char(data, 0)
	save_int32(data.data + 12, id)
	save_int32(data.data + 16, kind)
	save_int32(data.data + 20, 1)
	return data

int win_broker_queue(win_broker_wire* wire, string_builder* packet):
	if (wire.failed || packet.length > WIN_BROKER_FRAME || packet.length < 24): return 0
	int remaining = wire.output.length - wire.sent
	if (packet.length > WIN_BROKER_QUEUE - remaining):
		wire.failed = 1
		return 0
	if (wire.sent):
		for i in range(remaining): wire.output.data[i] = wire.output.data[wire.sent + i]
		wire.output.length = remaining
		wire.output.data[remaining] = 0
		wire.sent = 0
	save_int32(packet.data + 8, packet.length - 24)
	string_append_bytes(wire.output, packet.data, packet.length)
	return 1

int win_broker_complete(win_broker_wire* wire):
	return wire.input.length >= 24 && wire.input.length == 24 + load_int32(wire.input.data + 8)

void win_broker_pump(win_broker_wire* wire):
	if (wire == 0 || wire.failed): return
	for i in range(8):
		int count = wire.output.length - wire.sent
		if (count == 0): break
		if (count > 8192): count = 8192
		int sent = socket_send(wire.fd, wire.output.data + wire.sent, count, 16384 | 64)
		if (sent == -11 || sent == -4): break
		if (sent <= 0):
			wire.failed = 1
			return
		wire.sent = wire.sent + sent
	char[8192] chunk
	for i in range(8):
		if (win_broker_complete(wire)): break
		int wanted = 24 - wire.input.length
		if (wire.input.length >= 24): wanted = 24 + load_int32(wire.input.data + 8) - wire.input.length
		if (wanted > 8192): wanted = 8192
		int count = read(wire.fd, &chunk[0], wanted)
		if (count == -11 || count == -4): break
		if (count <= 0):
			wire.failed = 1
			return
		string_append_bytes(wire.input, &chunk[0], count)
		if (wire.input.length >= 24):
			char* data = wire.input.data
			int length = load_int32(data + 8)
			if (starts_with(data, c"WBRO0001") == 0 || length < 0 || length > WIN_BROKER_FRAME - 24 || load_int32(data + 12) < 1 || load_int32(data + 12) > WIN_BROKER_REQUESTS || load_int32(data + 20) != 1):
				wire.failed = 1
				return
