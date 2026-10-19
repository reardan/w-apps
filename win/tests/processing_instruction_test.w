import lib.assert
import win.script

void instruction_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"processing instruction DOM integration", ok)

int main():
	char* source = c"<?Before keep?><!doctype html><html><head><?Head data?></head><body><div id='content'>a<?In Data?>b</div></body></html><?After tail?>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	instruction_eval(script, c"const before=document.firstChild,after=document.lastChild,content=document.getElementById('content'),pi=content.childNodes[1];if(before.nodeType!==7||before.nodeName!=='Before'||before.target!=='Before'||before.data!=='keep'||before.nodeValue!=='keep'||before.textContent!=='keep'||before.childNodes.length!==0||before.ownerDocument!==document)throw 'PI fields';if(document.documentElement.nodeName!=='HTML'||document.head.firstChild.target!=='Head'||after.target!=='After'||after.data!=='tail')throw 'PI placement';if(pi.nodeType!==7||pi.target!=='In'||pi.data!=='Data'||content.childNodes.length!==3||content.textContent!=='ab')throw 'PI inert text';")
	instruction_eval(script, c"pi.nodeValue='changed';if(pi.data!=='changed'||pi.textContent!=='changed')throw 'nodeValue';pi.data='next';if(pi.nodeValue!=='next'||pi.firstChild!==null||pi.lastChild!==null)throw 'leaf data';pi.textContent=null;if(pi.data!==''||pi.nodeValue!=='')throw 'null text';pi.data='x\\u0000y';if(pi.data.length!==3||pi.nodeValue.charCodeAt(1)!==0||pi.textContent.charCodeAt(2)!==121)throw 'PI NUL';pi.data='saved';const fragment=document.createDocumentFragment();fragment.appendChild(pi);if(pi.parentNode!==fragment||fragment.textContent!==''||content.textContent!=='ab')throw 'PI fragment move';content.appendChild(fragment);if(content.lastChild!==pi||pi.ownerDocument!==document||pi.target!=='In'||fragment.firstChild!==null)throw 'PI stable identity';window.pi=pi;")
	js_runtime_collect(script.runtime)
	instruction_eval(script, c"if(pi.data!=='saved'||pi.target!=='In'||content.textContent!=='ab')throw 'PI lifetime';")
	# Character data remains atomic when the existing mutation byte cap refuses it.
	int bytes = script.dom_bytes
	script.dom_bytes = 4194304
	assert_equal(0, win_script_eval(script, c"pi.data='refused';", 18))
	assert_equal(5, script.runtime.completion.status)
	script.dom_bytes = bytes
	instruction_eval(script, c"if(pi.data!=='saved'||pi.firstChild!==null||pi.target!=='In')throw 'PI quota atomicity';")
	win_page_layout(page, 800)
	for i in range(page.runs.length):
		asserts(c"processing instructions do not produce rendered runs", page.runs[i].node.kind != HTML_PROCESSING_INSTRUCTION)
	win_script_free(script)
	win_page_free(page)
	# The tokenizer's PI data span may contain a literal NUL and outlives input.
	char* raw = strclone(c"<div><?T a_b?></div>")
	int length = strlen(raw)
	for i in range(length):
		if (raw[i] == '_'): raw[i] = 0
	page = win_page_parse(raw, length)
	free(raw)
	script = win_script_new(page)
	instruction_eval(script, c"const instruction=document.body.firstChild.firstChild;if(instruction.target!=='T'||instruction.data.length!==3||instruction.data.charCodeAt(0)!==97||instruction.data.charCodeAt(1)!==0||instruction.nodeValue.charCodeAt(2)!==98||instruction.textContent.length!==3)throw 'source PI NUL span';")
	win_script_free(script)
	win_page_free(page)
	println(c"Processing instruction native DOM identity, leaf data, inert text/layout and atomic limits: OK")
	return 0
