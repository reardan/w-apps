# Experimental frame-only transport. This is not the existing WINT snapshot
# protocol and does not enable canvas presentation or change isolation defaults.
# Wire v1: 48 little-endian bytes followed by a bounded binary pixel payload.
# Offsets: magic[4], version, kind, generation, sequence, format, width, height,
# stride, payload bytes, flags=0, reserved=0. IDs are positive signed int32.
# Format 1 is RGBA8, straight alpha, top-left origin, rows including stride pad.
import lib.lib
import structures.string

const int WIN_FRAME_HEADER = 48
const int WIN_FRAME_MAX_BYTES = 67108864
const int WIN_FRAME_MAX_DIMENSION = 16384
const int WIN_FRAME_PIXELS = 1
const int WIN_FRAME_ACK = 2
const int WIN_FRAME_RGBA8 = 1

struct win_frame_header:
	int kind
	int generation
	int sequence
	int format
	int width
	int height
	int stride
	int length

struct win_frame_decoder:
	char[48] header_bytes
	int header_count
	win_frame_header header
	char* pixels
	int pixel_count
	int limit
	# 0 needs input; 1 complete; -1 terminal malformed/truncated input.
	int status

struct win_frame_sender:
	int generation
	int sequence
	int limit
	# Owned until matching acknowledgement or a safe generation advance.
	string_builder* outgoing
	int sent

struct win_frame_receiver:
	int generation
	int sequence
	win_frame_header header
	# Owned while busy; release or generation advance frees the pixels.
	char* pixels
	int busy

int win_frame_limit_valid(int limit):
	return limit >= 4 && limit <= WIN_FRAME_MAX_BYTES

int win_frame_id_valid(int id):
	return id > 0 && id <= 2147483647

int win_frame_header_valid(win_frame_header header, int limit):
	if (win_frame_limit_valid(limit) == 0 || win_frame_id_valid(header.generation) == 0 || win_frame_id_valid(header.sequence) == 0): return 0
	if (header.kind == WIN_FRAME_ACK):
		return header.format == 0 && header.width == 0 && header.height == 0 && header.stride == 0 && header.length == 0
	if (header.kind != WIN_FRAME_PIXELS || header.format != WIN_FRAME_RGBA8): return 0
	if (header.width < 1 || header.width > WIN_FRAME_MAX_DIMENSION || header.height < 1 || header.height > WIN_FRAME_MAX_DIMENSION): return 0
	# Bound operands before multiplication, on 32-bit as well as 64-bit hosts.
	if (header.stride < header.width * 4 || header.stride > limit): return 0
	if (header.height > limit / header.stride): return 0
	if (header.length != header.stride * header.height): return 0
	return 1

# Explicit little-endian access makes the wire independent of native layout.
void win_frame_u32_write(char* data, int value):
	for i in range(4): data[i] = (value >> (i * 8)) & 255

int win_frame_u31_read(char* data):
	if ((data[3] & 128) != 0): return -1
	return (data[0] & 255) | ((data[1] & 255) << 8) | ((data[2] & 255) << 16) | ((data[3] & 255) << 24)

int win_frame_header_read(char* data, win_frame_header* header, int limit):
	if (data[0] != 'W' || data[1] != 'F' || data[2] != 'R' || data[3] != 'M'): return 0
	if (win_frame_u31_read(data + 4) != 1 || win_frame_u31_read(data + 40) != 0 || win_frame_u31_read(data + 44) != 0): return 0
	header.kind = win_frame_u31_read(data + 8)
	header.generation = win_frame_u31_read(data + 12)
	header.sequence = win_frame_u31_read(data + 16)
	header.format = win_frame_u31_read(data + 20)
	header.width = win_frame_u31_read(data + 24)
	header.height = win_frame_u31_read(data + 28)
	header.stride = win_frame_u31_read(data + 32)
	header.length = win_frame_u31_read(data + 36)
	return win_frame_header_valid(header[0], limit)

