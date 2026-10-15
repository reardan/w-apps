# CSS, ECMAScript, and browser standards gap analysis

Audit date: 2026-10-10. Application baseline: `3c80aa2668dfb8f97f21416c40caf430acc35eb4` (`origin/main`). W dependency: `f63d97aea815b3541ab78dd195ef8e1b17b4c30f`. Three parallel audits covered CSS, ECMAScript, and browser integration; findings below combine source inspection, standards references, and executable probes.

Win has a useful, tested browser foundation, but broad compatibility requires changes to core representations, not only more recognized syntax or property names. The immediate priorities are correctness of supported CSS, ECMAScript object/environment semantics, synchronous DOM properties, and a conformance harness that actually executes W. Full flex/grid algorithms and asynchronous JavaScript should build on those foundations.

This document is an analysis and implementation plan. It does not claim to exhaust every normative requirement or provide a conformance percentage. No engine code or dependency pin changed during this audit.

## Standards baseline and boundaries

CSS is a collection of modules. Use [CSS Snapshot 2026](https://www.w3.org/TR/css-2026/) to choose module baselines, then record the exact specification sections and test revisions for each implementation slice. Snapshot inclusion describes specification maturity, not how much of the web Win supports.

The published language baseline is [ECMAScript 2026, ECMA-262 edition 17](https://ecma-international.org/publications-and-standards/standards/ecma-262/). The [live TC39 specification](https://tc39.es/ecma262/multipage/overview.html) identifies itself as the 2027 draft at audit time. Pin the edition for acceptance criteria; track draft changes separately. W's parser currently targets an ES2020-shaped subset and its executable subset is considerably smaller.

DOM, events, `window`, timers, resource fetching, and script scheduling belong to host specifications, not ECMA-262. Assess them against [DOM](https://dom.spec.whatwg.org/), [HTML scripting](https://html.spec.whatwg.org/multipage/scripting.html), [HTML event loops](https://html.spec.whatwg.org/multipage/webappapis.html#event-loops), and [CSSOM](https://www.w3.org/TR/cssom-1/). Passing language tests alone cannot establish browser compatibility.

## What is implemented

| Layer | Existing implementation | Important boundary |
| --- | --- | --- |
| CSS syntax, W | Owned tokenizer, decoded tokens and source spans, balanced component ranges, rules/declarations/at-rules, recovery and allocation/depth limits | Syntax trees do not validate all selector or property grammars |
| Selectors, Win | Type/ID/class/attribute selectors, combinators, structural pseudo-classes, filtered `nth-child`, strict lists, forgiving `:is()`/`:where()`, specificity | Missing interaction state, `:has()`, pseudo-elements, namespaces and nesting; correctness defects remain in supported syntax |
| Cascade/values, Win | Author and inline styles, document source order, `!important`, inherited text styling, physical box properties, RGB/HSL colors, uniform borders, narrow media queries | Direct mutation of a compact computed-style struct; no general specified/computed/used-value pipeline |
| Layout/painting, Win | Block flow, wrapping text, images, form geometry, backgrounds/borders, visibility, equal-column flex/grid approximations | No complete formatting-context, intrinsic sizing, flex or grid implementation |
| JS parsing, W | Generated grammar plus contextual lexer; Script/Module modes; many ES2020 syntax forms and early-error checks | Parser acceptance is broader than AST lowering and execution, and still has false accepts/rejects |
| JS AST tooling, W | Owned lowered AST, printer, source edits, round trips, module-specifier transformation | Some parser-supported forms cannot be lowered; transformations are not runtime support |
| JS execution, W | Binary64 numbers, UTF-16 strings, lexical bindings/TDZ, ordinary closures, plain objects/arrays, control flow, exceptions, host calls, roots and cyclic collection | No complete object model, coercion, standard library, global environment or asynchronous execution model |
| Browser scripting, Win | Per-page realm, ordered classic scripts, stable DOM wrappers, queries/mutations, capture/target/bubble dispatch, cancellation, listener options | Snapshot-based properties and a completed-document script queue; no standard Window/CSSOM/event loop |

Primary implementation locations: [W CSS](../../w/libs/extras/css/css.w), [Win style](../src/win/style.w), [Win document/layout](../src/win/document.w), [W JavaScript](../../w/libs/extras/javascript/runtime.w), [Win script bindings](../src/win/script.w). Existing [CSS](css-compatibility.md) and [JavaScript](javascript-compatibility.md) compatibility documents accurately describe many deliberate limitations; the defects below add evidence beyond those feature lists.

## CSS correctness findings

The following cases were executed against the pinned code using temporary W probes. Numeric outputs are computed-style values, not screenshots. The default inherited font size in the length probes was 18px.

| Case | Observed | Required behavior / implication |
| --- | --- | --- |
| `width:2em;font-size:24px` versus the reverse order | 36px versus 48px | Both widths must resolve to 48px; winning `font-size` determines the element-relative unit |
| `font-size:1.5em` | 18px | 27px with an 18px inherited size |
| `width:9px;width:.5` | 0px | Nonzero unitless length is invalid; retain 9px |
| `width:1e2px` | 1px | 100px |
| `width:9px;width:10PX` | 9px | Units are ASCII case-insensitive; use 10px |
| `font-style:italic;font-style:inherit`, normal parent | Italic remains set | Restore the inherited normal value |
| `display:block;display:inherit` | Block remains set | Copy the parent's computed display value |
| `font-weight:700px` | Accepted as bold | Invalid dimension must not replace an earlier valid declaration |
| `grid-template-columns:garbage garbage` | Accepted as two columns | Invalid track syntax must be rejected |
| 101 repeated `.x` components | Specificity 10100, greater than ID score 10000 | No number of classes can outrank an ID |
| `#123` against `id="123"` | Matches | The unescaped selector is invalid; escaped identifier form is needed |
| `<a href="" disabled checked>` | Fails `:link`; matches `:disabled` and `:checked` | Empty `href` still establishes a link; arbitrary attributes do not make an anchor a disabled or checked form element |
| `@media screen screen and (min-width:1px garbage)` | Applies | Malformed media query must not apply |

The length failures originate in `win_css_length` (`style.w:639`), which uses integer conversion, case-sensitive suffix comparisons, and an 18px root-size constant. `win_css_value` (`:691`) resolves values while declarations are still competing. `win_css_value_valid` (`:902`) accepts some values without adequate token-kind/property grammar checks. Inheritance is accepted for several properties without the corresponding assignment behavior. These findings concern [CSS Values and Units](https://www.w3.org/TR/css-values-4/) and [cascade value processing and explicit defaulting](https://www.w3.org/TR/css-cascade-5/).

Specificity is packed into a scalar in `win_selector_branch_specificity` (`style.w:462`), and importance/inline status add larger scalar offsets in `win_css_rules` (`:1115`) and `win_computed_style` (`document.w:130`). Replace this representation with explicitly ordered fields; increasing the decimal multipliers only moves the failure threshold. Identifier-token handling and element state also need correction. The reference is [Selectors Level 4](https://www.w3.org/TR/selectors-4/), especially specificity and selector validity. Media parsing in `win_css_media` (`style.w:1085`) needs a complete accepted grammar, based on [Media Queries](https://www.w3.org/TR/mediaqueries-4/).

Source inspection found two upstream syntax/recovery differences that should be investigated with dedicated normative regressions. W's qualified-rule recovery stops at semicolons (`css.w:478`), which can turn `bad; a {color:red}` into an applicable `a` rule instead of retaining the invalid complete prelude. Consumers also reject some EOF-terminated functions even though CSS syntax automatically closes open constructs at EOF. Existing CSS tests encode portions of this behavior. Token metadata needs to preserve hash ID status rather than make downstream matchers infer it from the decoded text. These are [CSS Syntax Level 3](https://www.w3.org/TR/css-syntax-3/) issues, separate from Win's property semantics.

Stylesheet matching currently revalidates selectors per node and has no equivalent of the DOM-query work budget (`style.w:8`, `:1115`). Compile and cache selectors, then measure rule/node/sibling growth on bounded fixtures before introducing indexing and narrower invalidation. Resource bounds on input size alone do not establish responsive layout time.

### CSS implementation priorities

1. **Separate parsing, cascade selection, computation and used-value resolution.** Store validated specified values for each longhand. Select winners before resolving font-relative units; resolve percentages against the appropriate layout basis. Preserve fractions until a deliberate painting boundary. Represent `auto` and CSS-wide keywords as tagged values instead of overloaded negative integers.
2. **Use a structured cascade key.** Keep origin/importance, layer, inline status, specificity tuple, and source order separate. Initially retain the supported author/inline scope, but give later origins/layers a defined place. Apply shorthand validation/reset atomically before per-longhand competition. Add universal `initial`, `inherit`, `unset`, then `revert` and `revert-layer` with their required origin/layer machinery.
3. **Compile selectors once.** Preserve token distinctions, validate grammar before matching, store specificity tuples, and use the same matcher for DOM queries and stylesheets. Correct link/control state semantics and add `:hover`, `:focus`, `:focus-visible`, `:active` using explicit interaction state and invalidation. `:has()` needs bounded relative-selector matching and ancestor/sibling invalidation; it is not just another local predicate.
4. **Add custom properties on the new value pipeline.** Preserve token streams and case-sensitive names, inherited custom-property environments, fallback substitution, cycle detection, and invalid-at-computed-value behavior. An invalid substituted value does not simply expose an earlier declaration. Follow [Custom Properties Level 1](https://www.w3.org/TR/css-variables-1/).
5. **Expand module coverage in measurable slices.** Add `calc()`/`min()`/`max()`/`clamp()`, additional units, min/max sizes, logical properties, media grammar and `@supports`. Then layers/nesting, background images/gradients, complete named colors, side borders/radii, fonts, overflow, positioning and stacking. Gate each syntax claim on its corresponding semantics.

Keep newer color spaces, animation/transforms, generated content, tables, writing modes, bidi and shaping visible as separate workstreams. They have distinct rendering/text dependencies and should not disappear into a single “CSS complete” task.

## Layout and CSSOM findings

`win_layout_node` (`document.w:305`) combines HTML defaults, inherited styles, box construction, child traversal, line layout and output emission. Flex/grid handling (`:452`) divides the available width into equal columns; it does not implement flexible sizing or grid track sizing. It counts element children before checking whether they generate boxes. An executed fixture confirmed that direct text in a flex container disappears while an element child renders. The standards require anonymous items for applicable direct text: [Flexbox](https://www.w3.org/TR/css-flexbox-1/) and [Grid](https://www.w3.org/TR/css-grid-2/).

Source inspection also shows fixed `height` only enlarges the content extent (`document.w:492`), effectively behaving as a minimum when content is taller. Inline-block lacks an independent formatting context. Margin collapsing, negative-margin geometry, inline box fragments, overflow and intrinsic sizing are absent or incomplete. Adding `justify-content` alone would leave the fundamental item sizing wrong.

Some existing expectations must change intentionally: `win/tests/css_test.w:78` asserts equal flex columns, whereas default flex sizing does not require equal widths. Preserve regression coverage for application behavior while replacing approximation-specific assertions with normative cases. Also separate the hard-coded canvas insets in `document.w:505` from the CSS initial containing block and user-agent style defaults.

The next layout representation should separate the DOM, generated formatting boxes, and paint fragments. Define content/padding/border geometry, containing-block dimensions, intrinsic min/max-content measurements, baseline data, overflow and hit-test mapping. Implement block/inline correctness first, then flex item generation and the flex sizing algorithm, then grid track sizing and placement. Flex/grid can become independent agent tasks only after these interfaces are stable.

The browser probes exposed a second correctness boundary:

| Case | Observed | Expected direction |
| --- | --- | --- |
| Read `p.style.color` with `style="color:red"` | `undefined` | Read the inline declaration through CSSStyleDeclaration |
| `p.style.color='blue'; p.style.cssText='color:green'` | Inline string becomes `color:green;color:blue` | Later cssText replacement wins, leaving green |
| Set child `textContent`, then immediately read parent `textContent` | Old parent text | Synchronous DOM getter must see the mutation |
| Replace a `<style>` node's text from red to blue, then relayout | Existing text remains red | Reparse/invalidate the affected stylesheet |
| `window === document` | `true` | Distinct host objects |

`win_script_sync` (`script.w:204`) applies changed fields in a fixed array order. `win_script_refresh_binding` (`:251`) maintains snapshots rather than live property access. `win_script_new` (`:572`) binds both `window` and `globalThis` to the document wrapper. Initial stylesheet discovery is in `win_page_collect_styles` (`document.w:111`); mutation does not rebuild that state.

Fixing these together requires host-object property hooks in W and synchronous native DOM/CSSOM operations in Win. Retain stable wrapper identity and collection roots. Use an ordered declaration model for `style`, distinct Window/Document objects, and one mutation/invalidation path that updates stylesheets, resources, computed styles and layout as appropriate. Prototype interfaces and Web IDL conversions are a subsequent layer; adding snapshot fields perpetuates stale-read and ordering bugs.

## ECMAScript gap analysis

### The three support boundaries

`parser.w`, `lexical.w`, `validation.w`, `bindings.w` and `restrictions.w` decide whether source parses and passes implemented early errors. `lower.w` decides whether it has a supported owned AST representation. `runtime.w:780` performs an additional executable-subset preflight. These are three different capabilities and should be reported separately.

The parser recognizes many functions/arrows/classes/modules, destructuring, templates, regex literals, optional chaining and nullish expressions. That does not mean they execute. The runtime rejects `var`, `this`, arrows, classes, modules, `new`, generators/async, templates, regex execution, destructuring, `typeof`, loose equality, bitwise operations, remainder and exponentiation. It lacks normal prototypes/accessors, general coercion and most standard built-ins. Its initially installed globals are `undefined`, `NaN` and `Infinity`; Win supplies its own small host surface.

Edition coverage also needs an explicit ledger: Unicode identifiers use vendored Unicode 12.1 tables, regex flags are restricted to `gimsuy`, and probes reject numeric separators, logical assignment, top-level await, class fields/private fields/static blocks. BigInt literals can parse but do not execute. These are distinct from the early-error defects within the existing parser scope.

### Confirmed parser and semantic differences

| Probe | Current behavior | ECMAScript behavior |
| --- | --- | --- |
| `/(/;` | Parser accepts | Invalid regular-expression pattern |
| Module `export { missing };` | Parser accepts | Export of an undeclared local binding is an early error |
| Module `export default 1; export default 2;` | Parser accepts | Duplicate default export is an early error |
| `async function f(x = await 1) {}` | Parser accepts | Await expression prohibited in these formal parameters |
| `function* f(x = yield 1) {}` | Parser accepts | Yield expression prohibited in these formal parameters |
| Duplicate simple parameters in async/generator functions | Parser accepts | Early error |
| `a: b: while(false) { continue a; }` | Parser rejects | Valid chained labels around an iteration statement |
| Two ordinary top-level declarations of `f`, then `f()` | Throws duplicate callable binding | Valid script; later declaration supplies the function |
| Sloppy named function expression assigns to its own name | Throws constant-assignment error | Assignment to that immutable name is ignored in sloppy mode |
| `1; let x=2;` | Normal completion value is undefined | Script completion preserves 1 |
| `let x=0;while(x<1){x++;42;}` | Normal completion value is undefined | Completion preserves 42 |
| `try { missing; } catch(e) { e === undefined; }` | True | A ReferenceError object is caught, so false |
| `true.foo` | Throws property receiver error | Primitive property access returns undefined here |

The parser cases were executed with `js_parse`; runtime cases with `js_runtime_eval`. These are focused examples, not an exhaustive parser or runtime audit. Several runtime differences are explicitly documented subset contracts, particularly errors, coercion and completion values; changing them is a compatibility contract update, not merely filling in an undocumented feature.

Key implementation points are `js_runtime_function` (`runtime.w:315`), declaration instantiation (`:330`), flat property lookup/write (`:120`), binary operations (`:384`), member access (`:450`), execution/completions and preflight (`:780`). Parser context and label handling live in `validation.w`; parameter rules in `bindings.w`; regex lexical recognition is not a complete regex syntax validator. Compare against ECMA-262 [environment records](https://tc39.es/ecma262/multipage/executable-code-and-execution-contexts.html), [abstract operations](https://tc39.es/ecma262/multipage/abstract-operations.html), [ordinary/exotic objects](https://tc39.es/ecma262/multipage/ordinary-and-exotic-objects-behaviours.html), and [syntax and semantics](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html).

### Required runtime architecture

1. **Values, objects and abstract operations.** Define property descriptors, prototype links, internal Get/Set/Define/Delete operations, own-key ordering, primitive boxing, ToPrimitive/ToNumber/ToString/ToPropertyKey, and typed errors. Keep binding records separate from property descriptors. Introduce Symbol/BigInt deliberately rather than overloading strings/numbers.
2. **Environments, references and calls.** Separate global object and declarative records, function and block environments, variable declaration instantiation, strict/sloppy modes, references/receivers, `this`, `newTarget`, Call and Construct. Implement normal versus abrupt completion with an empty-value distinction. Preserve TDZ and per-iteration closures already present.
3. **Standard objects and common executable syntax.** Bootstrap Object/Function/Array/String/Number/Boolean/Error and useful methods, Math and JSON. Build `var`, arrows, templates, optional chaining, new operators, rest/spread and destructuring on the semantic operations they require. Arrays need holes, property attributes and length behavior, not only a list and counter. Iterators precede `for-of` and general spread.
4. **Modules and jobs.** Add module records, linking/evaluation and live bindings; define host resolution in Win separately. Add Promise jobs and host microtask checkpoints before async/await. Generators need resumable execution state; current terminal budget aborts are not suspension points. RegExp, collections, Date, typed arrays, buffers, Intl (a separate ECMA-402 standard), workers/shared memory and legacy web semantics each require their own scoped tracks.

The critical dependency is the object/environment/call model. Implementing classes, DOM accessors, or promises directly into the present flat property representation would create duplicated semantics and extensive rework. Keep the existing interpreter and W parser as the shared implementation; do not create a second language engine in Win.

Lifetime work also matters: property lookup is linear, collection occurs between evaluations, and retained script ASTs remain owned until realm destruction. A long allocation-heavy evaluation can hit limits despite unreachable intermediate values. Measure this separately from semantic conformance; introduce traced execution roots and safe points before collecting during calls or retaining suspended generator/async frames. Preserve terminal host-limit behavior as an explicit policy, and track browser-specific Annex B semantics separately.

## Browser execution and lifecycle gaps

`win_script_run_pending` (`script.w:730`) runs collected classic scripts in document order after parsing and does not model parser suspension, `async` or `defer`. `win_script_ready` (`:720`) emits DOMContentLoaded and load after the initial queue is finished. DOMContentLoaded must have its own dependency condition rather than wait for every image/resource; load has a different condition. Dynamically inserted scripts/styles and changed resource attributes need scheduling rules and cancellation tied to the document generation.

Current event capture/target/bubble dispatch, path snapshotting, once/passive behavior, propagation stopping and cancellation are valuable foundations. Remaining work includes distinct Window paths, native receiver/`this`, synthetic Event and dispatchEvent, listener objects/abort signals, event accessors, and correct ordering of event handlers relative to listeners. Forms also need dirty value/checked state and appropriate input/change timing, beyond attribute mirroring.

Introduce an explicit task queue, microtask checkpoint hook, monotonic clock/timer interface, document-generation cancellation and lifecycle state machine. Keep Promise machinery in W and task sources/network/rendering in Win. Parser-blocking scripts additionally require an incremental/resumable HTML parser upstream; do not promise them from a script-queue-only change. Fetch/storage/navigation are later host tracks with their own semantics.

## Test evidence and limitations

- `./win/build test`: passed all eight W suites and both Python integration scripts, including resource ordering, cancellation, forms, selectors/colors and DOM events.
- Focused W run: CSS plus 13 JavaScript targets passed; wexec reported 21 targets including dependencies. Coverage included lexer/parser/validation/bindings/restrictions, AST/text, round trips/transforms, runtime and retained invocation, with the declared memory and architecture variants. The x64 CSS target also reported a valid cached result.
- `./wbuild javascript_compatibility`: stopped at its required oracle-version check, installed Node `v22.23.2` versus pinned `v20.19.3`. It did not produce a new passing compatibility report.
- Temporary audit probes were compiled and run against the pinned code, confirming the tables above. No probe was added as a passing regression that enshrines incorrect behavior.
- The full W toolchain suite, native screenshot comparisons and upstream WPT/Test262 suites were not run. This was an audit with documentation changes, not a W implementation change.

The existing [JavaScript corpus](../../w/tests/javascript/corpus/README.md) vendors 18 Test262 files and checks syntax against a pinned Node version. In `tools/javascript_compatibility.py:234`, the controlled execution examples run Node, not W. Consequently, their passing results would not establish W execution semantics. Preserve this useful syntax gate, but label it precisely.

Add a W runtime runner with machine-readable results and fresh realms. A Test262 adapter must honor includes, strict/sloppy variants, module and async flags, expected error type/phase, host hooks and timeouts. Unsupported features and harness failures must be separate results, never counted as passes. Keep corpus commits, licenses and hashes pinned. Follow [Test262 interpretation rules](https://github.com/tc39/test262/blob/main/INTERPRETING.md). Node can help differential testing but does not replace normative expectations.

For CSS, begin with native token/selector/cascade/geometry assertions and imported, attributable fixtures. Add [WPT rendering reftests](https://web-platform-tests.org/writing-tests/reftests.html) with deterministic viewport/fonts and readiness conditions. Many [testharness.js tests](https://web-platform-tests.org/writing-tests/testharness-api.html) require language and DOM APIs Win does not yet support. Track native adaptations separately from unmodified WPT runs. A text dump cannot validate layout or painting.

Report counts separately for parser acceptance, early errors, runtime semantics, host APIs, computed style, geometry and rendering. Every expected failure needs a feature/bug identifier and reason. Track resource-limit failures independently from semantic failures. Existing bounds and memory tests must remain in place as representations expand.

## Parallel implementation plan

Use one coordinator plus three implementing agents, matching the available concurrency. The coordinator owns interfaces, cross-repository integration, combined tests and the W gitlink. Each agent owns a disjoint set of files per wave. The following paths for new modules are proposed, not existing files.

### Wave 0: interfaces and measurable baselines

| Owner | Work | Exclusive ownership | Exit criteria |
| --- | --- | --- | --- |
| Agent A — CSS foundation | Structured specificity/cascade keys, validated specified values, deferred unit resolution, inherited keyword fixes; extract selectors/value/cascade modules; repair upstream syntax metadata/recovery in a separate checkpoint | `win/src/win/style.w`, proposed `selectors.w`, `css_values.w`, `cascade.w`; W `libs/extras/css/*`; CSS-specific tests | Declaration permutation, fractional/exponent/case units, invalid fallback, inherited values, specificity and syntax recovery regressions pass |
| Agent B — JS core | Define value/property/environment/completion boundaries; begin descriptor/prototype and host-property hooks with preserved ownership/GC | W `libs/extras/javascript/runtime.w`, proposed runtime submodules; runtime tests | Existing execution/GC/limit tests pass; descriptors, receiver-aware operations and host get/set work in a standalone fixture |
| Agent C — conformance harness | Machine-readable W runtime driver, pinned case manifests, result taxonomy, selected CSS native fixture/reftest adapter | New W test/runner files and `tools/javascript_compatibility.py`; new Win harness files, not existing agents' test files | Current failures appear as tracked failures/unsupported results; no syntax-only result is reported as execution success |
| Coordinator | Review contracts, provide mechanical adapter changes in document/script call sites, integrate each checkpoint | `document.w`/`script.w` adapter call sites, docs, root gitlink | CSS and JS branches each integrate independently and the baseline suites stay green |

Before agents start dependent work, freeze the CSS specified/computed-value API, cascade-key comparison API, JS property/host-hook and rooting API, and test-result format. Keep the first JS core checkpoint small; complete environments/calls in Wave 1. Test authors can create fixtures against the agreed contract while implementation is in progress, but must not silently change that contract.

### Wave 1: exploit independent components

| Owner | Work | Prerequisite | Exit criteria |
| --- | --- | --- | --- |
| Agent A — layout | Extract box/fragment geometry from document traversal; correct fixed sizing, inline-block, item generation, intrinsic sizing | Wave 0 computed-style API | Direct flex text survives; hidden children do not consume tracks; fixed-height overflow and block/inline fixtures have correct geometry |
| Agent B — JS environments/calls | Global/function environments, `var`, strictness, references/`this`, completion values and errors | Wave 0 object operations | Selected declaration/function/call/completion Test262 families execute correctly; host-call ownership stays intact |
| Agent C — JS front end | Repair early errors and labels; then add only a declared syntax slice | Own `lexical.w`, `validation.w`, `bindings.w`, `restrictions.w`, grammar, and later `lower.w`/AST/printer with explicit ownership | Regex/module/parameter negatives and chained-label positive cases pass; lowering/execution status is separately recorded |

Agent B and C must agree on AST additions before syntax expansion. CSS selector/state/custom-property work can follow Agent A's layout checkpoint or take a later slot; do not assign a fourth concurrent implementer or overlap edits in `style.w`.

### Wave 2: browser semantics and useful language coverage

| Owner | Work | Prerequisite | Exit criteria |
| --- | --- | --- | --- |
| Agent A — CSS layout algorithms | Flex sizing/alignment/wrapping, then grid sizing/placement; custom properties and broader values in a separate ordered slice | Stable box/intrinsic-size API | Scoped Flexbox/Grid fixture groups pass including mixed text, hidden items, min/max constraints and overflow |
| Agent B — JS built-ins/syntax | Intrinsics, arrays, coercion/operators, arrows/templates/iterators/destructuring in dependency order | Object/environment/call model plus lowerer support | Declared runtime families execute in W; no blanket feature flag based only on parsing |
| Agent C — DOM/CSSOM | Synchronous properties, distinct Window/Document, CSSStyleDeclaration, mutation/resource invalidation and receiver-aware events | Stable host hooks and computed-style API | Same-evaluation parent reads, cssText assignment order, style reads, dynamic stylesheet replacement and event receiver tests pass |

Agent C owns `script.w` and its new DOM/CSSOM modules. Agent A owns layout modules and the layout portion of `document.w`; changes to mutation hooks in that shared file go through the coordinator or a serialized handoff. Any runtime hook extensions needed by DOM are requested from Agent B rather than edited concurrently.

### Wave 3: asynchronous host and module integration

- Agent A owns remaining CSS interaction/conditional/layer slices and visual regressions.
- Agent B owns W module records, Promise jobs and resumable execution primitives, with generators/async layered afterward.
- Agent C owns Win task sources, microtask checkpoints, timers, lifecycle and async/defer scheduling. Parser-blocking scripts wait on an upstream resumable HTML parser. Module resolution waits on W module interfaces.
- The coordinator validates cross-layer ordering: script execution, microtasks, DOM mutations, style/layout updates, events and navigation teardown. Fetch and other host services follow explicit scoped milestones.

These waves are dependency order, not equal-duration sprints. Object semantics, inline formatting, flex/grid and asynchronous execution each need several reviewable increments. Do not estimate completion from source-line count or equate a green local suite with full standards coverage.

### Repository and merge discipline

Reusable CSS syntax and all JavaScript engine changes belong in the W repository; Win owns matching/cascade/layout and browser APIs. W is a git submodule, so engine commits need their own branches and review, followed by a deliberate parent gitlink update. Do not pull W's latest main independently of this plan or duplicate its parser/runtime in Win.

Use isolated worktrees for implementing agents and initialize their dependency checkouts at the agreed pin. Do not share generated `bin/` directories across independently changing grammar/runtime branches. Give each task a base SHA, owned paths, interface dependencies, exact failing examples, required checks and an explicit out-of-scope list. The coordinator integrates W branches and runs its required checks before advancing the application pin, then runs the complete Win suite against that pin.

For W edits, follow [W's agent instructions](../../w/AGENTS.md): structured checks after `.w` edits, manifest-driven test selection, required full `./wbuild tests`, and compiler verification/coverage rules if compiler code is touched. For Win edits, run focused tests during development and `./win/build test` before integration. Add native rendering checks when layout/painting changes. Every implementation slice updates the compatibility matrix with implemented, partial, unsupported and tested boundaries.

Recommended first assignment: execute Wave 0. It fixes existing CSS behavior, creates the shared JS semantics needed by the browser, and establishes honest regression measurements while preserving useful parallelism.
