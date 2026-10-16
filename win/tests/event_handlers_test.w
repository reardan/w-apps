import lib.assert
import win.script

void handler_eval(win_script* script, char* source):
	int ok = win_script_eval(script, source, strlen(source))
	if (ok == 0): println(script.error)
	asserts(c"nullable EventHandler IDL", ok)

int main():
	char* html = c"<body><button id='inline' onclick='order+=\"I\"; return false;'>Inline</button><button id='button'>Button</button><input id='input'></body>"
	win_page* page = win_page_parse(html, strlen(html))
	win_script* script = win_script_new(page)
	handler_eval(script, c"let order='';const inline=document.getElementById('inline');const button=document.getElementById('button');const input=document.getElementById('input');if(!('onclick' in button)||!('oninput' in input)||!('onsubmit' in button)||button.onclick!==null||input.oninput!==null||window.onresize!==null||document.onvisibilitychange!==null)throw 'IDL presence';if('onclick' in document.createTextNode('x'))throw 'text IDL';inline.addEventListener('click',function(){order+='A';});const first=new Event('click',{cancelable:true});if(typeof inline.onclick!=='function'||inline.dispatchEvent(first)!==false||order!=='IA'||!first.defaultPrevented)throw 'initial inline order';")
	handler_eval(script, c"order='';button.addEventListener('click',function(){order+='A';});button.onclick=function(e){if(this!==button||e.currentTarget!==button)throw 'handler receiver';order+='H';};button.addEventListener('click',function(){order+='B';});button.dispatchEvent(new Event('click'));if(order!=='AHB')throw 'registration order';order='';button.onclick=function(){order+='J';};button.dispatchEvent(new Event('click'));if(order!=='AJB')throw 'replacement keeps position';")
	handler_eval(script, c"order='';button.onclick=null;button.onclick=function(){order+='H';return false;};const event=new Event('click',{cancelable:true});if(button.dispatchEvent(event)!==false||order!=='ABH'||!event.defaultPrevented)throw 'reenabled handler position';order='';button.setAttribute('onclick','order+=\"K\"; return false;');button.dispatchEvent(new Event('click'));if(order!=='ABK')throw 'attribute replaces cached callback';order='';button.removeAttribute('onclick');button.dispatchEvent(new Event('click'));if(order!=='AB'||button.onclick!==null)throw 'attribute removal';")
	handler_eval(script, c"button.onclick='order=\"wrong\"';if(button.onclick!==null)throw 'noncallable handler';button.onclick={};if(button.onclick!==null)throw 'object handler';let count=0;function shared(){count++;}input.oninput=shared;input.addEventListener('input',shared);input.dispatchEvent(new Event('input'));if(count!==2)throw 'IDL separate from duplicate rules';input.removeEventListener('input',shared);input.dispatchEvent(new Event('input'));if(count!==3)throw 'remove listener keeps IDL';")
	handler_eval(script, c"order='';const late=document.createElement('button');late.addEventListener('click',function(){order+='A';late.onclick=function(){order+='J';};});late.onclick=function(){order+='H';};late.dispatchEvent(new Event('click'));if(order!=='AJ')throw 'live handler update';order='';const stop=document.createElement('button');stop.addEventListener('click',function(e){order+='A';e.stopImmediatePropagation();});stop.onclick=function(){order+='H';};stop.dispatchEvent(new Event('click'));if(order!=='A')throw 'immediate propagation';")
	assert_equal(0, script.failures)
	win_script_free(script)
	win_page_free(page)
	println(c"Win nullable event handlers, inline invalidation and registration order: OK")
	return 0
