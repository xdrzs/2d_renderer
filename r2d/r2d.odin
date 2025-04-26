// NOTE: Múltiplos shaders:
// 		 Bom, eu já estou usando múltiplos shaders ao passo que eu tenho o shader padrão que renderiza
// 		 tudo e o shader para os círculos. O processo pra usar mais um shader seria similar.
//       Ou daria pra chamar `flush`, usar o programa do novo shader com `UseProgram` e usar o `vertex_data` mesmo.
package r2d

import "base:intrinsics"

import    "core:fmt"
import    "core:os"
import    "core:os/os2"
import    "core:math"
import la "core:math/linalg"
import    "core:mem"
import    "core:time"

import gl    "vendor:OpenGL"
import       "vendor:glfw"
import stbi  "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"
import stbtt "vendor:stb/truetype"

// :Vertex
MAX_QUADS     :: 1024
MAX_TRIANGLES :: MAX_QUADS * 2
MAX_VERTICES  :: MAX_TRIANGLES * 3
Vertex :: struct {
	pos  : [2]f32,
	color: [4]f32,
	uv   : [2]f32,
	slot : f32,
}

// :Renderer
MAX_SLOTS :: 2
Renderer_2D :: struct {
	vao: u32,
	vbo: u32,

	window_size_width : ^i32,
	window_size_height: ^i32,

	shader: Shader,

	projection: matrix[4,4]f32,

	vertex_data : [MAX_VERTICES]Vertex,
	triangle_count: i32,

	circles: struct {
		vao: u32,
		vbo: u32,
		shader: Shader,
		vertex_data: [MAX_CIRCLES*6]Circle_Vertex,
		triangle_count: i32,
	},

	texture_slots: i32,
	slots: [MAX_SLOTS]Atlas,
	slot_of_all_white: i32,
}
r: Renderer_2D

Texture_Id :: enum {
	all_white,
	colored,
	arrow,
}

renderer_2d_init :: proc(texture_slot_of_all_white_image: i32, ctx_width, ctx_height: ^i32) {
	r.slot_of_all_white = texture_slot_of_all_white_image

	r.window_size_width  = ctx_width
	r.window_size_height = ctx_height

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.GenVertexArrays(1, &r.vao)
	gl.BindVertexArray(r.vao)
	defer gl.BindVertexArray(0)

	gl.GenBuffers(1, &r.vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	gl.BufferData(gl.ARRAY_BUFFER, MAX_VERTICES * size_of(Vertex), raw_data(r.vertex_data[:]), gl.DYNAMIC_DRAW)

	assert(size_of(Vertex) == 9 * size_of(f32)) // :Vertex => a gente precisa habilitar o atributo se a gente adicionar algo ao `Vertex`
	offset: i32
	n: i32 = 2
	id: u32
	gl.VertexAttribPointer(id, n, gl.FLOAT, false, size_of(Vertex), 0)
	gl.EnableVertexAttribArray(id)
	offset += n
	id += 1

	n = 4
	gl.VertexAttribPointer(id, n, gl.FLOAT, false, size_of(Vertex), uintptr(offset * size_of(f32)))
	gl.EnableVertexAttribArray(id)
	offset += n
	id += 1

	n = 2
	gl.VertexAttribPointer(id, n, gl.FLOAT, false, size_of(Vertex), uintptr(offset * size_of(f32)))
	gl.EnableVertexAttribArray(id)
	offset += n
	id += 1

	n = 1
	gl.VertexAttribPointer(id, n, gl.FLOAT, false, size_of(Vertex), uintptr(offset * size_of(f32)))
	gl.EnableVertexAttribArray(id)
	offset += n
	id += 1

	r.shader = shader_init(vert_shader, frag_shader)

	// :Circles
	gl.GenVertexArrays(1, &r.circles.vao)
	gl.BindVertexArray(r.circles.vao)
	defer gl.BindVertexArray(0)

	gl.GenBuffers(1, &r.circles.vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.circles.vbo)
	defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	gl.BufferData(gl.ARRAY_BUFFER, MAX_CIRCLES * 6 * size_of(Circle_Vertex), raw_data(r.circles.vertex_data[:]), gl.DYNAMIC_DRAW)

	// `pos`
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Circle_Vertex), 0)
	gl.EnableVertexAttribArray(0)

	// `col`
	gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Circle_Vertex), uintptr(2 * size_of(f32)))
	gl.EnableVertexAttribArray(1)

	// `uv`
	gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Circle_Vertex), uintptr(6 * size_of(f32)))
	gl.EnableVertexAttribArray(2)

	r.circles.shader = shader_init(circle_vert_shader, circle_frag_shader)
}

