# Protocol prototype only: no browser presentation or worker integration.
import lib.assert
import lib.net
import win.frame_transport

win_frame_header frame_test_header(int generation, int sequence):
	win_frame_header header
	header.kind = WIN_FRAME_PIXELS
	header.generation = generation
	header.sequence = sequence
	header.format = WIN_FRAME_RGBA8
	header.width = 2
	header.height = 2
	header.stride = 12
	header.length = 24
	return header

win_frame_header frame_test_ack(int generation, int sequence):
	win_frame_header header
	header.kind = WIN_FRAME_ACK
	header.generation = generation
	header.sequence = sequence
	header.format = 0
	header.width = 0
	header.height = 0
	header.stride = 0
	header.length = 0
	return header

void test_frame_codec():
	char[24] pixels
	for i in range(24): pixels[i] = (i * 37) & 255
	string_builder* frame = win_frame_encode(frame_test_header(1, 1), &pixels[0], 24, 24)
	asserts(c"encode accepts padded RGBA rows", frame != 0 && frame.length == 72)
	pixels[0] = 99
	assert_equal(0, frame.data[WIN_FRAME_HEADER] & 255)
	pixels[0] = 0
	assert_equal(0, cast(int, win_frame_encode(frame_test_header(1, 1), &pixels[0], 23, 24)))
	assert_equal(0, cast(int, win_frame_decoder_new(WIN_FRAME_MAX_BYTES + 1)))
	win_frame_decoder* decoder = win_frame_decoder_new(24)
	for i in range(WIN_FRAME_HEADER - 1):
		assert_equal(1, win_frame_decoder_feed(decoder, frame.data + i, 1))
		asserts(c"partial header never allocates payload", decoder.pixels == 0 && decoder.status == 0)
	assert_equal(0, win_frame_decoder_reset(decoder))
	for i in range(WIN_FRAME_HEADER - 1, frame.length): assert_equal(1, win_frame_decoder_feed(decoder, frame.data + i, 1))
	assert_equal(1, decoder.status)
	assert_equal(12, decoder.header.stride)
	for i in range(24): assert_equal(pixels[i] & 255, decoder.pixels[i] & 255)
	assert_equal(0, win_frame_decoder_feed(decoder, frame.data, frame.length))
	assert_equal(1, win_frame_decoder_reset(decoder))
	# A single read may contain two messages; the decoder consumes only one.
	string_builder* joined = string_new()
	string_append_bytes(joined, frame.data, frame.length)
	string_append_bytes(joined, frame.data, frame.length)
	assert_equal(frame.length, win_frame_decoder_feed(decoder, joined.data, joined.length))
	assert_equal(1, win_frame_decoder_reset(decoder))
	assert_equal(frame.length, win_frame_decoder_feed(decoder, joined.data + frame.length, frame.length))
	assert_equal(1, win_frame_decoder_eof(decoder))
	win_frame_decoder_free(decoder)
	string_free(joined)
	string_free(frame)

void frame_test_bad(int offset, int value, int limit):
	char[24] pixels
	for i in range(24): pixels[i] = 0
	string_builder* frame = win_frame_encode(frame_test_header(1, 1), &pixels[0], 24, 24)
	win_frame_u32_write(frame.data + offset, value)
	win_frame_decoder* decoder = win_frame_decoder_new(limit)
	assert_equal(WIN_FRAME_HEADER, win_frame_decoder_feed(decoder, frame.data, frame.length))
	asserts(c"malformed frame rejected before allocation", decoder.status == -1 && decoder.pixels == 0 && decoder.pixel_count == 0)
	assert_equal(0, win_frame_decoder_reset(decoder))
	assert_equal(0, win_frame_decoder_feed(decoder, frame.data, frame.length))
	win_frame_decoder_free(decoder)
	string_free(frame)

void test_frame_negative_headers():
	frame_test_bad(0, 0, 24)
	frame_test_bad(4, 2, 24)
	frame_test_bad(8, 3, 24)
	frame_test_bad(12, 0, 24)
	frame_test_bad(16, 0, 24)
	frame_test_bad(20, 2, 24)
	frame_test_bad(24, 0, 24)
	frame_test_bad(24, 16385, 24)
	frame_test_bad(28, 0, 24)
	frame_test_bad(28, 2147483647, WIN_FRAME_MAX_BYTES)
	frame_test_bad(32, 7, 24)
	frame_test_bad(32, 2147483647, WIN_FRAME_MAX_BYTES)
	frame_test_bad(36, 23, 24)
	frame_test_bad(36, cast(int, 0x80000000), 24)
	frame_test_bad(40, 1, 24)
	frame_test_bad(44, 1, 24)
	frame_test_bad(36, 24, 20)
	# Ack frames must have no pixel metadata or payload.
	frame_test_bad(8, WIN_FRAME_ACK, 24)
	win_frame_header large = frame_test_header(1, 1)
	large.width = 16384
	large.height = 16384
	large.stride = 2147483647
	large.length = 4
	assert_equal(0, win_frame_header_valid(large, WIN_FRAME_MAX_BYTES))
	# These individually valid fields multiply to 2^32; division rejects it
	# before 32-bit overflow could make the zero payload appear consistent.
	large.stride = 262144
	large.length = 0
	assert_equal(0, win_frame_header_valid(large, WIN_FRAME_MAX_BYTES))

