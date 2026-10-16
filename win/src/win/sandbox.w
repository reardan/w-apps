# Opt-in Linux x86-64 offline confinement, not a complete desktop sandbox.
# ABI constants: Linux 7.0 include/uapi/linux/{landlock,seccomp,filter}.h.
# Landlock ABI8 TSYNC is mandatory because GL drivers create threads before
# policy installation. Existing X11/DRI descriptors retain their authority.
import lib.process
import lib.env
import structures.string

char* win_sandbox_root

int win_sandbox_abi():
	if (__word_size__ != 8 || SYS_OPEN != 2 || SYS_EXECVE != 59): return -1
	return syscall7(444, 0, 0, 1, 0, 0, 0)

int win_sandbox_requested():
	return win_sandbox_root != 0

# Require the kernel primitive: a guessed descriptor ceiling is not enough
# when the launcher supplied high-numbered files or connected sockets.
int win_sandbox_close_inherited():
	return close_range(3, -1, 0) == 0

int win_sandbox_graphics_fd(int fd, char* target):
	if (starts_with(target, c"socket:[")):
		int32 domain = 0
		int32 kind = 0
		int32 size = 4
		if (syscall7(55, fd, 1, 39, cast(int, &domain), cast(int, &size), 0) != 0 || domain != 1): return 0
		size = 4
		if (syscall7(55, fd, 1, 3, cast(int, &kind), cast(int, &size), 0) != 0 || kind != 1): return 0
		char[128] peer
		size = 128
		return syscall7(52, fd, cast(int, &peer[0]), cast(int, &size), 0, 0, 0) == 0
	if (starts_with(target, c"/dev/dri/")): return 1
	if (strcmp(target, c"/dev/nvidiactl") == 0 || strcmp(target, c"/dev/nvidia-modeset") == 0 || strcmp(target, c"/dev/nvidia-uvm") == 0 || strcmp(target, c"/dev/nvidia-uvm-tools") == 0): return 1
	if (starts_with(target, c"/dev/nvidia")):
		char* number = target + 11
		if (number[0] < '0' || number[0] > '9'): return 0
		if (number[1] == 0): return 1
		return number[0] == '1' && number[1] >= '0' && number[1] <= '5' && number[2] == 0
	# Anonymous GPU allocations and driver synchronization objects only.
	return strcmp(target, c"/dmabuf:") == 0 || strcmp(target, c"/memfd:allocation fd (deleted)") == 0 || strcmp(target, c"anon_inode:sync_file") == 0 || strcmp(target, c"anon_inode:[eventfd]") == 0 || strcmp(target, c"anon_inode:[eventpoll]") == 0

# Run after TSYNC, using a directory opened before confinement. No new
# unrestricted opens can race this audit. Unknown driver capabilities cause
# startup failure rather than quietly expanding the policy's authority.
int win_sandbox_audit_descriptors(int directory):
	char[4096] entries
	char[512] target
	int seen = 0
	while (1):
		int count = syscall7(217, directory, cast(int, &entries[0]), 4096, 0, 0, 0)
		if (count == 0): return 1
		if (count < 0): return 0
		int at = 0
		while (at < count):
			if (at + 20 > count): return 0
			int length = (entries[at + 16] & 255) | ((entries[at + 17] & 255) << 8)
			if (length < 20 || length > count - at): return 0
			char* name = &entries[at + 19]
			if (name[0] != '.'):
				int fd = atoi(name)
				if (fd > 2 && fd != directory):
					int size = syscall7(267, directory, cast(int, name), cast(int, &target[0]), 511, 0, 0)
					# A driver thread may have closed the handle during enumeration.
					if (size != -2):
						if (size < 0 || size >= 511): return 0
						target[size] = 0
						if (win_sandbox_graphics_fd(fd, &target[0]) == 0): return 0
				seen = seen + 1
				if (seen > 4096): return 0
			at = at + length
	return 0

