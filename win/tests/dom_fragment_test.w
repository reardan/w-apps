import lib.assert
import win.script

void fragment_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"DOM DocumentFragment semantics", ok)

int main():
	char* source = c"<div id='root'><span id='before'>before</span><span id='after'>after</span></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	fragment_eval(script, c"const root=document.getElementById('root'),before=document.getElementById('before'),after=document.getElementById('after');const f=document.createDocumentFragment();const nodes=f.childNodes;if(f.nodeType!==11||f.nodeName!=='#document-fragment'||f.nodeValue!==null||f.ownerDocument!==document||f.parentNode!==null||nodes.length!==0||f.firstChild!==null||f.lastChild!==null||f.textContent!=='')throw 'fragment fields';const a=document.createElement('b'),b=document.createTextNode('text');a.textContent='a';if(f.appendChild(a)!==a||f.appendChild(b)!==b||nodes.length!==2||nodes[0]!==a||nodes[1]!==b||a.parentNode!==f||f.textContent!=='atext')throw 'fragment children';")
	fragment_eval(script, c"let seen=0;a.addEventListener('saved',function(){seen++;});if(root.insertBefore(f,after)!==f||f.parentNode!==null||f.firstChild!==null||f.lastChild!==null||nodes.length!==0||before.nextSibling!==a||a.nextSibling!==b||b.nextSibling!==after||a.parentNode!==root||b.parentNode!==root)throw 'splice middle';a.dispatchEvent(new Event('saved'));if(seen!==1)throw 'wrapper listener identity';if(root.appendChild(f)!==f||root.lastChild!==after)throw 'empty splice';f.appendChild(a);f.appendChild(b);root.insertBefore(f,before);if(root.firstChild!==a||b.nextSibling!==before||f.firstChild!==null)throw 'splice first';f.appendChild(a);f.appendChild(b);root.appendChild(f);if(root.lastChild!==b||after.nextSibling!==a||b.nextSibling!==null)throw 'splice last';")
	fragment_eval(script, c"const outer=document.createDocumentFragment(),inner=document.createDocumentFragment();inner.appendChild(a);inner.appendChild(b);if(outer.appendChild(inner)!==inner||inner.childNodes.length!==0||outer.childNodes.length!==2||a.parentNode!==outer)throw 'fragment into fragment';let invalid=0;try{outer.appendChild(outer);}catch(e){if(e.name==='HierarchyRequestError')invalid++;}try{a.appendChild(outer);}catch(e){if(e.name==='HierarchyRequestError')invalid++;}try{root.insertBefore(outer,inner);}catch(e){if(e.name==='NotFoundError')invalid++;}try{root.removeChild(outer);}catch(e){if(e.name==='NotFoundError')invalid++;}try{outer.appendChild(document);}catch(e){if(e.name==='HierarchyRequestError')invalid++;}if(invalid!==5||outer.childNodes.length!==2||outer.firstChild!==a||outer.lastChild!==b||a.parentNode!==outer)throw 'atomic invalid fragment';const create=document.createDocumentFragment;let receiver=false;try{create();}catch(e){receiver=true;}if(!receiver)throw 'creation receiver';window.fragmentRoot=root;window.fragmentValue=outer;")
	# Reserve traversal/list budget before emptying a fragment or moving a child.
	js_runtime* rt = script.runtime
	js_value* window = js_runtime_get(rt, rt.global, c"window")
	js_value* target = js_runtime_get(rt, window, c"fragmentRoot")
	js_value* fragment = js_runtime_get(rt, window, c"fragmentValue")
	win_dom_binding* binding = 0
	for i in range(script.bindings.length):
		if (script.bindings[i].object == target): binding = script.bindings[i]
	list[js_value*] args = new list[js_value*]
	args.push(fragment)
	rt.remaining = script.bindings.length + 2
	win_dom_tree_mutate(binding, target, args, 0)
	assert_equal(5, rt.completion.status)
	__w_list_free(cast(__w_list*, args))
	fragment_eval(script, c"if(outer.childNodes.length!==2||outer.firstChild!==a||a.parentNode!==outer||root.firstChild!==before||root.lastChild!==after)throw 'budget atomicity';root.appendChild(outer);if(a.parentNode!==root||outer.childNodes.length!==0)throw 'recovery';outer.appendChild(a);if(outer.removeChild(a)!==a||a.parentNode!==null||outer.lastChild!==null)throw 'fragment remove';")
	win_script_free(script)
	win_page_free(page)
	println(c"Win DocumentFragment identity, splicing, hierarchy and atomic limits: OK")
	return 0
