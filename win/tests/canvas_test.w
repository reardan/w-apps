# Headless lifecycle/layout always; pass --gpu under Xvfb for real GL coverage.
import lib.assert
import lib.args
import graphics.window
import win.canvas
import win.document

win_canvas* test_canvas

js_value* canvas_host(void* context, list[js_value*] args):
	js_runtime* rt = cast(js_runtime*, context)
	list[js_value*] call = new list[js_value*]
	for i in range(2, args.length): call.push(args[i])
	int length = 0
	char* name = js_text_to_utf8(args[1].text, &length)
	js_value* result = win_canvas_call(test_canvas, rt, name, call)
	free(name)
	__w_list_free(cast(__w_list*, call))
	return result

void canvas_eval(js_runtime* rt, char* source):
	js_completion* result = js_runtime_eval(rt, source, strlen(source), 1000000)
	if (result.status):
		print_error(source)
		print_error(c"\n")
		if (result.value != 0 && result.value.kind == 4):
			int length = 0
			char* message = js_text_to_utf8(result.value.text, &length)
			print_error(message)
			print_error(c"\n")
			free(message)
	assert_equal(0, result.status)

void test_canvas_layout():
	char* source = c"<canvas id='default'>fallback</canvas><canvas width='80' height='40'></canvas><canvas width='80' height='40' style='width:160px'></canvas><canvas width='80' height='40' style='height:60px'></canvas><canvas width='0' height='0'></canvas><canvas width='-2' height='oops'></canvas><div style='display:flex;width:200px'><canvas style='max-width:100px'></canvas></div>"
	win_page* page = win_page_parse(source, strlen(source))
	win_page_layout(page, 800)
	assert_equal(7, page.runs.length)
	assert1(page.runs[0].width == 300.0 && page.runs[0].height == 150.0)
	assert1(page.runs[1].width == 80.0 && page.runs[1].height == 40.0)
	assert1(page.runs[2].width == 160.0 && page.runs[2].height == 80.0)
	assert1(page.runs[3].width == 120.0 && page.runs[3].height == 60.0)
	assert1(page.runs[4].width == 0.0 && page.runs[4].height == 0.0)
	assert1(page.runs[5].width == 300.0 && page.runs[5].height == 150.0)
	assert1(page.runs[6].width == 100.0 && page.runs[6].height == 50.0)
	win_page_free(page)

