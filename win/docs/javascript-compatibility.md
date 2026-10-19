# Page JavaScript

Outstanding mandatory work is tracked in the [standards ledger](standards-ledger.json)
and [shared implementation contracts](browser-contracts.md). Selected passing tests
do not close the broader standards families.

Win executes inline classic scripts and fetched external classic scripts in document order in a separate W JavaScript interpreter instance for each page/tab. Failed downloads and script exceptions produce a status diagnostic and do not prevent later scripts from running. The resource queue may fetch scripts concurrently, but execution waits for earlier script elements. Scripts use the fully parsed document; parser-blocking execution, `async` and `defer` scheduling are not modeled. `DOMContentLoaded` fires once on Document after the initial script queue finishes, with `readyState` set to `interactive`; it does not wait for unrelated image downloads. `load` fires once on Window after all initial resources finish, with `readyState` set to `complete`.

This is an implementation of W's bounded JavaScript language subset, not an ECMAScript-complete browser engine. Supported language features include `let`/`const`, function/global `var` hoisting, ordinary and async functions/closures, synchronous and async arrows, method-call receivers (`this`), objects and arrays, property access/assignment, conditionals, loops, labelled blocks/loops with targeted `break`/`continue`, arithmetic, strict comparisons, `typeof`, and exceptions. Arrows retain the enclosing receiver. Global `this` now identifies Window; general sloppy receiver substitution remains incomplete. See [W's runtime contract](../../w/docs/projects/javascript.md). Unsupported syntax/operations produce a diagnostic, including generators, async methods, and arbitrary-precision BigInt arithmetic. RegExp literals/constructors, exec/test and String.replace implement a bounded UTF-16 subset with explicit unsupported features; see [the RegExp contract](../../w/docs/projects/javascript_regexp.md). Bounded classes support constructors, prototype/static methods, inheritance, super-constructor calls and instanceof; accessors/private fields/super-property access remain outside the class subset. Bounded 64-bit BigInt arithmetic preserves exact bits and rejects overflow. Bounded binding patterns/defaults/rest, spread, optional chaining, and selected native constructors are now supported. Bounded abstract equality (`==`/`!=`) performs ordinary primitive conversion; Addition and bitwise operators implement bounded ordinary primitive/numeric conversion; other arithmetic coercion and many standard built-ins remain outside the subset. Iterative logical, comma, conditional, binary and statement-tail evaluation avoids artificial AST recursion while retaining execution and call-depth limits. For-in enumerates descriptor/prototype keys with mutation rules; `in` uses descriptor lookup and explicit native presence hooks. JSON script data is ignored. Module scripts use a bounded asynchronous source loader connected to W's [acyclic module foundation](../../w/docs/projects/javascript_modules.md), with same-origin named imports, live named variable/function/class exports and top-level await. Pending module evaluation lets Fetch/timers/Promise jobs advance and delays the initial DOMContentLoaded/load lifecycle; rejection is cached and reported without replaying module bodies. The bounded scheduling and storage APIs below are available, along with same-origin `fetch` and Promise-based `Response.text()` / `Response.arrayBuffer()` / `Response.json()` subsets. See [web application execution](web-app-compatibility.md) for wasm, canvas, and binary interfaces. XHR, location assignment, and access to W/OS capabilities from page code remain unavailable.