renderer_2d_begin :: proc() {
	r.triangle_count = 0
	r.circles.triangle_count = 0
}

flush :: proc(camera: Camera2D) {
	window_size := [2]f32{ f32(r.window_size_width^), f32(r.window_size_height^) }
	move := window_size * 0.5
	camera_view: matrix[4,4]f32 = 1.0 *
		transform_translate(camera.center) *
		transform_scale(1/camera.zoom) *
		transform_translate(-move) 

	r.projection = la.matrix_ortho3d_f32(0, window_size.x, window_size.y, 0, -1, 1, false)
	camera_view = la.inverse(camera_view)
	projection_view := r.projection * camera_view

	gl.BindVertexArray(r.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.vbo)
	gl.UseProgram(r.shader)

	loc := gl.GetUniformLocation(r.shader, "u_projection_view")
	assert(loc != -1)
	gl.UniformMatrix4fv(loc, 1, false, &projection_view[0][0])

	for i in 0..<r.texture_slots {
		name_in_shader := fmt.ctprintf("texture%v", i)
		gl.Uniform1i(gl.GetUniformLocation(r.shader, name_in_shader), i)

		which_slot := gl.TEXTURE0 + u32(i)
		gl.ActiveTexture(which_slot)
		gl.BindTexture(gl.TEXTURE_2D, r.slots[i].texture_id)
	}

	n_vertices := 3 * r.triangle_count
	gl.BufferSubData(gl.ARRAY_BUFFER, 0, int(n_vertices * size_of(Vertex)), raw_data(r.vertex_data[:]))
	gl.DrawArrays(gl.TRIANGLES, 0, n_vertices)

	r.triangle_count = 0
}

flush_circles :: proc(camera: Camera2D) {
	window_size := [2]f32{ f32(r.window_size_width^), f32(r.window_size_height^) }
	move := window_size * 0.5
	camera_view: matrix[4,4]f32 = 1.0 *
		transform_translate(camera.center) *
		transform_scale(1/camera.zoom) *
		transform_translate(-move) 

	r.projection = la.matrix_ortho3d_f32(0, window_size.x, window_size.y, 0, -1, 1, false)
	camera_view = la.inverse(camera_view)
	projection_view := r.projection * camera_view

	gl.BindVertexArray(r.circles.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.circles.vbo)
	gl.UseProgram(r.circles.shader)

	loc := gl.GetUniformLocation(r.circles.shader, "u_projection_view")
	assert(loc != -1)
	gl.UniformMatrix4fv(loc, 1, false, &projection_view[0][0])

	n_vertices := 3 * r.circles.triangle_count
	gl.BufferSubData(gl.ARRAY_BUFFER, 0, int(n_vertices * size_of(Circle_Vertex)), raw_data(r.circles.vertex_data[:]))
	gl.DrawArrays(gl.TRIANGLES, 0, n_vertices)

	r.circles.triangle_count = 0
}

renderer_2d_end :: proc(camera: Camera2D) {
	flush(camera)

	flush_circles(camera)

	gl.BindVertexArray(0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.UseProgram(0)
}

renderer_2d_init_texture :: proc(atlas: Atlas, atlas_data: []byte) -> i32 {
	which_slot := r.texture_slots
	r.slots[which_slot] = atlas
	r.texture_slots += 1

	gl.GenTextures(1, &r.slots[which_slot].texture_id)
	gl.BindTexture(gl.TEXTURE_2D, r.slots[which_slot].texture_id)
	defer gl.BindTexture(gl.TEXTURE_2D, 0)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, atlas.w, atlas.h, 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(atlas_data))
	gl.GenerateMipmap(gl.TEXTURE_2D)

	return which_slot
}

