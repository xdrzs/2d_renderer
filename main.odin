package main

import "core:fmt"
import "core:os"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:time"

import    "vendor:glfw"
import gl "vendor:OpenGL"

import "r2d"

ctx := &r2d.ctx

main :: proc() {
	atlas: r2d.Atlas
	atlas.w = 1024
	atlas.h = 1024

	r2d.generate_all_white("./r2d/images/all_white.png")

	atlas_data := r2d.pack_into_atlas(&atlas, "./r2d/images", "./r2d/atlas.png", r2d.Texture_Id)

	font: r2d.Font
	font.first_char   = 32
	font.pixel_height = 32

	baked_font: r2d.Baked_Font
	baked_font.font = font
	baked_font.atlas.w = 512
	baked_font.atlas.h = 512

	font_atlas_data := r2d.init_font(&baked_font, "./r2d/fonts/básica_regular.ttf")

	if !glfw.Init() {
		fmt.println("GLFW error:", glfw.GetError())
		os.exit(1)
	}
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, gl.TRUE)

	ctx.width  = 800
	ctx.height = 600
	ctx.window = glfw.CreateWindow(ctx.width, ctx.height, "2D Renderer is not THAT hard", nil, nil)
	if ctx.window == nil {
		fmt.println("Failed to create GLFW window")
		glfw.Terminate()
		return
	}
	
	ctx.content_scale.x, ctx.content_scale.y = glfw.GetWindowContentScale(ctx.window)
	float_equals :: proc(v: f32, range: f32) -> bool {
		return abs(v - range) <= range
	}
	assert(float_equals(ctx.content_scale.x - math.floor(ctx.content_scale.x), 0.0001), fmt.tprintln("ctx.content_scale.x is some .number = ", ctx.content_scale.x))
	assert(float_equals(ctx.content_scale.y - math.floor(ctx.content_scale.y), 0.0001), fmt.tprintln("ctx.content_scale.y is some .number = ", ctx.content_scale.y))

	glfw.MakeContextCurrent(ctx.window)

	gl.load_up_to(3, 3, glfw.gl_set_proc_address) 

	gl.Viewport(0, 0, ctx.width*i32(ctx.content_scale.x), ctx.height*i32(ctx.content_scale.y))

	glfw.SetFramebufferSizeCallback(ctx.window, r2d.framebuffer_size_callback)
	glfw.SetWindowContentScaleCallback(ctx.window, r2d.window_content_scale_callback)
  
	r2d.renderer_2d_init(0, &ctx.width, &ctx.height)
	slot := r2d.renderer_2d_init_texture(atlas, atlas_data)
	baked_font.which_slot = r2d.renderer_2d_init_texture(baked_font.atlas, font_atlas_data)

	camera := r2d.camera_make(ctx.width, ctx.height)
	camera_ui := camera

	glfw.SwapInterval(0) // tentando tirar umas travadas do vsync

	// :init
	TOTAL_LIVES :: 5
	init :: proc() {
		gs.gravity = 128
		gs.lives   = TOTAL_LIVES

		gs.player.speed_base = 350

		gs.ball.radius = 10
		gs.ball.speed  = 300
		gs.ball.dir    = {1,1}
	}
	init()
	gs.player.size  = {100,30}
	player_start := [2]f32{f32(ctx.width)/2-gs.player.size.x/2, f32(ctx.height) - gs.player.size.y - 50}
	gs.player.pos = player_start
	gs.ball.center = {-100,-100}
	ball_radius_for_ui := gs.ball.radius

	level_layout(gs.level, camera)

	FPS: i64: 60
	frame_max_duration :: time.Duration(i64(time.Second) / FPS)

	frame_start := time.tick_now()
	for !glfw.WindowShouldClose(ctx.window) {
		dt := cast(f32) time.duration_seconds(frame_max_duration)

		// :input
		if glfw.GetKey(ctx.window, glfw.KEY_ESCAPE) == glfw.PRESS do glfw.SetWindowShouldClose(ctx.window, true)

		switch gs.state {
		case .level_start:
			if gs.lives > 0 {
				if glfw.GetKey(ctx.window, glfw.KEY_SPACE) == glfw.PRESS && gs.wait_a_few_secs <= 0 {
					gs.lives -= 1
					gs.state = .playing
					left   := camera.center.x - f32(ctx.width) /2/camera.zoom
					right  := camera.center.x + f32(ctx.width) /2/camera.zoom
					top    := camera.center.y - f32(ctx.height)/2/camera.zoom
					bottom := camera.center.y + f32(ctx.height)/2/camera.zoom

					normed: [2]f32
					normed.x = norm(f32(0), f32(ctx.width ), gs.ball.start_pos.x)
					normed.y = norm(f32(0), f32(ctx.height), gs.ball.start_pos.y)

					gs.ball.center.x = lerp(left, right , normed.x)
					gs.ball.center.y = lerp(top , bottom, normed.y)
				}
			}
			else {
				gs.state = .game_over
			}

			if      glfw.GetKey(ctx.window, glfw.KEY_D) == glfw.PRESS do gs.player.speed_curr =  gs.player.speed_base
			else if glfw.GetKey(ctx.window, glfw.KEY_A) == glfw.PRESS do gs.player.speed_curr = -gs.player.speed_base
			else                                                      do gs.player.speed_curr =  0


		case .playing:
			if      glfw.GetKey(ctx.window, glfw.KEY_D) == glfw.PRESS do gs.player.speed_curr =  gs.player.speed_base
			else if glfw.GetKey(ctx.window, glfw.KEY_A) == glfw.PRESS do gs.player.speed_curr = -gs.player.speed_base
			else                                                      do gs.player.speed_curr =  0

		case .zooming: break
		case .win: break

		case .game_over:
			if glfw.GetKey(ctx.window, glfw.KEY_SPACE) == glfw.PRESS {
				camera = r2d.camera_make(ctx.width, ctx.height)
				init()
				if gs.level != 1 {
					gs.player.size  = {100,30}
					player_start := [2]f32{f32(ctx.width)/2-gs.player.size.x/2, f32(ctx.height) - gs.player.size.y - 50}
					gs.player.pos = player_start
				}

				gs.level = 0
				clear(&gs.blocks)
				level_layout(gs.level, camera)
				gs.lives = TOTAL_LIVES
				gs.state = .level_start
				gs.wait_a_few_secs = 0.5
				gs.score = 0

			}

			if      glfw.GetKey(ctx.window, glfw.KEY_D) == glfw.PRESS do gs.player.speed_curr =  gs.player.speed_base
			else if glfw.GetKey(ctx.window, glfw.KEY_A) == glfw.PRESS do gs.player.speed_curr = -gs.player.speed_base
			else                                                      do gs.player.speed_curr =  0
		}

		left   := camera.center.x - f32(ctx.width)/2/camera.zoom
		right  := camera.center.x + f32(ctx.width)/2/camera.zoom
		top    := camera.center.y - f32(ctx.height)/2/camera.zoom
		bottom := camera.center.y + f32(ctx.height)/2/camera.zoom

		// :update
		if gs.wait_a_few_secs > 0 do gs.wait_a_few_secs -= dt

		if gs.state == .playing || gs.state == .level_start || gs.state == .game_over {
			new_x := gs.player.pos.x + gs.player.speed_curr * dt
			if new_x < left {
				gs.player.pos.x = left
			}
			else if new_x + gs.player.size.x > right {
				gs.player.pos.x = right - gs.player.size.x
			}
			else {
				gs.player.pos.x = new_x
			}
		}

		if gs.state == .playing {
			if collides(gs.ball, gs.player) { // Lição número 1 sobre programação: quando puder seja extremamente específico, ficar generalizando solução é coisa de babaca
				left  := abs(gs.player.pos.x - gs.ball.center.x)
				right := abs(gs.player.pos.x+gs.player.size.x - gs.ball.center.x)
				if left < right {
					gs.ball.center.x = gs.player.pos.x-gs.ball.radius
					gs.ball.dir.x = -1
				}
				else {
					gs.ball.center.x = gs.player.pos.x+gs.player.size.x+gs.ball.radius
					gs.ball.dir.x = 1
				}
			}
			ball_collisions(dt, left, right, top, bottom)
			if gs.ball.center.y - gs.ball.radius >= bottom {
				spawn_particles(15, gs.ball.center-gs.ball.radius, gs.ball.radius*2, GREEN, LIFETIME_DEFAULT, 5)
				gs.ball.center = -10000

				if gs.lives > 0 do gs.state = .level_start
				else            do gs.state = .game_over
			}

			if len(gs.blocks) == 0 {
				level_layout(gs.level, camera)
				spawn_particles(15, gs.ball.center-gs.ball.radius, gs.ball.radius*2, GREEN, LIFETIME_DEFAULT, 5)
				gs.ball.center = -10000
			}
		}
		else if gs.state == .zooming {
			camera.zoom = lerp(gs.camera_zoom_start, gs.camera_zoom_end, gs.camera_zoom_t)
			gs.camera_zoom_t += dt
			if gs.camera_zoom_t >= 1 {
				camera.zoom = gs.camera_zoom_end
				gs.state = .level_start
			}

			gs.player.pos.y = lerp(gs.player_pos_y_start, gs.player_pos_y_end, gs.player_pos_y_t)
			gs.player_pos_y_t += dt
		}
		else if gs.state == .win {
			gs.firework_spawn_at -= dt
			if gs.firework_spawn_at <= 0 {
				gs.firework_spawn_at = rand.float32_range(0, 3.5)

				firework: Firework
				firework.radius = rand.float32_range(4, 20)
				firework.pos.x  = rand.float32_range(left + 100, right - 100)
				firework.pos.y  = bottom + 100

				firework.pos_final.x  = rand.float32_range(camera.center.x - 100, camera.center.x + 100)
				firework.pos_final.y  = rand.float32_range(camera.center.y - 100, camera.center.y + 100)

				firework.color = rand.choice(all_colors[:])
				firework.speed = rand.float32_range(1000, 2000)

				append(&gs.fireworks, firework)
			}

			i: int = 0
			for i < len(gs.fireworks) {
				firework := &gs.fireworks[i]
				if float_equals(abs(firework.pos_final.x - firework.pos.x), 25) && float_equals(abs(firework.pos_final.y - firework.pos.y), 25) {
					MAX :: 30
					spawn_particles(int(firework.speed*0.002 * MAX), firework.pos, {}, firework.color, 3.5, firework.radius)
					unordered_remove(&gs.fireworks, i)
					continue
				}

				dir := linalg.normalize0(firework.pos_final - firework.pos)
				firework.pos += dir * firework.speed * dt

				i += 1
			}
		}
		
		i: int = 0
		for i < len(gs.particles) {
			particle := &gs.particles[i]
			if particle.lifetime_cur >= particle.lifetime_total {
				unordered_remove(&gs.particles, i)
				continue
			}

			particle.vel.y += dt * gs.gravity
			particle.pos   += particle.vel * dt

			particle.lifetime_cur += dt

			i += 1
		}
 
		// :render
		gl.ClearColor(0.0, 0.0, 0.0, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		r2d.renderer_2d_begin()
			for block in gs.blocks {
				r2d.draw_rect(block.pos, block.size, block.color)
			}
			r2d.flush(camera)

			for particle in gs.particles {
				color := particle.color
				color.a = 1 - norm(f32(0), particle.lifetime_total, particle.lifetime_cur)
				r2d.draw_circle(particle.pos, particle.radius, color)
			}
			r2d.flush_circles(camera)

			r2d.draw_rect(gs.player.pos, gs.player.size, RED)
			r2d.draw_circle(gs.ball.center, gs.ball.radius, GREEN)

			for firework in gs.fireworks {
				r2d.draw_circle(firework.pos, firework.radius, firework.color)
			}


		r2d.renderer_2d_end(camera)

		r2d.renderer_2d_begin()
			padding :: 20
			r2d.draw_text(&baked_font, fmt.tprintf("Pontuação: %v", gs.score), {padding, padding}, WHITE)

			text := "Vidas: "
			text_width := r2d.get_text_width(&baked_font, text)

			pad :: 4
			pos := [2]f32{
				f32(ctx.width)-text_width-(pad+ball_radius_for_ui*2)*TOTAL_LIVES-5,
				padding,
			}
			r2d.draw_text(&baked_font, text, pos, WHITE)
			curr_x := pos.x+text_width
			for i in 0..<gs.lives {
				curr_x += pad+ball_radius_for_ui
				curr_y := pos.y + ball_radius_for_ui
				defer curr_x += ball_radius_for_ui
				r2d.draw_circle({curr_x, curr_y}, ball_radius_for_ui, GREEN)

				gs.ball.start_pos = {curr_x, curr_y}
			}


			if gs.state == .level_start {
				if gs.lives == TOTAL_LIVES {
					r2d.draw_texture_by_center(slot, .arrow, {60,f32(ctx.height)-70}, WHITE, 2, math.PI/2)
					r2d.draw_text(&baked_font, "não deixa a bolinha passar daqui de baixo", {80,f32(ctx.height)-20}, WHITE)
				}
				r2d.draw_text(&baked_font, "pressione espaço para começar", {f32(ctx.width)/2,f32(ctx.height)/2}, WHITE)
			}
			else if gs.state == .win {
				r2d.draw_text(&baked_font, "parabains vc ganhol :)", {f32(ctx.width)/2,f32(ctx.height)/2}, WHITE)
			}
			else if gs.state == .game_over {
				r2d.draw_text(&baked_font, "vossa mercê perdestes, pressione\nespaço pra recomeçar", {f32(ctx.width)/2,f32(ctx.height)/2}, WHITE)
			}
		r2d.renderer_2d_end(camera_ui)

		glfw.SwapBuffers(ctx.window)
		glfw.PollEvents()

		// tentando manter o jogo a 60fps
		taken := time.tick_since(frame_start)
		assert(taken > 0)
		if taken < frame_max_duration {
			time.accurate_sleep(frame_max_duration - taken)
		}
		frame_start = time.tick_now()

	}
}

