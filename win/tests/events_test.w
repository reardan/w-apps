# Public constructor/dispatch binding tests. Native input is separately tested;
# these events are synthetic and never trigger browser default actions.
import lib.assert
import win.script

void event_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"Event API", ok)

int main():
	char* html = c"<body><div id='outer'><button id='inner' oninline='window.inlineEvent=event; return false;'>Go</button></div></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	event_eval(script, c"const outer=document.getElementById('outer'); const inner=document.getElementById('inner'); const e=new Event('test'); if(window.Event!==Event || e.type!=='test' || e.target!==null || e.currentTarget!==null || e.eventPhase!==0 || e.bubbles || e.cancelable || e.composed || e.defaultPrevented || e.isTrusted) throw 'defaults';")
	event_eval(script, c"let order=''; let seen=null; window.addEventListener('test',function(e){order+='W';},true); document.addEventListener('test',function(e){order+='D';},true); outer.addEventListener('test',function(e){order+='O';},true); inner.addEventListener('test',function(event){order+='T'; seen=event; if(event!==e || event.target!==inner || event.currentTarget!==inner || event.eventPhase!==2) throw 'identity';}); outer.addEventListener('test',function(e){order+='o';}); if(!inner.dispatchEvent(e) || order!=='WDOT' || seen!==e || e.target!==inner || e.currentTarget!==null || e.eventPhase!==0) throw 'nonbubbling';")
	event_eval(script, c"let count=0; const cancel=new Event('cancel',{bubbles:true,cancelable:true,composed:true}); inner.addEventListener('cancel',function(e){count+=1; e.preventDefault();}); outer.addEventListener('cancel',function(e){count+=10; if(!e.defaultPrevented) throw 'visible cancellation';}); if(inner.dispatchEvent(cancel)!==false || count!==11 || !cancel.defaultPrevented || !cancel.composed) throw 'cancel'; if(inner.dispatchEvent(cancel)!==false || count!==22) throw 'redispatch';")
	event_eval(script, c"const early=new Event('early',{cancelable:true}); early.preventDefault(); if(inner.dispatchEvent(early)!==false || !early.defaultPrevented) throw 'predispatch cancel'; const inert=new Event('inert'); inert.preventDefault(); if(inert.defaultPrevented || !inner.dispatchEvent(inert)) throw 'noncancelable';")
	event_eval(script, c"const passive=new Event('passive',{cancelable:true}); inner.addEventListener('passive',function(e){e.preventDefault();},{passive:true}); if(!inner.dispatchEvent(passive) || passive.defaultPrevented) throw 'passive';")
	event_eval(script, c"let nestedOrder=''; const a=new Event('a',{bubbles:true,cancelable:true}); const b=new Event('b',{cancelable:true}); inner.addEventListener('a',function(e){nestedOrder+='a'; if(!inner.dispatchEvent(b)) throw 'nested result'; if(e.currentTarget!==inner || e.eventPhase!==2) throw 'outer state'; e.preventDefault(); nestedOrder+='A';}); inner.addEventListener('b',function(e){nestedOrder+='b'; e.stopPropagation();}); outer.addEventListener('a',function(e){nestedOrder+='o';}); if(inner.dispatchEvent(a)!==false || nestedOrder!=='abAo' || b.currentTarget!==null || a.currentTarget!==null) throw 'nested dispatch';")
	event_eval(script, c"let recursive=0; const r=new Event('r'); inner.addEventListener('r',function(e){try {outer.dispatchEvent(e);} catch(err) {if(err.name==='InvalidStateError') recursive+=1;}},{once:true}); if(!inner.dispatchEvent(r) || recursive!==1 || !inner.dispatchEvent(r)) throw 'reentrant same event';")
	event_eval(script, c"let stopped=''; const stop=new Event('stop',{bubbles:true}); inner.addEventListener('stop',function(e){stopped+='1'; e.stopImmediatePropagation();},{once:true}); inner.addEventListener('stop',function(e){stopped+='2';}); outer.addEventListener('stop',function(e){stopped+='3';}); inner.dispatchEvent(stop); if(stopped!=='1') throw 'immediate'; stopped=''; inner.dispatchEvent(stop); if(stopped!=='23') throw 'stop flags cleared';")
	event_eval(script, c"let mutation=''; function removed(e){mutation+='X';} inner.addEventListener('mutate',function(e){mutation+='1'; inner.dispatchEvent(new Event('remove'));}); inner.addEventListener('mutate',removed); inner.addEventListener('mutate',function(e){mutation+='2';}); inner.addEventListener('remove',function(e){inner.removeEventListener('mutate',removed);},{once:true}); inner.dispatchEvent(new Event('mutate')); if(mutation!=='12') throw 'nested listener compaction';")
	event_eval(script, c"const inline=new Event('inline',{cancelable:true}); if(inner.dispatchEvent(inline)!==false || window.inlineEvent!==inline) throw 'nested inline compilation';")
	event_eval(script, c"let bad=0; try {inner.dispatchEvent({type:'test'});} catch(e) {bad+=1;} const dispatch=inner.dispatchEvent; try {dispatch(new Event('test'));} catch(e) {bad+=1;} try {new Event();} catch(e) {bad+=1;} try {new Event('x',false);} catch(e) {bad+=1;} if(bad!==4) throw 'validation';")
	event_eval(script, c"let tasks=''; inner.addEventListener('tasks',function(){tasks+='listener'; queueMicrotask(function(){tasks+='job';});}); inner.dispatchEvent(new Event('tasks')); tasks+='caller'; if(tasks!=='listenercaller') throw 'early checkpoint';")
	event_eval(script, c"if(tasks!=='listenercallerjob') throw 'missing checkpoint'; const empty=new Event(''); let empties=0; inner.addEventListener('',function(){empties+=1;}); inner.dispatchEvent(empty); if(empties!==1) throw 'empty type';")
	event_eval(script, c"try {e.type='forged';} catch(ignore) {} try {e.defaultPrevented=true;} catch(ignore) {} try {e.isTrusted=true;} catch(ignore) {} if(e.type!=='test' || e.defaultPrevented || e.isTrusted) throw 'readonly state';")
	event_eval(script, c"let inputText=''; const editor=document.createElement('textarea'); editor.addEventListener('input',function(e){if(!e.isComposing) inputText=editor.value;}); editor.value='paste😀'; const inputEvent=new Event('input',{bubbles:true}); inputEvent.isComposing=false; editor.dispatchEvent(inputEvent); if(inputText!=='paste😀') throw 'synthetic input surface';")
	assert_equal(0, script.failures)
	# Listener exceptions are reported, and neither escape dispatchEvent nor skip
	# later listeners. Keep this expected report separate from clean-path counts.
	event_eval(script, c"let survived=0; inner.addEventListener('throws',function(){throw 'reported listener';}); inner.addEventListener('throws',function(){survived+=1;}); if(!inner.dispatchEvent(new Event('throws')) || survived!==1) throw 'exception propagation';")
	assert_equal(1, script.failures)
	js_runtime_collect(script.runtime)
	event_eval(script, c"if(!cancel.defaultPrevented || cancel.target!==inner) throw 'GC retained event';")
	event_eval(script, c"const limitEvent=new Event('limit'); inner.addEventListener('limit',function(){while(true){}},{once:true});")
	char* expensive = c"try {inner.dispatchEvent(limitEvent);} catch(e) {} window.escapedBudget=true;"
	assert_equal(0, win_script_eval(script, expensive, strlen(expensive)))
	assert_equal(5, script.runtime.completion.status)
	event_eval(script, c"if(window.escapedBudget || limitEvent.currentTarget!==null || limitEvent.eventPhase!==0 || !inner.dispatchEvent(limitEvent)) throw 'terminal limit cleanup';")
	win_script_free(script)
	win_page_free(page)
	println(c"Win Event constructor and reentrant synthetic dispatch: OK")
	return 0