get_text_width :: proc(baked_font: ^Baked_Font, text: string) -> (width: f32) {
	curr: [2]f32
	for letter in text {
		if letter == '\n' {
			curr.x = 0
			continue
		}

		char_index := i32( letter - baked_font.font.first_char )
		// NOTE: From source:
		//    float x0,y0,s0,t0; // top-left
		//    float x1,y1,s1,t1; // bottom-right
		quad: stbtt.aligned_quad
		stbtt.GetPackedQuad(raw_data(baked_font.char_data[:]),
							baked_font.atlas.w, baked_font.atlas.h,
							char_index, &curr.x, &curr.y, &quad, false)

		if letter == ' ' do continue

		size: [2]f32
		size.x = abs(quad.x1 - quad.x0)
		if curr.x > width do width = curr.x
	}
	return
}

draw_text :: proc(baked_font: ^Baked_Font, text: string, pos: [2]f32, color: [4]f32) {
	ascent, descent, lineGap: i32
	stbtt.GetFontVMetrics(&baked_font.info, &ascent, &descent, &lineGap)
	font_scale := stbtt.ScaleForPixelHeight(&baked_font.info, baked_font.font.pixel_height)

	// É uma merda ter que calcular isso toda hora que a gente vai desenhar texto,
	// mas é o que tem pra hoje
	height: i32
	for letter in text {
		if letter == '\n' do break
		char_index := i32( letter - baked_font.font.first_char )
		x0, y0, x1, y1: i32
		stbtt.GetGlyphBox(&baked_font.info, char_index, &x0, &y0, &x1, &y1)

		glyph_height := abs(y1 - y0)
		if glyph_height > height do height = glyph_height
	}

	curr := pos
	curr.y += f32(height)*font_scale
	for letter in text {
		if letter == '\n' {
			curr.y += f32(ascent - descent + lineGap) * font_scale
			curr.x  = pos.x
			continue
		}

		char_index := i32( letter - baked_font.font.first_char )
		// NOTE: From source:
		//    float x0,y0,s0,t0; // top-left
		//    float x1,y1,s1,t1; // bottom-right
		quad: stbtt.aligned_quad
		stbtt.GetPackedQuad(raw_data(baked_font.char_data[:]),
							baked_font.atlas.w, baked_font.atlas.h,
							char_index, &curr.x, &curr.y, &quad, false)

		if letter == ' ' do continue

		size: [2]f32
		size.x = abs(quad.x1 - quad.x0)
		size.y = abs(quad.y1 - quad.y0)

		transform: matrix[4,4]f32 = 1 *
			transform_translate({quad.x0, quad.y0})

		uvs: [4]f32 = {quad.s0, quad.t0, quad.s1, quad.t1}
		draw_quad_transformed(transform, size, color, uvs, auto_cast baked_font.which_slot)
	}
}

draw_texture_by_center :: proc(which_slot: i32, id: Texture_Id, center: [2]f32, tint: [4]f32, scale: f32 = 1, radians: f32 = 0) {
	atlas := r.slots[which_slot]
	image := atlas.images[id]

	size: [2]f32
	size.x = cast(f32) image.w
	size.y = cast(f32) image.h

	move := [2]f32{0.5,0.5} * size

	transform: matrix[4,4]f32 = 1    *
		transform_translate(center)  *
		transform_rotate   (radians) *
		transform_scale    (scale)   *
		transform_translate(-move)
	
	draw_quad_transformed(transform, size, tint, image.uvs, which_slot)
}

draw_texture :: proc(which_slot: i32, id: Texture_Id, pos: [2]f32, tint: [4]f32, scale: f32 = 1, radians: f32 = 0) {
	atlas := r.slots[which_slot]
	image := atlas.images[id]

	size: [2]f32
	size.x = cast(f32) image.w
	size.y = cast(f32) image.h

	pivot_offset: [2]f32
	if radians != 0 {
		pivot_offset = 0.5
	}
	move := pivot_offset * size

	new_move := rotate_v2(move, radians)
	new_move.x, new_move.y = abs(new_move.x), abs(new_move.y)

	transform: matrix[4,4]f32 = 1 *
		transform_translate(pos) *
		transform_translate(new_move * scale) *
		transform_rotate   (radians) *
		transform_scale    (scale) *
		transform_translate(-move)
	
	draw_quad_transformed(transform, size, tint, image.uvs, which_slot)
}

