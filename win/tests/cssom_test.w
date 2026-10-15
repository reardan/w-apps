import lib.assert
import win.script

void cssom_eval(win_script* script, char* source):
	if (win_script_eval(script, source, strlen(source)) == 0):
		println(script.error)
		char* exception = win_js_text(script.runtime.completion.value)
		println(exception)
		free(exception)
		asserts(c"CSSOM script succeeds", 0)

void test_cssom_reflection():
	char* source = c"<main id='parent'><p id='p' style='color:red'><span id='child'>old</span></p><input id='field' value='old'></main>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	cssom_eval(script, c"const p=document.getElementById('p'); const parent=document.getElementById('parent'); const child=document.getElementById('child'); if(p.style.color!=='red') throw 'initial inline read'; child.textContent='new'; if(parent.textContent!=='new') throw 'stale parent'; p.id='changed'; if(p.id!=='changed'||document.getElementById('changed')!==p) throw 'id reflection';")
	cssom_eval(script, c"p.style.color='blue'; p.style.cssText='color:green'; if(p.style.color!=='green'||p.getAttribute('style')!=='color: green;') throw 'assignment order'; p.style.cssText='color:red'; p.style.color='blue'; if(p.style.color!=='blue') throw 'reverse order';")
	cssom_eval(script, c"p.style.width='9px'; p.style.width='.5'; if(p.style.width!=='9px') throw 'invalid overwrite'; p.style.color='bogus'; if(p.style.color!=='blue') throw 'invalid color'; p.style.color='red; width:10px'; if(p.style.color!=='blue') throw 'declaration injection';")
	cssom_eval(script, c"p.style.setProperty('color','red','important'); if(p.style.getPropertyPriority('COLOR')!=='important') throw 'priority'; p.style.setProperty('color','green','invalid'); if(p.style.color!=='red') throw 'invalid priority'; p.style.color='blue'; if(p.style.color!=='blue'||p.style.getPropertyPriority('color')!=='') throw 'priority reset'; if(p.style.removeProperty('color')!=='blue'||p.style.color!=='') throw 'remove';")
	cssom_eval(script, c"p.setAttribute('style','color:green!important;color:blue;unknown:value'); if(p.style.color!=='green'||p.style.cssText!=='color: green !important;') throw 'duplicate priority'; p.style='color:red'; if(p.style.color!=='red') throw 'forward cssText'; child.textContent=null; if(parent.textContent!=='') throw 'null text';")
	cssom_eval(script, c"const field=document.getElementById('field'); field.value='new'; if(field.value!=='new'||field.getAttribute('value')!=='new') throw 'value'; field.checked=true; if(!field.checked) throw 'checked'; document.title='Synchronous'; if(document.title!=='Synchronous') throw 'title';")
	js_runtime_collect(script.runtime)
	cssom_eval(script, c"if(p.style.color!=='red'||window===document||window.document!==document||globalThis!==window) throw 'identity after GC';")
	win_script_free(script)
	win_page_free(page)

win_box* cssom_box(win_page* page, char* id):
	for i in range(page.boxes.length):
		if (strcmp(win_attr(page.boxes[i].node, c"id"), id) == 0): return page.boxes[i]
	return 0

