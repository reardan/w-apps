import lib.assert
import win.script

void abort_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"AbortController/Signal API", ok)

int main():
	win_page* page = win_page_parse(c"<p>abort</p>", 12)
	win_script* script = win_script_new(page)
	abort_eval(script, c"const controller=new AbortController(); const signal=controller.signal; if(window.AbortController!==AbortController || window.AbortSignal!==AbortSignal || signal!==controller.signal || signal.aborted || signal.reason!==undefined || signal.onabort!==null) throw 'defaults'; signal.throwIfAborted(); let invalid=0; try {AbortController();} catch(e) {invalid++;} try {new AbortSignal();} catch(e) {invalid++;} const abort=controller.abort; try {abort();} catch(e) {invalid++;} const check=signal.throwIfAborted; try {check();} catch(e) {invalid++;} if(invalid!==4) throw 'branding';")
	abort_eval(script, c"let order=''; let delivered=null; function ordinary(e){order+='B'; if(this!==signal || e.target!==signal || e.currentTarget!==signal || e.eventPhase!==2 || !signal.aborted || signal.reason!==reason || !e.isTrusted || e.bubbles || e.cancelable || e.type!=='abort') throw 'abort event'; delivered=e;} const reason={why:'user'}; signal.addEventListener('abort',ordinary); signal.addEventListener('abort',ordinary,{once:true}); signal.onabort=function(e){order+='H';}; signal.addEventListener('abort',function(){order+='C';},true); signal.addEventListener('abort',function(){order+='L';},{once:true}); controller.abort(reason); controller.abort('ignored'); if(!signal.aborted || signal.reason!==reason || order!=='CBHL' || delivered.currentTarget!==null || delivered.eventPhase!==0) throw 'abort order'; let caught=false; try {signal.throwIfAborted();} catch(e) {caught=e===reason;} if(!caught) throw 'abort reason';")
	abort_eval(script, c"const defaults=new AbortController(); defaults.abort(); if(defaults.signal.reason.name!=='AbortError') throw 'default error'; const nullable=new AbortController(); nullable.abort(null); let nullCaught=false; try {nullable.signal.throwIfAborted();} catch(e) {nullCaught=e===null;} if(!nullCaught || nullable.signal.reason!==null) throw 'null reason'; try {signal.reason='forged'; signal.aborted=false; controller.signal=null;} catch(e) {} if(signal.reason!==reason || !signal.aborted || controller.signal!==signal) throw 'readonly';")
	abort_eval(script, c"const synthetic=new AbortController(); const target=synthetic.signal; let calls=''; const event=new Event('custom',{cancelable:true}); target.addEventListener('custom',function(e){calls+='P'; e.preventDefault();},{passive:true}); target.addEventListener('custom',function(e){calls+='O'; e.preventDefault();},{once:true}); if(target.dispatchEvent(event)!==false || calls!=='PO' || target.aborted || !event.defaultPrevented || event.isTrusted || event.target!==target) throw 'synthetic dispatch'; calls=''; target.dispatchEvent(event); if(calls!=='P') throw 'once'; target.dispatchEvent(new Event('abort')); if(target.aborted) throw 'synthetic abort changed state';")
	abort_eval(script, c"const mutations=new AbortController(); const m=mutations.signal; let changed=''; function remove(){changed+='X';} m.addEventListener('abort',function(e){changed+='1'; m.removeEventListener('abort',remove); m.addEventListener('abort',function(){changed+='late';}); m.onabort=null; mutations.abort('ignored');},{once:true}); m.addEventListener('abort',remove); m.onabort=function(){changed+='H';}; m.addEventListener('abort',function(){changed+='2';}); mutations.abort(); if(changed!=='12') throw 'mutating listeners'; const nested=new Event('nested'); let recursion=false; m.addEventListener('nested',function(e){try {m.dispatchEvent(e);} catch(error){recursion=error.name==='InvalidStateError';}}); m.dispatchEvent(nested); if(!recursion) throw 'dispatch guard';")
	abort_eval(script, c"const handler=new AbortController(); let handlers=''; handler.signal.onabort=function(){handlers+='old';}; handler.signal.addEventListener('abort',function(){handlers+='last';}); handler.signal.onabort=function(){handlers+='new';}; handler.abort(); if(handlers!=='newlast') throw 'handler replacement order';")
	abort_eval(script, c"const asyncController=new AbortController();let asyncOrder='';asyncController.signal.addEventListener('abort',async function(){asyncOrder+='a';await Promise.resolve(1);asyncOrder+='b';});asyncController.abort();asyncOrder+='c';if(asyncOrder!=='ac') throw 'async listener starts synchronously';")
	abort_eval(script, c"if(asyncOrder!=='acb') throw 'async listener continuation';")
	assert_equal(0, script.failures)
	abort_eval(script, c"const throwing=new AbortController(); let continued=false; throwing.signal.addEventListener('abort',function(){throw 'reported';}); throwing.signal.addEventListener('abort',function(){continued=true;}); throwing.abort(); if(!continued) throw 'listener exception propagated';")
	assert_equal(1, script.failures)
	js_runtime_collect(script.runtime)
	abort_eval(script, c"if(signal.reason!==reason || delivered.target!==signal || signal.onabort===null) throw 'GC roots'; const terminal=new AbortController(); terminal.signal.addEventListener('abort',function(){while(true){}});")
	char* limited = c"try {terminal.abort();} catch(e) {} window.escaped=true;"
	assert_equal(0, win_script_eval(script, limited, strlen(limited)))
	assert_equal(5, script.runtime.completion.status)
	abort_eval(script, c"if(window.escaped || !terminal.signal.aborted) throw 'terminal failure';")
	win_script_free(script)
	win_page_free(page)
	println(c"Win AbortController/Signal reasons, listeners, GC and limits: OK")
	return 0