# Copies caller-owned pixels. Payload length is exact, including row padding.
string_builder* win_frame_encode(win_frame_header header, char* pixels, int length, int limit):
	if (win_frame_header_valid(header, limit) == 0 || length != header.length || length > 0 && pixels == 0): return 0
	string_builder* result = string_new_sized(WIN_FRAME_HEADER + length + 1)
	string_append(result, c"WFRM")
	for i in range(4, WIN_FRAME_HEADER): string_append_char(result, 0)
	win_frame_u32_write(result.data + 4, 1)
	win_frame_u32_write(result.data + 8, header.kind)
	win_frame_u32_write(result.data + 12, header.generation)
	win_frame_u32_write(result.data + 16, header.sequence)
	win_frame_u32_write(result.data + 20, header.format)
	win_frame_u32_write(result.data + 24, header.width)
	win_frame_u32_write(result.data + 28, header.height)
	win_frame_u32_write(result.data + 32, header.stride)
	win_frame_u32_write(result.data + 36, header.length)
	if (length): string_append_bytes(result, pixels, length)
	return result

win_frame_decoder* win_frame_decoder_new(int limit):
	if (win_frame_limit_valid(limit) == 0): return 0
	win_frame_decoder* decoder = new win_frame_decoder()
	decoder.limit = limit
	return decoder

void win_frame_decoder_fail(win_frame_decoder* decoder):
	free(decoder.pixels)
	decoder.pixels = 0
	decoder.status = -1

# Return consumed input bytes. Stop exactly at one complete message, leaving
# coalesced bytes with the caller. No payload allocation precedes validation.
int win_frame_decoder_feed(win_frame_decoder* decoder, char* data, int length):
	if (decoder == 0 || length < 0 || length > 0 && data == 0): return -1
	if (decoder.status != 0): return 0
	int consumed = 0
	while (decoder.header_count < WIN_FRAME_HEADER && consumed < length):
		decoder.header_bytes[decoder.header_count] = data[consumed]
		decoder.header_count = decoder.header_count + 1
		consumed = consumed + 1
	if (decoder.header_count != WIN_FRAME_HEADER): return consumed
	if (decoder.pixels == 0 && decoder.pixel_count == 0):
		if (win_frame_header_read(&decoder.header_bytes[0], &decoder.header, decoder.limit) == 0):
			win_frame_decoder_fail(decoder)
			return consumed
		if (decoder.header.length == 0):
			decoder.status = 1
			return consumed
		decoder.pixels = cast(char*, __w_alloc(decoder.header.length))
	int count = length - consumed
	int remaining = decoder.header.length - decoder.pixel_count
	if (count > remaining): count = remaining
	for i in range(count): decoder.pixels[decoder.pixel_count + i] = data[consumed + i]
	decoder.pixel_count = decoder.pixel_count + count
	consumed = consumed + count
	if (decoder.pixel_count == decoder.header.length): decoder.status = 1
	return consumed

# A partial message cannot be discarded on a live byte stream. Close the
# transport and free/recreate this decoder after cancellation of partial input.
int win_frame_decoder_reset(win_frame_decoder* decoder):
	if (decoder == 0 || decoder.status != 1 && decoder.header_count > 0): return 0
	free(decoder.pixels)
	decoder.pixels = 0
	decoder.header_count = 0
	decoder.pixel_count = 0
	decoder.status = 0
	return 1

int win_frame_decoder_eof(win_frame_decoder* decoder):
	if (decoder.status == 1 || decoder.status == 0 && decoder.header_count == 0): return 1
	win_frame_decoder_fail(decoder)
	return 0

void win_frame_decoder_free(win_frame_decoder* decoder):
	if (decoder == 0): return
	free(decoder.pixels)
	free(decoder)

win_frame_sender* win_frame_sender_new(int generation, int limit):
	if (win_frame_id_valid(generation) == 0 || win_frame_limit_valid(limit) == 0): return 0
	win_frame_sender* sender = new win_frame_sender()
	sender.generation = generation
	sender.limit = limit
	return sender

