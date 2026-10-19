import lib.assert
import win.script

void collection_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"live getElementsByTagName semantics", ok)

void collection_quota_retry(win_script* script, win_dom_binding* binding, char* name, int allowance):
	js_runtime* rt = script.runtime
	list[js_value*] args = new list[js_value*]
	args.push(win_js_string(rt, name))
	int values = rt.max_values
	int properties = rt.max_properties
	int roots = rt.roots.length
	int bytes = script.dom_bytes
	void* previous = binding.collections
	if (allowance >= 0): rt.max_values = rt.heap.length + allowance
	else: rt.max_properties = 1
	rt.remaining = 100000
	win_dom_get_elements_by_tag(rt, binding, binding.object, args)
	assert_equal(5, rt.completion.status)
	asserts(c"failed collection never published", binding.collections == previous)
	assert_equal(bytes, script.dom_bytes)
	assert_equal(roots, rt.roots.length)
	rt.max_values = values
	rt.max_properties = properties
	rt.completion.status = 0
	rt.completion.value = rt.undefined_value
	rt.remaining = 100000
	js_value* retry = win_dom_get_elements_by_tag(rt, binding, binding.object, args)
	assert_equal(0, rt.completion.status)
	assert_equal(5, retry.kind)
	asserts(c"successful retry publishes owner", binding.collections != previous)
	asserts(c"successful retry cached", retry == win_dom_get_elements_by_tag(rt, binding, binding.object, args))
	assert_equal(roots + 1, rt.roots.length)
	__w_list_free(cast(__w_list*, args))

int main(int argc, char** argv):
	int guarded = argc == 2 && strcmp(argv[1], c"memory") == 0
	if (guarded):
		malloc_force_debug_mode()
		char* minimal = c"<span id='owned'>owned</span>"
		win_page* owned_page = win_page_parse(minimal, strlen(minimal))
		win_script* owned_script = win_script_new(owned_page)
		collection_eval(owned_script, c"let saved=document.getElementsByTagName('span');if(saved.length!==1||saved.namedItem('owned')!==saved[0])throw 'lifetime';")
		win_script_free(owned_script)
		win_page_free(owned_page)
		assert_equal(0, debug_alloc_report_leaks())
		println(c"Win live HTML collection guarded ownership: OK")
		return 0
	char* source = c"<html><head><title>Collection</title><meta name='timeout' content='long'></head><body><section id='root'><span id='a' name='shared'>a<b id='nested'>nested</b></span><span id='b' name='shared'>b</span></section><span id='outside'>outside</span></body></html>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	collection_eval(script, c"const root=document.getElementById('root'),a=document.getElementById('a'),b=document.getElementById('b'),nested=document.getElementById('nested'),outside=document.getElementById('outside');const spans=root.getElementsByTagName('SPAN');const all=root.getElementsByTagName('*');if(spans!==root.getElementsByTagName('span')||spans.length!==2||spans[0]!==a||spans[1]!==b||spans[2]!==undefined||spans.item(2)!==null||spans.item(-1)!==null||spans.item(4294967296)!==a)throw 'indices';if(all.length!==3||all[0]!==a||all[1]!==nested||all[2]!==b||root.getElementsByTagName('section').length!==0||document.getElementsByTagName('span').length!==3)throw 'descendants preorder';if(document.getElementsByTagName('meta')[0].getAttribute('content')!=='long'||document.getElementsByTagName('title')[0].textContent!=='Collection')throw 'WPT harness lookups';")
	collection_eval(script, c"if(spans.namedItem('shared')!==a||spans.shared!==a||spans.a!==a||spans.namedItem('b')!==b||spans.namedItem('')!==null||spans.namedItem('absent')!==null||spans.absent!==undefined||!('a' in spans)||!('1' in spans)||('2' in spans)||!('length' in spans)||!('item' in spans))throw 'named properties';spans.length=99;spans[0]=b;spans.shared=b;if(spans.length!==2||spans[0]!==a||spans.shared!==a)throw 'readonly';root.removeChild(a);if(spans.length!==1||spans[0]!==b||all.length!==1||spans.shared!==b||('a' in spans))throw 'live removal';root.appendChild(a);if(spans[0]!==b||spans[1]!==a||all[2]!==nested)throw 'live reorder';a.setAttribute('id','renamed');a.setAttribute('name','newname');if(spans.a!==undefined||spans.renamed!==a||spans.newname!==a)throw 'live attributes';")
	collection_eval(script, c"const f=document.createDocumentFragment();f.appendChild(root);if(spans.length!==2||all.length!==3||document.getElementsByTagName('span').length!==1)throw 'detached root';root.insertBefore(outside,b);if(spans.length!==3||spans[0]!==outside||document.getElementsByTagName('span').length!==0)throw 'move across scopes';document.body.appendChild(f);if(document.getElementsByTagName('span').length!==3||spans[0]!==outside)throw 'reinsert root';const collision=document.createElement('span');collision.setAttribute('id','item');root.appendChild(collision);if(typeof spans.item!=='function'||spans.namedItem('item')!==collision)throw 'builtin collision';const getter=root.getElementsByTagName;const item=spans.item;let rejected=0;try{getter('span');}catch(e){rejected++;}try{item(0);}catch(e){rejected++;}try{root.getElementsByTagName();}catch(e){rejected++;}if(rejected!==3)throw 'receivers';window.collectionRoot=root;")
	# Exhausted reads preserve collection ownership and are recoverable next entry.
	js_value* window = js_runtime_get(script.runtime, script.runtime.global, c"window")
	js_value* root_value = js_runtime_get(script.runtime, window, c"collectionRoot")
	win_dom_binding* binding = 0
	for i in range(script.bindings.length):
		if (script.bindings[i].object == root_value): binding = script.bindings[i]
	win_dom_collection* collection = cast(win_dom_collection*, binding.collections)
	int count = 0
	script.runtime.remaining = 1
	win_dom_collection_scan(collection, -1, 0, &count)
	assert_equal(5, script.runtime.completion.status)
	collection_eval(script, c"if(spans.length!==4||spans[0]!==outside||spans.namedItem('renamed')!==a)throw 'read budget recovery';")
	collection_quota_retry(script, binding, c"quota-first", 0)
	collection_quota_retry(script, binding, c"quota-method", 1)
	collection_quota_retry(script, binding, c"quota-second-method", 2)
	collection_quota_retry(script, binding, c"quota-property", -1)
	collection_eval(script, c"if(root.getElementsByTagName('quota-first').length!==0||spans.length!==4)throw 'quota cache recovery';")
	win_script_free(script)
	win_page_free(page)
	println(c"Win live HTML collections, named lookup, ownership and traversal bounds: OK")
	return 0
