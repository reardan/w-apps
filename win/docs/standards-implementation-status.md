# Standards implementation checkpoint

Work paused at the user's shutdown request. This is an incomplete draft of the
[standards implementation plan](standards-gap-analysis.md), not a completed roadmap.

## Saved implementation

- CSS now uses structured specificity/cascade keys and validated specified
  declarations, resolving font-relative values after selecting winners. Numeric
  lengths retain fractions, exponent syntax and case-insensitive units. The
  foundation also corrects selector state, invalid-value fallback, media grammar,
  inheritance/defaulting and upstream syntax metadata/recovery.
- W adds descriptors/prototypes, receiver-aware calls, synchronous host get/set
  hooks, typed errors, completion handling, `var` environments, `typeof`, and
  named-function binding corrections. Parser changes address scoped regex
  structure, module exports, parameter early errors and chained labels.
- A native conformance runner actually executes W, with pinned fixtures and
  explicit expected failures. It is not a complete Test262 harness.
- Win uses native property hooks for synchronous DOM reads/writes, ordered inline
  style mutation and reads, and basic CSSStyleDeclaration methods. Stylesheet
  text/tree mutations reconcile the active sheets. Window and Document are
  distinct wrappers; event calls preserve receivers. DOMContentLoaded no longer
  waits for an unrelated pending image before load.

The W dependency is published on `standards/integration`, commit `2673375a`, in
[draft W PR #647](https://github.com/reardan/w/pull/647). The application gitlink
references that published commit. All agent work was committed and integrated;
the last layout checkpoint is included explicitly as unvalidated WIP. It adds
generated items, intrinsic sizing helpers, initial row-flex shrinking, fixed-height
flow extent and visible-overflow page height. Inline-block remains deferred.

## Validation at shutdown

- CSS agent: full Win suite passed before the DOM integration; focused W CSS
  tests passed on both x86 and x64.
- Runtime agent: structured checks and four runtime suites passed, including
  their memory/ownership runs. One debug allocator run emitted a guard-page
  installation diagnostic while its leak checks and assertions still passed.
- Parser/harness agent: focused parser, validation, binding, restriction and new
  early-error tests passed. In that isolated branch, the conformance gate reported
  13 PASS and 9 XFAIL, plus seven runner-contract tests passing.
- Root: the new Win CSSOM/DOM mutation/lifecycle suite passed against the first
  runtime foundation and CSS integration. Structured checking passed.
- The layout WIP passed a structured x64 check only. Its execution and regression
  tests remain outstanding.
- Combined full W and Win suites have **not** been run on the final checkpoint.
  Do not treat the individual results as validation of the final combined tree.

## Resume here

1. Reconcile the conformance ledger with the runtime improvements. Fixed cases
   currently retain old XFAIL entries and should become ordinary expected passes;
   do not weaken the gate's XPASS or changed-failure checks.
2. Run the new CSSOM suite against the final dependency. Update the legacy
   `script_test.w` assertion that expects unspaced, unterminated inline-style
   serialization; prefer asserting the CSSOM property value. Review shorthand
   interactions and document the current limited serialization surface.
3. Review DOM hook ownership/budgets, dynamic stylesheet handling, Window event
   behavior, and separate lifecycle readiness before extending resource scheduling.
4. Add and run layout regressions for anonymous text, hidden items, intrinsic
   sizing, flex shrinking and fixed-height overflow. Follow W's structured checks and manifest-based test selection, then run its
   required `./wbuild tests`. Run `./win/build test` and relevant rendering checks.
5. Update the existing compatibility documents, which still describe parts of the
   old snapshot/property and integer-length behavior. Resolve integration failures
   before marking either PR ready for review.
6. Resume the plan's dependent work: formatting boxes/intrinsic sizing and actual
   flex/grid algorithms, more complete ECMAScript environments/built-ins,
   CSSOM/DOM interfaces, then asynchronous scheduling/modules. These remain open.

Agents used isolated worktrees under `/tmp/w-apps-standards-css`,
`/tmp/w-standards-runtime`, and `/tmp/w-standards-conformance`. Their committed
checkpoints are incorporated into the application and W draft branches; resuming
does not depend on those temporary directories or generated binaries.
