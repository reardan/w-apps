# Native WebGL subset. Each canvas owns an isolated GLX context and RGBA FBO.
# Callers must destroy canvases before their JS realm and native window.
import win.images
import libs.extras.javascript.runtime

c_lib "libGL.so.1"
extern int glXGetCurrentContext()
extern int glXGetCurrentDisplay()
extern int glXGetCurrentDrawable()
extern void glGenFramebuffers(int count, int32* ids)
extern void glDeleteFramebuffers(int count, int32* ids)
extern void glBindFramebuffer(int target, int id)
extern void glFramebufferTexture2D(int target, int attachment, int textarget, int texture, int level)
extern int glCheckFramebufferStatus(int target)
extern void glDeleteVertexArrays(int count, int32* ids)
extern void glGetIntegerv(int pname, int32* value)
extern void glGetFloatv(int pname, float32* value)
extern int glIsEnabled(int capability)
extern void glGenRenderbuffers(int count, int32* ids)
extern void glBindRenderbuffer(int target, int id)
extern void glRenderbufferStorage(int target, int format, int width, int height)
extern void glFramebufferRenderbuffer(int target, int attachment, int rendertarget, int id)

const int WIN_CANVAS_BYTES = 16777216
const int WIN_CANVAS_OBJECTS = 4096

struct win_gl_object:
	js_value* value
	int kind
	int32 id
	int length
	char* bytes
	int owner
	int generation
	int linked
	int width
	int height

struct win_gl_attrib:
	int enabled
	int buffer
	int size
	int type
	int stride
	int offset

struct win_gl_vao:
	int handle
	int elements
	win_gl_attrib[16] attribs

struct win_canvas:
	html_node* node
	int width
	int height
	int context
	int display
	int drawable
	int previous_context
	int previous_display
	int previous_drawable
	int32 framebuffer
	int32 color
	int32 depth
	int error
	int dirty
	int array_buffer
	int vao
	int program
	int active_texture
	int[16] textures
	int unpack_alignment
	int pack_alignment
	int allocated
	js_runtime* runtime
	list[win_gl_object*] objects
	list[win_gl_vao*] arrays
	char* pixels
	ui_image* image

void* win_canvas_alloc(int length):
	char* data = cast(char*, malloc(length))
	for i in range(length): data[i] = 0
	return data

void win_canvas_error(win_canvas* c, int error):
	if (c.error == 0): c.error = error

int win_canvas_enter(win_canvas* c):
	if (c == 0 || c.context == 0): return 0
	c.previous_context = glXGetCurrentContext()
	c.previous_display = glXGetCurrentDisplay()
	c.previous_drawable = glXGetCurrentDrawable()
	return glXMakeCurrent(c.display, c.drawable, c.context)

void win_canvas_leave(win_canvas* c):
	if (c.previous_context): glXMakeCurrent(c.previous_display, c.previous_drawable, c.previous_context)
	else: glXMakeCurrent(c.display, 0, 0)

int win_canvas_dimensions(int width, int height):
	return width >= 0 && height >= 0 && width <= 4096 && height <= 4096 && (width == 0 || height <= WIN_CANVAS_BYTES / 4 / width)

# Reset storage even when the dimensions are unchanged, as HTML canvas does.
int win_canvas_resize(win_canvas* c, int width, int height):
	if (win_canvas_dimensions(width, height) == 0): return 0
	if (c.image != 0):
		ui_image_release(c.image)
		c.image = 0
	if (c.pixels != 0): free(c.pixels)
	c.width = width
	c.height = height
	c.pixels = cast(char*, win_canvas_alloc(width * height * 4 + 1))
	c.dirty = 1
	if (win_canvas_enter(c)):
		int32 texture = 0
		float32[4] clear
		glGetIntegerv(0x8069, &texture)
		glGetFloatv(0x0C22, &clear[0])
		int scissor = glIsEnabled(GL_SCISSOR_TEST)
		glBindTexture(GL_TEXTURE_2D, c.color)
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, max(1, width), max(1, height), 0, GL_RGBA, GL_UNSIGNED_BYTE, 0)
		glBindFramebuffer(0x8D40, c.framebuffer)
		glFramebufferTexture2D(0x8D40, 0x8CE0, GL_TEXTURE_2D, c.color, 0)
		glBindRenderbuffer(0x8D41, c.depth)
		glRenderbufferStorage(0x8D41, 0x88F0, max(1, width), max(1, height))
		glFramebufferRenderbuffer(0x8D40, 0x821A, 0x8D41, c.depth)
		int complete = glCheckFramebufferStatus(0x8D40) == 0x8CD5
		glDisable(GL_SCISSOR_TEST)
		glClearColor(0.0, 0.0, 0.0, 0.0)
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | 0x400)
		glClearColor(clear[0], clear[1], clear[2], clear[3])
		if (scissor): glEnable(GL_SCISSOR_TEST)
		glBindTexture(GL_TEXTURE_2D, cast(int, texture))
		win_canvas_leave(c)
		if (complete == 0): return 0
	return 1