# Every returned entry is owned. Do not forward shell/cloud credentials,
# loader injection variables, cache paths or arbitrary driver configuration.
char** win_sandbox_environment(int parent):
	char** result = cast(char**, malloc(7 * __word_size__))
	char*[5] names
	names[0] = c"DISPLAY"
	names[1] = c"XAUTHORITY"
	names[2] = c"LANG"
	names[3] = c"LC_ALL"
	names[4] = c"LIBGL_ALWAYS_SOFTWARE"
	int count = 0
	for i in range(5):
		char* value = env_get(names[i])
		if (value != 0):
			string_builder* entry = string_from(names[i])
			string_append_char(entry, '=')
			string_append(entry, value)
			result[count] = strclone(entry.data)
			count = count + 1
			string_free(entry)
	string_builder* guard = string_from(c"WIN_SCRIPT_WORKER_PARENT=")
	string_append_int(guard, parent)
	result[count] = strclone(guard.data)
	string_free(guard)
	result[count + 1] = 0
	return result

void win_sandbox_environment_free(char** environment):
	for i in range(env_vector_count(environment)): free(env_entry_at(environment, i))
	free(cast(void*, environment))

# Explicit byte layout avoids native C struct padding differences.
int win_sandbox_path(int ruleset, char* path, int rights, int required, int directory):
	int flags = 2097152 | 524288
	if (directory): flags = flags | 65536
	int fd = open(path, flags, 0)
	if (fd < 0): return required == 0 && fd == -2
	if (directory == 2):
		# Reject aliases such as /tmp/.. or a symlink to the filesystem root.
		int slash = open(c"/", 2097152 | 524288 | 65536, 0)
		char[144] selected
		char[144] filesystem
		int valid = slash >= 0 && syscall7(5, fd, cast(int, &selected[0]), 0, 0, 0, 0) == 0 && syscall7(5, slash, cast(int, &filesystem[0]), 0, 0, 0, 0) == 0
		if (slash >= 0): close(slash)
		if (valid):
			int* a = cast(int*, &selected[0])
			int* b = cast(int*, &filesystem[0])
			valid = a[0] != b[0] || a[1] != b[1]
		if (valid == 0):
			close(fd)
			return 0
	char[12] rule
	for i in range(12): rule[i] = 0
	int* access = cast(int*, &rule[0])
	access[0] = rights
	save_int32(&rule[8], fd)
	int result = syscall7(445, ruleset, 1, cast(int, &rule[0]), 0, 0, 0)
	close(fd)
	return result == 0

void win_sandbox_bpf(char* filters, int* count, int code, int yes, int no, int constant):
	int at = count[0] * 8
	filters[at] = code & 255
	filters[at + 1] = (code >> 8) & 255
	filters[at + 2] = yes
	filters[at + 3] = no
	save_int32(filters + at + 4, constant)
	count[0] = count[0] + 1

void win_sandbox_deny(char* filters, int* count, int number, int error):
	win_sandbox_bpf(filters, count, 0x15, 0, 1, number)
	win_sandbox_bpf(filters, count, 0x06, 0, 0, 0x00050000 | error)

