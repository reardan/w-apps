# Parent-owned storage for isolated interactive pages

`win --isolated-interactive --storage /existing/profile/local.bin --page http://…`
uses one parent-owned local store shared by the app's tabs. Session stores belong
to parent tabs and survive content-worker replacement; they are not written to
disk. The existing profile lock excludes another Win process using the same file.
`--isolated-dump --storage` remains explicitly unsupported. Default execution and
isolation modes have not changed.

This implements a bounded method-based subset of the
[HTML Storage interface](https://html.spec.whatwg.org/multipage/webstorage.html#the-storage-interface):
`getItem`, `setItem`, `removeItem`, `clear`, `key` and `length`. Operations have
synchronous JavaScript results, origin-separated buckets, and shared visibility
across workers. Separate get/set calls are not a transaction. Local and session
stores retain the native limits: 1,024 entries and 1 MiB of origin/key/value bytes
per owner, with 65,536-byte fields. Existing UTF-8, primitive-conversion and integer
`key` index behavior is preserved. This does not add named-property Storage access,
`storage` events, Web IDL object conversion, lone-surrogate preservation or embedded
NUL support. The existing DOM conversion maps unsupported string representations
to empty strings; this is not full DOMString conformance.

The parent pins each worker to the canonical HTTP(S) origin of the requested
address. Requests cannot select an origin or provide a storage path. Same-origin
navigation and redirects work. A storage-enabled worker rejects a cross-origin
final document before parsing or executing it, with a specific terminal error.
The network fetch may already have followed its redirect. Parent-directed new
navigation creates a new worker with the new origin capability. Workers without
this storage bridge retain their existing cross-origin navigation behavior.
Local/opaque origins receive `SecurityError` on storage operations.

The bridge conveys no profile path or file descriptor to a content worker. It
uses the existing connected IPC socket; HTML snapshots remain display-only in
the parent. This does not remove ambient filesystem authority from ordinary
unsandboxed workers. The separate offline sandbox still has its documented
filesystem, network and driver restrictions; this change does not provide an
HTTP resource broker or make its local pages HTTP origins.

## Protocol and ownership

WINT's 24-byte header carries `WINT0001`, payload bytes, sequence, kind and revision
as little-endian 32-bit fields. Storage messages use revision 1 and a separate
monotonic RPC sequence; they do not consume input/snapshot sequence numbers.

| Kind | Payload |
| --- | --- |
| 200 request | generation, session selector (0/1), operation (get/set/remove/clear/key/length = 0…5), signed key index, key byte length, value byte length, then both UTF-8 strings |
| 201 reply | generation, error (none/Security/Quota/Unknown = 0…3), primitive kind, integer result, text byte length, then UTF-8 result |
| 202 terminal | generation and reason 1 (storage-enabled cross-origin navigation); sequence is the current snapshot/input sequence |

The key index is normally -1 or 0…1024. Index -2 with empty fields is an oversized
argument marker for get/set/remove: the parent checks origin and owner availability,
then returns a miss/no-op or quota error without allocating the oversized string.
The maximum request is 131,120 bytes and reply text is at most 65,536 bytes. Both
ends reject malformed lengths, NUL, invalid UTF-8 and stale identities before
publication. One RPC is outstanding per worker. Child JavaScript waits for its
reply; the UI polls nonblocking sockets. RPC progress never refreshes the outer
content request deadline. Frame ACKs and raw input retain their existing protocol.

## Durable writes and uncertain outcomes

The parent computes a bounded candidate copy and serializes requests behind its
publication, including reads from other tabs. A fresh trusted `--storage-helper`
process performs the existing mode-0600 atomic replacement and file/directory
barriers. The helper executes no document or JavaScript, closes inherited file
descriptors, and receives only an expected-parent environment entry. The parent
keeps the lifetime profile lock. Each helper phase has a five-second deadline;
helper and worker socket polls each transfer at most 64 KiB per direction.

A successful reply publishes the candidate. A definite pre-rename failure keeps
the previous owner; a post-rename barrier failure publishes the candidate and
returns `UnknownError`. If the helper dies, times out or returns invalid data, the
parent first kills/reaps it, then starts a bounded trusted disk-read helper.
Only a disk image matching the previous or candidate state is accepted. The
candidate match is adopted; either reconciled outcome reports `UnknownError`.
Unreadable, corrupt or unexpected disk contents poison the owner, so queued calls
cannot continue from assumed stale state. Reopening the profile is required.
A killed writer can leave an unpublished mode-0600 temporary file; recovery never
adopts a temporary file or mistakes it for the committed profile.

Closing the requesting worker releases its reference but does not revoke a write
already accepted by the parent. The parent continues publication/reconciliation.
Closing the parent cancels its helpers; the atomic disk image is validated on the
next startup. Standard kernel process teardown can still wait on uninterruptible
kernel I/O; the configured deadline is not a hard real-time guarantee.

## Validation

- `storage_commit_test.w`: real helper success, death before/after rename, corrupt
  publication, timeout, owner serialization, and requester-reference release.
- `storage_rpc_transport_test.w`: real fragmented AF_UNIX requests, malformed
  UTF-8/NUL/length/operation/selector, stale generation/sequence, unowned requests,
  and a continuous RPC stream that still reaches the total request deadline.
- `isolated_storage_integration.py`: actual content workers and GL contexts,
  shared tabs, concurrent writes, session continuity, process restart, second
  origin, Unicode, 65,536-byte values, oversize quotas/misses, same-origin redirects,
  explicit cross-origin denial, default navigation preservation, actual parent CLI
  presentation, and fragmented/stale/oversized/disconnected replies.
- Native persistence unit/restart/origin/session/locking tests remain passing.
  Commit and transport tests also pass with `W_DEBUG_ALLOC=1`.

The focused Xvfb shared-worker run on 2026-10-15 measured a maximum parent poll of
1 ms, including a 65,536-byte round trip. This is one local measurement, not a
latency bound or M3 application-conformance result.
