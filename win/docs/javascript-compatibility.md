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
- `addEventListener`, `removeEventListener`, function-valued `on...` properties, and inline event attributes for the supported language subset.
- `console.log`, `.warn`, and `.error` retain their first argument in a bounded per-page console buffer (the last 32 entries, at most 4 KiB each). A console panel is not yet provided.

Wrapper property writes are synchronized to the document before DOM host calls and after each evaluation/callback. Existing wrapper values are refreshed at host calls and before UI event dispatch. A directly read ancestor `textContent` can therefore be stale until the next host call after a descendant property assignment. `innerHTML`, live collections, attribute/property reflection beyond the listed fields, getters/setters, DOM prototypes, and mutation observers are not implemented. Node `tagName` uses the parser's lowercase spelling.

Events expose `type`, `target`, `currentTarget`, `defaultPrevented`, `preventDefault()`, and `stopPropagation()`. Click, input, change, and submit callbacks can mutate the page; canceling click/submit prevents the browser's default action. Events bubble through ancestors. Property/inline handlers returning `false` also cancel the default action. Event listener options, capture, and native JavaScript receiver/`this` semantics are not implemented.

## Limits and ownership

Each script/callback dispatch has a 100,000-step interpreter budget, including charged DOM traversals; depth is limited to 128. A script source is limited to 256 KiB and a realm retains at most 512 script ASTs, 100,000 runtime heap values, 1,024 node wrappers, and 1,024 registered listeners. The document has at most 20,000 nodes; DOM text/attribute strings are limited to 64 KiB and copied DOM mutation data has a conservative cumulative 4 MiB allocation budget. Appending a node cannot create cycles or exceed document depth limits. Reads of `textContent` return at most 64 KiB. These are deterministic limits, not resumable execution or a standards-compliant sandbox.

Collection runs between evaluations/dispatches; DOM wrappers and callbacks are rooted. Closing a tab or replacing its document frees its interpreter, callbacks, scripts, and DOM together. No script state is shared between tabs or carried into a newly loaded document.

Tests in `win/tests/script_test.w` cover mutation, selector identity, insertion, styles/classes, bubbling/cancelation, form input values, inline handlers, lifecycle, console storage, execution/allocation bounds, failure recovery, and realm isolation. The HTTP resource fixture checks ordered external execution and download-failure isolation.
