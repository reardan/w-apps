# Focused HTML text-control selection API tests; native editing/events are
# separate integration work. Run through the public JavaScript bindings.
import lib.assert
import win.script

void selection_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"selection API", ok)

int main():
	char* html = c"<body><textarea id='editor'></textarea><input id='text'><input id='number' type='number'><div id='other'></div></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	selection_eval(script, c"const editor=document.getElementById('editor'); const text=document.getElementById('text'); const number=document.getElementById('number'); if(typeof document.getElementById('other').setSelectionRange!=='undefined') throw 'non-control';")
	# Exact unconditional startup path in the unchanged mobile_input.mjs.
	selection_eval(script, c"editor.value='\\u200b'; editor.setSelectionRange(1,1); if(editor.selectionStart!==1 || editor.selectionEnd!==1 || editor.selectionDirection!=='none') throw 'resetEditor';")
	selection_eval(script, c"editor.value='A😀BC'; if(editor.selectionStart!==5 || editor.selectionEnd!==5) throw 'UTF16 value'; editor.setSelectionRange(1,3,'backward'); if(editor.selectionStart!==1 || editor.selectionEnd!==3 || editor.selectionDirection!=='backward') throw 'UTF16 range'; editor.value='A😀BC'; if(editor.selectionStart!==1 || editor.selectionEnd!==3) throw 'same-value selection';")
	selection_eval(script, c"editor.setSelectionRange(4,2,'forward'); if(editor.selectionStart!==2 || editor.selectionEnd!==2 || editor.selectionDirection!=='forward') throw 'reversed range'; editor.selectionStart=4; if(editor.selectionStart!==4 || editor.selectionEnd!==4) throw 'start raises end'; editor.selectionEnd=1; if(editor.selectionStart!==1 || editor.selectionEnd!==1) throw 'end lowers start'; editor.selectionDirection='invalid'; if(editor.selectionDirection!=='none') throw 'direction';")
	selection_eval(script, c"editor.setSelectionRange(-1,4294967297); if(editor.selectionStart!==1 || editor.selectionEnd!==1) throw 'unsigned modulo'; editor.setSelectionRange(NaN,Infinity); if(editor.selectionStart!==0 || editor.selectionEnd!==0) throw 'nonfinite'; editor.setSelectionRange(null,true); if(editor.selectionStart!==0 || editor.selectionEnd!==1) throw 'primitive'; editor.setSelectionRange(1.9,99); if(editor.selectionStart!==1 || editor.selectionEnd!==5) throw 'truncate and clamp';")
	selection_eval(script, c"editor.selectionStart=null; editor.selectionEnd=null; if(editor.selectionStart!==0 || editor.selectionEnd!==0) throw 'nullable setter'; editor.value='ab'; if(editor.selectionStart!==2 || editor.selectionDirection!=='none') throw 'changed-value caret'; editor.remove(); editor.setSelectionRange(0,1,'backward'); if(editor.selectionEnd!==1 || document.getElementById('editor')!==null) throw 'detached';")
	selection_eval(script, c"text.value='abc'; text.setSelectionRange(0,2); if(text.selectionEnd!==2 || text.selectionStart!==0) throw 'default type'; text.setAttribute('type','SEARCH'); text.setSelectionRange(1,2); if(text.selectionStart!==1) throw 'case-insensitive type'; text.setAttribute('type','nonsense'); if(text.selectionEnd!==2) throw 'invalid type defaults text';")
	selection_eval(script, c"if(number.selectionStart!==null || number.selectionEnd!==null || number.selectionDirection!==null) throw 'unsupported type getters'; let caught=0; try {number.setSelectionRange(0,1);} catch(e) {if(e.name==='InvalidStateError') caught+=1;} try {number.selectionStart=0;} catch(e) {if(e.name==='InvalidStateError') caught+=1;} try {number.selectionEnd=1;} catch(e) {if(e.name==='InvalidStateError') caught+=1;} try {number.selectionDirection='forward';} catch(e) {if(e.name==='InvalidStateError') caught+=1;} if(caught!==4) throw caught;")
	selection_eval(script, c"let failed=0; const detached=editor.setSelectionRange; try {detached(0,1);} catch(e) {failed+=1;} try {editor.setSelectionRange(1);} catch(e) {failed+=1;} if(failed!==2 || editor.selectionStart!==0 || editor.selectionEnd!==1) throw 'receiver and arguments';")
	# Native value mutations and retained wrappers remain bounded after GC.
	selection_eval(script, c"text.setSelectionRange(1,3); text.setAttribute('value','x'); if(text.selectionStart!==1 || text.selectionEnd!==1) throw 'clamp external value';")
	js_runtime_collect(script.runtime)
	selection_eval(script, c"editor.setSelectionRange(0,2); if(editor.selectionEnd!==2) throw 'retained node after GC';")
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)
	println(c"Win UTF-16 text-control selection ranges: OK")
	return 0
