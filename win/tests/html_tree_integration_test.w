import lib.assert
import win.script

void tree_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"HTML tree integration", ok)

int main():
	char* source = c"<!doctype html><html><head><title>tree</title></head><body><p id='p'>one<div id='d'>two&amp;three</div>tail<ul><li id='a'>a<li id='b'>b</ul></body></html>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	tree_eval(script, c"if(document.childNodes.length!==2||document.firstChild.nodeType!==10||document.lastChild!==document.documentElement||document.documentElement.nodeType!==1)throw 'doctype/document element';if(document.head.parentNode!==document.documentElement||document.body.parentNode!==document.documentElement||document.head.nextSibling!==document.body)throw 'head/body identity';")
	tree_eval(script, c"const p=document.getElementById('p'),d=document.getElementById('d'),a=document.getElementById('a'),b=document.getElementById('b');if(p.parentNode!==document.body||p.nextSibling!==d||p.textContent!=='one'||d.textContent!=='two&three'||d.childNodes.length!==1||d.firstChild.nodeType!==3||d.nextSibling.nodeValue!=='tail')throw 'implied paragraph and text coalescing';if(a.parentNode!==b.parentNode||a.nextSibling!==b||a.textContent!=='a'||b.textContent!=='b')throw 'implied list item';")
	win_script_free(script)
	win_page_free(page)
	# Win is a scripting-enabled document host; noscript markup stays inert text.
	source = c"<head><noscript id='head-no'><meta name='x'></noscript></head><body><noscript id='body-no'><b id='absent'>fallback</b></noscript><p id='visible'>shown</p>"
	page = win_page_parse(source, strlen(source))
	script = win_script_new(page)
	tree_eval(script, c"const headNo=document.getElementById('head-no'),bodyNo=document.getElementById('body-no');if(headNo.parentNode!==document.head||bodyNo.parentNode!==document.body||headNo.firstChild.nodeType!==3||bodyNo.firstChild.nodeType!==3||document.getElementById('absent')!==null||bodyNo.textContent!==\"<b id='absent'>fallback</b>\")throw 'scripting enabled noscript';")
	win_page_layout(page, 800)
	for i in range(page.runs.length):
		asserts(c"scripting-enabled fallback does not render", win_tag(page.runs[i].node, c"noscript") == 0)
	win_script_free(script)
	win_page_free(page)
	println(c"HTML doctype, implied closures and text identity through native DOM: OK")
	return 0
