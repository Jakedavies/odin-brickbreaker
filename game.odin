package game

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"


windowWidth: i32 = 1280
windowHeight: i32 = 720

EntityType :: enum {
	PLAYER,
	BALL,
	BLOCK,
	TOMBSTONE,
	PARTICLE,
}

ColliderShape :: enum {
	NONE,
	RECTANGLE,
	CIRCLE,
}

Entity :: struct {
	id:            i32,
	type:          EntityType,
	position:      rl.Vector2,
	velocity:      rl.Vector2,
	color:         rl.Color,
	update:        proc(entity: ^Entity, deltaTime: f32), // Update function for the entity
	size:          rl.Vector2, // Size of the entity
	tick_lifetime: bool,
	lifetime:      f32,
}

entities: [dynamic]Entity
tombstone_indices: [dynamic]int // Track available slots from removed entities

entity_count: i32 = 0
id :: proc() -> i32 {
	entity_count += 1
	return entity_count
}


game_state :: enum {
	PLAYING,
	PAUSED,
	GAME_OVER,
}

State :: struct {
	current: game_state,
	// Add more state variables as needed
	score:   i32,
}

state := State {
	current = game_state.PLAYING,
	score   = 0,
}
// Input handling with acceleration/deceleration for inertia
max_speed: f32 = 600
acceleration: f32 = 2000
friction: f32 = 1500

// Entity management functions

add_entity :: proc(entity: Entity) -> ^Entity {
	if len(tombstone_indices) > 0 {
		// Reuse a tombstone slot
		index := pop(&tombstone_indices)
		entities[index] = entity
		return &entities[index]
	} else {
		// Add new entity at the end
		append(&entities, entity)
		return &entities[len(entities) - 1]
	}
}

remove_entity :: proc(index: int) {
	// Find the index of this entity and add it to tombstone list
	if index < 0 || index >= len(entities) {
		rl.TraceLog(rl.TraceLogLevel.WARNING, "Invalid entity index for removal")
		return
	}
	append(&tombstone_indices, index)
	entities[index].type = EntityType.TOMBSTONE

}

update_entity :: proc(entity: ^Entity, deltaTime: f32) {
	// Update entity logic based on its type
	#partial switch entity_type := entity.type; entity_type {
	case EntityType.PLAYER:
		{
			target_velocity: f32 = 0
			if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
				target_velocity = -max_speed
			} else if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
				target_velocity = max_speed
			}

			// Apply acceleration or friction
			if target_velocity != 0 {
				// Accelerate towards target velocity
				if entity.velocity.x < target_velocity {
					entity.velocity.x += acceleration * deltaTime
					if entity.velocity.x > target_velocity {
						entity.velocity.x = target_velocity
					}
				} else if entity.velocity.x > target_velocity {
					entity.velocity.x -= acceleration * deltaTime
					if entity.velocity.x < target_velocity {
						entity.velocity.x = target_velocity
					}
				}
			} else {
				// Apply friction when no input
				if entity.velocity.x > 0 {
					entity.velocity.x -= friction * deltaTime
					if entity.velocity.x < 0 {
						entity.velocity.x = 0
					}
				} else if entity.velocity.x < 0 {
					entity.velocity.x += friction * deltaTime
					if entity.velocity.x > 0 {
						entity.velocity.x = 0
					}
				}
			}
		}
	}

	entity.position.x += entity.velocity.x * deltaTime
	entity.position.y += entity.velocity.y * deltaTime

	if entity.update != nil {
		// Call the entity's specific update function if it exists
		entity.update(entity, deltaTime)
	}
}