void test_canvas_gpu():
	gfx_window* window = gfx_window_open(c"canvas regression", 64, 64)
	assert1(window != 0)
	int main_context = glXGetCurrentContext()
	test_canvas = win_canvas_new(0, 16, 16, 1)
	assert1(test_canvas != 0 && test_canvas.context != 0)
	assert_equal(main_context, glXGetCurrentContext())
	js_runtime* rt = js_runtime_new()
	js_runtime_bind(rt, c"__winGL", canvas_host)
	canvas_eval(rt, win_canvas_bootstrap())
	canvas_eval(rt, c"var gl=__winGLContext(0);gl.clearColor(1,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT);var pixels=new Uint8Array(4);gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels);if(pixels[0]!==255||pixels[3]!==255)throw 'clear pixels';if(gl.getError()!==0)throw 'clear error';")
	canvas_eval(rt, c"var vs=gl.createShader(gl.VERTEX_SHADER);gl.shaderSource(vs,'#version 300 es\\nprecision highp float;in vec2 position;void main(){gl_Position=vec4(position,0.,1.);}');gl.compileShader(vs);if(!gl.getShaderParameter(vs,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(vs);var fs=gl.createShader(gl.FRAGMENT_SHADER);gl.shaderSource(fs,'#version 300 es\\nprecision highp float;uniform vec4 color;out vec4 pixel;void main(){pixel=color;}');gl.compileShader(fs);if(!gl.getShaderParameter(fs,gl.COMPILE_STATUS))throw gl.getShaderInfoLog(fs);var program=gl.createProgram();gl.attachShader(program,vs);gl.attachShader(program,fs);gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw gl.getProgramInfoLog(program);gl.useProgram(program);var color=gl.getUniformLocation(program,'color');gl.uniform4f(color,0,1,0,1);var buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);var attr=gl.getAttribLocation(program,'position');gl.enableVertexAttribArray(attr);gl.vertexAttribPointer(attr,2,gl.FLOAT,false,0,0);gl.drawArrays(gl.TRIANGLES,0,3);gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels);if(pixels[0]!==0||pixels[1]!==255)throw 'triangle pixels';if(gl.getError()!==0)throw 'triangle error';")
	canvas_eval(rt, c"var vao=gl.createVertexArray();gl.bindVertexArray(vao);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.enableVertexAttribArray(attr);gl.vertexAttribPointer(attr,2,gl.FLOAT,false,0,0);var elements=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,elements);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint8Array([0,1,2]),gl.STATIC_DRAW);gl.drawElements(gl.TRIANGLES,3,gl.UNSIGNED_BYTE,0);if(gl.getError()!==0)throw 'indexed draw';gl.drawElements(gl.TRIANGLES,4,gl.UNSIGNED_BYTE,0);if(gl.getError()!==gl.INVALID_OPERATION)throw 'index byte bounds';gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER,2,new Uint8Array([3]));gl.drawElements(gl.TRIANGLES,3,gl.UNSIGNED_BYTE,0);if(gl.getError()!==gl.INVALID_OPERATION)throw 'index vertex bounds';gl.deleteVertexArray(vao);gl.bindVertexArray(null);gl.linkProgram(program);gl.uniform4f(color,0,1,0,1);if(gl.getError()!==gl.INVALID_OPERATION)throw 'stale uniform';color=gl.getUniformLocation(program,'color');gl.uniform4f(color,0,1,0,1);var padding=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,padding);gl.texImage2D(gl.TEXTURE_2D,0,gl.R8,1,2,0,gl.RED,gl.UNSIGNED_BYTE,new Uint8Array(2));if(gl.getError()!==gl.INVALID_OPERATION)throw 'unpack alignment';gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);gl.texImage2D(gl.TEXTURE_2D,0,gl.R8,1,2,0,gl.RED,gl.UNSIGNED_BYTE,new Uint8Array([0,255]));if(gl.getError()!==0)throw 'packed upload';gl.deleteTexture(padding);")
	canvas_eval(rt, c"gl.drawArrays(gl.TRIANGLES,0,4);if(gl.getError()!==gl.INVALID_OPERATION)throw 'vertex bounds';gl.bindBuffer(gl.ARRAY_BUFFER,{});if(gl.getError()!==gl.INVALID_OPERATION)throw 'forged handle';gl.bufferSubData(gl.ARRAY_BUFFER,24,new Uint8Array(1));if(gl.getError()!==gl.INVALID_VALUE)throw 'upload bounds';gl.readPixels(0,0,2,2,gl.RGBA,gl.UNSIGNED_BYTE,pixels);if(gl.getError()!==gl.INVALID_OPERATION)throw 'read bounds';var tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,tex);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA8,1,1,0,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array([0,0,255,255]));gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array([255,255,0,255]));if(gl.getError()!==0)throw 'texture upload';gl.deleteTexture(tex);gl.deleteTexture(tex);if(gl.getError()!==0)throw 'repeat delete';gl.bindTexture(gl.TEXTURE_2D,tex);if(gl.getError()!==gl.INVALID_OPERATION)throw 'deleted handle';gl.enable(gl.SCISSOR_TEST);gl.scissor(0,15,16,1);gl.clearColor(1,0,0,1);gl.clear(gl.COLOR_BUFFER_BIT);")
	assert_equal(main_context, glXGetCurrentContext())
	ui_renderer renderer
	ui_render_init(&renderer)
	ui_render_begin(&renderer, 64, 64)
	win_canvas_draw(&renderer, test_canvas, ui_rect(0.0, 0.0, 16.0, 16.0))
	assert1(test_canvas.image != 0)
	assert_equal(255, test_canvas.image.pixels[0] & 255)
	assert_equal(0, test_canvas.image.pixels[1] & 255)
	assert_equal(255, test_canvas.image.pixels[(15 * 16 * 4) + 1] & 255)
	ui_render_end(&renderer)
	char[4] composited
	glReadPixels(2, 63, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &composited[0])
	assert_equal(255, composited[0] & 255)
	assert_equal(0, composited[1] & 255)
	glReadPixels(2, 49, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &composited[0])
	assert_equal(0, composited[0] & 255)
	assert_equal(255, composited[1] & 255)
	win_canvas* second = win_canvas_new(0, 4, 4, 1)
	win_canvas* first = test_canvas
	test_canvas = second
	canvas_eval(rt, c"gl.bindBuffer(gl.ARRAY_BUFFER,buffer);if(gl.getError()!==gl.INVALID_OPERATION)throw 'cross context handle';")
	test_canvas = first
	win_canvas_free(second)
	assert1(win_canvas_resize(first, 8, 8))
	canvas_eval(rt, c"gl.readPixels(0,0,1,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels);if(pixels[0]!==0||pixels[3]!==0)throw 'resize clear';")
	win_canvas_free(test_canvas)
	ui_render_destroy(&renderer)
	js_runtime_free(rt)
	gfx_window_destroy(window)

int main(int argc, int argv):
	args_init(argc, argv)
	win_canvas_free(0)
	assert1(win_canvas_new(0, -1, 1, 0) == 0)
	assert1(win_canvas_dimensions(4096, 4096) == 0)
	win_canvas* c = win_canvas_new(0, 300, 150, 0)
	assert1(c != 0 && c.context == 0)
	assert1(win_canvas_resize(c, 0, 0))
	assert1(win_canvas_resize(c, 4097, 1) == 0)
	win_canvas_free(c)
	test_canvas_layout()
	if (args_has_bool_flag(c"gpu")): test_canvas_gpu()
	print(c"canvas_test: OK\n")
	return 0