draw_line :: proc(start: [2]f32, end: [2]f32, color: [4]f32, thickness: f32 = 1) {
	if thickness <= 0 do return

	dir     := la.normalize0(end - start)
	length  := la.length(end - start)
	if length <= 0 do return

	radians := la.angle_between([2]f32{1,0}, dir)
	if dir.y < 0 do radians = -radians

	size := [2]f32{length, thickness*2}
	pivot_offset :: [2]f32{0,0.5}
	move := pivot_offset * size

	transform: matrix[4,4]f32 = 1    *
		transform_translate(start)   *
		transform_rotate   (radians) *
		transform_translate(-move)

	atlas := r.slots[r.slot_of_all_white]
	id := Texture_Id.all_white
	image := atlas.images[id]
	draw_quad_transformed(transform, size, color, image.uvs, r.slot_of_all_white)
}

draw_rect :: proc(pos: [2]f32, size: [2]f32, color: [4]f32, radians: f32 = 0) {
	atlas := r.slots[r.slot_of_all_white]
	id := Texture_Id.all_white
	image := atlas.images[id]

	pivot_offset: [2]f32
	if radians != 0 {
		pivot_offset = 0.5
	}
	move := pivot_offset * size

	transform: matrix[4,4]f32 = 1           *
		transform_translate(pos + move * 1) *
		transform_rotate   (radians)        *
		transform_translate(-move)

	draw_quad_transformed(transform, size, color, image.uvs, r.slot_of_all_white)
}

draw_quad_transformed :: proc(transform: matrix[4,4]f32, size: [2]f32, color: [4]f32, uvs: [4]f32, which_slot: i32) {
	tl := [2]f32{0,0}
	tr := [2]f32{size.x,0}
	br := size
	bl := [2]f32{0,size.y}

	tl = (transform * [4]f32{tl.x, tl.y, 0, 1}).xy
	tr = (transform * [4]f32{tr.x, tr.y, 0, 1}).xy
	br = (transform * [4]f32{br.x, br.y, 0, 1}).xy
	bl = (transform * [4]f32{bl.x, bl.y, 0, 1}).xy

	a := Vertex{
		tl,
		color,
		uvs.xy,
		auto_cast which_slot,
	}

	b := Vertex{
		tr,
		color,
		uvs.zy,
		auto_cast which_slot,
	}

	c := Vertex{
		br,
		color,
		uvs.zw,
		auto_cast which_slot,
	}

	d := Vertex{
		bl,
		color,
		uvs.xw,
		auto_cast which_slot,
	}
	push_quad(a, b, c, d)
}

draw_circle :: proc(center: [2]f32, radius: f32, color: [4]f32) {
	size: [2]f32 = 2*radius

	transform: matrix[4,4]f32 = 1 *
		transform_translate(center - size*0.5)

	// Mesma coisa que `push_quad`, mas especificamente só pra círculos
	tl := [2]f32{0,0}
	tr := [2]f32{size.x,0}
	br := size
	bl := [2]f32{0,size.y}

	tl = (transform * [4]f32{tl.x, tl.y, 0, 1}).xy
	tr = (transform * [4]f32{tr.x, tr.y, 0, 1}).xy
	br = (transform * [4]f32{br.x, br.y, 0, 1}).xy
	bl = (transform * [4]f32{bl.x, bl.y, 0, 1}).xy

	a := Circle_Vertex{
		tl,
		color,
		{0,0},
	}

	b := Circle_Vertex{
		tr,
		color,
		{1,0},
	}

	c := Circle_Vertex{
		br,
		color,
		{1,1},
	}

	d := Circle_Vertex{
		bl,
		color,
		{0,1},
	}

	r.circles.vertex_data[r.circles.triangle_count * 3 + 0] = a
	r.circles.vertex_data[r.circles.triangle_count * 3 + 1] = b
	r.circles.vertex_data[r.circles.triangle_count * 3 + 2] = c
	r.circles.triangle_count += 1

	assert(r.circles.triangle_count < MAX_CIRCLES*2) // 2 triângulos por quad, 1 quad por círculo

	r.circles.vertex_data[r.circles.triangle_count * 3 + 0] = a
	r.circles.vertex_data[r.circles.triangle_count * 3 + 1] = c
	r.circles.vertex_data[r.circles.triangle_count * 3 + 2] = d
	r.circles.triangle_count += 1

	assert(r.circles.triangle_count < MAX_CIRCLES*2)
}