win_canvas* win_canvas_new(html_node* node, int width, int height, int gl_ready):
	if (win_canvas_dimensions(width, height) == 0): return 0
	win_canvas* c = new win_canvas()
	c.node = node
	c.objects = new list[win_gl_object*]
	c.objects.push(0)
	c.arrays = new list[win_gl_vao*]
	c.arrays.push(new win_gl_vao())
	c.unpack_alignment = 4
	c.pack_alignment = 4
	if (gl_ready && glXGetCurrentContext() != 0):
		c.display = glXGetCurrentDisplay()
		c.drawable = glXGetCurrentDrawable()
		int32[5] attrs
		attrs[0] = GLX_RGBA
		attrs[1] = GLX_DOUBLEBUFFER
		attrs[2] = GLX_DEPTH_SIZE
		attrs[3] = 16
		attrs[4] = 0
		x_visual_info* visual = glXChooseVisual(c.display, XDefaultScreen(c.display), &attrs[0])
		if (visual != 0):
			c.context = glXCreateContext(c.display, visual, 0, 1)
			XFree(cast(int, visual))
		if (win_canvas_enter(c)):
			glGenFramebuffers(1, &c.framebuffer)
			glGenTextures(1, &c.color)
			glGenRenderbuffers(1, &c.depth)
			glViewport(0, 0, width, height)
			win_canvas_leave(c)
	if (win_canvas_resize(c, width, height) == 0):
		if (c.context): glXDestroyContext(c.display, c.context)
		c.context = 0
	return c

void win_canvas_free(win_canvas* c):
	if (c == 0): return
	# Destroying the private context releases every native object, including
	# delete-pending shader/program objects retained by GL attachments.
	if (c.context): glXDestroyContext(c.display, c.context)
	if (c.image != 0): ui_image_release(c.image)
	for i in range(1, c.objects.length):
		win_gl_object* object = c.objects[i]
		if (c.runtime != 0): js_runtime_unroot(c.runtime, object.value)
		if (object.bytes != 0): free(object.bytes)
		free(object)
	for i in range(c.arrays.length): free(c.arrays[i])
	__w_list_free(cast(__w_list*, c.objects))
	__w_list_free(cast(__w_list*, c.arrays))
	free(c.pixels)
	free(c)

void win_canvas_draw(ui_renderer* renderer, win_canvas* c, ui_rect rect):
	if (c == 0 || c.context == 0 || c.width == 0 || c.height == 0 || renderer.gl_ready == 0): return
	if (c.dirty && win_canvas_enter(c)):
		glPixelStorei(0x0D05, 1)
		glReadPixels(0, 0, c.width, c.height, GL_RGBA, GL_UNSIGNED_BYTE, c.pixels)
		glPixelStorei(0x0D05, c.pack_alignment)
		win_canvas_leave(c)
		int stride = c.width * 4
		for y in range(c.height / 2):
			for x in range(stride):
				int top = y * stride + x
				int bottom = (c.height - y - 1) * stride + x
				char saved = c.pixels[top]
				c.pixels[top] = c.pixels[bottom]
				c.pixels[bottom] = saved
		if (c.image == 0): c.image = ui_image_create(renderer, c.width, c.height, c.pixels, stride * c.height)
		else: ui_image_update(c.image, c.pixels, stride * c.height)
		c.dirty = 0
	if (c.image != 0): ui_draw_image(renderer, c.image, rect, 1.0)

# Numeric arguments are finite, bounded signed values before FFI conversion.
int win_gl_int(list[js_value*] args, int index):
	if (index >= args.length): return 0
	js_value* value = args[index]
	if (value.kind == 2): return cast(int, value.number)
	if (value.kind != 3 || f64is_nan(value.number) || value.number < -2147483648.0 || value.number > 2147483647.0): return 0
	return cast(int, value.number)

float32 win_gl_float(list[js_value*] args, int index):
	if (index >= args.length): return 0.0
	if (args[index].kind != 3 || f64is_nan(args[index].number) || fabs64(args[index].number) > 3.4e38): return 0.0
	return cast(float32, args[index].number)

int win_gl_handle(win_canvas* c, list[js_value*] args, int index, int kind, int nullable):
	if (index >= args.length):
		win_canvas_error(c, 0x0501)
		return -1
	js_value* value = args[index]
	if (nullable && value.kind == 1): return 0
	for i in range(1, c.objects.length):
		win_gl_object* object = c.objects[i]
		if (object.value == value && object.kind == kind): return i
	win_canvas_error(c, 0x0502)
	return -1

int win_gl_id(win_canvas* c, int handle):
	if (handle <= 0): return 0
	return cast(int, c.objects[handle].id)

js_value* win_gl_object_new(win_canvas* c, js_runtime* rt, int kind, int id):
	if (c.objects.length >= WIN_CANVAS_OBJECTS || id == 0):
		win_canvas_error(c, 0x0505)
		return js_runtime_alloc(rt, 1)
	win_gl_object* object = new win_gl_object()
	object.kind = kind
	object.id = cast(int32, id)
	object.value = js_runtime_alloc(rt, 5)
	js_runtime_root(rt, object.value)
	c.objects.push(object)
	return object.value

js_value* win_gl_string(js_runtime* rt, char* source):
	js_text* text = js_runtime_key(source)
	js_value* result = js_runtime_string(rt, text)
	js_text_free(text)
	return result

win_gl_vao* win_gl_array(win_canvas* c):
	for i in range(c.arrays.length):
		if (c.arrays[i].handle == c.vao): return c.arrays[i]
	return c.arrays[0]

