# Trusted parent-owned persistence service. No page code or profile path reaches
# the content worker. Each poll performs at most 64 KiB of socket I/O.
import win.storage
import lib.process
import lib.net

struct win_storage_job:
	win_storage_context* owner
	win_storage_context* candidate
	win_storage_result* result
	process* child
	string_builder* outgoing
	string_builder* incoming
	char* executable
	int sent
	int started
	int phase                 # 1 commit, 2 reconcile after uncertain publication
	int done
	int refs
	int timeout_ms

int win_storage_read_exact(int fd, char* data, int length):
	int at = 0
	while (at < length):
		int count = read(fd, data + at, length - at)
		if (count == -4): continue
		if (count <= 0): return 0
		at = at + count
	return 1

int win_storage_send_exact(int fd, char* data, int length):
	int at = 0
	while (at < length):
		int count = socket_send(fd, data + at, length - at, 16384)
		if (count == -4): continue
		if (count <= 0): return 0
		at = at + count
	return 1

# Reply status: 1 durable; 2 pre-rename failure; 3 renamed/barrier failed;
# 4 disk contents; 5 absent; 6 unreadable/invalid. Length is bounded before alloc.
int win_storage_helper(char* path, int action):
	if (path == 0 || path[0] == 0 || (action != 1 && action != 2)): return 2
	string_builder* data = string_new()
	int status = 6
	if (action == 1):
		char[4] word
		if (win_storage_read_exact(0, &word[0], 4) == 0):
			string_free(data)
			return 2
		int length = load_le32(&word[0])
		if (length < 12 || length > 1060876):
			string_free(data)
			return 2
		char* bytes = cast(char*, malloc(length))
		if (win_storage_read_exact(0, bytes, length)):
			win_storage_context* decoded = win_storage_decode(bytes, length)
			if (decoded != 0):
				fs_replace_report report
				int replaced = fs_replace_durable_mode(path, bytes, length, 384, &report)
				status = 2
				if (replaced == IO_OK): status = 1
				else if (report.renamed): status = 3
			win_storage_free(decoded)
		free(bytes)
	else:
		io_result result
		int fd = fs_open(path, FS_O_RDONLY | FS_O_CLOEXEC, 0, &result)
		if (fd < 0 && result.native_error == 2): status = 5
		if (fd >= 0):
			char[8192] bytes
			int valid = 1
			while (1):
				int count = read(fd, &bytes[0], 8192)
				if (count == -4): continue
				if (count == 0): break
				if (count < 0 || count > 1060876 - data.length):
					valid = 0
					break
				string_append_bytes(data, &bytes[0], count)
			if (io_close(fd, &result) != IO_OK): valid = 0
			win_storage_context* decoded = 0
			if (valid): decoded = win_storage_decode(data.data, data.length)
			if (decoded != 0): status = 4
			win_storage_free(decoded)
		if (status != 4): string_clear(data)
	char[8] header
	store_le32(&header[0], status)
	store_le32(&header[4], data.length)
	int ok = win_storage_send_exact(0, &header[0], 8)
	if (ok): ok = win_storage_send_exact(0, data.data, data.length)
	string_free(data)
	if (ok): return 0
	return 2

void win_storage_job_release(win_storage_job* job):
	if (job == 0): return
	job.refs = job.refs - 1
	if (job.refs > 0): return
	if (job.child != 0): process_free(job.child)
	win_storage_free(job.candidate)
	win_storage_result_free(job.result)
	string_free(job.outgoing)
	string_free(job.incoming)
	free(job.executable)
	free(job)

void win_storage_job_cancel(void* context):
	win_storage_job* job = cast(win_storage_job*, context)
	job.owner = 0
	job.done = 1
	job.result.error = 3
	job.result.message = c"Storage owner closed"
	if (job.child != 0): process_free(job.child)
	job.child = 0
	win_storage_job_release(job)

int win_storage_job_spawn(win_storage_job* job, int phase):
	if (job.child != 0): process_free(job.child)
	job.child = 0
	job.phase = phase
	job.sent = 0
	job.started = process_monotonic_ms()
	string_clear(job.incoming)
	string_clear(job.outgoing)
	if (phase == 1):
		string_builder* bytes = win_storage_encode(job.candidate)
		char[4] word
		store_le32(&word[0], bytes.length)
		string_append_bytes(job.outgoing, &word[0], 4)
		string_append_bytes(job.outgoing, bytes.data, bytes.length)
		string_free(bytes)
	char[8] pair
	if (syscall7(53, 1, 1 | 524288, 0, cast(int, &pair[0]), 0, 0) < 0): return 0
	int parent_fd = load_int32(&pair[0])
	int child_fd = load_int32(&pair[4])
	char* action = c"1"
	if (phase == 2): action = c"2"
	char*[6] argv
	argv[0] = job.executable
	argv[1] = c"--storage-helper"
	argv[2] = job.owner.path
	argv[3] = c"--storage-action"
	argv[4] = action
	argv[5] = 0
	char* pid_text = itoa(getpid())
	char* expected = strjoin(c"WIN_SCRIPT_WORKER_PARENT=", pid_text)
	char*[2] environment
	environment[0] = expected
	environment[1] = 0
	int pid = fork()
	if (pid == 0):
		setpgid(0, 0)
		close(parent_fd)
		process_redirect(child_fd, 0)
		process_redirect_null(1, 1)
		process_redirect_null(2, 1)
		process_close_from(3)
		execve(job.executable, &argv[0], &environment[0])
		exit(127)
	close(child_fd)
	free(expected)
	free(pid_text)
	if (pid < 0):
		close(parent_fd)
		return 0
	setpgid(pid, pid)
	job.child = new process()
	job.child.pid = pid
	job.child.stdin_fd = -1
	job.child.stdout_fd = parent_fd
	job.child.stderr_fd = -1
	return socket_set_nonblocking(parent_fd) == 0

