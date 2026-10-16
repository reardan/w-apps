# Opt-in Linux offline worker confinement

`--isolated-interactive --sandbox-root ABS_DIR` adds enforced OS restrictions to
the interactive worker and its resource helpers. The default execution modes
are unchanged. This is a staged **offline** profile, not HTTP M1–M3 parity or a
complete desktop security boundary. It requires Linux x86-64, Landlock ABI 8,
thread-synchronized Landlock and seccomp installation, `/proc/self/fd`, and
`close_range`. A requested profile fails closed when those requirements or the
descriptor audit cannot be satisfied. Unsupported headless-worker flags are
rejected, including combinations with `--isolated-interactive`.

For a local page whose dependencies are within the selected directory:

```sh
xvfb-run -a win/bin/win --isolated-interactive \
  --sandbox-root /absolute/content --page /absolute/content/index.html
```

The initial address must be local. Network resources are rejected; no TCP port,
origin wildcard or unrestricted fetch fallback is permitted. Win's existing
Fetch API requires HTTP(S), so selecting this profile does **not** make the
unchanged HTTP/Wasm acceptance hosts work offline. A parent-owned resource
broker remains necessary for sandboxed HTTP compatibility.

## Installation and retained authority

The normal parent launch supplies only `DISPLAY`, `XAUTHORITY`, `LANG`, `LC_ALL`,
`LIBGL_ALWAYS_SOFTWARE` when present, plus the expected-parent PID. Cloud/shell
credentials, loader injection variables, cookie state, cache paths and arbitrary
driver configuration are not inherited. Standard input is the connected worker
protocol socket; standard output/error are `/dev/null`. Resource helpers receive
only their protocol pipe/socket and `/dev/null`; the parent applies the same
profile to helpers used to load snapshot-linked CSS/images. A child-only policy
would leave those parent-initiated loads unrestricted.

Before opening graphics, the worker requires `close_range(3, UINT_MAX, 0)` to
remove inherited descriptors, including those above the library's fallback
close-loop ceiling. It accepts only local X display forms (`:N` or `unix:N`).
Trusted startup opens the unmapped GLX drawable. Before parsing or executing page
bytes, the worker sets `no_new_privs` and installs Landlock and seccomp with
TSYNC, including every GL thread already running. Restrictions survive fork and
exec. The process remains in its cancellation group: subsequent `setsid` and
`setpgid` calls are denied.

After both policies are installed, a pre-opened `/proc/self/fd` directory is used
to audit retained descriptors. Above descriptors 0–2, only connected AF_UNIX
stream sockets, the named GPU devices below, dma-bufs, Mesa's exact anonymous
`/memfd:allocation fd (deleted)` allocation handle, sync files, eventfds and
epoll handles are accepted. Unknown retained regular files, unconnected/TCP/UDP
sockets, other devices and unknown anonymous handles reject startup. The audit
directory is then closed. It is bounded to 4,096 entries and 511-byte link
targets. This can reject an untested driver's otherwise legitimate capabilities;
there is no automatic widening or unsandboxed retry. Non-graphics resource
helpers retain no descriptor above stdio: their policy entry closes that whole
range directly, including when they already inherit the worker's confinement.
They do not need to reopen the now-inaccessible `/proc/self/fd` directory.

Existing connected X/driver sockets and GPU mappings remain powerful
capabilities. Landlock does not revoke existing descriptor authority. In
particular, an X11 connection can affect the desktop session; driver ioctls and
graphics-server descriptor passing are not independently brokered. **This
profile does not isolate a compromised worker from the connected desktop or GPU
driver.** A dedicated X server is used for reproducible acceptance. The parent
still parses bounded inert HTML/CSS/image/pixel data and is outside this policy;
those parsers and the driver/server remain trusted components.

## Filesystem and process/network policy

All filesystem rights known through Landlock ABI 8 are handled. No creation,
unlink, rename/link, truncate or ordinary file-write rights are granted. The
selected root must be an existing absolute directory, and aliases of `/` are
rejected by device/inode identity. Symlinks and `..` do not bypass Landlock's
resolved-object checks.

| Path/capability | Granted access |
| --- | --- |
| Selected content directory | Read files and list directories |
| Win executable and `/lib64/ld-linux-x86-64.so.2` | Read and direct execute |
| `/usr/lib`, `/lib`, optional `/lib64` | Read files and list directories |
| Optional `/etc/ld.so.cache` | Read |
| Optional `/usr/share/fonts`, `/etc/fonts`, `/var/cache/fontconfig` | Read files and list directories |
| `/dev/null` | Read/write |
| `/dev/urandom` | Read |
| Optional `/dev/dri` | Read/write/list and device ioctls |
| Optional `/dev/nvidiactl`, `/dev/nvidia-modeset`, `/dev/nvidia-uvm`, `/dev/nvidia-uvm-tools`, `/dev/nvidia0` through `15` | Read/write and device ioctls |

