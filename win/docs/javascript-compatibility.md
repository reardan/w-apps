# Page JavaScript

Win executes inline classic scripts and fetched external classic scripts in document order in a separate W JavaScript interpreter instance for each page/tab. Failed downloads and script exceptions produce a status diagnostic and do not prevent later scripts from running. The resource queue may fetch scripts concurrently, but execution waits for earlier script elements. Scripts use the fully parsed document; parser-blocking execution, `async` and `defer` scheduling are not modeled. `DOMContentLoaded` and `load` fire once after the initial script/resource queue finishes.

This is an implementation of W's bounded JavaScript language subset, not an ECMAScript-complete browser engine. Supported language features include `let`/`const`, ordinary functions/closures, objects and arrays, property access/assignment, conditionals, loops, arithmetic, strict comparisons, and exceptions. See [W's runtime contract](../../w/docs/projects/javascript.md). Unsupported syntax produces a diagnostic: notably `var`, arrow functions, `this`, classes, modules, generators, async functions, implicit coercion, and many standard built-ins. JSON script data is ignored; module scripts report that modules are unsupported. There are no timers, promises, fetch/XHR, browser storage, navigation bindings, or access to W/OS capabilities from page code.

## DOM bindings

`document`, `window.document`, and `document.body` expose stable element wrappers. The limited `window`/`globalThis` object aliases the document and supports event registration; it is not the interpreter's lexical global environment.

Available operations:

- `getElementById`, `querySelector`, and `querySelectorAll` (a static array) using Win's supported CSS selectors.
- `textContent`, `value`, `id`, `className`, `checked`, and `hidden` properties; `document.title` and `document.readyState`.
- `getAttribute`, `setAttribute`, and `removeAttribute`.
- `createElement`, `createTextNode`, `appendChild`, and `remove`. Detached nodes remain owned until the page is freed, so retained wrappers remain safe.
- `classList.add`, `.remove`, `.toggle`, and `.contains` with one class token per call.
- `style.cssText`, `.color`, `.backgroundColor`, `.display`, `.fontSize`, `.fontWeight`, `.width`, `.height`, `.margin`, `.padding`, and `.border` writes. Style property reads do not compute the cascade; use `getAttribute('style')` to read the serialized inline style.
- `addEventListener`, `removeEventListener`, function-valued `on...` properties, and inline event attributes for the supported language subset. Listener registration accepts a boolean capture argument or an options object with `capture`, `once`, and `passive`; removal matches the callback, event type, and capture flag.
- `console.log`, `.warn`, and `.error` retain their first argument in a bounded per-page console buffer (the last 32 entries, at most 4 KiB each). A console panel is not yet provided.

Wrapper property writes are synchronized to the document before DOM host calls and after each evaluation/callback. Existing wrapper values are refreshed at host calls and before UI event dispatch. A directly read ancestor `textContent` can therefore be stale until the next host call after a descendant property assignment. `innerHTML`, live collections, attribute/property reflection beyond the listed fields, getters/setters, DOM prototypes, and mutation observers are not implemented. Node `tagName` uses the parser's lowercase spelling.

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
Listener objects with `handleEvent`, abort signals, synthetic `Event` constructors
and `dispatchEvent`, shadow DOM event paths, and native JavaScript receiver/`this`
semantics remain unsupported. The limited window binding shares document event
registration rather than supplying a distinct Window event target.
Property/inline handlers run after registered noncapture listeners at their node,
rather than interleaving in registration order. Event fields are ordinary mutable
wrapper properties, not native read-only accessors.

## Limits and ownership

Each script/callback dispatch has a 100,000-step interpreter budget, including charged DOM traversals; depth is limited to 128. A script source is limited to 256 KiB and a realm retains at most 512 script ASTs, 100,000 runtime heap values, 1,024 node wrappers, and 1,024 registered listeners. The document has at most 20,000 nodes; DOM text/attribute strings and listener type names are limited to 64 KiB and copied DOM mutation data (including listener type names) has a conservative cumulative 4 MiB allocation budget. Removed/once listeners release their registrations and callback roots after dispatch; removals outside dispatch reclaim slots immediately. Interpreter limit failures terminate the dispatch, while ordinary callback exceptions allow later listeners to run. Appending a node cannot create cycles or exceed document depth limits. Reads of `textContent` return at most 64 KiB. These are deterministic limits, not resumable execution or a standards-compliant sandbox.

Collection runs between evaluations/dispatches; DOM wrappers and callbacks are rooted. Closing a tab or replacing its document frees its interpreter, callbacks, scripts, and DOM together. No script state is shared between tabs or carried into a newly loaded document.

Tests in `win/tests/script_test.w` cover mutation, selector identity, insertion, styles/classes, event phases and options, propagation/cancelation, form input values, inline handlers, lifecycle, console storage, execution/allocation bounds, failure recovery, and realm isolation. The HTTP resource fixture checks ordered external execution and download-failure isolation. `win/fixtures/standards.html` and the browser integration suite exercise capture/once listeners and canceled form navigation together with expanded CSS selectors and colors. This increment expands browser bindings; W's ECMAScript language subset is unchanged.