create_explosion_particles :: proc(position: rl.Vector2, size: rl.Vector2, color: rl.Color) {
	particle_count := 20
	for i in 0 ..< particle_count {
		angle := (cast(f32)i / cast(f32)particle_count) * math.PI * 2
		speed := 200 + cast(f32)rl.GetRandomValue(0, 200)

		particle := Entity {
			id            = id(),
			type          = EntityType.PARTICLE,
			position      = rl.Vector2{position.x + size.x / 2, position.y + size.y / 2},
			velocity      = rl.Vector2{math.cos(angle) * speed, math.sin(angle) * speed},
			size          = rl.Vector2 {
				cast(f32)rl.GetRandomValue(3, 8),
				cast(f32)rl.GetRandomValue(3, 8),
			},
			color         = rl.Color{color.r, color.g, color.b, 255},
			lifetime      = 1.0,
			tick_lifetime = true, // Sparkles will tick down their lifetime
		}
		add_entity(particle)
	}

	// Add extra sparkles
	for i in 0 ..< 10 {
		angle := cast(f32)rl.GetRandomValue(0, 360) * math.PI / 180
		speed := 300 + cast(f32)rl.GetRandomValue(0, 300)

		sparkle := Entity {
			id            = id(),
			type          = EntityType.PARTICLE,
			position      = rl.Vector2{position.x + size.x / 2, position.y + size.y / 2},
			velocity      = rl.Vector2{math.cos(angle) * speed, math.sin(angle) * speed},
			size          = rl.Vector2{2, 2},
			color         = rl.Color{255, 255, 255, 255},
			lifetime      = 0.5,
			tick_lifetime = true, // Sparkles will tick down their lifetime
		}
		add_entity(sparkle)
	}
}

update_particle :: proc(entity: ^Entity, deltaTime: f32) {
	if entity.tick_lifetime {
		entity.lifetime -= deltaTime
	}

	// Apply gravity
	entity.velocity.y += 400 * deltaTime

	// Fade out
	if entity.lifetime > 0 {
		alpha_ratio := entity.lifetime / 1.0
		entity.color.a = cast(u8)(255 * alpha_ratio)
	}
}

update :: proc() {
	deltaTime := rl.GetFrameTime()

	for i := 0; i < len(entities); i += 1 {
		entity := &entities[i]
		// Skip tombstoned entities
		if entity.type == EntityType.TOMBSTONE {
			continue
		}

		update_entity(entity, deltaTime)

		// Update particles and tombstone them when dead
		if entity.type == EntityType.PARTICLE {
			update_particle(entity, deltaTime)
		}

		if entity.lifetime <= 0 && entity.tick_lifetime {
			remove_entity(i)
		}
	}

}

get_player :: proc() -> ^Entity {
	for &entity in entities {
		if entity.type == EntityType.PLAYER {
			return &entity
		}
	}
	// if no player, error fatal
	rl.TraceLog(rl.TraceLogLevel.FATAL, "No player entity found")
	panic("No player entity found")
}

update_ball :: proc(entity: ^Entity, deltaTime: f32) {
	// Bounce off walls
	ball_radius := entity.size.x / 2
	if entity.position.x - ball_radius < 0 ||
	   entity.position.x + ball_radius > cast(f32)rl.GetScreenWidth() {
		entity.velocity.x = -entity.velocity.x
	}
	if entity.position.y - ball_radius < 0 {
		entity.velocity.y = -entity.velocity.y
	}
	if entity.position.y + ball_radius > cast(f32)rl.GetScreenHeight() {
		// you lose
		state.current = game_state.GAME_OVER
		return
	}
	// check player position
	player := get_player()
	if entity.position.y + ball_radius >= player.position.y &&
	   entity.position.x + ball_radius >= player.position.x &&
	   entity.position.x - ball_radius <= player.position.x + player.size.x {
		// Bounce off player
		entity.velocity.y = -abs(entity.velocity.y)

		// Add paddle velocity influence
		paddle_influence: f32 = 0.5 // How much the paddle speed affects the ball
		entity.velocity.x += player.velocity.x * paddle_influence

		// Add angle based on hit position for more control
		hit_position := (entity.position.x - player.position.x) / player.size.x
		angle_modifier := (hit_position - 0.5) * 400 // -200 to +200 based on hit location
		entity.velocity.x += angle_modifier

		// Clamp ball speed to prevent it from going too fast
		max_ball_speed: f32 = 600
		ball_speed := math.sqrt(
			entity.velocity.x * entity.velocity.x + entity.velocity.y * entity.velocity.y,
		)
		if ball_speed > max_ball_speed {
			scale := max_ball_speed / ball_speed
			entity.velocity.x *= scale
			entity.velocity.y *= scale
		}

		// Move the ball above the player to prevent multiple collisions
		entity.position.y = player.position.y - ball_radius
	}

	// collision check any blocks
	for &block in entities {
		if block.type == EntityType.BLOCK &&
		   rect_collide_circle(block.position, block.size, entity.position, entity.size.x / 2) {

			// Create explosion particles
			create_explosion_particles(block.position, block.size, block.color)

			block.type = EntityType.TOMBSTONE // Mark block as a tombstone
			state.score += 1 // Increment score

			// Bounce off the block
			if entity.position.x + entity.size.x / 2 < block.position.x ||
			   entity.position.x + entity.size.x / 2 > block.position.x + block.size.x {
				entity.velocity.x = -entity.velocity.x
			} else {
				entity.velocity.y = -entity.velocity.y
			}
		}
	}
}