int win_frame_sender_submit(win_frame_sender* sender, int width, int height, int stride, char* pixels, int length):
	if (sender == 0 || sender.outgoing != 0 || sender.sequence >= 2147483647): return 0
	win_frame_header header
	header.kind = WIN_FRAME_PIXELS
	header.generation = sender.generation
	header.sequence = sender.sequence + 1
	header.format = WIN_FRAME_RGBA8
	header.width = width
	header.height = height
	header.stride = stride
	header.length = length
	string_builder* outgoing = win_frame_encode(header, pixels, length, sender.limit)
	if (outgoing == 0): return 0
	sender.outgoing = outgoing
	sender.sent = 0
	sender.sequence = header.sequence
	return 1

# Caller writes outgoing.data + sent, then reports the actual write count.
int win_frame_sender_advance(win_frame_sender* sender, int count):
	if (sender == 0 || sender.outgoing == 0 || count < 0 || count > sender.outgoing.length - sender.sent): return 0
	sender.sent = sender.sent + count
	return 1

int win_frame_sender_ack(win_frame_sender* sender, win_frame_header header):
	if (sender == 0 || sender.outgoing == 0 || sender.sent != sender.outgoing.length): return 0
	if (win_frame_header_valid(header, sender.limit) == 0 || header.kind != WIN_FRAME_ACK || header.generation != sender.generation || header.sequence != sender.sequence): return 0
	if (sender.outgoing != 0): string_free(sender.outgoing)
	sender.outgoing = 0
	sender.sent = 0
	return 1

# 1 advanced; 0 invalid/stale ID; -1 reconnect required (partial frame sent).
# Refusal preserves every field so a caller cannot corrupt a live stream.
int win_frame_sender_generation(win_frame_sender* sender, int generation):
	if (sender == 0 || win_frame_id_valid(generation) == 0 || generation <= sender.generation): return 0
	if (sender.outgoing != 0 && sender.sent > 0 && sender.sent < sender.outgoing.length): return -1
	if (sender.outgoing != 0): string_free(sender.outgoing)
	sender.outgoing = 0
	sender.sent = 0
	sender.sequence = 0
	sender.generation = generation
	return 1

void win_frame_sender_free(win_frame_sender* sender):
	if (sender == 0): return
	if (sender.outgoing != 0): string_free(sender.outgoing)
	free(sender)

win_frame_receiver* win_frame_receiver_new(int generation):
	if (win_frame_id_valid(generation) == 0): return 0
	win_frame_receiver* receiver = new win_frame_receiver()
	receiver.generation = generation
	return receiver

# Move payload ownership from the complete decoder into the presentation slot.
# Rejected stale/duplicate/busy frames remain owned by the decoder.
int win_frame_receiver_take(win_frame_receiver* receiver, win_frame_decoder* decoder):
	if (receiver == 0 || decoder == 0 || receiver.busy || decoder.status != 1 || decoder.header.kind != WIN_FRAME_PIXELS): return 0
	if (decoder.header.generation != receiver.generation || decoder.header.sequence <= receiver.sequence): return 0
	receiver.header = decoder.header
	receiver.sequence = decoder.header.sequence
	receiver.pixels = decoder.pixels
	receiver.busy = 1
	decoder.pixels = 0
	win_frame_decoder_reset(decoder)
	return 1

# Acknowledge only after the consumer finishes using the borrowed pixel pointer.
# Returned acknowledgement bytes are owned by the caller.
string_builder* win_frame_receiver_release(win_frame_receiver* receiver):
	if (receiver == 0 || receiver.busy == 0): return 0
	win_frame_header header
	header.kind = WIN_FRAME_ACK
	header.generation = receiver.generation
	header.sequence = receiver.sequence
	header.format = 0
	header.width = 0
	header.height = 0
	header.stride = 0
	header.length = 0
	string_builder* ack = win_frame_encode(header, 0, 0, 4)
	free(receiver.pixels)
	receiver.pixels = 0
	receiver.busy = 0
	return ack

int win_frame_receiver_generation(win_frame_receiver* receiver, int generation):
	if (receiver == 0 || win_frame_id_valid(generation) == 0 || generation <= receiver.generation): return 0
	free(receiver.pixels)
	receiver.pixels = 0
	receiver.busy = 0
	receiver.generation = generation
	receiver.sequence = 0
	return 1

void win_frame_receiver_free(win_frame_receiver* receiver):
	if (receiver == 0): return
	free(receiver.pixels)
	free(receiver)
