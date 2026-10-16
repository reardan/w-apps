import lib.assert
import win.script

void replace_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"Element.replaceChildren", ok)

int main():
	char* html = c"<body><div id='container'><span id='old'>old</span></div><div id='elsewhere'><span id='a'>A</span><span id='b'>B</span></div></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	replace_eval(script, c"const container=document.getElementById('container'); const old=document.getElementById('old'); const elsewhere=document.getElementById('elsewhere'); const a=document.getElementById('a'); const b=document.getElementById('b'); const fragment=document.createElement('div'); fragment.textContent='replacement'; container.replaceChildren(fragment); if(container.textContent!=='replacement' || document.getElementById('old')!==null || old.textContent!=='old') throw 'replace identity';")
	replace_eval(script, c"container.replaceChildren(); if(container.textContent!=='' || fragment.textContent!=='replacement') throw 'empty replacement'; container.replaceChildren('start',a,'/',b,7,null,undefined,true); if(container.textContent!=='startA/B7nullundefinedtrue' || elsewhere.textContent!=='') throw 'variadic node and string';")
	replace_eval(script, c"container.replaceChildren(a,b,a); if(container.textContent!=='BA' || container.querySelector('span')!==b) throw 'duplicate node order'; let hits=0; a.addEventListener('saved',function(){hits+=1;}); container.replaceChildren(b); if(document.getElementById('a')!==null) throw 'detached'; container.replaceChildren(a); a.dispatchEvent(new Event('saved')); if(hits!==1 || container.querySelector('span')!==a) throw 'retained listeners';")
	replace_eval(script, c"let errors=0; try {container.replaceChildren(container);} catch(e) {if(e.name==='HierarchyRequestError') errors+=1;} try {container.replaceChildren(document);} catch(e) {if(e.name==='HierarchyRequestError') errors+=1;} try {a.replaceChildren(container);} catch(e) {if(e.name==='HierarchyRequestError') errors+=1;} if(errors!==3 || container.textContent!=='A') throw 'hierarchy';")
	replace_eval(script, c"const nested=document.createElement('div'); const child=document.createElement('span'); child.textContent='nested'; nested.appendChild(child); container.replaceChildren(nested,child); if(container.textContent!=='nested' || nested.textContent!=='' || container.querySelector('span')!==child) throw 'moving descendant';")
	replace_eval(script, c"const detached=document.createElement('div'); detached.replaceChildren(old,'end'); if(detached.textContent!=='oldend' || document.getElementById('old')!==null) throw 'detached parent'; const replace=detached.replaceChildren; let caught=false; try {replace('wrong receiver');} catch(e) {caught=true;} if(!caught || detached.textContent!=='oldend') throw 'receiver';")
	replace_eval(script, c"const style=document.createElement('style'); style.textContent='#container{padding:7px}'; container.replaceChildren(style); if(getComputedStyle(container).paddingLeft!=='7px') throw 'stylesheet insertion'; container.replaceChildren(); if(getComputedStyle(container).paddingLeft==='7px') throw 'stylesheet removal';")
	assert_equal(0, script.failures)
	# A terminal allocation refusal must happen before detaching old children.
	replace_eval(script, c"container.replaceChildren('kept');")
	string_builder* excessive = string_from(c"container.replaceChildren('")
	for i in range(65537): string_append_char(excessive, 'x')
	string_append(excessive, c"');")
	assert_equal(0, win_script_eval(script, excessive.data, excessive.length))
	assert_equal(5, script.runtime.completion.status)
	string_free(excessive)
	replace_eval(script, c"if(container.textContent!=='kept') throw 'allocation refusal changed target';")
	win_script_free(script)
	win_page_free(page)
	println(c"Win Element.replaceChildren identity, ordering and hierarchy: OK")
	return 0