push_quad :: proc(tl, tr, br, bl: Vertex) {
	push_triangle(tl, tr, br)
	push_triangle(tl, br, bl)
}

push_triangle :: proc(a, b, c: Vertex) {
	r.vertex_data[r.triangle_count * 3 + 0] = a
	r.vertex_data[r.triangle_count * 3 + 1] = b
	r.vertex_data[r.triangle_count * 3 + 2] = c
	r.triangle_count += 1
	assert(r.triangle_count < MAX_TRIANGLES)
}

Image :: struct {
	w, h: i32,
	data: [^]byte,
	uvs : [4]f32,
}

generate_all_white :: proc(path: cstring) {
	color := [4]u8{255,255,255,255}
	stbi.write_png(path, 1, 1, 4, raw_data(color[:]), 1 * 4)
}

N_IMAGES :: 12
Atlas :: struct {
	w, h: i32,
	texture_id: u32,
	image_count: i32,
	images: [N_IMAGES]Image,
}

pack_into_atlas :: proc(atlas: ^Atlas, path: string, final_atlas_file_name: string, $T: typeid) -> []byte where intrinsics.type_is_enum(T) {
	ctx  : stbrp.Context
	nodes := make([]stbrp.Node, atlas.w*2, context.temp_allocator)
	stbrp.init_target(&ctx, atlas.w, atlas.h, &nodes[0], atlas.w*2)
	rects : [dynamic]stbrp.Rect
	for name, id in T {
		final_path := fmt.tprintf("%v/%v.png", path, name)

		dst := make([]u8, len(final_path)+1, context.temp_allocator)
		copy_from_string(dst[:], final_path)
		dst[len(dst)-1] = 0

		width, height, n_channels: i32
		data := stbi.load(cstring(raw_data(dst[:])), &width, &height, &n_channels, 0)
		assert(n_channels == 4)

		append(&rects, stbrp.Rect{ id = auto_cast id, w = auto_cast width, h = auto_cast height })
		image: Image
		image.w = width
		image.h = height
		image.data = data
		atlas.images[atlas.image_count] = image
		atlas.image_count += 1
	}

	ok := stbrp.pack_rects(&ctx, &rects[0], cast(i32) len(rects))
	if ok == 0 {
		assert(false, "failed to pack")
	}

	atlas_data, err2 := mem.alloc_bytes( cast(int) (atlas.w * atlas.h * 4) )
	if err2 != nil {
		assert(false, fmt.tprintln("we need more memory for the atlas:", err2))
	}

	for rect in rects {
		assert(cast(bool)rect.was_packed)
		image := &atlas.images[rect.id]

		for y in 0..<image.h {
			atlas_start := i32(rect.y) + y * atlas.w * 4 + i32(rect.x) * 4
			copy_slice(atlas_data[atlas_start:atlas_start + i32(rect.w) * 4],
					   image.data[y * image.w * 4:(y+1) * image.w * 4])
		}

		uvs  := &image.uvs
		uvs.x = cast(f32)rect.x / cast(f32)atlas.w
		uvs.y = cast(f32)rect.y / cast(f32)atlas.h
		uvs.z = uvs.x + cast(f32)image.w / cast(f32)atlas.w
		uvs.w = uvs.y + cast(f32)image.h / cast(f32)atlas.h

		stbi.image_free(image.data)
	}

	out := make([]u8, len(final_atlas_file_name)+1, context.temp_allocator)
	copy_from_string(out[:], final_atlas_file_name)
	out[len(out)-1] = 0
	stbi.write_png(cstring(raw_data(out[:])), atlas.w, atlas.h, 4, raw_data(atlas_data), 4 * atlas.w)
	return atlas_data
}

