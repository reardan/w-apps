import lib.assert
import lib.args
import lib.thread
import win.sandbox

struct sandbox_test_state:
	int ready
	int parent
	char* outside

void sandbox_test_thread(void* argument):
	sandbox_test_state* state = cast(sandbox_test_state*, argument)
	thread_wait_word(&state.ready)
	assert_equal(-13, open(state.outside, 0, 0))
	assert_equal(-1, syscall7(41, 2, 1, 0, 0, 0, 0))
	# SIGCONT is harmless even if a regression mistakenly permits it.
	assert_equal(-1, kill(state.parent, 18))

void sandbox_test_child(char* root, char* inside, char* outside, char* escape, int parent):
	sandbox_test_state state
	state.ready = 0
	state.parent = parent
	state.outside = outside
	wthread* thread = thread_spawn(sandbox_test_thread, cast(void*, &state))
	assert1(thread != 0)
	# Only connected local streams survive the descriptor audit.
	char[8] initial_pair
	assert_equal(0, syscall7(53, 1, 1, 0, cast(int, &initial_pair[0]), 0, 0))
	int socket_fd = load_int32(&initial_pair[0])
	asserts(c"Landlock ABI8 + TSYNC policy installation", win_sandbox_apply(root, args_program(), 1))
	state.ready = 1
	thread_wake_word(&state.ready)
	assert_equal(0, thread_join(thread))
	int fd = open(inside, 0, 0)
	assert1(fd >= 0)
	char data
	assert_equal(1, read(fd, &data, 1))
	assert_equal('x', data)
	close(fd)
	assert_equal(-13, open(outside, 0, 0))
	assert_equal(-13, open(escape, 0, 0))
	assert_equal(-13, open(c"/proc/self/environ", 0, 0))
	assert_equal(-13, open(c"/proc/self/mem", 2, 0))
	assert_equal(-13, open(inside, 1, 0))
	assert_equal(-13, open(inside, 513, 0))
	assert_equal(-13, unlink(inside))
	string_builder* created = string_from(root)
	string_append(created, c"/new")
	assert_equal(-13, open(created.data, 65, 384))
	assert_equal(-13, mkdir(created.data, 448))
	assert_equal(-13, syscall7(82, cast(int, inside), cast(int, created.data), 0, 0, 0, 0))
	assert_equal(-13, syscall7(86, cast(int, inside), cast(int, created.data), 0, 0, 0, 0))
	assert_equal(-1, syscall7(90, cast(int, inside), 511, 0, 0, 0, 0))
	assert_equal(-1, syscall7(188, cast(int, inside), cast(int, c"user.test"), cast(int, c"x"), 1, 0, 0))
	char*[2] shell
	shell[0] = c"/bin/sh"
	shell[1] = 0
	assert_equal(-13, execve(shell[0], &shell[0], env_current()))
	assert_equal(-1, syscall7(41, 2, 1, 0, 0, 0, 0))
	assert_equal(-1, syscall7(41, 2, 2, 0, 0, 0, 0))
	assert_equal(-1, syscall7(41, 1, 1, 0, 0, 0, 0))
	assert_equal(-1, syscall7(42, socket_fd, 0, 0, 0, 0, 0))
	close(socket_fd)
	close(load_int32(&initial_pair[4]))
	char[8] pair
	assert_equal(0, syscall7(53, 1, 1, 0, cast(int, &pair[0]), 0, 0))
	close(load_int32(&pair[0]))
	close(load_int32(&pair[4]))
	assert_equal(-1, syscall7(53, 1, 2, 0, cast(int, &pair[0]), 0, 0))
	assert_equal(-1, syscall7(101, 16, parent, 0, 0, 0, 0))
	assert_equal(-1, syscall7(310, parent, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(311, parent, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(438, -1, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(272, 0x10000000, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(56, 0x10000000, 0, 0, 0, 0, 0))
	assert_equal(-38, syscall7(435, 0, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(425, 1, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(319, cast(int, c"test"), 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(302, parent, 0, 0, 0, 0, 0))
	char[16] limits
	assert_equal(0, syscall7(302, 0, 3, 0, cast(int, &limits[0]), 0, 0))
	assert_equal(-1, syscall7(302, 0, 3, cast(int, &limits[0]), 0, 0, 0))
	assert_equal(-1, syscall7(203, parent, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(29, 0, 4096, 896, 0, 0, 0))
	assert_equal(-1, syscall7(30, 0, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(109, 0, 0, 0, 0, 0, 0))
	assert_equal(-1, syscall7(112, 0, 0, 0, 0, 0, 0))
	assert_equal(-1, kill(parent, 18))
	assert_equal(0, kill(getpid(), 18))
	# The same executable remains available for confined resource helpers;
	# both restrictions survive fork + exec, without reinstallation.
	int child = fork()
	assert1(child >= 0)
	if (child == 0):
		char*[4] arguments
		arguments[0] = args_program()
		arguments[1] = c"--confined-child"
		arguments[2] = outside
		arguments[3] = 0
		execve(arguments[0], &arguments[0], env_current())
		exit(2)
	int status = 0
	assert_equal(child, wait4(child, &status, 0, 0))
	assert_equal(0, status)
	string_free(created)

int main(int argc, int argv):
	args_init(argc, argv)
	if (args_has_flag(c"confined-child")):
		assert_equal(-13, open(args_value(c"confined-child"), 0, 0))
		assert_equal(-1, syscall7(41, 2, 1, 0, 0, 0, 0))
		return 0
	assert_equal(0, win_sandbox_apply(c"/", args_program(), 1))
	assert_equal(0, win_sandbox_apply(c"relative", args_program(), 1))
	char** environment = win_sandbox_environment(getpid())
	for i in range(env_vector_count(environment)):
		char* entry = env_entry_at(environment, i)
		assert1(env_match_name(entry, c"DISPLAY") >= 0 || env_match_name(entry, c"XAUTHORITY") >= 0 || env_match_name(entry, c"LANG") >= 0 || env_match_name(entry, c"LC_ALL") >= 0 || env_match_name(entry, c"LIBGL_ALWAYS_SOFTWARE") >= 0 || env_match_name(entry, c"WIN_SCRIPT_WORKER_PARENT") >= 0)
	win_sandbox_environment_free(environment)
	if (win_sandbox_abi() < 8):
		println(c"SKIP kernel enforcement tests: Landlock ABI8 unavailable (requested profile fails closed)")
		return 0
	assert_equal(0, win_sandbox_apply(c"/tmp/..", args_program(), 1))
	string_builder* root = string_from(c"/tmp/win-sandbox-")
	string_append_int(root, getpid())
	assert_equal(0, mkdir(root.data, 448))
	string_builder* inside = string_from(root.data)
	string_append(inside, c"/inside")
	string_builder* outside = string_from(root.data)
	string_append(outside, c"-outside")
	string_builder* escape = string_from(root.data)
	string_append(escape, c"/escape")
	int fd = open(inside.data, 193, 384)
	assert1(fd >= 0)
	assert_equal(1, write(fd, c"x", 1))
	close(fd)
	fd = open(outside.data, 193, 384)
	assert1(fd >= 0)
	close(fd)
	assert_equal(0, syscall7(88, cast(int, outside.data), cast(int, escape.data), 0, 0, 0, 0))
	int parent = getpid()
	int child = fork()
	assert1(child >= 0)
	if (child == 0):
		# Retained ambient file authority must reject the entire profile, even
		# though Landlock cannot revoke this already-open descriptor itself.
		fd = open(outside.data, 0, 0)
		assert1(fd >= 0)
		assert_equal(0, win_sandbox_apply(root.data, args_program(), 1))
		exit(0)
	int status = 0
	assert_equal(child, wait4(child, &status, 0, 0))
	assert_equal(0, status)
	for i in range(3):
		child = fork()
		assert1(child >= 0)
		if (child == 0):
			int domain = 2
			int kind = 1
			if (i == 1): kind = 2
			if (i == 2): domain = 1
			assert1(syscall7(41, domain, kind, 0, 0, 0, 0) >= 0)
			assert_equal(0, win_sandbox_apply(root.data, args_program(), 1))
			exit(0)
		status = 0
		assert_equal(child, wait4(child, &status, 0, 0))
		assert_equal(0, status)
	child = fork()
	assert1(child >= 0)
	if (child == 0):
		sandbox_test_child(root.data, inside.data, outside.data, escape.data, parent)
		exit(0)
	status = 0
	assert_equal(child, wait4(child, &status, 0, 0))
	unlink(escape.data)
	unlink(inside.data)
	unlink(outside.data)
	rmdir(root.data)
	assert_equal(0, status)
	string_free(escape)
	string_free(outside)
	string_free(inside)
	string_free(root)
	println(c"Offline sandbox: read/write/exec/network/process denial, GL-thread TSYNC, exec inheritance: OK")
	return 0
