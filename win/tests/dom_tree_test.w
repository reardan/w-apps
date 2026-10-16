import lib.assert
import win.script

void tree_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"DOM tree semantics", ok)

int main():
	char* source = c"<!doctype html><html><head><title>Tree</title></head><body><div id='root'><span id='a'>A</span><span id='b'>B</span></div><div id='other'></div></body></html>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	tree_eval(script, c"const root=document.getElementById('root');const a=document.getElementById('a');const b=document.getElementById('b');const other=document.getElementById('other');if(document.nodeType!==9||document.nodeName!=='#document'||document.ownerDocument!==null||document.parentNode!==null)throw 'document';if(document.documentElement!==document.querySelector('html')||document.head!==document.querySelector('head')||document.body!==document.querySelector('body'))throw 'document elements';if(root.nodeType!==1||root.nodeName!=='DIV'||root.tagName!=='DIV'||root.localName!=='div'||root.namespaceURI!=='http://www.w3.org/1999/xhtml'||root.ownerDocument!==document)throw 'element names';if(root.parentNode!==document.body||root.firstChild!==a||root.lastChild!==b||a.nextSibling!==b||b.nextSibling!==null)throw 'tree links';")
	tree_eval(script, c"const nodes=root.childNodes;if(nodes!==root.childNodes||nodes.length!==2||nodes[0]!==a||nodes[1]!==b||nodes[2]!==undefined||nodes.item(2)!==null||nodes.item(0)!==a||Array.isArray(nodes))throw 'live collection';nodes.length=99;nodes[0]=b;if(nodes.length!==2||nodes[0]!==a)throw 'readonly collection';if(other.appendChild(a)!==a||nodes.length!==1||nodes[0]!==b||a.parentNode!==other)throw 'move';if(root.insertBefore(a,b)!==a||nodes.length!==2||nodes[0]!==a||nodes[1]!==b||other.firstChild!==null)throw 'insert';root.insertBefore(a,a);if(nodes[0]!==a||a.nextSibling!==b)throw 'insert self';root.insertBefore(a,null);if(nodes[0]!==b||nodes[1]!==a||a.nextSibling!==null||root.lastChild!==a)throw 'insert append';root.insertBefore(b,a);if(nodes[0]!==b||nodes[1]!==a)throw 'adjacent';if(root.removeChild(b)!==b||b.parentNode!==null||b.nextSibling!==null||nodes.length!==1||root.firstChild!==a||root.lastChild!==a)throw 'remove';")
	tree_eval(script, c"let errors=0;try{root.removeChild(b);}catch(e){if(e.name==='NotFoundError')errors++;}try{root.insertBefore(b,other);}catch(e){if(e.name==='NotFoundError')errors++;}try{root.appendChild(root);}catch(e){if(e.name==='HierarchyRequestError')errors++;}try{a.appendChild(root);}catch(e){if(e.name==='HierarchyRequestError')errors++;}try{root.appendChild(document);}catch(e){if(e.name==='HierarchyRequestError')errors++;}try{a.firstChild.appendChild(b);}catch(e){if(e.name==='HierarchyRequestError')errors++;}if(errors!==6||root.firstChild!==a||a.parentNode!==root||b.parentNode!==null)throw 'atomic hierarchy';")
	tree_eval(script, c"const text=document.createTextNode('A😀');if(text.nodeType!==3||text.nodeName!=='#text'||text.data!=='A😀'||text.nodeValue!=='A😀'||text.textContent!=='A😀'||text.ownerDocument!==document||text.parentNode!==null||text.childNodes.length!==0)throw 'text';root.appendChild(text);text.data='Bé';if(root.textContent!=='ABé'||text.nodeValue!=='Bé')throw 'data write';text.nodeValue=null;if(text.data!=='')throw 'nullable nodeValue';text.data=null;if(text.data!=='null')throw 'data conversion';text.nodeValue=42;if(text.data!=='42')throw 'primitive conversion';root.nodeValue='ignored';if(root.nodeValue!==null||root.textContent!=='A42')throw 'element nodeValue';")
	tree_eval(script, c"const upper=document.createElement('ARTICLE');const ns=document.createElementNS('http://www.w3.org/1999/xhtml','section');if(upper.localName!=='article'||upper.tagName!=='ARTICLE'||ns.localName!=='section')throw 'creation';let invalid=false;try{document.createElement('bad name');}catch(e){invalid=e.name==='InvalidCharacterError';}if(!invalid)throw 'invalid name';let receiver=false;const insert=root.insertBefore;try{insert(b,null);}catch(e){receiver=true;}if(!receiver)throw 'receiver';const head=document.head;document.documentElement.removeChild(head);if(document.head!==null||head.ownerDocument!==document)throw 'live head';document.documentElement.insertBefore(head,document.body);if(document.head!==head)throw 'restore head';")
	tree_eval(script, c"let calls=0;a.addEventListener('saved',function(){calls++;});root.removeChild(a);root.appendChild(a);a.dispatchEvent(new Event('saved'));if(calls!==1)throw 'identity listeners';const style=document.createElement('style');style.textContent='#root{padding:9px}';root.insertBefore(style,root.firstChild);if(getComputedStyle(root).paddingLeft!=='9px')throw 'insert styles';root.removeChild(style);if(getComputedStyle(root).paddingLeft==='9px')throw 'remove styles';")
	assert_equal(0, script.failures)
	# Exhaustion is checked before removing the child from its existing parent.
	js_value* root = js_runtime_get(script.runtime, script.runtime.global, c"root")
	# Top-level lexical declarations are not global object properties: use a host-visible alias.
	tree_eval(script, c"window.treeRoot=root;window.treeOther=other;window.treeA=a;")
	js_value* window = js_runtime_get(script.runtime, script.runtime.global, c"window")
	root = js_runtime_get(script.runtime, window, c"treeRoot")
	js_value* target = js_runtime_get(script.runtime, window, c"treeOther")
	js_value* child = js_runtime_get(script.runtime, window, c"treeA")
	win_dom_binding* binding = 0
	for i in range(script.bindings.length):
		if (script.bindings[i].object == target): binding = script.bindings[i]
	list[js_value*] args = new list[js_value*]
	args.push(child)
	script.runtime.remaining = script.bindings.length + 3
	win_dom_tree_mutate(binding, target, args, 0)
	assert_equal(5, script.runtime.completion.status)
	__w_list_free(cast(__w_list*, args))
	tree_eval(script, c"if(a.parentNode!==root||other.firstChild!==null)throw 'budget atomicity';")
	win_script_free(script)
	win_page_free(page)
	println(c"Win HTML DOM tree identity, live children, mutation and atomic failures: OK")
	return 0