void test_frame_eof():
	char[24] pixels
	for i in range(24): pixels[i] = i
	string_builder* frame = win_frame_encode(frame_test_header(1, 1), &pixels[0], 24, 24)
	for count in range(1, frame.length):
		win_frame_decoder* decoder = win_frame_decoder_new(24)
		assert_equal(count, win_frame_decoder_feed(decoder, frame.data, count))
		assert_equal(0, win_frame_decoder_eof(decoder))
		asserts(c"truncation frees partial payload and is terminal", decoder.pixels == 0 && decoder.status == -1)
		win_frame_decoder_free(decoder)
	win_frame_decoder* empty = win_frame_decoder_new(24)
	assert_equal(1, win_frame_decoder_eof(empty))
	win_frame_decoder_free(empty)
	string_free(frame)

void test_frame_lifecycle():
	char[24] pixels
	for i in range(24): pixels[i] = i
	win_frame_sender* sender = win_frame_sender_new(1, 24)
	assert_equal(1, win_frame_sender_submit(sender, 2, 2, 12, &pixels[0], 24))
	assert_equal(0, win_frame_sender_submit(sender, 2, 2, 12, &pixels[0], 24))
	assert_equal(0, win_frame_sender_ack(sender, frame_test_ack(1, 1)))
	assert_equal(0, win_frame_sender_advance(sender, sender.outgoing.length + 1))
	assert_equal(1, win_frame_sender_advance(sender, 1))
	assert_equal(-1, win_frame_sender_generation(sender, 2))
	asserts(c"partial generation refusal preserves queued frame", sender.generation == 1 && sender.sequence == 1 && sender.sent == 1 && sender.outgoing != 0)
	assert_equal(1, win_frame_sender_advance(sender, sender.outgoing.length - 1))
	assert_equal(1, win_frame_sender_generation(sender, 2))
	asserts(c"complete stale frame can be cancelled at a wire boundary", sender.outgoing == 0 && sender.sequence == 0)
	assert_equal(1, win_frame_sender_submit(sender, 2, 2, 12, &pixels[0], 24))
	assert_equal(1, win_frame_sender_advance(sender, sender.outgoing.length))
	assert_equal(0, win_frame_sender_ack(sender, frame_test_ack(1, 1)))
	assert_equal(0, win_frame_sender_ack(sender, frame_test_ack(2, 2)))
	asserts(c"stale acknowledgement does not release current frame", sender.outgoing != 0)
	assert_equal(1, win_frame_sender_ack(sender, frame_test_ack(2, 1)))
	assert_equal(0, win_frame_sender_ack(sender, frame_test_ack(2, 1)))
	sender.sequence = 2147483647
	assert_equal(0, win_frame_sender_submit(sender, 2, 2, 12, &pixels[0], 24))
	assert_equal(1, win_frame_sender_generation(sender, 3))
	win_frame_sender_free(sender)
	win_frame_receiver* receiver = win_frame_receiver_new(2)
	win_frame_decoder* decoder = win_frame_decoder_new(24)
	string_builder* stale = win_frame_encode(frame_test_header(1, 1), &pixels[0], 24, 24)
	win_frame_decoder_feed(decoder, stale.data, stale.length)
	assert_equal(0, win_frame_receiver_take(receiver, decoder))
	asserts(c"stale frame remains decoder owned", decoder.pixels != 0 && receiver.pixels == 0)
	win_frame_decoder_reset(decoder)
	string_free(stale)
	string_builder* current = win_frame_encode(frame_test_header(2, 1), &pixels[0], 24, 24)
	win_frame_decoder_feed(decoder, current.data, current.length)
	char* transferred = decoder.pixels
	assert_equal(1, win_frame_receiver_take(receiver, decoder))
	asserts(c"take transfers ownership without copying", receiver.pixels == transferred && decoder.pixels == 0 && decoder.status == 0)
	win_frame_decoder_feed(decoder, current.data, current.length)
	assert_equal(0, win_frame_receiver_take(receiver, decoder))
	string_builder* ack = win_frame_receiver_release(receiver)
	asserts(c"release invalidates borrowed pixels", receiver.pixels == 0 && receiver.busy == 0 && ack != 0)
	assert_equal(0, win_frame_receiver_take(receiver, decoder))
	win_frame_decoder_reset(decoder)
	win_frame_u32_write(current.data + 16, 2)
	win_frame_decoder_feed(decoder, current.data, current.length)
	assert_equal(1, win_frame_receiver_take(receiver, decoder))
	assert_equal(1, win_frame_receiver_generation(receiver, 3))
	asserts(c"navigation releases presentation ownership", receiver.pixels == 0 && receiver.busy == 0 && receiver.sequence == 0)
	assert_equal(0, cast(int, win_frame_receiver_release(receiver)))
	assert_equal(0, win_frame_receiver_generation(receiver, 2))
	string_free(current)
	string_free(ack)
	win_frame_decoder_free(decoder)
	win_frame_receiver_free(receiver)