int win_gl_buffer(win_canvas* c, int target):
	if (target == GL_ARRAY_BUFFER): return c.array_buffer
	if (target == GL_ELEMENT_ARRAY_BUFFER): return win_gl_array(c).elements
	win_canvas_error(c, 0x0500)
	return 0

int win_gl_type_size(int type):
	if (type == 0x1400 || type == 0x1401): return 1
	if (type == 0x1402 || type == 0x1403): return 2
	if (type == 0x1404 || type == 0x1405 || type == GL_FLOAT): return 4
	return 0

int win_gl_draw_bounds(win_canvas* c, int last):
	if (c.program == 0 || c.objects[c.program].kind != 4 || c.objects[c.program].linked == 0): return 0
	win_gl_vao* vao = win_gl_array(c)
	for i in range(16):
		win_gl_attrib* attr = &vao.attribs[i]
		if (attr.enabled):
			if (attr.buffer == 0): return 0
			win_gl_object* buffer = c.objects[attr.buffer]
			if (buffer.kind != 1): return 0
			int size = attr.size * win_gl_type_size(attr.type)
			if (size == 0): return 0
			int stride = attr.stride
			if (stride == 0): stride = size
			if (last >= 0 && (attr.offset > buffer.length - size || last > (buffer.length - size - attr.offset) / stride)): return 0
	return 1

int win_gl_pixel_length(int width, int height, int format, int type, int alignment):
	if (type != GL_UNSIGNED_BYTE || (format != GL_RGBA && format != GL_RED)): return -1
	if (win_canvas_dimensions(width, height) == 0): return -1
	if (width == 0 || height == 0): return 0
	int bpp = 4
	if (format == GL_RED): bpp = 1
	int row = width * bpp
	int stride = (row + alignment - 1) / alignment * alignment
	return (height - 1) * stride + row

