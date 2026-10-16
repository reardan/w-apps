# Bounded HTML DOM tree APIs

Node wrappers expose live `parentNode`, `firstChild`, `lastChild`, `nextSibling`,
`ownerDocument`, `nodeType`, `nodeName`, and `nodeValue`. HTML elements additionally
expose `tagName`, `localName` and the HTML `namespaceURI`. Document's
`documentElement`, `head` and `body` getters follow the current tree. Text nodes
support `data` and nullable `nodeValue` writes. Scalar UTF-8 without NUL is the
current backing representation; unsupported string/object conversions fail.

`childNodes` returns one stable, live, non-Array object per wrapper. Its numeric
indices, length, `item(number)` and property-presence checks read the current tree;
length and index assignments cannot modify the tree. Iterators, forEach and full
own-key/descriptor reflection are not implemented for this host collection.

Element `appendChild`/`insertBefore` and Node `removeChild` preserve wrapper and
listener identity. They reject cycles and invalid reference/child relationships,
and charge ancestry/subtree/list scans before changing either tree. Depth remains
bounded at 128. Detached nodes remain owned by the document until realm teardown.
The direct tests cover first/last/middle moves, insertion before self, detached
nodes, live collections, invalid references, cycles, listener identity, stylesheet
invalidation, and failure atomicity under exhausted execution fuel.

Document creation supports `createElement`, HTML-namespace `createElementNS`, and
`createTextNode`. Element names are limited to unprefixed ASCII names starting
with a letter and then letters, digits, `-`, `_` or `.`. Ordinary createElement
lowercases ASCII names; createElementNS preserves case. Other namespaces,
customized built-ins, fragments, cross-document adoption, comment mutation,
Document child insertion and full Web IDL conversions remain unsupported.

The algorithms follow the [DOM Standard](https://dom.spec.whatwg.org/#interface-node)
and [pre-insert validity](https://dom.spec.whatwg.org/#concept-node-pre-insert),
within those explicit limits. Existing script, replaceChildren, CSSOM, focus and
Event regressions pass. The combined guard-allocator run hit this environment's
VMA/bookkeeping limit, so it supplies no passing guarded-lifetime evidence.
