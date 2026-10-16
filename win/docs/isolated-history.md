# Isolated same-document History

The interactive parent mirrors the live worker's bounded History table and sends
chrome Back/Forward through the same ordered queue as native input. A live
same-document traversal dispatches `popstate` in the existing child realm. It
preserves application variables, pending/cancelled request state, form values,
focus, and selection. The parent still has no page JavaScript realm.

`--worker-history` opts a graphics worker into WINT kind 103, revision 3. Browser
interactive sessions require this profile; direct legacy transport consumers can
continue using kind 100/101/102. Kind 103 extends kind 102's canvas manifest and
36-byte input metadata with a length-prefixed history table before the address,
title and HTML strings. The table contains count/current index and up to 128
entries, each with little-endian int32 serial, document epoch, scroll offset,
address length and state length, followed by UTF-8 address and JSON state bytes.
Empty state bytes mean top-level `undefined`. Escaped NUL and lone UTF-16
surrogates remain unchanged in the serialized state.

The receiver validates exact lengths, increasing unique entry IDs, current index,
document epochs, non-regressing document identity, scalar UTF-8, address syntax,
JSON syntax/depth and current-entry/address agreement before publication. Focus,
selection, document identity and owned history strings remain pending until all
canvas frames validate and their ACKs have been sent. Input acquired while old
pixels are displayed retains the old document identity; real document replacement
discards such queued input rather than applying it to a new document.

Chrome traversal is kind 6, revision 3: exactly four little-endian int32 fields
`{worker_generation, document_generation, delta, zero}`. Nonzero delta is bounded
to -127 through 127. It shares the eight-entry owned input queue, never coalesces
with text/mouse input, and resolves its target only after preceding input and
frame publication. Thus click → pushState → Back and Back → typing preserve task
order. Cross-worker fallback waits at the same queue position. Focus loss removes
unsent ordinary input, preserves ordered history controls, and appends pointer
cancellation. Queue overflow stops/reaps content explicitly; it never silently
drops a traversal.

A history table is limited to 1 MiB; each state is at most 64 KiB and the native
address resolver retains its existing 4096-byte limit. `pushState` and
`replaceState` check aggregate capacity before changing state or URL and throw
`QuotaExceededError` on overflow. Fragment navigation performs the same aggregate
preflight and reports a status error without committing the navigation. An
unrepresentable table discovered during serialization fails the transport instead
of truncating entries or silently restarting the realm. Validation is syntax-only
and does not allocate a parent JSON object tree. A measured 960,664-byte,
16-entry table took 12 ms to validate and less than 1 ms to copy on the development
host; this is a sample, not a latency guarantee.

A dead/replaced worker is not restarted automatically. Explicit traversal to an
entry outside the live worker reloads its URL in a new process. This fallback
currently starts the new page's initial history state; it does not restore the
retired realm's saved `history.state` or application variables. The live-realm
same-document path is the state-preserving contract in this slice.

Checks are `interactive_history_test.w` (malformed/stale metadata and atomic
publication), `history_transport_quota_test.w` (atomic mutation/fragment limits),
`isolated_history_cancel_test.w` (cancellation ordering), and
`isolated_history_integration.py` (real child FIFO input/traversal, Unicode state,
focus/selection, cross-worker and crash fallback). The unchanged Preact
`isolated_workflow_integration.py` repeats the actual controls at 800×600 and
360×640 and verifies retained child identity, `Cancelled` result and typed name
across Back/Forward, alongside API/error/abort/theme/persistence checks.