Library/font/device paths are explicit authority outside the content tree.
Missing optional paths add no rights; other installation failures reject the
profile. An unsupported GPU configuration may fail during initialization or
readback. Captures clear their destination, preserve preexisting WebGL errors,
and reject new readback errors instead of publishing uninitialized allocator
bytes. NVIDIA's extra nodes are needed by context creation/readback after the
initial GL setup; a syscall trace established that dependency.

Landlock also handles TCP bind/connect with no allowances and enables both
signal and abstract-UNIX-socket scopes. Signals to unrelated processes, including
the parent, are denied while same-domain/descendant lifecycle operations remain
available. The seccomp filter rejects non-x86-64/x32 ABIs and denies:

- Network endpoint creation, bind, connect, listen and accept. Only AF_UNIX
  stream `socketpair` is allowed for private helper IPC; datagram pairs are
  rejected. Existing connected graphics/protocol streams remain usable.
- `ptrace`, `process_vm_readv/writev`, `pidfd_getfd`, process advice/release,
  process scheduling/priority/affinity changes and System V shared-memory,
  semaphore and message-queue operations. `prlimit64` allows only a read-only
  query with PID 0 and a null new-limit pointer.
- Namespace/mount operations, namespace flags to `clone`, `bpf`, perf events,
  keyrings, io_uring, open-by-handle APIs, kernel module/kexec/reboot and I/O
  privilege controls. `clone3` returns ENOSYS to permit libc's ordinary thread
  fallback. Normal fork/threads remain available.
- chmod/chown/timestamp/xattr mutation families, anonymous memfd creation,
  `execveat`, accounting and clock adjustment.

The concrete syscall list and BPF argument checks are in
[`sandbox.w`](../src/win/sandbox.w). This is an explicit restriction set, **not a
general syscall allowlist**. Metadata queries such as `stat` and `readlink` do not
hide the surrounding filesystem namespace. Direct execution of `/bin/sh` is
denied, but the allowed ELF loader and readable mapped code mean this is not a
code-execution allowlist; the threat model already assumes compromised worker
code, which retains the same inherited authority restrictions. No claim is made
of kernel/driver exploit resistance, a PID/memory quota, or denial-of-service
containment beyond the existing interpreter fuel and request/cancellation
limits. GPU calls can still stall. Native persistent storage is not exposed to
this worker filesystem; shared storage needs parent-owned IPC.

## Validation

`win/build test` discovers the two new W roots and Python integration. Focused
graphics acceptance:

```sh
xvfb-run -a python3 win/tests/sandbox_integration.py win/bin/win
```

The kernel test checks outside/symlink/proc reads, content writes/create/unlink/
rename/hardlink, metadata mutations, direct shell exec, TCP/UDP/UNIX creation,
connect, ptrace/process memory, resource controls, namespace creation, io_uring,
signal scoping, cancellation-group escape and retained ambient-file rejection.
A thread created before installation performs negative operations after TSYNC;
a subsequently forked/exec'd helper verifies inherited restrictions.

The integration denies the Landlock syscall to simulate an unavailable kernel
and verifies startup rejection. On ABI 8 it exercises a real local shader
compile/link/draw, exact RGBA frames, ACK backpressure, resize, stale ACK rejection
and teardown, including SIGKILL and partial-response cancellation. It checks
every live GL thread's no-new-privileges/seccomp state,
removal of an inherited descriptor above 1,024, the normal parent's environment
whitelist, positive in-root CSS, negative outside/symlink/remote CSS, and actual
parent-window pixels. A TCP listener must receive no connection. The focused
capture test forces an incomplete framebuffer and verifies failed readback is
zeroed and rejected. On an older kernel the enforcement/GL tests report a skip;
the unavailable-kernel fail-closed test still runs.

Recorded Xvfb and native NVIDIA evidence is in `offline-sandbox-evidence.json`.
The tested window has 16,384 exact blue canvas pixels and 547,744 green CSS
background pixels; two intentional forbidden stylesheets are reported as
resource failures, with zero script failures. This proves the stated local
profile, not modern-browser M1–M3 parity or full M4 acceptance.

Primary Linux contracts: [Landlock userspace API](https://docs.kernel.org/userspace-api/landlock.html),
[seccomp filters](https://docs.kernel.org/userspace-api/seccomp_filter.html), and
[no_new_privs](https://docs.kernel.org/userspace-api/no_new_privs.html).
