import lib.assert
import win.script

int script_eval(win_script* script, char* text):
	int result = win_script_eval(script, text, strlen(text))
	if (result == 0): print(script.error)
	return result

html_node* script_node(win_script* script, char* id):
	list[html_node*] found = new list[html_node*]
	win_dom_query(script, script.page.html.root, id, 1, found)
	html_node* result = 0
	if (found.length > 0): result = found[0]
	__w_list_free(cast(__w_list*, found))
	return result

void main():
	char* html = c"<title>Before</title><div id='parent'><p id='message' class='note'>before</p><button id='button'>Go</button><input id='field' value='initial'></div>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	assert_equal(0, script.failures)
	asserts(c"DOM mutation", script_eval(script, c"const message=document.getElementById('message'); message.textContent='after'; message.className='changed'; document.title='After';"))
	char* text = win_dom_text(script_node(script, c"message"))
	assert_strings_equal(c"after", text)
	free(text)
	assert_strings_equal(c"After", page.title)
	assert_strings_equal(c"changed", win_attr(script_node(script, c"message"), c"class"))
	asserts(c"selectors and wrapper identity", script_eval(script, c"if(document.querySelector('#parent > .changed') !== message) throw 'identity'; if(document.querySelectorAll('input').length !== 1) throw 'query'; message.setAttribute('data-test','yes'); if(message.getAttribute('data-test') !== 'yes') throw 'attribute';"))
	asserts(c"style and classes", script_eval(script, c"message.style.color='red'; message.style.fontSize='24px'; message.classList.add('active'); if(!message.classList.contains('active')) throw 'class add'; message.classList.toggle('active'); if(message.classList.contains('active')) throw 'class toggle';"))
	asserts(c"style attributes applied", ends_with(win_attr(script_node(script, c"message"), c"style"), c"font-size:24px"))
	asserts(c"node insertion", script_eval(script, c"const added=document.createElement('p'); added.id='added'; added.textContent='new node'; document.body.appendChild(added);"))
	asserts(c"inserted discoverable", script_node(script, c"added") != 0)
	asserts(c"event binding", script_eval(script, c"let clicks=0; const button=document.getElementById('button'); button.addEventListener('click',function(event){clicks=clicks+1; message.textContent='clicked'; event.preventDefault();}); document.getElementById('parent').addEventListener('click',function(event){message.setAttribute('data-bubble','yes');});"))
	assert_equal(0, win_script_dispatch(script, script_node(script, c"button"), c"click"))
	text = win_dom_text(script_node(script, c"message"))
	assert_strings_equal(c"clicked", text)
	free(text)
	assert_strings_equal(c"yes", win_attr(script_node(script, c"message"), c"data-bubble"))
	asserts(c"event closure survived collection", script_eval(script, c"if(clicks !== 1) throw 'click count';"))
	win_dom_set_attr(script_node(script, c"field"), c"value", c"typed")
	asserts(c"input handler", script_eval(script, c"document.getElementById('field').addEventListener('input',function(event){message.textContent=event.target.value;});"))
	assert_equal(1, win_script_dispatch(script, script_node(script, c"field"), c"input"))
	text = win_dom_text(script_node(script, c"message"))
	assert_strings_equal(c"typed", text)
	free(text)
	asserts(c"inline handler setup", script_eval(script, c"document.getElementById('field').setAttribute('onchange','document.title=\"Inline\"; return false;'); console.log('recorded');"))
	assert_equal(0, win_script_dispatch(script, script_node(script, c"field"), c"change"))
	assert_strings_equal(c"Inline", page.title)
	assert_equal(1, script.console.length)
	assert_strings_equal(c"recorded", script.console[0])
	asserts(c"ready handler", script_eval(script, c"document.addEventListener('DOMContentLoaded',function(event){document.title='Ready';});"))
	win_script_ready(script)
	assert_strings_equal(c"Ready", page.title)
	asserts(c"execution budget stops loop", win_script_eval(script, c"while(true){}", 13) == 0)
	asserts(c"later scripts survive error", script_eval(script, c"document.title='Recovered';"))
	assert_strings_equal(c"Recovered", page.title)
	script.dom_bytes = 4194304
	asserts(c"DOM allocation budget", win_script_eval(script, c"message.textContent='limited';", 30) == 0)
	win_script_free(script)
	win_page_free(page)
	# Independent page realms never see another tab's lexical bindings.
	page = win_page_parse(c"<p>Second</p>", 13)
	script = win_script_new(page)
	asserts(c"isolated realm", win_script_eval(script, c"clicks;", 7) == 0)
	win_script_free(script)
	win_page_free(page)
	print(c"script tests passed")