// :Font
N_CHARS :: 0xFF - 32 // Latin-1 Supplement
Font :: struct {
	pixel_height: f32,
	first_char  : rune,
}

Baked_Font :: struct {
	ctx: stbtt.pack_context,
	char_data: [N_CHARS]stbtt.packedchar,
	info: stbtt.fontinfo,

	font: Font,
	atlas: Atlas,
	which_slot: i32,
}

init_font :: proc(baked_font: ^Baked_Font, fullpath: string) -> []byte {
	font_data, err := os2.read_entire_file_from_path(fullpath, context.temp_allocator)
	assert(err == nil, fmt.tprintfln("Could not read file %v, error: %v", fullpath, err))

	assert(baked_font.atlas.w > 0 && baked_font.atlas.h > 0, "Atlas uninitialized")
	bit_map, err1 := mem.alloc_bytes(int(baked_font.atlas.w * baked_font.atlas.h))
	assert(err1 == .None, fmt.tprintln("Error allocating bitmap:", err1))

	ret := stbtt.PackBegin(&baked_font.ctx, raw_data(bit_map), baked_font.atlas.w, baked_font.atlas.h, 0, 1, nil)
	assert(ret == 1)


	ret = stbtt.PackFontRange(&baked_font.ctx, raw_data(font_data), 0,
					    baked_font.font.pixel_height, i32(baked_font.font.first_char), N_CHARS,
						raw_data(baked_font.char_data[:])
	)
	assert(ret > 0, fmt.tprintln("ret =", ret))
	stbtt.PackEnd(&baked_font.ctx)

	stbtt.InitFont(&baked_font.info, raw_data(font_data), 0)

	stbi.write_png("./r2d/font.png",
				   auto_cast baked_font.atlas.w,
				   auto_cast baked_font.atlas.h, 1, // `1` é o númerode canais "encodado" naquele byte
				   raw_data(bit_map), auto_cast baked_font.atlas.w)
	
	rgba_bit_map, err2 := mem.alloc_bytes(int(baked_font.atlas.w*baked_font.atlas.h) * 4)
	assert(err2 == .None, fmt.tprintln("Error allocating rgba_bitmap:", err2))
	for i in 0..<len(bit_map) {
		rgba_bit_map[4*i+0] = bit_map[i]
		rgba_bit_map[4*i+1] = bit_map[i]
		rgba_bit_map[4*i+2] = bit_map[i]
		rgba_bit_map[4*i+3] = bit_map[i]
	}
	free(raw_data(bit_map))
	return rgba_bit_map
}

// :Camera
Camera2D :: struct {
	center: [2]f32,
	zoom  : f32,
}

camera_make :: proc(width, height: i32) -> (c: Camera2D) {
	c.zoom = 1
	c.center = {f32(width)/2,f32(height)/2}
	return
}

Window_Context :: struct {
	window: glfw.WindowHandle,
	content_scale: [2]f32,
	width: i32,
	height: i32,
}
ctx: Window_Context

// :Shader
Shader :: u32

vert_shader: cstring = `
#version 330 core

layout (location = 0) in vec2  a_pos;
layout (location = 1) in vec4  a_color;
layout (location = 2) in vec2  a_uv;
layout (location = 3) in float a_slot;

out vec2  v_uv;
out vec4  v_color;
out float v_slot;

uniform mat4 u_projection_view;

void main() {
	gl_Position = u_projection_view * vec4(a_pos, 0., 1.);
	v_color = a_color;
	v_uv    = a_uv;
	v_slot  = a_slot;
}
`

frag_shader: cstring = `
#version 330 core

in vec4  v_color;
in vec2  v_uv;
in float v_slot;

out vec4 final_color;

uniform sampler2D texture0;
uniform sampler2D texture1;

void main() {
	vec4 col;
	if      ( v_slot == 0. ) col = texture(texture0, v_uv);
	else if ( v_slot == 1. ) col = texture(texture1, v_uv);

	col *= v_color;
	final_color = col;
}
`