update_player :: proc(entity: ^Entity, deltaTime: f32) {
	// Clamp player position to window bounds and stop velocity when hitting edges
	if entity.position.x < 0 {
		entity.position.x = 0
		if entity.velocity.x < 0 {
			entity.velocity.x = 0 // Stop leftward movement at left edge
		}
	} else if (entity.position.x + entity.size.x) > cast(f32)rl.GetScreenWidth() {
		entity.position.x = cast(f32)rl.GetScreenWidth() - entity.size.x
		if entity.velocity.x > 0 {
			entity.velocity.x = 0 // Stop rightward movement at right edge
		}
	}

	if entity.position.y < 0 {
		entity.position.y = 0
		if entity.velocity.y < 0 {
			entity.velocity.y = 0
		}
	} else if (entity.position.y + entity.size.y) > cast(f32)rl.GetScreenHeight() {
		entity.position.y = cast(f32)rl.GetScreenHeight() - entity.size.y
		if entity.velocity.y > 0 {
			entity.velocity.y = 0
		}
	}

}

draw_paddle :: proc(entity: ^Entity) {
	// Metallic base layer
	rl.DrawRectangleV(entity.position, entity.size, rl.Color{40, 40, 50, 255})

	// Main gradient body
	topColor := rl.Color{100, 120, 180, 255}
	bottomColor := rl.Color{60, 70, 120, 255}
	rl.DrawRectangleGradientV(
		cast(i32)entity.position.x,
		cast(i32)entity.position.y,
		cast(i32)entity.size.x,
		cast(i32)entity.size.y,
		topColor,
		bottomColor,
	)

	// Highlight strip
	highlightHeight := entity.size.y * 0.3
	rl.DrawRectangleV(
		entity.position,
		rl.Vector2{entity.size.x, highlightHeight},
		rl.Color{150, 170, 220, 120},
	)

	// Edge glow effects
	edgeWidth: f32 = 3
	rl.DrawRectangleV(
		rl.Vector2{entity.position.x, entity.position.y},
		rl.Vector2{edgeWidth, entity.size.y},
		rl.Color{180, 200, 255, 180},
	)
	rl.DrawRectangleV(
		rl.Vector2{entity.position.x + entity.size.x - edgeWidth, entity.position.y},
		rl.Vector2{edgeWidth, entity.size.y},
		rl.Color{180, 200, 255, 180},
	)

	// Center power indicator
	centerWidth := entity.size.x * 0.4
	centerX := entity.position.x + (entity.size.x - centerWidth) / 2
	rl.DrawRectangleV(
		rl.Vector2{centerX, entity.position.y + entity.size.y * 0.3},
		rl.Vector2{centerWidth, entity.size.y * 0.4},
		rl.Color{100, 255, 200, 80},
	)
}