gs: Game_State
Game_State :: struct {
	player: Player,
	ball: Ball,
	blocks: [dynamic]Block,
	particles: [dynamic]Particle,
	fireworks: [dynamic]Firework,
	firework_spawn_at: f32,

	score: i32,
	level: i32,
	lives: i32,
	state: State,

	camera_zoom_start: f32,
	camera_zoom_end  : f32,
	camera_zoom_t    : f32,

	player_pos_y_start: f32,
	player_pos_y_end  : f32,
	player_pos_y_t    : f32,

	wait_a_few_secs: f32,

	using config: Config,
}

State :: enum {
	level_start,
	playing,
	zooming,
	win,
	game_over,
}

Config :: struct {
	gravity: f32,
}

Firework :: struct {
	pos      : [2]f32,
	pos_final: [2]f32,
	speed    : f32,
	radius   : f32,
	color    : [4]f32,
}

LIFETIME_DEFAULT :: 2.2
Particle :: struct {
	pos     : [2]f32,
	radius  : f32,
	vel     : [2]f32,
	color   : [4]f32,

	lifetime_total: f32,
	lifetime_cur: f32,
}

Block :: struct {
	pos  : [2]f32,
	size : [2]f32,
	color: [4]f32,
}

Player :: struct {
	pos  : [2]f32,
	size : [2]f32,

	speed_curr: f32,
	speed_base: f32,
}

