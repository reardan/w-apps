import lib.assert
import win.broker

void broker_reject_packet(int sequence, int kind, int declared):
	char[8] pair
	assert_equal(0, syscall7(53, 1, 1, 0, cast(int, &pair[0]), 0, 0))
	int peer = load_int32(&pair[4])
	win_broker* broker = win_broker_new(load_int32(&pair[0]), c"/nonexistent")
	string_builder* data = win_broker_packet(sequence, kind)
	save_int32(data.data + 8, declared)
	assert_equal(data.length, socket_send(peer, data.data, data.length, 16384))
	win_broker_poll(broker)
	assert_equal(1, broker.wire.failed)
	win_broker_free(broker)
	close(peer)
	string_free(data)

void broker_denies_address(char* address):
	char[8] pair
	assert_equal(0, syscall7(53, 1, 1, 0, cast(int, &pair[0]), 0, 0))
	int peer = load_int32(&pair[4])
	win_broker* broker = win_broker_new(load_int32(&pair[0]), c"/nonexistent")
	string_builder* data = win_broker_packet(1, 1)
	for i in range(24): string_append_char(data, 0)
	save_int32(data.data + 24, 1)
	save_int32(data.data + 28, strlen(address))
	save_int32(data.data + 32, 3)
	save_int32(data.data + 40, 3)
	string_append(data, address)
	string_append(data, c"GET*/*")
	save_int32(data.data + 8, data.length - 24)
	assert_equal(9, socket_send(peer, data.data, 9, 16384))
	win_broker_poll(broker)
	assert_equal(0, broker.wire.failed)
	assert_equal(9, broker.wire.input.length)
	assert_equal(data.length - 9, socket_send(peer, data.data + 9, data.length - 9, 16384))
	win_broker_poll(broker)
	assert_equal(0, broker.wire.failed)
	assert_equal(0, broker.jobs.length)
	assert_equal(40, broker.wire.output.length)
	assert_equal(1, load_int32(broker.wire.output.data + 24))
	win_broker_free(broker)
	close(peer)
	string_free(data)

void broker_backpressure_timeout():
	char[8] pair
	assert_equal(0, syscall7(53, 1, 1, 0, cast(int, &pair[0]), 0, 0))
	int peer = load_int32(&pair[4])
	win_broker* broker = win_broker_new(load_int32(&pair[0]), c"/nonexistent")
	string_builder* data = win_broker_packet(1, 3)
	char[8192] zeros
	for i in range(8192): zeros[i] = 0
	for i in range(128): string_append_bytes(data, &zeros[0], 8192)
	assert_equal(1, win_broker_queue(broker.wire, data))
	string_free(data)
	int pid = fork()
	assert1(pid >= 0)
	if (pid == 0):
		setpgid(0, 0)
		process_sleep_ms(10000)
		exit(0)
	setpgid(pid, pid)
	win_broker_job* job = new win_broker_job()
	job.id = 1
	job.load = new win_load()
	job.load.output = string_new()
	job.load.started = time_monotonic_ms() - 13000
	job.load.child = new process()
	job.load.child.pid = pid
	job.load.child.stdin_fd = -1
	job.load.child.stdout_fd = -1
	job.load.child.stderr_fd = -1
	broker.jobs.push(job)
	win_broker_poll(broker)
	assert1(broker.wire.sent < broker.wire.output.length)
	assert_equal(1, job.load.finished)
	assert1(job.load.child == 0)
	int status = 0
	assert_equal(-10, wait4(pid, &status, 1, 0))
	win_broker_free(broker)
	close(peer)

int main():
	broker_backpressure_timeout()
	string_builder* packet = win_broker_packet(1, 1)
	for i in range(24): string_append_char(packet, 0)
	save_int32(packet.data + 24, 5)
	save_int32(packet.data + 28, 18)
	save_int32(packet.data + 32, 3)
	save_int32(packet.data + 40, 3)
	string_append(packet, c"http://127.0.0.1/GET*/*")
	assert_equal(0, win_broker_request_valid(packet.data, packet.length))
	save_int32(packet.data + 28, 17)
	assert_equal(1, win_broker_request_valid(packet.data, packet.length))
	save_int32(packet.data + 44, 65537)
	assert_equal(0, win_broker_request_valid(packet.data, packet.length))
	save_int32(packet.data + 44, 0)
	save_int32(packet.data + 24, 6)
	assert_equal(0, win_broker_request_valid(packet.data, packet.length))
	string_free(packet)
	broker_reject_packet(1, 1, 71856)
	broker_reject_packet(1, 2, 0)
	broker_reject_packet(1, 3, 0)
	broker_reject_packet(4097, 1, 0)
	broker_reject_packet(1, 1, -1)
	win_sandbox_origin = c"http://127.0.0.1:1"
	broker_denies_address(c"http://localhost:1/forbidden")
	broker_denies_address(c"file:///etc/passwd")
	broker_denies_address(c"/etc/passwd")
	win_load* forbidden = win_load_start(c"/nonexistent", c"file:///etc/passwd")
	assert_equal(1, forbidden.finished)
	assert_equal(1, forbidden.error != 0)
	assert_equal(1, forbidden.child == 0)
	win_load_free(forbidden)
	forbidden = win_load_start(c"/nonexistent", c"http://localhost:1/secret")
	assert_equal(1, forbidden.finished)
	assert_equal(1, forbidden.error != 0)
	assert_equal(1, forbidden.child == 0)
	win_load_free(forbidden)
	println(c"Broker framing, resource kinds, quotas, and origin rejection passed")
	return 0