shader_init :: proc(vertex, fragment: cstring) -> Shader {
	vertex := vertex
	vertex_shader := gl.CreateShader(gl.VERTEX_SHADER)
	gl.ShaderSource(vertex_shader, 1, &vertex, nil)
	gl.CompileShader(vertex_shader)

	success: i32
	SIZE :: 512
	info_log: [SIZE]u8
	gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		gl.GetShaderInfoLog(vertex_shader, SIZE, nil, raw_data(info_log[:]))
		fmt.println("ERROR::SHADER::VERTEX::COMPILATION_FAILED")
		fmt.println(string(info_log[:]))
		fmt.println(vertex)
	}

	fragment_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
	fragment := fragment
	gl.ShaderSource(fragment_shader, 1, &fragment, nil)
	gl.CompileShader(fragment_shader)

	gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		gl.GetShaderInfoLog(fragment_shader, SIZE, nil, raw_data(info_log[:]))
		fmt.println("ERROR::SHADER::FRAGMENT::COMPILATION_FAILED")
		fmt.println(string(info_log[:]))
		fmt.println(fragment)
	}

	shader := gl.CreateProgram()
	gl.AttachShader(shader, vertex_shader)
	gl.AttachShader(shader, fragment_shader)
	gl.LinkProgram(shader)
	gl.GetProgramiv(shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		gl.GetProgramInfoLog(shader, SIZE, nil, raw_data(info_log[:]))
		fmt.println("ERROR::PROGRAM::LINKAGE_FAILED")
		fmt.println(string(info_log[:]))
		fmt.println(fragment)
	}

	gl.DetachShader(shader, vertex_shader)
	gl.DetachShader(shader, fragment_shader)
	gl.DeleteShader(vertex_shader)
	gl.DeleteShader(fragment_shader)

	return shader
}

MAX_CIRCLES :: 512
Circle_Vertex :: struct {
	pos: [2]f32,
	col: [4]f32,
	uv : [2]f32,
}

circle_vert_shader: cstring = `
#version 330 core

layout (location = 0) in vec2 a_pos;
layout (location = 1) in vec4 a_color;
layout (location = 2) in vec2 a_uv;

out vec4 v_color;
out vec2 v_uv;

uniform mat4 u_projection_view;

void main() {
	gl_Position = u_projection_view * vec4(a_pos, 0., 1.);
	v_color = a_color;
	v_uv = a_uv;
}
`

circle_frag_shader: cstring = `
#version 330 core

in vec4 v_color;
in vec2 v_uv;

out vec4 final_color;

float circle(vec2 uv, vec2 center, float radius) {
	return step(length(uv - center), radius);
}

void main() {
	// :Circles: A gente sempre vai usar .5 aqui e cada quad vai ser um quadrado de lado 2*raio
	float c = circle(v_uv, vec2(.5), .5); 
	vec4 col = c * v_color;

	final_color = col;
}
`

transform_translate :: proc "contextless" (v: [2]f32) -> matrix[4,4]f32 {
	return la.matrix4_translate_f32({v.x,v.y,0})
}

transform_rotate :: proc "contextless" (radians: f32) -> matrix[4,4]f32 {
	return la.matrix4_rotate_f32(radians, {0,0,1})
}

transform_scale :: proc "contextless" (scale: f32) -> matrix[4,4]f32 {
	return la.matrix4_scale_f32({scale,scale,1})
}

rotate_v2 :: proc "contextless" (v: [2]f32, radians: f32) -> [2]f32 {
	cos := math.cos(radians)
	sin := math.sin(radians)
	return {
		v.x * cos - v.y * sin,
		v.x * sin + v.y * cos,
	}
}

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, i32(ctx.content_scale.x)*width, i32(ctx.content_scale.y)*height)
	ctx.width  = width
	ctx.height = height
}

window_content_scale_callback :: proc "c" (window: glfw.WindowHandle, xscale, yscale: f32) {
	ctx.content_scale.x, ctx.content_scale.y = xscale, yscale
}