draw_brick :: proc(entity: ^Entity) {
	// Shadow/depth effect
	shadowOffset: f32 = 2
	rl.DrawRectangleV(
		rl.Vector2{entity.position.x + shadowOffset, entity.position.y + shadowOffset},
		entity.size,
		rl.Color{0, 0, 0, 100},
	)

	// Base brick with gradient
	baseColor := entity.color
	darkColor := rl.Color {
		cast(u8)(cast(f32)baseColor.r * 0.6),
		cast(u8)(cast(f32)baseColor.g * 0.6),
		cast(u8)(cast(f32)baseColor.b * 0.6),
		baseColor.a,
	}
	rl.DrawRectangleGradientV(
		cast(i32)entity.position.x,
		cast(i32)entity.position.y,
		cast(i32)entity.size.x,
		cast(i32)entity.size.y,
		baseColor,
		darkColor,
	)

	// Inner frame
	frameThickness: f32 = 3
	innerPos := rl.Vector2{entity.position.x + frameThickness, entity.position.y + frameThickness}
	innerSize := rl.Vector2{entity.size.x - frameThickness * 2, entity.size.y - frameThickness * 2}
	rl.DrawRectangleLinesEx(
		rl.Rectangle{innerPos.x, innerPos.y, innerSize.x, innerSize.y},
		2,
		rl.Color{255, 255, 255, 50},
	)

	// Glossy highlight
	highlightHeight := entity.size.y * 0.35
	rl.DrawRectangleGradientV(
		cast(i32)entity.position.x,
		cast(i32)entity.position.y,
		cast(i32)entity.size.x,
		cast(i32)highlightHeight,
		rl.Color{255, 255, 255, 80},
		rl.Color{255, 255, 255, 0},
	)

	// Energy core effect in center
	coreSize := rl.Vector2{entity.size.x * 0.6, entity.size.y * 0.4}
	corePos := rl.Vector2 {
		entity.position.x + (entity.size.x - coreSize.x) / 2,
		entity.position.y + (entity.size.y - coreSize.y) / 2,
	}
	glowIntensity := cast(u8)(math.sin(cast(f64)rl.GetTime() * 3.0) * 30.0 + 50.0)
	rl.DrawRectangleV(
		corePos,
		coreSize,
		rl.Color{baseColor.r, baseColor.g, baseColor.b, glowIntensity},
	)
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	draw_shader()

	// Draw main entities
	for &entity in entities {
		switch entity.type {
		case .PLAYER:
			draw_paddle(&entity)
		case .BLOCK:
			draw_brick(&entity)
		case .BALL:
			// Enhanced ball with glow effect
			ballPos := rl.Vector2{entity.position.x, entity.position.y}
			ballRadius := entity.size.x / 2

			// Outer glow
			rl.DrawCircleV(ballPos, ballRadius * 2, rl.Color{255, 100, 100, 30})
			rl.DrawCircleV(ballPos, ballRadius * 1.5, rl.Color{255, 150, 150, 60})

			// Main ball
			rl.DrawCircleV(ballPos, ballRadius, entity.color)

			// Inner highlight
			highlightOffset := ballRadius * 0.3
			rl.DrawCircleV(
				rl.Vector2{ballPos.x - highlightOffset, ballPos.y - highlightOffset},
				ballRadius * 0.3,
				rl.Color{255, 255, 255, 180},
			)
		case .TOMBSTONE:
		case .PARTICLE:
		// Don't draw particles in the main loop
		}
	}

	// Draw particles on top with additive blending for glow effect
	rl.BeginBlendMode(rl.BlendMode.ADDITIVE)
	for &entity in entities {
		if entity.type == EntityType.PARTICLE {
			// Draw particle with glow
			rl.DrawCircleV(
				entity.position,
				entity.size.x,
				rl.Color{entity.color.r, entity.color.g, entity.color.b, entity.color.a},
			)
			// Extra glow layer
			rl.DrawCircleV(
				entity.position,
				entity.size.x * 2,
				rl.Color {
					entity.color.r,
					entity.color.g,
					entity.color.b,
					cast(u8)(cast(f32)entity.color.a * 0.3),
				},
			)
		}
	}
	rl.EndBlendMode()

	str: cstring = strings.clone_to_cstring(fmt.aprintf("Score: %d", state.score))
	// draw the score
	rl.DrawText(str, cast(i32)(windowWidth - 150), cast(i32)(10), 20, rl.WHITE)

	// If we are in game over state, draw the game over text
	if state.current == game_state.GAME_OVER {
		rl.DrawText(
			"Game Over",
			cast(i32)(windowWidth / 2 - 50),
			cast(i32)(windowHeight / 2 - 20),
			20,
			rl.RED,
		)
		rl.DrawText(
			"Press R to restart",
			cast(i32)(windowWidth / 2 - 80),
			cast(i32)(windowHeight / 2 + 10),
			20,
			rl.GRAY,
		)
	}


	rl.EndDrawing()
}