# Methods return undefined on GL errors; getError drains the sticky error.
# Host-side binary access validates detached buffers and offset views first.
js_value* win_canvas_call(win_canvas* c, js_runtime* rt, char* method, list[js_value*] args):
	js_value* result = rt.undefined_value
	if (c == 0 || c.context == 0): return js_runtime_alloc(rt, 1)
	if (c.runtime != 0 && c.runtime != rt): return js_runtime_alloc(rt, 1)
	c.runtime = rt
	if (win_canvas_enter(c) == 0): return js_runtime_alloc(rt, 1)
	int a = win_gl_int(args, 0)
	int b = win_gl_int(args, 1)
	int d = win_gl_int(args, 2)
	int e = win_gl_int(args, 3)
	int f = win_gl_int(args, 4)
	int g = win_gl_int(args, 5)
	int h = win_gl_int(args, 6)
	int j = win_gl_int(args, 7)
	if (strcmp(method, c"getError") == 0):
		int error = c.error
		c.error = 0
		if (error == 0): error = glGetError()
		result = js_runtime_number(rt, cast(float64, error))
	elif (strcmp(method, c"isContextLost") == 0): result = js_runtime_boolean(rt, 0)
	elif (strcmp(method, c"getParameter") == 0):
		if (a == GL_VENDOR || a == GL_RENDERER || a == GL_VERSION): result = win_gl_string(rt, glGetString(a))
		else: win_canvas_error(c, 0x0500)
	elif (strcmp(method, c"viewport") == 0 || strcmp(method, c"scissor") == 0):
		if (d < 0 || e < 0): win_canvas_error(c, 0x0501)
		elif (strcmp(method, c"viewport") == 0): glViewport(a, b, d, e)
		else: glScissor(a, b, d, e)
	elif (strcmp(method, c"clearColor") == 0): glClearColor(win_gl_float(args, 0), win_gl_float(args, 1), win_gl_float(args, 2), win_gl_float(args, 3))
	elif (strcmp(method, c"clear") == 0):
		if ((a & ~(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | 0x400)) != 0): win_canvas_error(c, 0x0501)
		else:
			glClear(a)
			c.dirty = 1
	elif (strcmp(method, c"enable") == 0 || strcmp(method, c"disable") == 0):
		if (a != GL_BLEND && a != GL_SCISSOR_TEST && a != GL_DEPTH_TEST && a != GL_CULL_FACE && a != 0x0BD0): win_canvas_error(c, 0x0500)
		elif (strcmp(method, c"enable") == 0): glEnable(a)
		else: glDisable(a)
	elif (strcmp(method, c"blendFunc") == 0): glBlendFunc(a, b)
	elif (strcmp(method, c"finish") == 0 || strcmp(method, c"flush") == 0): glFinish()
	elif (strcmp(method, c"pixelStorei") == 0):
		if (a != GL_UNPACK_ALIGNMENT && a != 0x0D05): win_canvas_error(c, 0x0500)
		elif (b != 1 && b != 2 && b != 4 && b != 8): win_canvas_error(c, 0x0501)
		else:
			glPixelStorei(a, b)
			if (a == GL_UNPACK_ALIGNMENT): c.unpack_alignment = b
			else: c.pack_alignment = b
	elif (strcmp(method, c"readPixels") == 0):
		int length = win_gl_pixel_length(d, e, f, g, c.pack_alignment)
		if (args.length < 7 || length < 0 || f != GL_RGBA || a < 0 || b < 0 || a > c.width - d || b > c.height - e): win_canvas_error(c, 0x0501)
		elif (js_runtime_binary_byte_length(rt, args[6]) < length || js_runtime_binary_data(rt, args[6]) == 0): win_canvas_error(c, 0x0502)
		else: glReadPixels(a, b, d, e, f, g, cast(char*, js_runtime_binary_data(rt, args[6])))
	elif (strcmp(method, c"createBuffer") == 0 || strcmp(method, c"createTexture") == 0 || strcmp(method, c"createVertexArray") == 0 || strcmp(method, c"createShader") == 0 || strcmp(method, c"createProgram") == 0):
		int kind = 1
		int32 id = 0
		if (c.objects.length >= WIN_CANVAS_OBJECTS):
			win_canvas_error(c, 0x0505)
			result = js_runtime_alloc(rt, 1)
		else:
			if (strcmp(method, c"createBuffer") == 0): glGenBuffers(1, &id)
			elif (strcmp(method, c"createTexture") == 0):
				kind = 2
				glGenTextures(1, &id)
			elif (strcmp(method, c"createShader") == 0):
				kind = 3
				if (a == GL_VERTEX_SHADER || a == GL_FRAGMENT_SHADER): id = cast(int32, glCreateShader(a))
				else: win_canvas_error(c, 0x0500)
			elif (strcmp(method, c"createProgram") == 0):
				kind = 4
				id = cast(int32, glCreateProgram())
			else:
				kind = 5
				glGenVertexArrays(1, &id)
			if (id):
				result = win_gl_object_new(c, rt, kind, cast(int, id))
				if (kind == 5):
					win_gl_vao* vao = new win_gl_vao()
					vao.handle = c.objects.length - 1
					c.arrays.push(vao)
			else: result = js_runtime_alloc(rt, 1)
	elif (strcmp(method, c"deleteBuffer") == 0 || strcmp(method, c"deleteTexture") == 0 || strcmp(method, c"deleteVertexArray") == 0 || strcmp(method, c"deleteShader") == 0 || strcmp(method, c"deleteProgram") == 0):
		int kind = 1
		if (strcmp(method, c"deleteTexture") == 0): kind = 2
		if (strcmp(method, c"deleteShader") == 0): kind = 3
		if (strcmp(method, c"deleteProgram") == 0): kind = 4
		if (strcmp(method, c"deleteVertexArray") == 0): kind = 5
		# Repeated deletion is a no-op, but foreign objects remain invalid.
		int handle = 0
		if (args.length > 0 && args[0].kind != 1):
			for i in range(1, c.objects.length):
				if (c.objects[i].value == args[0] && (c.objects[i].kind == kind || c.objects[i].kind == -kind)): handle = i
			if (handle == 0): win_canvas_error(c, 0x0502)
		if (handle > 0 && c.objects[handle].kind > 0):
			win_gl_object* object = c.objects[handle]
			if (kind == 1):
				glDeleteBuffers(1, &object.id)
				c.allocated = c.allocated - object.length
				if (object.bytes != 0): free(object.bytes)
				object.bytes = 0
				object.length = 0
				if (c.array_buffer == handle): c.array_buffer = 0
				for i in range(c.arrays.length):
					if (c.arrays[i].elements == handle): c.arrays[i].elements = 0
			elif (kind == 2):
				glDeleteTextures(1, &object.id)
				c.allocated = c.allocated - object.length
				object.length = 0
				for i in range(16):
					if (c.textures[i] == handle): c.textures[i] = 0
			elif (kind == 3): glDeleteShader(cast(int, object.id))
			elif (kind == 4):
				glDeleteProgram(cast(int, object.id))
				if (c.program == handle):
					glUseProgram(0)
					c.program = 0
			else:
				glDeleteVertexArrays(1, &object.id)
				if (c.vao == handle): c.vao = 0
			object.kind = -kind
	elif (strcmp(method, c"bindBuffer") == 0):
		int handle = win_gl_handle(c, args, 1, 1, 1)
		if (a != GL_ARRAY_BUFFER && a != GL_ELEMENT_ARRAY_BUFFER): win_canvas_error(c, 0x0500)
		elif (handle >= 0):
			glBindBuffer(a, win_gl_id(c, handle))
			if (a == GL_ARRAY_BUFFER): c.array_buffer = handle
			else: win_gl_array(c).elements = handle
	elif (strcmp(method, c"bufferData") == 0 || strcmp(method, c"bufferSubData") == 0):
		int handle = win_gl_buffer(c, a)
		if (handle == 0): win_canvas_error(c, 0x0502)
		else:
			win_gl_object* buffer = c.objects[handle]
			int index = 1
			int offset = 0
			int sub = strcmp(method, c"bufferSubData") == 0
			if (sub):
				index = 2
				offset = b
			if (args.length <= index): win_canvas_error(c, 0x0501)
			else:
				char* data = cast(char*, js_runtime_binary_data(rt, args[index]))
				int length = js_runtime_binary_byte_length(rt, args[index])
				if (sub == 0 && args[index].kind == 3): length = b
				if (length < 0 || length > WIN_CANVAS_BYTES || offset < 0 || (data == 0 && (sub || args[index].kind != 3))): win_canvas_error(c, 0x0501)
				elif (sub && (offset > buffer.length || length > buffer.length - offset)): win_canvas_error(c, 0x0501)
				elif (sub == 0 && (d != GL_STATIC_DRAW && d != GL_DYNAMIC_DRAW && d != GL_STREAM_DRAW)): win_canvas_error(c, 0x0500)
				elif (sub == 0 && c.allocated - buffer.length + length > WIN_CANVAS_BYTES): win_canvas_error(c, 0x0505)
				else:
					if (sub == 0):
						c.allocated = c.allocated - buffer.length + length
						if (buffer.bytes != 0): free(buffer.bytes)
						buffer.bytes = cast(char*, win_canvas_alloc(length + 1))
						buffer.length = length
					for i in range(length):
						if (data != 0): buffer.bytes[offset + i] = data[i]
					if (sub): glBufferSubData(a, offset, length, buffer.bytes + offset)
					else: glBufferData(a, length, buffer.bytes, d)
	elif (strcmp(method, c"bindVertexArray") == 0):
		int handle = win_gl_handle(c, args, 0, 5, 1)
		if (handle >= 0):
			glBindVertexArray(win_gl_id(c, handle))
			c.vao = handle
	elif (strcmp(method, c"enableVertexAttribArray") == 0 || strcmp(method, c"disableVertexAttribArray") == 0):
		if (a < 0 || a >= 16): win_canvas_error(c, 0x0501)
		else:
			int enabled = strcmp(method, c"enableVertexAttribArray") == 0
			win_gl_array(c).attribs[a].enabled = enabled
			if (enabled): glEnableVertexAttribArray(a)
			else: glDisableVertexAttribArray(a)
	elif (strcmp(method, c"vertexAttribPointer") == 0):
		int size = win_gl_type_size(d)
		if (a < 0 || a >= 16 || b < 1 || b > 4 || f < 0 || f > 255 || g < 0): win_canvas_error(c, 0x0501)
		elif (size == 0): win_canvas_error(c, 0x0500)
		elif (c.array_buffer == 0 || g % size != 0 || f % size != 0): win_canvas_error(c, 0x0502)
		else:
			win_gl_attrib* attr = &win_gl_array(c).attribs[a]
			attr.buffer = c.array_buffer
			attr.size = b
			attr.type = d
			attr.stride = f
			attr.offset = g
			glVertexAttribPointer(a, b, d, e != 0, f, g)
	elif (strcmp(method, c"drawArrays") == 0 || strcmp(method, c"drawElements") == 0):
		int indexed = strcmp(method, c"drawElements") == 0
		int count = d
		int last = b + d - 1
		int valid = 1
		if (a < 0 || a > 6):
			win_canvas_error(c, 0x0500)
			valid = 0
		if (indexed):
			count = b
			int size = win_gl_type_size(d)
			int handle = win_gl_array(c).elements
			if (d != GL_UNSIGNED_BYTE && d != 0x1403 && d != GL_UNSIGNED_INT): valid = 0
			elif (handle == 0 || e < 0 || e % size != 0 || b < 0): valid = 0
			else:
				win_gl_object* buffer = c.objects[handle]
				if (e > buffer.length || b > (buffer.length - e) / size): valid = 0
				else:
					last = -1
					for i in range(b):
						int value = 0
						for part in range(size): value = value | ((buffer.bytes[e + i * size + part] & 255) << (part * 8))
						if (value > last): last = value
		elif (b < 0 || d < 0): valid = 0
		if (count > 1048576 || (indexed == 0 && b > 2147483647 - count)): valid = 0
		if (valid == 0 || win_gl_draw_bounds(c, last) == 0): win_canvas_error(c, 0x0502)
		elif (count > 0):
			if (indexed): glDrawElements(a, b, d, e)
			else: glDrawArrays(a, b, d)
			c.dirty = 1
	elif (strcmp(method, c"activeTexture") == 0):
		if (a < GL_TEXTURE0 || a >= GL_TEXTURE0 + 16): win_canvas_error(c, 0x0500)
		else:
			c.active_texture = a - GL_TEXTURE0
			glActiveTexture(a)
	elif (strcmp(method, c"bindTexture") == 0):
		int handle = win_gl_handle(c, args, 1, 2, 1)
		if (a != GL_TEXTURE_2D): win_canvas_error(c, 0x0500)
		elif (handle >= 0):
			c.textures[c.active_texture] = handle
			glBindTexture(a, win_gl_id(c, handle))
	elif (strcmp(method, c"texParameteri") == 0):
		if (a != GL_TEXTURE_2D || (b != GL_TEXTURE_MIN_FILTER && b != GL_TEXTURE_MAG_FILTER && b != GL_TEXTURE_WRAP_S && b != GL_TEXTURE_WRAP_T)): win_canvas_error(c, 0x0500)
		elif (c.textures[c.active_texture] == 0): win_canvas_error(c, 0x0502)
		else: glTexParameteri(a, b, d)
	elif (strcmp(method, c"texImage2D") == 0 || strcmp(method, c"texSubImage2D") == 0):
		int sub = strcmp(method, c"texSubImage2D") == 0
		int width = e
		int height = f
		int format = h
		int type = j
		if (sub):
			width = f
			height = g
		int length = win_gl_pixel_length(width, height, format, type, c.unpack_alignment)
		int handle = c.textures[c.active_texture]
		if (a != GL_TEXTURE_2D || b != 0 || length < 0): win_canvas_error(c, 0x0501)
		elif (handle == 0 || args.length < 9): win_canvas_error(c, 0x0502)
		else:
			win_gl_object* texture = c.objects[handle]
			char* pixels = cast(char*, js_runtime_binary_data(rt, args[8]))
			int null_data = args[8].kind == 1
			if ((pixels == 0 || js_runtime_binary_byte_length(rt, args[8]) < length) && (sub || null_data == 0)): win_canvas_error(c, 0x0502)
			elif (sub && (d < 0 || e < 0 || d > texture.width - width || e > texture.height - height)): win_canvas_error(c, 0x0501)
			elif (sub == 0 && (g != 0 || (d != GL_R8 && d != GL_RGBA8) || (d == GL_R8 && format != GL_RED) || (d == GL_RGBA8 && format != GL_RGBA))): win_canvas_error(c, 0x0501)
			elif (sub == 0 && c.allocated - texture.length + width * height * 4 > WIN_CANVAS_BYTES): win_canvas_error(c, 0x0505)
			elif (sub): glTexSubImage2D(a, b, d, e, width, height, format, type, pixels)
			else:
				# WebGL zero-initializes null uploads; native GL does not.
				if (null_data): pixels = cast(char*, win_canvas_alloc(length + 1))
				glTexImage2D(a, b, d, width, height, 0, format, type, pixels)
				if (null_data): free(pixels)
				c.allocated = c.allocated - texture.length + width * height * 4
				texture.length = width * height * 4
				texture.width = width
				texture.height = height
	elif (strcmp(method, c"shaderSource") == 0):
		int handle = win_gl_handle(c, args, 0, 3, 0)
		if (handle > 0 && args.length > 1):
			if (args[1].kind != 4 || args[1].text.units.length > 262144): win_canvas_error(c, 0x0501)
			else:
				int length = 0
				char* source = js_text_to_utf8(args[1].text, &length)
				glShaderSource(win_gl_id(c, handle), 1, &source, 0)
				free(source)
	elif (strcmp(method, c"compileShader") == 0):
		int handle = win_gl_handle(c, args, 0, 3, 0)
		if (handle > 0): glCompileShader(win_gl_id(c, handle))
	elif (strcmp(method, c"attachShader") == 0):
		int program = win_gl_handle(c, args, 0, 4, 0)
		int shader = win_gl_handle(c, args, 1, 3, 0)
		if (program > 0 && shader > 0): glAttachShader(win_gl_id(c, program), win_gl_id(c, shader))
	elif (strcmp(method, c"linkProgram") == 0):
		int handle = win_gl_handle(c, args, 0, 4, 0)
		if (handle > 0):
			glLinkProgram(win_gl_id(c, handle))
			int32 status = 0
			glGetProgramiv(win_gl_id(c, handle), GL_LINK_STATUS, &status)
			c.objects[handle].linked = cast(int, status)
			c.objects[handle].generation = c.objects[handle].generation + 1
	elif (strcmp(method, c"useProgram") == 0):
		int handle = win_gl_handle(c, args, 0, 4, 1)
		if (handle > 0 && c.objects[handle].linked == 0): win_canvas_error(c, 0x0502)
		elif (handle >= 0):
			glUseProgram(win_gl_id(c, handle))
			c.program = handle
	elif (strcmp(method, c"getShaderParameter") == 0 || strcmp(method, c"getProgramParameter") == 0 || strcmp(method, c"getShaderInfoLog") == 0 || strcmp(method, c"getProgramInfoLog") == 0):
		int shader = strcmp(method, c"getShaderParameter") == 0 || strcmp(method, c"getShaderInfoLog") == 0
		int log = strcmp(method, c"getShaderInfoLog") == 0 || strcmp(method, c"getProgramInfoLog") == 0
		int kind = 4
		if (shader): kind = 3
		int handle = win_gl_handle(c, args, 0, kind, 0)
		if (handle > 0):
			if (log):
				char* source = cast(char*, win_canvas_alloc(65536))
				int32 length = 0
				if (shader): glGetShaderInfoLog(win_gl_id(c, handle), 65535, &length, source)
				else: glGetProgramInfoLog(win_gl_id(c, handle), 65535, &length, source)
				result = win_gl_string(rt, source)
				free(source)
			else:
				int32 value = 0
				if ((shader && b != GL_COMPILE_STATUS && b != GL_INFO_LOG_LENGTH && b != 0x8B4F && b != 0x8B80) || (shader == 0 && b != GL_LINK_STATUS && b != GL_INFO_LOG_LENGTH && b != 0x8B80 && b != 0x8B85 && b != 0x8B86 && b != 0x8B89)): win_canvas_error(c, 0x0500)
				else:
					if (shader): glGetShaderiv(win_gl_id(c, handle), b, &value)
					else: glGetProgramiv(win_gl_id(c, handle), b, &value)
					if (b == GL_LINK_STATUS || b == GL_COMPILE_STATUS || b == 0x8B80): result = js_runtime_boolean(rt, cast(int, value))
					else: result = js_runtime_number(rt, cast(float64, value))
	elif (strcmp(method, c"getAttribLocation") == 0 || strcmp(method, c"getUniformLocation") == 0):
		int handle = win_gl_handle(c, args, 0, 4, 0)
		if (handle > 0 && args.length > 1 && args[1].kind == 4):
			if (args[1].text.units.length > 1024 || c.objects[handle].linked == 0): win_canvas_error(c, 0x0502)
			else:
				int length = 0
				char* name = js_text_to_utf8(args[1].text, &length)
				if (strcmp(method, c"getAttribLocation") == 0): result = js_runtime_number(rt, cast(float64, glGetAttribLocation(win_gl_id(c, handle), name)))
				else:
					int location = glGetUniformLocation(win_gl_id(c, handle), name)
					if (location < 0): result = js_runtime_alloc(rt, 1)
					else:
						result = win_gl_object_new(c, rt, 6, location + 1)
						if (result.kind == 5):
							win_gl_object* uniform = c.objects[c.objects.length - 1]
							uniform.owner = handle
							uniform.generation = c.objects[handle].generation
				free(name)
	elif (strcmp(method, c"uniform1i") == 0 || strcmp(method, c"uniform1f") == 0 || strcmp(method, c"uniform2f") == 0 || strcmp(method, c"uniform3f") == 0 || strcmp(method, c"uniform4f") == 0 || strcmp(method, c"uniformMatrix4fv") == 0):
		int handle = win_gl_handle(c, args, 0, 6, 1)
		if (handle > 0):
			win_gl_object* uniform = c.objects[handle]
			if (c.program != uniform.owner || c.objects[uniform.owner].generation != uniform.generation): win_canvas_error(c, 0x0502)
			else:
				int location = cast(int, uniform.id) - 1
				if (strcmp(method, c"uniform1i") == 0): glUniform1i(location, b)
				elif (strcmp(method, c"uniform1f") == 0): glUniform1f(location, win_gl_float(args, 1))
				elif (strcmp(method, c"uniform2f") == 0): glUniform2f(location, win_gl_float(args, 1), win_gl_float(args, 2))
				elif (strcmp(method, c"uniform3f") == 0): glUniform3f(location, win_gl_float(args, 1), win_gl_float(args, 2), win_gl_float(args, 3))
				elif (strcmp(method, c"uniform4f") == 0): glUniform4f(location, win_gl_float(args, 1), win_gl_float(args, 2), win_gl_float(args, 3), win_gl_float(args, 4))
				elif (args.length < 3 || b != 0): win_canvas_error(c, 0x0501)
				else:
					int length = js_runtime_binary_byte_length(rt, args[2])
					byte* data = js_runtime_binary_data(rt, args[2])
					if (data == 0 || length % 64 != 0 || length > WIN_CANVAS_BYTES): win_canvas_error(c, 0x0501)
					else: glUniformMatrix4fv(location, length / 64, 0, cast(float32*, data))
	else: win_canvas_error(c, 0x0502)
	win_canvas_leave(c)
	return result

