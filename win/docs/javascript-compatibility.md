# Page JavaScript

Win executes inline classic scripts and fetched external classic scripts in document order in a separate W JavaScript interpreter instance for each page/tab. Failed downloads and script exceptions produce a status diagnostic and do not prevent later scripts from running. The resource queue may fetch scripts concurrently, but execution waits for earlier script elements. Scripts use the fully parsed document; parser-blocking execution, `async` and `defer` scheduling are not modeled. `DOMContentLoaded` fires once on Document after the initial script queue finishes, with `readyState` set to `interactive`; it does not wait for unrelated image downloads. `load` fires once on Window after all initial resources finish, with `readyState` set to `complete`.

This is an implementation of W's bounded JavaScript language subset, not an ECMAScript-complete browser engine. Supported language features include `let`/`const`, function/global `var` hoisting, ordinary functions/closures, synchronous arrows, method-call receivers (`this`), objects and arrays, property access/assignment, conditionals, loops, arithmetic, strict comparisons, `typeof`, and exceptions. Arrows retain the enclosing receiver; global `this` and sloppy receiver substitution/boxing remain unsupported. See [W's runtime contract](../../w/docs/projects/javascript.md). Unsupported syntax/operations produce a diagnostic, including classes, modules, generators, async functions, destructuring, `new`, and regex execution. Implicit operator coercion and many standard built-ins are also outside the subset. JSON script data is ignored; module scripts report that modules are unsupported. There are no timers, promises, fetch/XHR, browser storage, navigation bindings, or access to W/OS capabilities from page code.

## DOM bindings

`document`, `window.document`, and `document.body` expose stable element wrappers. The limited `window`/`globalThis` object is distinct from Document and has its own event registrations. `window.document === document` and `globalThis === window`; the Window wrapper is not the interpreter's lexical global environment, so global declarations do not automatically become Window properties.

Available operations:

- `getElementById`, `querySelector`, and `querySelectorAll` (a static array) using Win's supported CSS selectors.
- Element `matches(selector)` returns a boolean; `closest(selector)` checks the element and then its ancestors, returning the nearest matching wrapper or null, including in detached trees. These and the query methods share filtered nth-child selectors and forgiving `:is()`/`:where()` lists. An invalid or unsupported strict selector list throws a catchable object with `name: 'SyntaxError'` and a `message`, even on an empty tree; native DOMException prototypes are not implemented. A valid forgiving list with no surviving branches simply matches nothing.
- `textContent`, `value`, `id`, `className`, `checked`, and `hidden` properties; `document.title` and `document.readyState`.
- `getAttribute`, `setAttribute`, and `removeAttribute`.
- `createElement`, `createTextNode`, `appendChild`, and `remove`. Detached nodes remain owned until the page is freed, so retained wrappers remain safe.
- `classList.add`, `.remove`, `.toggle`, and `.contains` with one class token per call.
- `style.cssText`, `.color`, `.backgroundColor`, `.display`, `.fontSize`, `.fontWeight`, `.width`, `.height`, `.margin`, `.padding`, and `.border` reads/writes. `getPropertyValue`, `getPropertyPriority`, `setProperty`, and `removeProperty` operate on supported CSS property names; `setProperty` accepts an optional `important` priority. Reads return specified inline values, not computed cascade values. `cssText` normalizes declaration order, separators, and spacing. Invalid individual property assignments leave existing declarations unchanged; replacing `cssText` keeps only valid supported declarations. The interface does not implement `getComputedStyle`, stylesheet rule APIs, or complete CSSStyleDeclaration enumeration/serialization.
- `addEventListener`, `removeEventListener`, function-valued `on...` properties, and inline event attributes for the supported language subset. Listener registration accepts a boolean capture argument or an options object with `capture`, `once`, and `passive`; removal matches the callback, event type, and capture flag.
- `console.log`, `.warn`, and `.error` retain their first argument in a bounded per-page console buffer (the last 32 entries, at most 4 KiB each). A console panel is not yet provided.

For the supported `margin`, `padding`, and `border` shorthands, assignment replaces
all constituent longhands and their previous priorities. Longhand changes preserve
siblings; removing a shorthand removes its components, and removing a longhand
does not revive an earlier shorthand value. Shorthand reads reconstruct the
winning longhands when all components are present with matching priorities,
otherwise returning an empty string. Border's omitted components read as
`medium`, `none`, and `currentcolor`. Serialization keeps a surviving complete
shorthand or expands its surviving components; it does not promise a browser's
canonical CSS text spelling.

Native property hooks read and write the document synchronously: an ancestor `textContent` read immediately observes a descendant assignment without an intervening host call. Inline style mutations are synchronous too. Embedded stylesheet text changes and stylesheet insertion, removal, and reordering reconcile active sheets at evaluation/host boundaries. Existing linked stylesheets are retained by node and URL. Resource discovery remains limited to the initial document: dynamically inserted external scripts, links, and images or changed resource URLs do not start new fetches, and inserted scripts do not execute. `innerHTML`, live collections, attribute/property reflection beyond the listed fields, DOM prototypes, and mutation observers are not implemented. W supplies host descriptor/prototype hooks, but this does not expose the full JavaScript accessor or DOM interface surface. Node `tagName` uses the parser's lowercase spelling.

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
Listener objects with `handleEvent`, abort signals, synthetic `Event` constructors
and `dispatchEvent`, and shadow DOM event paths remain unsupported.
Property/inline handlers run after registered noncapture listeners at their node,
rather than interleaving in registration order. Event fields are ordinary mutable
wrapper properties, not native read-only accessors.

## Limits and ownership

DOM selector calls parse once per call and charge validation, matching, nested
filters, and ancestor/sibling traversal against the interpreter budget. Exhaustion
is a terminal limit failure, not a catchable selector syntax error; subsequent
evaluations start with a fresh budget.

Each script/callback dispatch has a 100,000-step interpreter budget, including charged DOM traversals; depth is limited to 128. A script source is limited to 256 KiB and a realm retains at most 512 script ASTs, 100,000 runtime heap values, 1,024 node wrappers, and 1,024 registered listeners. The document has at most 20,000 nodes; DOM text/attribute strings and listener type names are limited to 64 KiB and copied DOM mutation data (including listener type names) has a conservative cumulative 4 MiB allocation budget. Removed/once listeners release their registrations and callback roots after dispatch; removals outside dispatch reclaim slots immediately. Interpreter limit failures terminate the dispatch, while ordinary callback exceptions allow later listeners to run. Appending a node cannot create cycles or exceed document depth limits. Reads of `textContent` return at most 64 KiB. These are deterministic limits, not resumable execution or a standards-compliant sandbox.

Collection runs between evaluations/dispatches; DOM wrappers and callbacks are rooted. Closing a tab or replacing its document frees its interpreter, callbacks, scripts, and DOM together. No script state is shared between tabs or carried into a newly loaded document.

Tests in `win/tests/script_test.w` cover mutation, selector identity, insertion, styles/classes, event phases and options, propagation/cancelation, form input values, inline handlers, lifecycle, console storage, execution/allocation bounds, failure recovery, and realm isolation. The HTTP resource fixture checks ordered external execution and download-failure isolation. `win/fixtures/standards.html` and the browser integration suite exercise capture/once listeners and canceled form navigation together with expanded CSS selectors and colors. `win/tests/cssom_test.w` additionally covers synchronous DOM properties, inline CSSOM operations, stylesheet mutations, distinct Window events, receiver identity, and separate DOM/content load readiness. W's merged runtime foundation expands the subset described above; these tests do not establish full ECMAScript or DOM conformance.