# Exercise actual AF_UNIX byte streams with different write/read fragment sizes,
# kernel backpressure, delayed acknowledgements and peer disconnect.
void test_frame_socket_transfer():
	int[2] pair
	assert_equal(0, socket_pair(&pair[0]))
	assert_equal(0, socket_set_nonblocking(pair[0]))
	assert_equal(0, socket_set_nonblocking(pair[1]))
	int send_buffer = 4096
	assert_equal(0, sys_setsockopt(pair[0], 1, 7, &send_buffer, 4))
	int length = 65536
	char* pixels = cast(char*, malloc(length))
	for i in range(length): pixels[i] = (i * 37) & 255
	win_frame_sender* sender = win_frame_sender_new(7, length)
	win_frame_receiver* receiver = win_frame_receiver_new(7)
	win_frame_decoder* decoder = win_frame_decoder_new(length)
	win_frame_decoder* ack_decoder = win_frame_decoder_new(4)
	for iteration in range(16):
		assert_equal(1, win_frame_sender_submit(sender, 128, 128, 512, pixels, length))
		# Fill the kernel queue before allowing any reads.
		int blocked = 0
		for i in range(100):
			int written = socket_send(pair[0], sender.outgoing.data + sender.sent, 1024, 16384 | 64)
			if (written == -11):
				blocked = 1
				break
			asserts(c"socket writes make bounded progress", written > 0)
			assert_equal(1, win_frame_sender_advance(sender, written))
		asserts(c"kernel send backpressure observed", blocked && sender.sent < sender.outgoing.length)
		assert_equal(-1, win_frame_sender_generation(sender, 8))
		char[113] chunk
		int polls = 0
		while (decoder.status == 0):
			int remaining = sender.outgoing.length - sender.sent
			if (remaining > 0):
				if (remaining > 997): remaining = 997
				int written = socket_send(pair[0], sender.outgoing.data + sender.sent, remaining, 16384 | 64)
				if (written > 0): assert_equal(1, win_frame_sender_advance(sender, written))
				else: asserts(c"only EAGAIN may delay local socket send", written == -11)
			int count = read(pair[1], &chunk[0], 113)
			if (count > 0): assert_equal(count, win_frame_decoder_feed(decoder, &chunk[0], count))
			else: asserts(c"only EAGAIN may delay local socket read", count == -11)
			polls = polls + 1
			asserts(c"fragmented transfer watchdog", polls < 10000)
		assert_equal(1, decoder.status)
		assert_equal(0, win_frame_sender_submit(sender, 128, 128, 512, pixels, length))
		assert_equal(1, win_frame_receiver_take(receiver, decoder))
		for i in range(length): assert_equal(pixels[i] & 255, receiver.pixels[i] & 255)
		string_builder* ack = win_frame_receiver_release(receiver)
		for i in range(ack.length):
			assert_equal(1, socket_send(pair[1], ack.data + i, 1, 16384))
			assert_equal(1, read(pair[0], &chunk[0], 1))
			assert_equal(1, win_frame_decoder_feed(ack_decoder, &chunk[0], 1))
		assert_equal(1, ack_decoder.status)
		assert_equal(1, win_frame_sender_ack(sender, ack_decoder.header))
		assert_equal(1, win_frame_decoder_reset(ack_decoder))
		asserts(c"frame ownership released before next submission", sender.outgoing == 0 && receiver.pixels == 0 && decoder.pixels == 0)
		string_free(ack)
	# Actual peer EOF with a truncated header is a terminal protocol failure.
	assert_equal(4, socket_send(pair[0], c"WFRM", 4, 16384))
	close(pair[0])
	char[48] partial
	assert_equal(4, read(pair[1], &partial[0], 48))
	assert_equal(4, win_frame_decoder_feed(decoder, &partial[0], 4))
	assert_equal(0, read(pair[1], &partial[0], 48))
	assert_equal(0, win_frame_decoder_eof(decoder))
	close(pair[1])
	free(pixels)
	win_frame_sender_free(sender)
	win_frame_receiver_free(receiver)
	win_frame_decoder_free(decoder)
	win_frame_decoder_free(ack_decoder)

int main():
	malloc_force_debug_mode()
	test_frame_codec()
	test_frame_negative_headers()
	test_frame_eof()
	test_frame_lifecycle()
	test_frame_socket_transfer()
	assert_equal(0, debug_alloc_report_leaks())
	println(c"Frame transport prototype: fragmented sockets, bounds, generation, acknowledgements and ownership: OK")
	return 0