int win_sandbox_filter():
	char[2048] filters
	int count = 0
	# Reject compat/x32 syscall ABIs, even after an attempted alternate exec.
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 4)
	win_sandbox_bpf(&filters[0], &count, 0x15, 1, 0, cast(int, 0xc000003e))
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, cast(int, 0x80000000))
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 0)
	# libc/GL may query their own stack limit. Never allow resource-limit
	# changes, or queries/changes aimed at another process.
	win_sandbox_bpf(&filters[0], &count, 0x15, 0, 9, 302)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 16)
	win_sandbox_bpf(&filters[0], &count, 0x15, 0, 5, 0)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 32)
	win_sandbox_bpf(&filters[0], &count, 0x15, 0, 3, 0)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 36)
	win_sandbox_bpf(&filters[0], &count, 0x15, 0, 1, 0)
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, 0x7fff0000)
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, 0x00050001)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 0)
	win_sandbox_bpf(&filters[0], &count, 0x35, 0, 1, 0x40000000)
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, cast(int, 0x80000000))
	# clone3's pointed-to argument cannot be inspected by classic BPF. ENOSYS
	# permits libc's ordinary pthread clone fallback; namespace flags are denied.
	win_sandbox_deny(&filters[0], &count, 435, 38)
	win_sandbox_bpf(&filters[0], &count, 0x15, 0, 4, 56)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 16)
	win_sandbox_bpf(&filters[0], &count, 0x45, 0, 1, 0x7e020080)
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, 0x00050001)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 0)
	# Only connected AF_UNIX stream pairs are needed for private IPC. Datagram
	# pairs would permit sendto to ambient pathname sockets despite connect denial.
	win_sandbox_bpf(&filters[0], &count, 0x15, 0, 7, 53)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 16)
	win_sandbox_bpf(&filters[0], &count, 0x15, 1, 0, 1)
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, 0x00050001)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 24)
	win_sandbox_bpf(&filters[0], &count, 0x54, 0, 0, 15)
	win_sandbox_bpf(&filters[0], &count, 0x15, 1, 0, 1)
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, 0x00050001)
	win_sandbox_bpf(&filters[0], &count, 0x20, 0, 0, 0)
	# Network endpoints, process access, kernel administration, metadata writes,
	# anonymous executable files, and asynchronous I/O that bypasses these calls.
	int[80] denied
	denied[0] = 41
	denied[1] = 42
	denied[2] = 43
	denied[3] = 49
	denied[4] = 50
	denied[5] = 288
	denied[6] = 101
	denied[7] = 310
	denied[8] = 311
	denied[9] = 438
	denied[10] = 165
	denied[11] = 166
	denied[12] = 155
	denied[13] = 161
	denied[14] = 272
	denied[15] = 308
	denied[16] = 321
	denied[17] = 298
	denied[18] = 248
	denied[19] = 249
	denied[20] = 250
	denied[21] = 425
	denied[22] = 426
	denied[23] = 427
	denied[24] = 428
	denied[25] = 429
	denied[26] = 430
	denied[27] = 431
	denied[28] = 432
	denied[29] = 433
	denied[30] = 442
	denied[31] = 90
	denied[32] = 91
	denied[33] = 268
	denied[34] = 452
	denied[35] = 92
	denied[36] = 93
	denied[37] = 94
	denied[38] = 260
	denied[39] = 132
	denied[40] = 235
	denied[41] = 261
	denied[42] = 280
	denied[43] = 188
	denied[44] = 189
	denied[45] = 190
	denied[46] = 197
	denied[47] = 198
	denied[48] = 199
	denied[49] = 319
	denied[50] = 447
	denied[51] = 322
	denied[52] = 169
	denied[53] = 172
	denied[54] = 173
	denied[55] = 175
	denied[56] = 176
	denied[57] = 246
	denied[58] = 313
	denied[59] = 320
	denied[60] = 303
	denied[61] = 304
	denied[62] = 159
	denied[63] = 163
	# Same-UID process resource controls and System V IPC are ambient authority.
	denied[64] = 302
	denied[65] = 141
	denied[66] = 142
	denied[67] = 144
	denied[68] = 203
	denied[69] = 314
	denied[70] = 440
	denied[71] = 448
	denied[72] = 29
	denied[73] = 30
	denied[74] = 31
	denied[75] = 64
	denied[76] = 65
	denied[77] = 66
	denied[78] = 68
	denied[79] = 69
	for i in range(80): win_sandbox_deny(&filters[0], &count, denied[i], 1)
	win_sandbox_deny(&filters[0], &count, 70, 1)
	win_sandbox_deny(&filters[0], &count, 71, 1)
	win_sandbox_deny(&filters[0], &count, 220, 1)
	# Preserve the launcher's cancellation group even after worker compromise.
	win_sandbox_deny(&filters[0], &count, 109, 1)
	win_sandbox_deny(&filters[0], &count, 112, 1)
	win_sandbox_bpf(&filters[0], &count, 0x06, 0, 0, 0x7fff0000)
	char[16] program
	for i in range(16): program[i] = 0
	program[0] = count & 255
	program[1] = (count >> 8) & 255
	int* address = cast(int*, &program[8])
	address[0] = cast(int, &filters[0])
	# SECCOMP_SET_MODE_FILTER, TSYNC. Nonzero includes offending-thread IDs.
	return syscall7(317, 1, 1, cast(int, &program[0]), 0, 0, 0) == 0

