package game

import rl "vendor:raylib"


windowWidth: i32 = 1280
windowHeight: i32 = 720

EntityType :: enum {
	PLAYER,
	BALL,
	BLOCK,
}

Entity :: struct {
	id:       i32,
	type:     EntityType,
	position: rl.Vector2,
	size:     rl.Vector2,
	velocity: rl.Vector2,
	clamp:    bool, // Whether to clamp the entity's position within the window bounds
	color:    rl.Color,
	update:   proc(entity: ^Entity, deltaTime: f32), // Update function for the entity
}

entities: [dynamic]Entity

entity_count: i32 = 0
id :: proc() -> i32 {
	entity_count += 1
	return entity_count
}

update_entity :: proc(entity: ^Entity, deltaTime: f32) {
	// Update entity logic based on its type
	#partial switch entity_type := entity.type; entity_type {
	case EntityType.PLAYER:
		{
			// input handling
			if rl.IsKeyDown(.LEFT) {
				entity.velocity.x = -400
			} else if rl.IsKeyDown(.RIGHT) {
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


	// Clamp player position to window bounds
	if entity.clamp {
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
	if entity.position.x < 0 ||
	   (entity.position.x + entity.size.x) > cast(f32)rl.GetScreenWidth() {
		entity.velocity.x = -entity.velocity.x
	}
	if entity.position.y < 0 ||
	   (entity.position.y + entity.size.y) > cast(f32)rl.GetScreenHeight() {
		entity.velocity.y = -entity.velocity.y
	}
	// check player position
	player := get_player()
	if entity.position.y + entity.size.y >= player.position.y &&
	   entity.position.x + entity.size.x >= player.position.x &&
	   entity.position.x <= player.position.x + player.size.x {
		// Bounce off player
		entity.velocity.y = -entity.velocity.y
		// Move the ball above the player
		entity.position.y = player.position.y - entity.size.y
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
				rl.Vector2 {
					entity.position.x + entity.size.x / 2,
					entity.position.y + entity.size.y / 2,
				},
				entity.size.x / 2,
				entity.color,
			)
		}
	}

	rl.EndDrawing()
}

init :: proc() {
	append(
		&entities,
		// add the player
		Entity {
			id = id(),
			type = EntityType.PLAYER,
			position = rl.Vector2{cast(f32)windowWidth / 2 - 64, cast(f32)windowHeight - 64},
			size = rl.Vector2{128, 32},
			velocity = rl.Vector2{0, 0},
			clamp = true,
			color = rl.WHITE,
		},
		// add a ball
		Entity {
			id       = id(),
			type     = EntityType.BALL,
			position = rl.Vector2{cast(f32)windowWidth / 2 - 16, cast(f32)windowHeight / 2 - 16},
			size     = rl.Vector2{32, 32},
			velocity = rl.Vector2{200, 200},
			clamp    = true,
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
					clamp = true,
					color = rl.BLUE,
				},
			)
		}
	}

}

main :: proc() {
	rl.InitWindow(windowWidth, windowHeight, "My First Game")

	init()

	for !rl.WindowShouldClose() {
		update()
		draw()
	}

	rl.CloseWindow()
}