init :: proc() {
	// Clear entities and tombstones for fresh start
	clear(&entities)
	clear(&tombstone_indices)

	// Add the player
	add_entity(
		Entity {
			id            = id(),
			type          = EntityType.PLAYER,
			position      = rl.Vector2{cast(f32)windowWidth / 2 - 64, cast(f32)windowHeight - 64},
			size          = rl.Vector2{128, 32},
			velocity      = rl.Vector2{0, 0},
			color         = rl.WHITE,
			update        = update_player, // Assign the player update function
			tick_lifetime = false,
		},
	)

	// Add a ball
	add_entity(
		Entity {
			id            = id(),
			type          = EntityType.BALL,
			position      = rl.Vector2{cast(f32)windowWidth / 2, cast(f32)windowHeight / 2},
			size          = rl.Vector2{32, 32},
			velocity      = rl.Vector2{200, 200},
			color         = rl.RED,
			update        = update_ball, // Assign the ball update function
			tick_lifetime = false,
		},
	)

	// add some blocks, dynamically sized
	rows: i32 = 3
	cols: i32 = 5
	padding: i32 = 10
	block_width := (windowWidth / cols) - padding
	block_height: i32 = 50

	// Space-themed color palette for bricks
	colors := [3]rl.Color {
		rl.Color{255, 100, 200, 255}, // Nebula pink
		rl.Color{100, 200, 255, 255}, // Cosmic blue
		rl.Color{200, 100, 255, 255}, // Galaxy purple
	}

	for i in 0 ..< cols {
		for j in 0 ..< rows {
			add_entity(
				Entity {
					id            = id(),
					type          = EntityType.BLOCK,
					position      = rl.Vector2 {
						cast(f32)(i * (block_width + padding) + padding / 2),
						cast(f32)(j * (block_height + padding) + padding / 2),
					},
					size          = rl.Vector2{cast(f32)block_width, cast(f32)block_height},
					velocity      = rl.Vector2{0, 0},
					color         = colors[j % 3], // Cycle through colors by row
					tick_lifetime = false,
				},
			)
		}
	}
}

shader: rl.Shader
timeLocation: i32
resolutionLocation: i32

load_shader :: proc() -> rl.Shader {
	s := rl.LoadShader("res/shaders/lighting.vs", "res/shaders/lighting.fs")
	if s.id == 0 {
		rl.TraceLog(rl.TraceLogLevel.FATAL, "Failed to load shader")
		panic("Failed to load shader")
	}

	// Get uniform locations
	timeLocation = rl.GetShaderLocation(s, "iTime")
	resolutionLocation = rl.GetShaderLocation(s, "iResolution")

	return s
}

draw_shader :: proc() {
	// Update shader uniforms
	time := cast(f32)rl.GetTime()
	resolution := [2]f32{cast(f32)windowWidth, cast(f32)windowHeight}

	rl.SetShaderValue(shader, timeLocation, &time, rl.ShaderUniformDataType.FLOAT)
	rl.SetShaderValue(shader, resolutionLocation, &resolution, rl.ShaderUniformDataType.VEC2)

	// Draw the space background
	rl.BeginShaderMode(shader)
	rl.DrawRectangle(0, 0, windowWidth, windowHeight, rl.WHITE)
	rl.EndShaderMode()
}

main :: proc() {
	rl.InitWindow(windowWidth, windowHeight, "Odin Brickbreaker")

	shader = load_shader()

	init()

	for !rl.WindowShouldClose() {
		if state.current == game_state.PLAYING {
			update()
		} else if state.current == game_state.GAME_OVER {
			if rl.IsKeyPressed(.R) {
				// Reset the game
				clear(&entities)
				state.current = game_state.PLAYING

				init() // Reinitialize the game
			}
		}
		draw()
	}

	rl.CloseWindow()
}

rect_collide_circle :: proc(
	rect_pos: rl.Vector2, // top left
	rect_size: rl.Vector2,
	circle: rl.Vector2,
	radius: f32,
) -> bool {
	// Find the closest point on the rectangle to the circle
	closest_x := math.clamp(circle.x, rect_pos.x, rect_pos.x + rect_size.x)
	closest_y := math.clamp(circle.y, rect_pos.y, rect_pos.y + rect_size.y)

	// Calculate the distance from the circle's center to this closest point
	distance_x := circle.x - closest_x
	distance_y := circle.y - closest_y

	// If the distance is less than the radius, there is a collision
	return (distance_x * distance_x + distance_y * distance_y) < (radius * radius)
}