void test_cssom_shorthands():
	char* source = c"<div id='parent' style='width:400px'><div id='box' style='width:100px;height:10px;margin:1px;margin-left:2px!important;padding:1px;padding-left:9px;border:1px solid red;border-width:9px!important'></div></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	cssom_eval(script, c"const box=document.getElementById('box'); if(box.style.getPropertyValue('margin-left')!=='2px'||box.style.margin!==''||box.style.getPropertyPriority('margin')!=='') throw 'mixed priority'; box.style.margin='3px'; box.style.padding='2px 4px'; box.style.border='3px solid blue'; if(box.style.margin!=='3px'||box.style.getPropertyValue('margin-left')!=='3px'||box.style.getPropertyPriority('margin-left')!=='') throw 'shorthand resets longhand'; if(box.style.getPropertyValue('padding-left')!=='4px'||box.style.getPropertyValue('border-width')!=='3px') throw 'shorthand components';")
	win_page_layout(page, 600)
	win_box* parent = cssom_box(page, c"parent")
	win_box* box = cssom_box(page, c"box")
	asserts(c"shorthand assignments replace old longhands in layout", box != 0 && parent != 0 && box.x == parent.x + 3.0 && box.width == 114.0 && box.height == 20.0 && box.border == 3 && box.border_color.b == 1.0)
	cssom_eval(script, c"box.style.setProperty('margin-left','7px'); box.style.setProperty('padding-left','6px'); box.style.setProperty('border-width','5px'); if(box.style.margin!=='3px 3px 3px 7px'||box.style.padding!=='2px 4px 2px 6px'||box.style.border!=='5px solid blue') throw 'longhand updates shorthand reads'; box.style.cssText=box.style.cssText;")
	win_page_layout(page, 600)
	parent = cssom_box(page, c"parent")
	box = cssom_box(page, c"box")
	asserts(c"longhand assignments and cssText roundtrip preserve sibling components", box.x == parent.x + 7.0 && box.width == 120.0 && box.height == 24.0 && box.border == 5)
	cssom_eval(script, c"if(box.style.removeProperty('margin-left')!=='7px'||box.style.margin!==''||box.style.getPropertyValue('margin-top')!=='3px') throw 'remove one component'; if(box.style.removeProperty('padding')!=='2px 4px 2px 6px'||box.style.getPropertyValue('padding-left')!=='') throw 'remove padding'; if(box.style.removeProperty('border')!=='5px solid blue'||box.style.getPropertyValue('border-width')!=='') throw 'remove border';")
	win_page_layout(page, 600)
	parent = cssom_box(page, c"parent")
	box = cssom_box(page, c"box")
	asserts(c"removals clear layout values without reviving older declarations", box.x == parent.x && box.width == 100.0 && box.height == 10.0 && box.border == 0)
	cssom_eval(script, c"box.style.cssText='margin:1px!important;margin-left:2px!important'; if(box.style.margin!=='1px 1px 1px 2px'||box.style.getPropertyPriority('margin')!=='important') throw 'uniform priority'; box.style.setProperty('margin-left','8px'); if(box.style.margin!==''||box.style.getPropertyPriority('margin-top')!=='important'||box.style.getPropertyPriority('margin-left')!=='') throw 'longhand priority reset'; box.style.setProperty('margin','2px 4px','important'); if(box.style.margin!=='2px 4px'||box.style.getPropertyPriority('margin')!=='important') throw 'priority shorthand'; box.style.margin='1px bogus'; if(box.style.margin!=='2px 4px'||box.style.getPropertyPriority('margin')!=='important') throw 'invalid shorthand is atomic'; box.style.setProperty('margin','','invalid'); if(box.style.getPropertyValue('margin-top')!==''||box.style.margin!=='') throw 'empty assignment removes with any priority';")
	cssom_eval(script, c"box.style.cssText='margin-left:9px;margin:1px;margin-left:2px;margin:3px'; if(box.style.margin!=='3px'||box.style.getPropertyValue('margin-left')!=='3px') throw 'source declaration order'; box.style.cssText=box.style.cssText; if(box.style.getPropertyValue('margin-left')!=='3px') throw 'serialized order'; box.style.margin='1em 2em 3em 4em'; if(box.style.getPropertyValue('margin-left')!=='4em') throw 'specified units'; box.style.margin='inherit'; if(box.style.margin!=='inherit'||box.style.getPropertyValue('margin-left')!=='inherit') throw 'wide shorthand'; box.style.setProperty('margin-left','1px'); if(box.style.margin!=='') throw 'mixed wide values';")
	cssom_eval(script, c"box.style.border='solid'; if(box.style.getPropertyValue('border-width')!=='medium'||box.style.getPropertyValue('border-color')!=='currentcolor'||box.style.border!=='medium solid currentcolor') throw 'border resets'; box.style.setProperty('border-color','rgb(0 0 255)'); if(box.style.border!=='medium solid rgb(0 0 255)') throw 'functional border color'; box.style.removeProperty('border-width'); if(box.style.border!==''||box.style.getPropertyValue('border-style')!=='solid') throw 'partial border removal'; box.style.border='initial'; if(box.style.border!=='initial') throw 'wide border';")
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)

void test_stylesheet_mutation():
	char* source = c"<style id='sheet'>p{color:red}</style><p id='p'>word</p>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	cssom_eval(script, c"const sheet=document.getElementById('sheet'); sheet.textContent='p{color:blue}';")
	win_page_layout(page, 600)
	assert_equal(1, page.runs.length)
	asserts(c"mutated stylesheet applies", page.runs[0].color.b > 0.9 && page.runs[0].color.r < 0.1)
	cssom_eval(script, c"sheet.remove();")
	assert_equal(0, page.stylesheets.length)
	cssom_eval(script, c"const fresh=document.createElement('style'); fresh.textContent='p{color:green}'; document.body.appendChild(fresh);")
	win_page_layout(page, 600)
	asserts(c"inserted stylesheet applies", page.runs[0].color.g > 0.49 && page.runs[0].color.b < 0.1)
	cssom_eval(script, c"document.body.appendChild(sheet);")
	win_page_layout(page, 600)
	asserts(c"reinserted stylesheet follows DOM order", page.runs[0].color.b > 0.9)
	win_script_free(script)
	win_page_free(page)

void test_window_and_lifecycle():
	char* source = c"<button id='b'>Go</button>"
	win_page* page = win_page_parse(source, strlen(source))
	win_script* script = win_script_new(page)
	cssom_eval(script, c"let order=''; window.addEventListener('DOMContentLoaded',function(e){if(this!==window||e.target!==document) throw 'window receiver'; order+='w';}); document.addEventListener('DOMContentLoaded',function(e){if(this!==document||document.readyState!=='interactive') throw 'document receiver'; order+='d';}); window.addEventListener('load',function(e){if(this!==window||document.readyState!=='complete') throw 'load receiver'; order+='l';});")
	win_resources* resources = new win_resources()
	resources.entries = new list[win_resource*]
	win_resource* image = new win_resource()
	image.kind = c"image"
	resources.entries.push(image)
	win_script_run_pending(script, resources)
	assert_equal(1, script.dom_ready)
	assert_equal(0, script.ready)
	cssom_eval(script, c"if(order!=='dw') throw order;")
	image.finished = 1
	win_script_run_pending(script, resources)
	cssom_eval(script, c"if(order!=='dwl') throw order;")
	win_script_run_pending(script, resources)
	cssom_eval(script, c"if(order!=='dwl') throw 'duplicate lifecycle';")
	assert_equal(0, script.failures)
	free(image)
	__w_list_free(cast(__w_list*, resources.entries))
	free(resources)
	win_script_free(script)
	win_page_free(page)

int main():
	test_cssom_reflection()
	test_cssom_shorthands()
	test_stylesheet_mutation()
	test_window_and_lifecycle()
	println(c"Win synchronous DOM, CSSOM, stylesheet mutation and lifecycle: OK")
	return 0