# Call before parsing any page bytes. Existing GL setup is trusted startup;
# Landlock and seccomp TSYNC cover all its threads before content can run.
int win_sandbox_apply(char* root, char* executable, int graphics):
	if (root == 0 || root[0] != '/' || root[1] == 0 || win_sandbox_abi() < 8): return 0
	# Non-graphics helpers need no retained descriptor above stdio and may
	# already inherit confinement (which correctly denies reopening /proc).
	if (graphics == 0 && win_sandbox_close_inherited() == 0): return 0
	if (syscall7(157, 38, 1, 0, 0, 0, 0) != 0): return 0
	char[24] attributes
	for i in range(24): attributes[i] = 0
	int* policy = cast(int*, &attributes[0])
	policy[0] = 65535
	policy[1] = 3
	policy[2] = 3
	int ruleset = syscall7(444, cast(int, &attributes[0]), 24, 0, 0, 0, 0)
	if (ruleset < 0): return 0
	int descriptors = -1
	if (graphics): descriptors = open(c"/proc/self/fd", 65536 | 524288, 0)
	if (graphics && descriptors < 0):
		close(ruleset)
		return 0
	int ok = win_sandbox_path(ruleset, root, 12, 1, 2)
	if (ok): ok = win_sandbox_path(ruleset, executable, 5, 1, 0)
	# Runtime data is read-only. Execute is granted only to this binary and
	# its ELF interpreter, not arbitrary programs in the content directory.
	if (ok): ok = win_sandbox_path(ruleset, c"/usr/lib", 12, 1, 1)
	if (ok): ok = win_sandbox_path(ruleset, c"/lib", 12, 1, 1)
	if (ok): ok = win_sandbox_path(ruleset, c"/lib64", 12, 0, 1)
	if (ok): ok = win_sandbox_path(ruleset, c"/lib64/ld-linux-x86-64.so.2", 5, 1, 0)
	if (ok): ok = win_sandbox_path(ruleset, c"/etc/ld.so.cache", 4, 0, 0)
	if (ok): ok = win_sandbox_path(ruleset, c"/usr/share/fonts", 12, 0, 1)
	if (ok): ok = win_sandbox_path(ruleset, c"/etc/fonts", 12, 0, 1)
	if (ok): ok = win_sandbox_path(ruleset, c"/var/cache/fontconfig", 12, 0, 1)
	if (ok): ok = win_sandbox_path(ruleset, c"/dev/null", 6, 1, 0)
	if (ok): ok = win_sandbox_path(ruleset, c"/dev/urandom", 4, 1, 0)
	# Explicit retained graphics authority: DRI devices are not ordinary files.
	if (ok): ok = win_sandbox_path(ruleset, c"/dev/dri", 32782, 0, 1)
	# NVIDIA creates additional context/device handles after initial GL setup.
	# Grant only these device nodes, never the whole /dev directory.
	if (ok): ok = win_sandbox_path(ruleset, c"/dev/nvidiactl", 32774, 0, 0)
	if (ok): ok = win_sandbox_path(ruleset, c"/dev/nvidia-modeset", 32774, 0, 0)
	if (ok): ok = win_sandbox_path(ruleset, c"/dev/nvidia-uvm", 32774, 0, 0)
	if (ok): ok = win_sandbox_path(ruleset, c"/dev/nvidia-uvm-tools", 32774, 0, 0)
	for i in range(16):
		string_builder* device = string_from(c"/dev/nvidia")
		string_append_int(device, i)
		if (ok): ok = win_sandbox_path(ruleset, device.data, 32774, 0, 0)
		string_free(device)
	if (ok): ok = syscall7(446, ruleset, 8, 0, 0, 0, 0) == 0
	close(ruleset)
	if (ok): ok = win_sandbox_filter()
	if (ok && graphics): ok = win_sandbox_audit_descriptors(descriptors)
	if (descriptors >= 0): close(descriptors)
	return ok