Ball :: struct {
	start_pos: [2]f32,

	center: [2]f32,
	radius: f32,
	dir   : [2]f32,
	speed : f32,
}

get_extents_of_world_shown_on_camera :: proc(camera: r2d.Camera2D) -> [2]f32 {
	return {
		f32(ctx.width )/camera.zoom,
		f32(ctx.height)/camera.zoom,
	}
}

level_layout :: proc(level: i32, camera: r2d.Camera2D) {
	switch level {
	case 0:
		assert(len(gs.blocks) == 0)
		block_size :: [2]f32{70,40}
		padding    :: [2]f32{15, 20}
		n          :: [2]f32{6,3}
		size := n * (block_size + padding)

		start  := camera.center - size/2
		top    := camera.center.y - f32(ctx.height)/2/camera.zoom
		start.y = top + 0.2 * get_extents_of_world_shown_on_camera(camera).y

		for y in 0..<n.y {
			for x in 0..<n.x {
				block: Block
				block.pos  = start + [2]f32{f32(x),f32(y)} * (block_size + padding)
				block.size = block_size
				block.color = YELLOW
				append(&gs.blocks, block)
			}
		}
	case 1:
		gs.player.speed_base *= 2.2
		gs.ball.speed   *= 1.8
		gs.ball.radius  *= 2

		gs.camera_zoom_start = camera.zoom
		gs.camera_zoom_end   = camera.zoom / 2
		gs.camera_zoom_t     = 0


		block_size :: [2]f32{90,60}
		padding    :: [2]f32{15, 20}
		n          :: [2]f32{9,5}
		size := n * (block_size + padding)

		start  := camera.center - size/2
		top    := camera.center.y - f32(ctx.height)/2/gs.camera_zoom_end
		start.y = top + 0.1 * get_extents_of_world_shown_on_camera({ center = camera.center, zoom = gs.camera_zoom_end}).y

		for y in 0..<n.y {
			for x in 0..<n.x {
				block: Block
				block.pos  = start + [2]f32{f32(x),f32(y)} * (block_size + padding)
				block.size = block_size
				block.color = BLUE
				append(&gs.blocks, block)
			}
		}

		left   := camera.center.x - f32(ctx.width) /2/gs.camera_zoom_end
		right  := camera.center.x + f32(ctx.width) /2/gs.camera_zoom_end
		bottom := camera.center.y + f32(ctx.height)/2/gs.camera_zoom_end

		gs.player_pos_y_start = gs.player.pos.y
		gs.player_pos_y_end   = bottom - 200
		gs.player_pos_y_t     = 0

		block: Block
		block.pos  = {left+100, bottom-100}
		block.size = block_size + {100, 0}
		block.color = BLUE
		append(&gs.blocks, block)

		b := block
		b.pos.x = right-100-block.size.x
		append(&gs.blocks, b)
		gs.state = .zooming

	case 2:
		gs.state = .win

	case:
		assert(false, fmt.tprintfln("Haven't created level %v yet!", level))
	}
	gs.level += 1
}

