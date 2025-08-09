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
}

ColliderShape :: enum {
	NONE,
	RECTANGLE,
	CIRCLE,
}

Entity :: struct {
	id:       i32,
	type:     EntityType,
	position: rl.Vector2,
	velocity: rl.Vector2,
	color:    rl.Color,
	update:   proc(entity: ^Entity, deltaTime: f32), // Update function for the entity
	size:     rl.Vector2, // Size of the entity
	lifetime: f32, // For particles - time until removal
}

entities: [dynamic]Entity

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


update_entity :: proc(entity: ^Entity, deltaTime: f32) {
	// Update entity logic based on its type
	#partial switch entity_type := entity.type; entity_type {
	case EntityType.PLAYER:
		{
			// input handling
			if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
				entity.velocity.x = -400
			} else if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
				entity.velocity.x = 400
			} else {
				entity.velocity.x = 0
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

update :: proc() {
	deltaTime := rl.GetFrameTime()

	for &entity in entities {
		update_entity(&entity, deltaTime)
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
		entity.velocity.y = -entity.velocity.y
		// Move the ball above the player
		entity.position.y = player.position.y - ball_radius
	}

	// collision check any blocks
	for &block in entities {
		if block.type == EntityType.BLOCK &&
		   rect_collide_circle(block.position, block.size, entity.position, entity.size.x / 2) {

			fmt.printf("Collision with block at position: %v\n", block.position)
			fmt.printf("Entity position: %v\n", block.size)
			fmt.printf("Entity position: %v\n", entity.position)
			fmt.printf("Entity size: %v\n", entity.position)


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
	// Clamp player position to window bounds
	if entity.position.x < 0 {
		entity.position.x = 0
	} else if (entity.position.x + entity.size.x) > cast(f32)rl.GetScreenWidth() {
		entity.position.x = cast(f32)rl.GetScreenWidth() - entity.size.x
	}

	if entity.position.y < 0 {
		entity.position.y = 0
	} else if (entity.position.y + entity.size.y) > cast(f32)rl.GetScreenHeight() {
		entity.position.y = cast(f32)rl.GetScreenHeight() - entity.size.y
	}

}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	for &entity in entities {
		switch entity.type {
		case EntityType.PLAYER:
			fallthrough // Player is drawn as a rectangle
		case EntityType.BLOCK:
			rl.DrawRectangleV(entity.position, entity.size, entity.color)
		case EntityType.BALL:
			rl.DrawCircleV(
				rl.Vector2{entity.position.x, entity.position.y},
				entity.size.x / 2,
				entity.color,
			)
		case .TOMBSTONE:
		}
		// Tombstone is not drawn, but could be added later
	}

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
	append(
		&entities,
		// add the player
		Entity {
			id       = id(),
			type     = EntityType.PLAYER,
			position = rl.Vector2{cast(f32)windowWidth / 2 - 64, cast(f32)windowHeight - 64},
			size     = rl.Vector2{128, 32},
			velocity = rl.Vector2{0, 0},
			color    = rl.WHITE,
			update   = update_player, // Assign the player update function
		},
		// add a ball
		Entity {
			id       = id(),
			type     = EntityType.BALL,
			position = rl.Vector2{cast(f32)windowWidth / 2, cast(f32)windowHeight / 2},
			size     = rl.Vector2{32, 32},
			velocity = rl.Vector2{200, 200},
			color    = rl.RED,
			update   = update_ball, // Assign the ball update function
		},
	)
	// add some blocks, dynamically sized
	rows: i32 = 3
	cols: i32 = 5
	padding: i32 = 10
	block_width := (windowWidth / cols) - padding
	block_height: i32 = 50
	for i in 0 ..< cols {
		for j in 0 ..< rows {
			append(
				&entities,
				Entity {
					id = id(),
					type = EntityType.BLOCK,
					position = rl.Vector2 {
						cast(f32)(i * (block_width + padding) + padding / 2),
						cast(f32)(j * (block_height + padding) + padding / 2),
					},
					size = rl.Vector2{cast(f32)block_width, cast(f32)block_height},
					velocity = rl.Vector2{0, 0},
					color = rl.BLUE,
				},
			)
		}
	}
}

main :: proc() {
	rl.InitWindow(windowWidth, windowHeight, "Odin Brickbreaker")

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