void win_storage_job_finish(win_storage_job* job, int adopt, int error, int poison):
	if (adopt): win_storage_swap(job.owner, job.candidate)
	job.owner.poisoned = poison
	job.owner.pending = 0
	job.owner.cancel_pending = 0
	job.owner = 0
	job.done = 1
	job.result.error = error
	if (error != 0): job.result.message = c"Persistent storage publication or durability failed"
	if (job.child != 0): process_free(job.child)
	job.child = 0
	win_storage_job_release(job)

# Return an owned reference; owner retains another reference across worker death.
win_storage_job* win_storage_job_start(win_storage_context* owner, char* executable, char* origin, int operation, char* key, char* value, int index):
	if (owner.pending != 0): return 0
	win_storage_job* job = new win_storage_job()
	job.refs = 1
	job.timeout_ms = 5000
	job.executable = strclone(executable)
	job.outgoing = string_new()
	job.incoming = string_new()
	string_builder* data = win_storage_encode(owner)
	job.candidate = win_storage_decode(data.data, data.length)
	string_free(data)
	job.result = win_storage_execute(job.candidate, origin, operation, key, value, index, 0)
	if (job.result.error || owner.poisoned || owner.path == 0):
		job.done = 1
		if (owner.poisoned || owner.path == 0):
			job.result.error = 3
			job.result.message = c"Persistent storage unavailable"
		return job
	job.owner = owner
	owner.pending = job
	owner.cancel_pending = win_storage_job_cancel
	job.refs = 2
	if (win_storage_job_spawn(job, 1) == 0): win_storage_job_finish(job, 0, 3, 0)
	return job

int win_storage_bytes_equal(string_builder* expected, char* actual, int length):
	if (expected.length != length): return 0
	for i in range(length):
		if (expected.data[i] != actual[i]): return 0
	return 1

void win_storage_job_poll(win_storage_context* owner):
	if (owner == 0 || owner.pending == 0): return
	win_storage_job* job = cast(win_storage_job*, owner.pending)
	int failed = process_monotonic_ms() - job.started >= job.timeout_ms
	if (job.child == 0): failed = 1
	char[8192] bytes
	if (failed == 0):
		int fd = job.child.stdout_fd
		for i in range(8):
			int length = job.outgoing.length - job.sent
			if (length == 0): break
			if (length > 8192): length = 8192
			int count = socket_send(fd, job.outgoing.data + job.sent, length, 16384 | 64)
			if (count == -4 || count == -11): break
			if (count <= 0):
				failed = 1
				break
			job.sent = job.sent + count
		for i in range(8):
			if (failed): break
			int wanted = 8 - job.incoming.length
			if (job.incoming.length >= 8): wanted = 8 + load_le32(job.incoming.data + 4) - job.incoming.length
			if (wanted == 0): break
			if (wanted > 8192): wanted = 8192
			int count = read(fd, &bytes[0], wanted)
			if (count == -4 || count == -11): break
			if (count <= 0):
				failed = 1
				break
			string_append_bytes(job.incoming, &bytes[0], count)
			if (job.incoming.length >= 8):
				int length = load_le32(job.incoming.data + 4)
				if (length < 0 || length > 1060876 || (job.phase == 1 && length != 0)): failed = 1
		if (failed == 0 && job.incoming.length >= 8 && job.incoming.length == 8 + load_le32(job.incoming.data + 4)):
			int status = load_le32(job.incoming.data)
			if (job.phase == 1 && status >= 1 && status <= 3):
				int error = 0
				if (status == 2): error = 2
				if (status == 3): error = 3
				win_storage_job_finish(job, status != 2, error, 0)
				return
			if (job.phase == 2):
				string_builder* old = win_storage_encode(owner)
				string_builder* next = win_storage_encode(job.candidate)
				int old_matches = status == 5 && owner.entries.length == 0
				int new_matches = 0
				if (status == 4):
					old_matches = win_storage_bytes_equal(old, job.incoming.data + 8, job.incoming.length - 8)
					new_matches = win_storage_bytes_equal(next, job.incoming.data + 8, job.incoming.length - 8)
				string_free(old)
				string_free(next)
				win_storage_job_finish(job, new_matches, 3, old_matches == 0 && new_matches == 0)
				return
			failed = 1
	if (failed):
		# Kill and reap before rereading: the old helper cannot publish later.
		if (job.phase == 1 && win_storage_job_spawn(job, 2)): return
		win_storage_job_finish(job, 0, 3, 1)