all_colors := [][4]f32{
	YELLOW,
	BLUE  ,
	GREEN ,
	RED   ,
	{.3 ,0 ,.8 ,1},
	{.05,.8,.55,1},
	{1. ,.5,.0 ,1},
}

YELLOW :: [4]f32{1,1,0,1}
BLUE   :: [4]f32{0,0,1,1}
GREEN  :: [4]f32{0,1,0,1}
RED    :: [4]f32{1,0,0,1}

WHITE :[4]f32 : 1

norm :: proc(a, b, value: $T) -> T {
	return (value - a) / (b - a)
}

lerp :: proc(a, b: $T, t: f32) -> T {
	return a + (b - a) * t
}

collides_with_player :: proc(ball: Ball, player: Player) -> bool {
	switch {
		case ball.center.x + ball.radius < player.pos.x: return false
		case ball.center.x - ball.radius > player.pos.x + player.size.x: return false
		case ball.center.y + ball.radius < player.pos.y: return false
		case ball.center.y - ball.radius > player.pos.y + player.size.y: return false
	}
	return true
}

collides_with_block :: proc(ball: Ball, block: Block) -> bool {
	switch {
		case ball.center.x + ball.radius < block.pos.x: return false
		case ball.center.x - ball.radius > block.pos.x + block.size.x: return false
		case ball.center.y + ball.radius < block.pos.y: return false
		case ball.center.y - ball.radius > block.pos.y + block.size.y: return false
	}
	return true
}
collides :: proc{collides_with_player, collides_with_block}