# Borrowed bootstrap text; parent binds __winGL and owns context identity.
char* win_canvas_bootstrap():
	return c"function __winGLContext(id){var gl={};gl.viewport=function(a,b,c,d){return __winGL(id,'viewport',a,b,c,d);};gl.scissor=function(a,b,c,d){return __winGL(id,'scissor',a,b,c,d);};gl.clearColor=function(a,b,c,d){return __winGL(id,'clearColor',a,b,c,d);};gl.clear=function(a){return __winGL(id,'clear',a);};gl.enable=function(a){return __winGL(id,'enable',a);};gl.disable=function(a){return __winGL(id,'disable',a);};gl.blendFunc=function(a,b){return __winGL(id,'blendFunc',a,b);};gl.getError=function(){return __winGL(id,'getError');};gl.finish=function(){return __winGL(id,'finish');};gl.flush=function(){return __winGL(id,'flush');};gl.pixelStorei=function(a,b){return __winGL(id,'pixelStorei',a,b);};gl.getParameter=function(a){return __winGL(id,'getParameter',a);};gl.readPixels=function(a,b,c,d,e,f,g){return __winGL(id,'readPixels',a,b,c,d,e,f,g);};gl.createBuffer=function(){return __winGL(id,'createBuffer');};gl.deleteBuffer=function(a){return __winGL(id,'deleteBuffer',a);};gl.bindBuffer=function(a,b){return __winGL(id,'bindBuffer',a,b);};gl.bufferData=function(a,b,c){return __winGL(id,'bufferData',a,b,c);};gl.bufferSubData=function(a,b,c){return __winGL(id,'bufferSubData',a,b,c);};gl.createVertexArray=function(){return __winGL(id,'createVertexArray');};gl.deleteVertexArray=function(a){return __winGL(id,'deleteVertexArray',a);};gl.bindVertexArray=function(a){return __winGL(id,'bindVertexArray',a);};gl.enableVertexAttribArray=function(a){return __winGL(id,'enableVertexAttribArray',a);};gl.disableVertexAttribArray=function(a){return __winGL(id,'disableVertexAttribArray',a);};gl.vertexAttribPointer=function(a,b,c,d,e,f){return __winGL(id,'vertexAttribPointer',a,b,c,d,e,f);};gl.drawArrays=function(a,b,c){return __winGL(id,'drawArrays',a,b,c);};gl.drawElements=function(a,b,c,d){return __winGL(id,'drawElements',a,b,c,d);};gl.createTexture=function(){return __winGL(id,'createTexture');};gl.deleteTexture=function(a){return __winGL(id,'deleteTexture',a);};gl.bindTexture=function(a,b){return __winGL(id,'bindTexture',a,b);};gl.texImage2D=function(a,b,c,d,e,f,g,h,j){return __winGL(id,'texImage2D',a,b,c,d,e,f,g,h,j);};gl.texSubImage2D=function(a,b,c,d,e,f,g,h,j){return __winGL(id,'texSubImage2D',a,b,c,d,e,f,g,h,j);};gl.texParameteri=function(a,b,c){return __winGL(id,'texParameteri',a,b,c);};gl.activeTexture=function(a){return __winGL(id,'activeTexture',a);};gl.createShader=function(a){return __winGL(id,'createShader',a);};gl.shaderSource=function(a,b){return __winGL(id,'shaderSource',a,b);};gl.compileShader=function(a){return __winGL(id,'compileShader',a);};gl.getShaderParameter=function(a,b){return __winGL(id,'getShaderParameter',a,b);};gl.getShaderInfoLog=function(a){return __winGL(id,'getShaderInfoLog',a);};gl.deleteShader=function(a){return __winGL(id,'deleteShader',a);};gl.createProgram=function(){return __winGL(id,'createProgram');};gl.attachShader=function(a,b){return __winGL(id,'attachShader',a,b);};gl.linkProgram=function(a){return __winGL(id,'linkProgram',a);};gl.getProgramParameter=function(a,b){return __winGL(id,'getProgramParameter',a,b);};gl.getProgramInfoLog=function(a){return __winGL(id,'getProgramInfoLog',a);};gl.useProgram=function(a){return __winGL(id,'useProgram',a);};gl.deleteProgram=function(a){return __winGL(id,'deleteProgram',a);};gl.getAttribLocation=function(a,b){return __winGL(id,'getAttribLocation',a,b);};gl.getUniformLocation=function(a,b){return __winGL(id,'getUniformLocation',a,b);};gl.uniform1i=function(a,b){return __winGL(id,'uniform1i',a,b);};gl.uniform1f=function(a,b){return __winGL(id,'uniform1f',a,b);};gl.uniform2f=function(a,b,c){return __winGL(id,'uniform2f',a,b,c);};gl.uniform3f=function(a,b,c,d){return __winGL(id,'uniform3f',a,b,c,d);};gl.uniform4f=function(a,b,c,d,e){return __winGL(id,'uniform4f',a,b,c,d,e);};gl.uniformMatrix4fv=function(a,b,c){return __winGL(id,'uniformMatrix4fv',a,b,c);};gl.isContextLost=function(){return __winGL(id,'isContextLost');};gl.DEPTH_BUFFER_BIT=0x100;gl.COLOR_BUFFER_BIT=0x4000;gl.POINTS=0x0000;gl.LINES=0x0001;gl.TRIANGLES=0x0004;gl.TRIANGLE_STRIP=0x0005;gl.TRIANGLE_FAN=0x0006;gl.DEPTH_TEST=0x0B71;gl.CULL_FACE=0x0B44;gl.BLEND=0x0BE2;gl.SCISSOR_TEST=0x0C11;gl.TEXTURE_2D=0x0DE1;gl.UNSIGNED_BYTE=0x1401;gl.UNSIGNED_INT=0x1405;gl.FLOAT=0x1406;gl.RGBA=0x1908;gl.VENDOR=0x1F00;gl.RENDERER=0x1F01;gl.VERSION=0x1F02;gl.SRC_ALPHA=0x0302;gl.ONE_MINUS_SRC_ALPHA=0x0303;gl.ARRAY_BUFFER=0x8892;gl.ELEMENT_ARRAY_BUFFER=0x8893;gl.STATIC_DRAW=0x88E4;gl.DYNAMIC_DRAW=0x88E8;gl.FRAGMENT_SHADER=0x8B30;gl.VERTEX_SHADER=0x8B31;gl.COMPILE_STATUS=0x8B81;gl.LINK_STATUS=0x8B82;gl.INFO_LOG_LENGTH=0x8B84;gl.TEXTURE0=0x84C0;gl.TEXTURE_MAG_FILTER=0x2800;gl.TEXTURE_MIN_FILTER=0x2801;gl.TEXTURE_WRAP_S=0x2802;gl.TEXTURE_WRAP_T=0x2803;gl.NEAREST=0x2600;gl.LINEAR=0x2601;gl.CLAMP_TO_EDGE=0x812F;gl.RED=0x1903;gl.R8=0x8229;gl.RGBA8=0x8058;gl.UNPACK_ALIGNMENT=0x0CF5;gl.STREAM_DRAW=0x88E0;gl.NO_ERROR=0;gl.INVALID_ENUM=0x500;gl.INVALID_VALUE=0x501;gl.INVALID_OPERATION=0x502;gl.OUT_OF_MEMORY=0x505;gl.UNSIGNED_SHORT=0x1403;gl.PACK_ALIGNMENT=0x0D05;gl.ZERO=0;gl.ONE=1;return gl;}"