Array callback methods now include generic `every`, `forEach`, `map`, `filter`,
`find`, `findIndex`, `findLast`, `findLastIndex`, `reduce` and `reduceRight`.
They preserve callback order, sparse/inherited properties, live mutation and
shared execution limits; custom species and Symbol hooks remain unsupported.
See the [array iteration contract](../../w/docs/projects/javascript_array.md#callback-iteration).

`String(value)` supports bounded ordinary object conversion and Error
stringification. String, Number and Boolean constructors create traced primitive
wrappers; `Object(value)` boxes supported primitives, including bounded BigInt.
String wrappers expose immutable UTF-16 indices and length. Symbol hooks remain
unsupported. Ordinary Object/Reflect descriptor, prototype, extensibility and
receiver operations are implemented with ownership and exception checks; array
descriptor mutation and general native exotic reflection remain incomplete.
`parseFloat` and `Number.parseFloat` share a bounded decimal-prefix parser with
ECMAScript whitespace, signed zero, Infinity and correctly rounded binary64
results. These do not imply general implicit coercion.

## Tasks and storage

The default script/task budget is 1,000,000 shared JavaScript/Wasm steps.
`--execution-budget N` explicitly selects 1–200,000,000 steps for ordinary native
pages and new tabs. The same cap covers script/module entry, event dispatch,
timers, animation batches and microtask checkpoints; reentrant imports do not
refill fuel. Suspended async tasks conserve their original budget. Native Fetch
settlement retains its independent 100,000-step entry bound. Isolated interactive
workers receive the selected budget; isolated headless dumps reject custom budgets
until policy forwarding exists. Higher budgets can block the
parent UI for seconds; they permit measured experiments, not responsiveness claims.
All heap/source/stack/resource limits remain enforced independently.


`requestAnimationFrame` and `cancelAnimationFrame` run bounded callbacks before
painting the visible tab, with one relative monotonic timestamp per frame. Nested
registrations wait for the next frame, and cancellation can remove a later
callback from the current batch. Up to 256 callbacks share a 1,000,000-step frame
budget. Ordinary headless dumps do not run frames; isolated interactive ticks can.

`setTimeout`, `setInterval`, `clearTimeout`, and `clearInterval` are available on
the global scope and Window. Callbacks must be functions; source-string timers
are rejected. Numeric delays are clamped to 0–2,147,483,647 ms (intervals have a
1 ms minimum); delay coercion is not implemented. Timers accept up to three extra
callback arguments and invoke ordinary callbacks with Window as `this`. There
are at most 256 active timers. Timer IDs are unique within a realm, and either
clear function can cancel either timer kind.

Browser polling runs at most 64 due callbacks with a shared 1,000,000-step budget.
Equal deadlines preserve registration order. Timers created by a timer callback
wait until a later poll, and intervals coalesce missed deadlines rather than
replaying a backlog. A callback exception is recorded without preventing later
timers; a terminal interpreter limit ends that poll. Each registration owns its
callback/argument roots, including during self-cancellation. Navigation and tab
closure free them; Stop cancels timers and queued microtasks.

The runtime provides `new Promise(executor)`, `Promise.resolve`,
`Promise.reject`, `then`, `catch`, `finally`, and `queueMicrotask`. Executors run
synchronously; reactions run at checkpoints. Settlement is first-call-wins,
chains adopt native promises and generic thenables, and retained jobs participate
in garbage collection. Resolution reads `then` synchronously and queues its call;
shared resolving capabilities enforce first-call-wins even with reentrancy.
`finally` awaits cleanup and preserves the original result unless cleanup fails.
`Promise.all`, `race`, and `allSettled` accept the supported array/string
iterables, preserve result ordering, and assimilate thenables. Custom iterators,
`Promise.any`, generic constructors/species, and unhandled-rejection events remain
unsupported.
Async functions and top-level module await use suspended
W generator stacks resumed by Promise jobs. Suspension is bounded to 32 tasks,
8 MiB of stack storage and a separate retained-root quota; fuel is conserved
across checkpoints. Stop/navigation unwind suspended native temporaries and
invalidate queued resumptions before freeing host records. Await assimilates
thenables through the same Promise resolution mechanism.

The runtime provides `queueMicrotask` and bounded Promise jobs. The script host
runs explicit microtask checkpoints after script evaluation and event dispatch,
before timer polling (including polls with no timers), and after each timer
callback. Checkpoints install the active document so Promise/fetch callbacks can
use DOM methods and synchronize their mutations. Terminal evaluation failures
retain their diagnostic instead of beginning another checkpoint. Deterministic
native tests use `win_script_poll_at(script, now_ms)`; production uses monotonic
`win_script_poll(script)`.

`localStorage` and `sessionStorage` support `getItem`, `setItem`, `removeItem`,
`clear`, `key`, and `length`. Explicit storage owners retain local data for the
app lifetime and session data for the tab lifetime, including reloads. Local data
is shared with other tabs at the same origin; session data is not.
Session storage is memory-only. Local storage also defaults to memory-only;
`--storage FILE` opts into a versioned disk store protected by a lifetime advisory
lock. The parent directory must exist. Mutations publish mode-0600 files through
atomic replacement with file/directory synchronization. Prepublication failures
restore the old memory state; a postpublication directory-sync failure retains
the new state and throws `UnknownError`. Malformed records fail closed without
replacement. Isolated interactive mode supports the option through
[parent-owned storage IPC](isolated-storage.md); headless isolated dump refuses it.
The origin is parsed from
the final document URL and includes normalized scheme, host, and effective port;
paths do not split an origin. File/invalid origins throw `SecurityError` rather
than sharing an opaque bucket.

Each owner is bounded to 1 MiB and 1,024 entries across its origins; keys and
values are at most 64 KiB each. Quota failures throw `QuotaExceededError` and leave
the old value intact. Strings use the browser binding's bounded primitive string
conversion. Named-property storage access, storage events,
full Web IDL coercion, and new-tab session copying are not implemented.

## Fetch

`fetch(url, options)` and `window.fetch(url, options)` support HTTP(S) to the document's own
scheme/host/effective-port origin. Relative references resolve against its final
URL. Cross-origin redirects are rejected before the foreign request; local files
and CORS requests are unavailable. Options may supply `method`, `body`, native `signal`, and a plain data record
of Content-Type/Accept headers. Bodies are bounded to 64 KiB, accept strings or
copied BufferSource views and preserve embedded NUL bytes. GET/HEAD reject
bodies; CONNECT/TRACE/TRACK are forbidden. Unsupported headers/options are
rejected rather than silently ignored. Binary request framing, redirect behavior
and exact limits are described in [network compatibility](network-compatibility.md). Loading uses cancellable child processes and existing deadlines.

The returned native Promise fulfills with `status`, `ok`, `url`, `bodyUsed`, and
`text()`, `arrayBuffer()`, and `json()`. HTTP error statuses still fulfill; transport failures reject.
`text()`, `arrayBuffer()` and `json()` return Promises and share a single-use body. Bodies
are limited to 4 MiB each; `text()` additionally requires valid UTF-8 and at most
64 KiB. Binary bodies are preserved byte-for-byte. Encoding replacement for text,
streaming, blob helpers, response headers, and XHR remain unsupported.
`json()` accepts up to 64 KiB, uses forgiving UTF-8 decoding, then strict bounded
JSON parsing, with `SyntaxError` rejection and consumed-on-failure semantics. A page allows three
concurrent fetches, 64 requests over its lifetime, and 4 MiB of retained body
bytes. Responses remain owned until document teardown. `AbortController` exposes a
stable branded `signal`, exact `reason`, `aborted`, `throwIfAborted`, `onabort`
and function-valued abort listeners. Native observers cancel/reap Fetch workers
before JS listeners run. Aborting after fulfillment rejects unread response
bodies. At most 256 controllers are retained per realm and 1,024 active listeners
per signal. Signal composition/timeouts, full prototypes and DOMException classes
remain unsupported. Navigation/tab closure
cancel outstanding workers before freeing their realm.

`--dump` waits for pending fetches and module evaluation (including awaited
timers), but does not wait for unrelated future timers or recurring intervals. `--isolated-dump` executes the complete headless pipeline in a child;
see the [process boundary](script-isolation.md) for limits.

## DOM bindings

`history.pushState`, `replaceState`, `back`, `forward`, `go`, `length` and
`state` integrate with tab history. Same-document mutations retain the realm,
update Location/search and relative-resource bases, and require an HTTP(S) URL
at the existing origin. Back/forward/go enqueue at most 32 traversals and deliver
trusted, nonbubbling `popstate` with the restored state; push/replace do not fire
it. History is bounded to 128 entries. Isolated interactive execution preserves
live same-document state through [versioned History IPC](isolated-history.md),
with a 1 MiB aggregate table bound and explicit retired-realm reload limits. Cross-document traversal reloads the page;
there is no back/forward page cache.

State supports null, top-level undefined, strings, booleans, finite numbers other
than negative zero, and dense JSON-compatible plain object/array trees. Each
snapshot is independently cloned, bounded to 64 KiB, 32 levels and 4,096 object
identities. Unsupported values, cycles/shared object references, accessors,
`toJSON`, sparse arrays and extra array properties throw `DataCloneError` before
mutation. This is a storage subset, not general structured clone. General URL
argument coercion, complete `go` Web IDL conversion, scrollRestoration, hashchange,
navigation assignment and the Navigation API remain unsupported.

The additional host surface includes `location.search`, mutable
`URLSearchParams`, viewport globals and resize events, `getBoundingClientRect`,
client/offset dimensions, and live computed padding/font-size/pointer-events/flex-direction reads through
`getComputedStyle`. VisualViewport, general computed styles, and navigation
assignment are not implemented.

The bounded parameter-list behavior follows the [URL Standard](https://url.spec.whatwg.org/#interface-urlsearchparams)
and [Web IDL pair iteration](https://webidl.spec.whatwg.org/#es-iterable).
`new URLSearchParams(init)` accepts strings, another native parameter list,
arrays of two-item arrays, and plain records with enumerable own string keys.
Omitted/undefined initialization creates an empty list; null is converted to
the string `"null"`, producing a `null` key with an empty value.
It provides `size`, `get`, `getAll`, `has`, `append`, `set`, `delete`, `sort`,
`toString`, and `forEach`. Duplicate names retain insertion order; `set` replaces
the first matching value and removes later duplicates. `has` and `delete`
accept an optional value filter (explicit `undefined` means no filter).
Serialization uses UTF-8 form encoding, including `+` for spaces and uppercase
percent escapes. Decoding preserves embedded NUL and replaces malformed UTF-8;
USVString conversion replaces lone surrogates. Sorting is stable by UTF-16 code
units. String conversion supports primitives and the runtime's explicit ordinary
conversion methods, including `String(params)`.

`forEach(callback, thisArg)` visits the current list by index and observes
appends, deletions, replacements, and sorting during callbacks. It passes value,
name, and the original parameter object, propagates callback exceptions, and
shares the active task's fuel. Async callbacks retain their arguments across
await; iteration itself does not await their results. Methods check the native
receiver and can be borrowed between parameter objects.

Each list has at most 1,024 pairs and 65,536 UTF-16 units across names/values;
input strings and serialized output are each limited to 65,536 units. A realm
retains at most 256 parameter objects and 524,288 combined name/value units until
document teardown. Failed construction releases its native allocations. Mutation
and sort budget/quota failures preserve the existing list, apart from mutations
already performed by user conversion functions or callbacks. Serialization can
exceed its limit even when the unencoded list fits. These are terminal host
limits, not standard URL API exceptions.

This is a standalone parameter-list subset: the `URL` class and live
`URL.searchParams` association, general iterable initializers, Symbol hooks,
`entries`/`keys`/`values` iterator objects, and complete Web IDL reflection remain
unsupported. `forEach` is the supported iteration interface. The existing
History API can consume `'?' + params.toString()` for same-origin routing.

`document`, `window.document`, and `document.body` expose stable element wrappers. The limited `window`/`globalThis` object is distinct from Document and has its own event registrations. `window.document === document` and `window === self === globalThis === this` at classic-script top level. Window is the object-backed global: supported global `var` and function declarations are reflected as properties, while lexical declarations retain separate bindings and TDZ precedence. Full GlobalDeclarationInstantiation, browsing-context relationships and Window exotic reflection remain incomplete; `parent` and `top` currently identify the sole Window and `opener` is null.

Available operations:

- `getElementById`, `querySelector`, and `querySelectorAll` (a static array) using Win's supported CSS selectors. Document and Element `getElementsByTagName` return bounded live collections with `length`, index access, `item` and named lookup. Traversal observes current descendants, including detached owned trees; full HTMLCollection/Web IDL reflection remains incomplete.
- Element `matches(selector)` returns a boolean; `closest(selector)` checks the element and then its ancestors, returning the nearest matching wrapper or null, including in detached trees. These and the query methods share filtered nth-child selectors and forgiving `:is()`/`:where()` lists. An invalid or unsupported strict selector list throws a catchable object with `name: 'SyntaxError'` and a `message`, even on an empty tree; native DOMException prototypes are not implemented. A valid forgiving list with no surviving branches simply matches nothing.
- `textContent`, `value`, `id`, `className`, `checked`, and `hidden` properties; `document.title` and `document.readyState`.
- `getAttribute`, `setAttribute`, and `removeAttribute`.
- Input/textarea `selectionStart`, `selectionEnd`, `selectionDirection`, and `setSelectionRange` use UTF-16 offsets with clamping. Native focus, editing and selection task events remain incomplete.
- `createElement`, `createTextNode`, `createDocumentFragment`, `appendChild`, `insertBefore`, `removeChild`, `replaceChildren`, and `remove`. Fragment insertion moves its children in order after hierarchy preflight, preserving wrappers and listeners. Element `replaceChildren` accepts nodes and primitive strings with preflight hierarchy validation; Document and DocumentFragment variants are absent. Detached nodes remain owned until the page is freed, so retained wrappers remain safe.
- `classList.add`, `.remove`, `.toggle`, and `.contains` with one class token per call.
- `style.cssText`, `.color`, `.backgroundColor`, `.display`, `.fontSize`, `.fontWeight`, `.width`, `.height`, `.margin`, `.padding`, `.border`, `.flex`, `.flexGrow`, `.flexShrink`, `.flexBasis`, `.flexDirection`, `.pointerEvents`, and `.justifyContent` reads/writes. `getPropertyValue`, `getPropertyPriority`, `setProperty`, and `removeProperty` operate on supported CSS property names; `setProperty` accepts an optional `important` priority. Reads return specified inline values, not computed cascade values. `cssText` normalizes declaration order, separators, and spacing. Invalid individual property assignments leave existing declarations unchanged; replacing `cssText` keeps only valid supported declarations. The interface does not implement general computed styles, stylesheet rule APIs, or complete CSSStyleDeclaration enumeration/serialization; limited computed padding/font-size/pointer-events/flex-direction reads are listed above.
- `addEventListener`, `removeEventListener`, function-valued `on...` properties, and inline event attributes for the supported language subset. Listener registration accepts a boolean capture argument or an options object with `capture`, `once`, and `passive`; removal matches the callback, event type, and capture flag.
- `console.log`, `.warn`, and `.error` retain their first argument in a bounded per-page console buffer (the last 32 entries, at most 4 KiB each). A console panel is not yet provided.

For the supported `margin`, `padding`, `border`, and `flex` shorthands, assignment replaces
all constituent longhands and their previous priorities. Longhand changes preserve
siblings; removing a shorthand removes its components, and removing a longhand
does not revive an earlier shorthand value. Shorthand reads reconstruct the
winning longhands when all components are present with matching priorities,
otherwise returning an empty string. Border's omitted components read as
`medium`, `none`, and `currentcolor`. Serialization keeps a surviving complete
shorthand or expands its surviving components; it does not promise a browser's
canonical CSS text spelling.

Native property hooks read and write the document synchronously: an ancestor `textContent` read immediately observes a descendant assignment without an intervening host call. Inline style mutations are synchronous too. Embedded stylesheet text changes and stylesheet insertion, removal, and reordering reconcile active sheets at evaluation/host boundaries. Existing linked stylesheets are retained by node and URL. Resource discovery reconciles connected scripts, links, and images and changed resource URLs during browser polling. Newly connected classic scripts execute once per node, including after initial page load; removing and reinserting an executed script does not replay it. Detached pending scripts are skipped. Discovery and execution are bounded and polled, not the complete HTML script preparation algorithm. `innerHTML`, live collections beyond `getElementsByTagName`, attribute/property reflection beyond the listed fields, DOM prototypes, and mutation observers are not implemented. W now supplies separately owned HTML fragment parsing for supported text/HTML contexts; table/select/template and foreign-content contexts remain unsupported, and this API is not yet exposed through `innerHTML`. W supplies host descriptor/prototype hooks, but this does not expose the full JavaScript accessor or DOM interface surface. Node `tagName` uses the parser's lowercase spelling.

Events expose `type`, `target`, `currentTarget`, `eventPhase`, `bubbles`,
`cancelable`, `defaultPrevented`, `preventDefault()`, `stopPropagation()`, and
`stopImmediatePropagation()`. Dispatch visits ancestor capture listeners, target
capture/bubble listeners, then ancestor bubble listeners. The ancestor path is
fixed before callbacks run, so detaching or reparenting nodes does not change an
event already in progress. Each node/phase invocation snapshots registrations;
removed listeners are skipped, and additions can run in later phases. `once`
listeners are removed before invocation, and passive callbacks cannot cancel the
default action. After dispatch, `currentTarget` is null and `eventPhase` is zero.

Click, input, change, submit, and reset callbacks can mutate the page. Click,
submit, and reset are cancelable; input, change, `DOMContentLoaded`, and load are
not. All these events except load bubble. Property/inline handlers returning
`false` cancel only cancelable events. Removing a listener requires the same
capture flag used at registration; `once` and `passive` do not affect its identity.

The event behavior follows the supported portions of the
[DOM event dispatch model](https://dom.spec.whatwg.org/#concept-event-dispatch).
Listeners and property/inline handlers receive their current event target as
`this`; arrows keep their lexical receiver. Connected-node event paths include
Window after Document, while detached trees do not reach either. Window and
Document retain separate listener registrations, and page load targets Window.
`new Event(type, options)` and `dispatchEvent(event)` support synthetic dispatch,
including reentrancy, event identity, nested dispatch and the same listener rules.
Core event fields are read-only; synthetic events have `isTrusted:false`. Nested
dispatch checkpoints run after the outermost invocation. Listener objects with
`handleEvent`, listener abort options, and shadow DOM event paths remain unsupported.
Supported property/inline handlers interleave with listeners in registration
order, as detailed below. Core event fields use native read-only descriptors.

## Limits and ownership

DOM selector calls parse once per call and charge validation, matching, nested
filters, and ancestor/sibling traversal against the interpreter budget. Exhaustion
is a terminal limit failure, not a catchable selector syntax error; subsequent
evaluations start with a fresh budget.

Each script/callback dispatch defaults to a 1,000,000-step interpreter budget, including charged DOM traversals; depth is limited to 128. A script source is limited to 256 KiB and a realm retains at most 512 script ASTs, 100,000 runtime heap values, 1,024 node wrappers, and 1,024 registered listeners. The document has at most 20,000 nodes; DOM text/attribute strings and listener type names are limited to 64 KiB and copied DOM mutation data (including listener type names) has a conservative cumulative 4 MiB allocation budget. Removed/once listeners release their registrations and callback roots after dispatch; removals outside dispatch reclaim slots immediately. Interpreter limit failures terminate the dispatch, while ordinary callback exceptions allow later listeners to run. Appending a node cannot create cycles or exceed document depth limits. Reads of `textContent` return at most 64 KiB. These are deterministic limits, not resumable execution or a standards-compliant sandbox.

Collection runs between evaluations/dispatches; DOM wrappers and callbacks are rooted. Closing a tab or replacing its document frees its interpreter, callbacks, scripts, and DOM together. JavaScript realms are separate across tabs and navigation. Explicit app/tab storage owners retain the origin-keyed storage data described above across replacement realms.

Tests in `win/tests/script_test.w` cover timer ordering/cancellation/bounds, microtask checkpoints, storage reload/origin/tab isolation and quotas, mutation, selector identity, insertion, styles/classes, event phases and options, propagation/cancelation, form input values, inline handlers, lifecycle, console storage, execution/allocation bounds, failure recovery, and realm isolation. The HTTP resource fixture checks ordered external execution and download-failure isolation. `win/fixtures/standards.html` and the browser integration suite exercise capture/once listeners and canceled form navigation together with expanded CSS selectors and colors. `win/tests/cssom_test.w` additionally covers synchronous DOM properties, inline CSSOM operations, stylesheet mutations, distinct Window events, receiver identity, and separate DOM/content load readiness. W's merged runtime foundation expands the subset described above; these tests do not establish full ECMAScript or DOM conformance.

The standards command `./win/build standards` runs a [bounded upstream Test262 runtime profile](../../w/tests/javascript/test262/README.md) in addition to static WPT rendering. Labelled control flow includes nested/chained labels, outward jumps, and finally propagation; Annex B labelled function declarations remain unsupported.

The runtime provides bounded `JSON.parse`/`JSON.stringify`, preserving UTF-16
strings (including escaped NUL/lone surrogates), strict number/syntax validation,
property ordering, toJSON, cycle and BigInt errors. Revivers/replacers and broader
coercion are outside this subset; see W's runtime contract for exact limits.

Live HTML Node tree access, child lists, Text data and bounded node creation/moves
are described in [the DOM tree contract](dom-tree.md). Native property presence
uses explicit hooks and does not invoke getters or force layout. Mouse pointer
input and capture use an ordered bounded native queue; native and programmatic
focus synchronize activeElement, focus events and UTF-16 text selections.
Ordered portable KEY/CHAR/NAV records now deliver logical keyboard events and
cancelable beforeinput followed by input for native edits. Unicode input and
Backspace pass through the unchanged mobile host into its wasm field; the hidden
textarea resets after each edit. Unknown hardware keys report Unidentified.
Bounded preedit snapshots produce compositionstart/update/end; the backend
provides no committed payload at PREEDIT_END, so compositionend.data is empty
and later CHAR events perform the commit. Full platform IME behavior remains
unsupported; focused tests do not establish X11/Windows key translation parity.

Supported nullable `on*` handler properties now register in listener order.
Replacing a callback keeps its slot; clearing and re-enabling moves it to a new
slot. Inline attribute changes invalidate the compiled handler, and a returned
false value cancels cancelable events. The implementation covers the names in
`win/src/win/event_handlers.w`, including the onclick/oninput/onsubmit properties
used by the pinned framework. Window ErrorEvent extra arguments, body-to-window
handler aliases and inline form/name scope remain unsupported.

Ordinary functions provide shared `call`, `apply` and `bind`, including bounded
bound construction. Strict/non-simple functions provide unmapped arguments,
and generic array-like `slice` uses property presence before reading elements.
Sloppy mapped arguments remain unsupported. Shared String prototype casing uses
Unicode 12.1 mappings with default final-sigma handling and resource bounds; see
[W’s casing contract](../../w/docs/projects/javascript_string_case.md).

## Keyboard accessibility

Tab and Shift+Tab traverse links, form controls and explicit `tabindex` elements.
Positive indices sort first by value, with DOM order breaking ties; zero/native
entries follow current DOM order. Negative indices remain programmatically
focusable but are omitted from sequential traversal. Hidden and disabled content
are skipped; visible descendants may override inherited `visibility:hidden`.
`pointer-events:none` does not remove keyboard access.

Traversal and Enter-link activation run through the ordered native input path,
including isolated workers. Canceling keydown suppresses the default; link
activation dispatches a cancelable click and observes a handler's changed href
before navigating. Focus rings and reveal use the final box or inline-run
geometry. Native new-tab link targets work; isolated new-tab transport is still
unsupported. Traversal wraps within the document and is bounded to 20,000 nodes
and depth 128.

These changes improve keyboard access. Linux AT-SPI/screen-reader integration,
ARIA semantic trees, shadow/iframe focus scopes, radio-group roving focus and
complete platform keyboard/IME support remain open. Tests cover native and
isolated traversal/activation and actual rendered focus pixels.