hor_collisions :: proc(dt: f32, left, right: f32) {
	ball_new_x := gs.ball.center.x + gs.ball.dir.x * gs.ball.speed * dt
	new_ball := gs.ball
	new_ball.center.x = ball_new_x

	if ball_new_x + gs.ball.radius >= right {
		gs.ball.dir.x *= -1
		gs.ball.center.x = right-gs.ball.radius
		return
	}
	else if ball_new_x - gs.ball.radius <= left {
		gs.ball.dir.x *= -1
		gs.ball.center.x = left+gs.ball.radius
		return
	}

	if collides(new_ball, gs.player) {
		gs.ball.dir.x *= -1
		return
	}

	i: int
	for i < len(gs.blocks) {
		block := gs.blocks[i]
		if collides(new_ball, block) {
			gs.ball.dir.x *= -1

			spawn_particles(30, block.pos, block.size, block.color, LIFETIME_DEFAULT, 5)
			gs.score += 1
			unordered_remove(&gs.blocks, i)
			return
		}
		else {
			i += 1
		}
	}
	gs.ball.center.x = ball_new_x
}

ver_collisions :: proc(dt: f32, top, bottom: f32) {
	ball_new_y := gs.ball.center.y + gs.ball.dir.y * gs.ball.speed * dt
	new_ball := gs.ball
	new_ball.center.y = ball_new_y

	if ball_new_y - gs.ball.radius <= top {
		gs.ball.dir.y *= -1
		return
	}

	if collides(new_ball, gs.player) {
		if      gs.player.speed_curr > 0 do gs.ball.dir.x =  1
		else if gs.player.speed_curr < 0 do gs.ball.dir.x = -1
		gs.ball.dir.y *= -1
		return
	}

	i: int
	for i < len(gs.blocks) {
		block := gs.blocks[i]
		if collides(new_ball, block) {
			gs.ball.dir.y *= -1

			spawn_particles(30, block.pos, block.size, block.color, LIFETIME_DEFAULT, 5)
			gs.score += 1
			unordered_remove(&gs.blocks, i)
			return
		}
		else {
			i += 1
		}
	}

	gs.ball.center.y = ball_new_y
}

ball_collisions :: proc(dt: f32, left, right, top, bottom: f32) {
	hor_collisions(dt, left, right)
	ver_collisions(dt, top , bottom)
}

spawn_particles :: proc(count: int, pos: [2]f32, size: [2]f32, color: [4]f32, lifetime: f32, radius: f32) {
	for i in 0..<count {
		particle: Particle
		particle.radius = radius
		particle.lifetime_total = lifetime
		particle.color = color

		pos_x := rand.float32_range(pos.x, pos.x + size.x)
		pos_y := rand.float32_range(pos.y, pos.y + size.y)
		particle.pos = {pos_x,pos_y}

		vels := [?]f32{-1,0,1}
		vel_x := rand.choice(vels[:])
		vel_y := rand.choice(vels[:])
		speed := rand.float32_range(30, 70)
		particle.vel = {vel_x,vel_y} * speed

		append(&gs.particles, particle)
	}
}
