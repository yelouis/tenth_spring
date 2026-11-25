class_name PlayerWalker
extends Node2D

## game/world/player_walker.gd — Emerald-Accurate 1-Tile Discrete Walking Character (Item 69 / Decisions 79–80)
## Contract: Decisions 79–80 (F77, F78, F81, F86); docs/implementation_plan_travel_and_time.md §(c)

const PlayerSprites := preload("res://world/player_sprites.gd")
const TileSynth2 := preload("res://world/tile_synth/tile_synth2.gd")

const TILE_PX: float = 32.0
const BUMP_DURATION_FRAMES: int = 32 # Emerald WALK_IN_PLACE_SLOW: 32 frames (16 foot + 16 stand)
const DUST_FRAME_COUNT: int = 3
const DUST_FRAME_DURATION_FRAMES: int = 8 # Emerald sAnim_GroundImpactDust: 3 * 8 = 24 frames

# Emerald sJumpY_High (src/event_object_movement.c:8393-8396) doubled for 32px tiles (1 entry per 2 frames of 32)
const LEDGE_HOP_Y_PX: Array[float] = [
	-8.0, -12.0, -16.0, -20.0, -22.0, -24.0, -24.0, -24.0,
	-22.0, -20.0, -18.0, -16.0, -12.0, -8.0, 0.0, 0.0
]

signal step_started(from_tile: Vector2i, to_tile: Vector2i, info: Dictionary)
signal step_completed(tile: Vector2i, info: Dictionary)
signal step_blocked(tile: Vector2i, info: Dictionary)
signal door_stepped(door_info: Dictionary)
signal turned(new_facing: String)
signal interact_pressed(facing_tile: Vector2i, standing_tile: Vector2i, facing_dir: String)
signal cancel_pressed()
signal visual_position_updated()

enum State { IDLE, TURNING, MOVING, BUMPING }

var grid_pos: Vector2i = Vector2i.ZERO
var render_origin_tile: Vector2i = Vector2i.ZERO
var facing: String = "S"
var sprite_index: int = 0
var input_enabled: bool = true
var live_input_enabled: bool = true

var _state: int = State.IDLE
var _move_kind: String = "walk" # "walk" | "run" | "ledge" | "slide"
var _move_from: Vector2i = Vector2i.ZERO
var _move_to: Vector2i = Vector2i.ZERO
var _move_info: Dictionary = {}
var _move_elapsed: float = 0.0
var _move_duration: float = 16.0 / 60.0
var _turn_elapsed: float = 0.0
var _turn_held_released: bool = false
var _bump_elapsed: float = 0.0
var _foot_parity: int = 0 # 0 = step_l, 1 = step_r
var _hop_offset_px: float = 0.0
var _cur_mode: String = "walk"
var _cur_pose: String = "stand"
var _force_no_rom: bool = false
var _step_evaluator: Callable = Callable()
var _visual_world_pos: Vector2 = Vector2.ZERO

var _shadow_sprite: Sprite2D = null
var _dust_sprite: Sprite2D = null
var _sprite: Sprite2D = null
var _dust_active: bool = false
var _dust_elapsed: float = 0.0
var _dust_frame: int = 0
var _dust_world_pos: Vector2 = Vector2.ZERO

func _init() -> void:
	# Run PlayerWalker._process before MapViewer._process so camera and sprite always lock to the same frame (F89)
	process_priority = -10
	# Shadow sits on ground under the player (Emerald FLDEFF_SHADOW: gFieldEffectObjectTemplate_ShadowMedium)
	_shadow_sprite = Sprite2D.new()
	_shadow_sprite.name = "JumpShadow"
	_shadow_sprite.centered = false
	_shadow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow_sprite.offset = Vector2(0.0, -16.0)
	_shadow_sprite.visible = false
	add_child(_shadow_sprite)

	# Player sprite drawn above shadow
	_sprite = Sprite2D.new()
	_sprite.name = "PlayerSprite"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.offset = Vector2(0.0, -64.0)
	add_child(_sprite)

	# Ground impact dust drawn in front of player feet on landing tile (Emerald FLDEFF_DUST: 16x8 -> 32x16)
	_dust_sprite = Sprite2D.new()
	_dust_sprite.name = "LandingDust"
	_dust_sprite.centered = false
	_dust_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dust_sprite.offset = Vector2(0.0, -12.0)
	_dust_sprite.visible = false
	add_child(_dust_sprite)
	_refresh_sprite_texture()
	_refresh_effect_textures()

func set_force_no_rom(enabled: bool) -> void:
	_force_no_rom = enabled
	_refresh_sprite_texture()
	_refresh_effect_textures()

func set_sprite_index(idx: int) -> void:
	sprite_index = clampi(idx, 0, 1)
	_refresh_sprite_texture()

func set_step_evaluator(fn: Callable) -> void:
	_step_evaluator = fn

static func _get_config() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		return (ml as SceneTree).root.get_node_or_null("/root/Config")
	return null

static func walk_step_duration() -> float:
	var cfg := _get_config()
	var frames := int(cfg.get("player_walk_frames_per_tile")) if (cfg != null and "player_walk_frames_per_tile" in cfg) else 16
	return float(maxi(1, frames)) / 60.0

static func run_step_duration() -> float:
	var cfg := _get_config()
	var frames := int(cfg.get("player_run_frames_per_tile")) if (cfg != null and "player_run_frames_per_tile" in cfg) else 8
	return float(maxi(1, frames)) / 60.0

static func ledge_hop_duration() -> float:
	var cfg := _get_config()
	var frames := int(cfg.get("player_ledge_hop_frames")) if (cfg != null and "player_ledge_hop_frames" in cfg) else 32
	return float(maxi(1, frames)) / 60.0

static func turn_delay_duration() -> float:
	var cfg := _get_config()
	var frames := int(cfg.get("player_turn_frames")) if (cfg != null and "player_turn_frames" in cfg) else 8
	return float(maxi(1, frames)) / 60.0

static func bump_duration() -> float:
	return float(BUMP_DURATION_FRAMES) / 60.0

static func dust_total_duration() -> float:
	return float(DUST_FRAME_COUNT * DUST_FRAME_DURATION_FRAMES) / 60.0

static func dir_vec_to_facing(dir: Vector2i) -> String:
	if dir.y < 0:
		return "N"
	if dir.y > 0:
		return "S"
	if dir.x < 0:
		return "W"
	if dir.x > 0:
		return "E"
	return ""

static func facing_to_dir_vec(dir_str: String) -> Vector2i:
	match dir_str.strip_edges().to_upper():
		"N":
			return Vector2i(0, -1)
		"S":
			return Vector2i(0, 1)
		"W":
			return Vector2i(-1, 0)
		"E":
			return Vector2i(1, 0)
		_:
			return Vector2i(0, 1)

static func tile_to_foot_world_pos(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) * TILE_PX, float(tile.y + 1) * TILE_PX)

func tile_to_foot_render_pos(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x - render_origin_tile.x) * TILE_PX, float(tile.y - render_origin_tile.y + 1) * TILE_PX)

func set_render_origin_tile(origin_tile: Vector2i) -> void:
	render_origin_tile = origin_tile
	if _state == State.MOVING:
		_update_moving_visual()
	else:
		_visual_world_pos = tile_to_foot_render_pos(grid_pos)
		position = Vector2(round(_visual_world_pos.x), round(_visual_world_pos.y))
		visual_position_updated.emit()

func place_at(tile: Vector2i, dir_str: String = "S", reset_parity: bool = true) -> void:
	grid_pos = tile
	facing = PlayerSprites.normalize_facing(dir_str)
	_state = State.IDLE
	_move_kind = "walk"
	_move_from = tile
	_move_to = tile
	_move_info = {}
	_move_elapsed = 0.0
	_turn_elapsed = 0.0
	_turn_held_released = false
	_bump_elapsed = 0.0
	_hop_offset_px = 0.0
	if reset_parity:
		_foot_parity = 0
	_dust_active = false
	_dust_elapsed = 0.0
	_dust_frame = 0
	_visual_world_pos = tile_to_foot_render_pos(tile)
	position = Vector2(round(_visual_world_pos.x), round(_visual_world_pos.y))
	_cur_mode = "walk"
	_cur_pose = "stand"
	if _shadow_sprite != null:
		_shadow_sprite.visible = false
	if _dust_sprite != null:
		_dust_sprite.visible = false
	_apply_sprite_visual()
	visual_position_updated.emit()

func is_moving() -> bool:
	return _state == State.MOVING

func is_turning() -> bool:
	return _state == State.TURNING

func is_bumping() -> bool:
	return _state == State.BUMPING

func is_shadow_visible() -> bool:
	return _shadow_sprite != null and _shadow_sprite.visible

func is_dust_visible() -> bool:
	return _dust_active and _dust_sprite != null and _dust_sprite.visible

func current_dust_frame() -> int:
	return _dust_frame if _dust_active else -1

func current_anim_mode() -> String:
	return _cur_mode

func current_anim_pose() -> String:
	return _cur_pose

func current_hop_offset_px() -> float:
	return _hop_offset_px

func facing_tile() -> Vector2i:
	return grid_pos + facing_to_dir_vec(facing)

func get_camera_target() -> Vector2:
	return Vector2(round(_visual_world_pos.x + TILE_PX * 0.5), round(_visual_world_pos.y - TILE_PX * 0.5))

func start_forced_slide(to_tile: Vector2i, slide_tiles: int, info: Dictionary = {}) -> void:
	_move_from = grid_pos
	_move_to = to_tile
	_move_info = info.duplicate(true)
	_move_kind = "slide"
	_move_elapsed = 0.0
	_move_duration = float(maxi(1, slide_tiles)) * (8.0 / 60.0) # Emerald 8 frames/tile = 7.5 tps
	_hop_offset_px = 0.0
	_state = State.MOVING
	_cur_mode = "walk"
	_cur_pose = "stand"
	if _shadow_sprite != null:
		_shadow_sprite.visible = false
	_apply_sprite_visual()

func _read_live_dir() -> Vector2i:
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		return Vector2i(0, -1)
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		return Vector2i(0, 1)
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		return Vector2i(-1, 0)
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		return Vector2i(1, 0)
	return Vector2i.ZERO

func _is_live_running() -> bool:
	return Input.is_key_pressed(KEY_SHIFT)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not live_input_enabled or not visible:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER or ke.keycode == KEY_SPACE or ke.keycode == KEY_Z:
				# Cannot interact during movement or a 32-frame wall bump (Decision 80 F86a)
				if _state == State.IDLE:
					interact_pressed.emit(facing_tile(), grid_pos, facing)
					get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ESCAPE or ke.keycode == KEY_X:
				cancel_pressed.emit()

func _process(delta: float) -> void:
	if not visible:
		return
	if not input_enabled or not live_input_enabled:
		if _state != State.IDLE or _dust_active:
			step_simulation(delta, Vector2i.ZERO, false)
		return
	step_simulation(delta, _read_live_dir(), _is_live_running())

func _advance_dust(dt: float) -> void:
	if not _dust_active:
		return
	_dust_elapsed += dt
	if _dust_elapsed + 1e-9 >= dust_total_duration():
		_dust_active = false
		_dust_elapsed = 0.0
		_dust_frame = 0
		if _dust_sprite != null:
			_dust_sprite.visible = false
		return
	var f_idx := clampi(floori(_dust_elapsed * 60.0 / float(DUST_FRAME_DURATION_FRAMES) + 1e-6), 0, DUST_FRAME_COUNT - 1)
	_dust_frame = f_idx
	if _dust_sprite != null:
		_dust_sprite.texture = PlayerSprites.resolve_dust_texture(f_idx, _force_no_rom)
		_dust_sprite.position = Vector2(round(_dust_world_pos.x - position.x), round(_dust_world_pos.y - position.y))
		_dust_sprite.visible = true

func _spawn_landing_dust(at_tile: Vector2i) -> void:
	_dust_active = true
	_dust_elapsed = 0.0
	_dust_frame = 0
	_dust_world_pos = tile_to_foot_render_pos(at_tile)
	if _dust_sprite != null:
		_dust_sprite.texture = PlayerSprites.resolve_dust_texture(0, _force_no_rom)
		_dust_sprite.position = Vector2(round(_dust_world_pos.x - position.x), round(_dust_world_pos.y - position.y))
		_dust_sprite.visible = true

func step_simulation(delta: float, held_dir: Vector2i, running: bool) -> void:
	var dt_total: float = maxf(0.0, delta)
	var dust_already_spawned := _dust_active
	var rem: float = dt_total
	var safety := 0
	while safety < 8:
		safety += 1
		if _state == State.BUMPING:
			# Emerald WALK_IN_PLACE_SLOW: runs full 32 frames before player can turn, step, or interact
			var bump_need: float = bump_duration() - _bump_elapsed
			if rem + 1e-9 >= bump_need:
				rem = maxf(0.0, rem - bump_need)
				_bump_elapsed = 0.0
				_foot_parity = 1 - _foot_parity
				_state = State.IDLE
				_cur_mode = "walk"
				_cur_pose = "stand"
				_apply_sprite_visual()
				if held_dir != Vector2i.ZERO:
					var req_f := dir_vec_to_facing(held_dir)
					if req_f == facing:
						_try_begin_step(held_dir, running)
						if rem > 1e-9 and (_state == State.MOVING or _state == State.BUMPING):
							continue
					else:
						# New direction after bump finishes starts a turn-in-place
						continue
				break
			else:
				_bump_elapsed += rem
				rem = 0.0
				_update_bumping_visual()
				break

		if _state == State.MOVING:
			var needed: float = _move_duration - _move_elapsed
			if rem + 1e-9 >= needed:
				rem = maxf(0.0, rem - needed)
				var expected_tile := _move_to
				_finish_current_move()
				if grid_pos != expected_tile or _state != State.IDLE:
					# Handler triggered a floor transition, teleport, or forced gust slide
					break
				if held_dir != Vector2i.ZERO and _move_kind != "slide":
					var next_dir_str := dir_vec_to_facing(held_dir)
					if next_dir_str != facing:
						facing = next_dir_str
						turned.emit(facing)
					_try_begin_step(held_dir, running)
					if rem > 1e-9 and (_state == State.MOVING or _state == State.BUMPING):
						continue
				break
			else:
				_move_elapsed += rem
				rem = 0.0
				_update_moving_visual()
				break

		if _state == State.TURNING:
			var req_t := dir_vec_to_facing(held_dir)
			if held_dir == Vector2i.ZERO or req_t != facing:
				_turn_held_released = true
			var turn_need: float = turn_delay_duration() - _turn_elapsed
			if rem + 1e-9 >= turn_need:
				rem = maxf(0.0, rem - turn_need)
				_turn_elapsed = 0.0
				_foot_parity = 1 - _foot_parity
				_state = State.IDLE
				_cur_mode = "walk"
				_cur_pose = "stand"
				_apply_sprite_visual()
				if not _turn_held_released and held_dir != Vector2i.ZERO and dir_vec_to_facing(held_dir) == facing:
					_try_begin_step(held_dir, running)
					if rem > 1e-9 and (_state == State.MOVING or _state == State.BUMPING):
						continue
				break
			else:
				_turn_elapsed += rem
				rem = 0.0
				_update_turning_visual()
				break

		# State.IDLE
		if held_dir == Vector2i.ZERO:
			break

		var req_facing := dir_vec_to_facing(held_dir)
		if req_facing != facing:
			# Emerald WALK_IN_PLACE_FAST: 8 frames (4 frames next foot + 4 frames stand)
			facing = req_facing
			_state = State.TURNING
			_turn_elapsed = 0.0
			_turn_held_released = false
			_update_turning_visual()
			turned.emit(facing)
			if rem <= 1e-9:
				break
			continue
		else:
			_try_begin_step(held_dir, running)
			if rem > 1e-9 and (_state == State.MOVING or _state == State.BUMPING):
				continue
			break

	if dust_already_spawned:
		_advance_dust(dt_total)
	elif _dust_active and _dust_sprite != null:
		# Dust spawned during this frame's landing: keep pinned on landing tile at frame 0
		_dust_sprite.position = Vector2(round(_dust_world_pos.x - position.x), round(_dust_world_pos.y - position.y))

func _try_begin_step(dir: Vector2i, running: bool) -> bool:
	var eval_res: Dictionary = {}
	if _step_evaluator.is_valid():
		eval_res = _step_evaluator.call(grid_pos, dir)
	else:
		eval_res = {"action": "step", "to": grid_pos + dir}

	var action := str(eval_res.get("action", "blocked"))
	if action == "door":
		_cur_mode = "walk"
		_cur_pose = "stand"
		_apply_sprite_visual()
		door_stepped.emit(eval_res)
		return false
	if action == "step":
		_move_from = grid_pos
		_move_to = eval_res.get("to", grid_pos + dir)
		_move_info = eval_res
		_move_kind = "run" if running else "walk"
		_move_elapsed = 0.0
		_move_duration = run_step_duration() if running else walk_step_duration()
		_hop_offset_px = 0.0
		_state = State.MOVING
		if _shadow_sprite != null:
			_shadow_sprite.visible = false
		_update_moving_visual()
		step_started.emit(_move_from, _move_to, eval_res)
		return true
	if action == "ledge":
		_move_from = grid_pos
		_move_to = eval_res.get("to", grid_pos + dir * 2)
		_move_info = eval_res
		_move_kind = "ledge"
		_move_elapsed = 0.0
		_move_duration = ledge_hop_duration()
		_state = State.MOVING
		if _shadow_sprite != null:
			_shadow_sprite.texture = PlayerSprites.resolve_shadow_texture(_force_no_rom)
			_shadow_sprite.visible = true
		_update_moving_visual()
		step_started.emit(_move_from, _move_to, eval_res)
		return true

	# Blocked: start Emerald 32-frame WALK_IN_PLACE_SLOW wall bump (Decision 80 F86a)
	_state = State.BUMPING
	_bump_elapsed = 0.0
	_update_bumping_visual()
	step_blocked.emit(eval_res.get("tile", grid_pos + dir), eval_res)
	return false

func _finish_current_move() -> void:
	var finished_info := _move_info
	var finished_kind := _move_kind
	grid_pos = _move_to
	_visual_world_pos = tile_to_foot_render_pos(grid_pos)
	position = Vector2(round(_visual_world_pos.x), round(_visual_world_pos.y))
	_hop_offset_px = 0.0
	_state = State.IDLE
	_move_elapsed = 0.0
	if _shadow_sprite != null:
		_shadow_sprite.visible = false
	if finished_kind == "ledge":
		# Ledge hop plays 2 full half-cycles (8 foot + 8 stand + 8 other foot + 8 stand), so parity returns cleanly.
		var land_cls: int = int(finished_info.get("landing_class", TileSynth2.TILE_GRASS))
		if land_cls != TileSynth2.TILE_TALL_GRASS and land_cls != TileSynth2.TILE_WATER:
			_spawn_landing_dust(grid_pos)
	elif finished_kind != "slide":
		_foot_parity = 1 - _foot_parity
	_cur_mode = "walk"
	_cur_pose = "stand"
	_apply_sprite_visual()
	visual_position_updated.emit()
	step_completed.emit(grid_pos, finished_info)

func _update_bumping_visual() -> void:
	# First 16 frames (t < 0.5) foot frame, last 16 frames (t >= 0.5) stand frame
	_cur_mode = "walk"
	_cur_pose = ("step_l" if _foot_parity == 0 else "step_r") if (_bump_elapsed + 1e-9 < 16.0 / 60.0) else "stand"
	_apply_sprite_visual()

func _update_turning_visual() -> void:
	# Emerald WALK_IN_PLACE_FAST: first 4 frames next foot frame, last 4 frames stand frame
	_cur_mode = "walk"
	_cur_pose = ("step_l" if _foot_parity == 0 else "step_r") if (_turn_elapsed + 1e-9 < 4.0 / 60.0) else "stand"
	_apply_sprite_visual()

func _update_moving_visual() -> void:
	var t: float = clampf(_move_elapsed / maxf(0.0001, _move_duration), 0.0, 1.0)
	var p0 := tile_to_foot_render_pos(_move_from)
	var p1 := tile_to_foot_render_pos(_move_to)
	_visual_world_pos = p0.lerp(p1, t)
	position = Vector2(round(_visual_world_pos.x), round(_visual_world_pos.y))
	visual_position_updated.emit()

	if _move_kind == "ledge":
		var f_idx := clampi(floori(_move_elapsed * 60.0 + 1e-6), 0, 31)
		_hop_offset_px = LEDGE_HOP_Y_PX[clampi(f_idx >> 1, 0, 15)]
		_cur_mode = "walk"
		# Normal walking cycle during 32-frame hop: 8f first foot, 8f stand, 8f other foot, 8f stand
		if f_idx < 8:
			_cur_pose = "step_l" if _foot_parity == 0 else "step_r"
		elif f_idx < 16:
			_cur_pose = "stand"
		elif f_idx < 24:
			_cur_pose = "step_r" if _foot_parity == 0 else "step_l"
		else:
			_cur_pose = "stand"
		if _shadow_sprite != null:
			_shadow_sprite.visible = true
	elif _move_kind == "run":
		_hop_offset_px = 0.0
		_cur_mode = "run"
		# Exact Emerald running split: 5/8 (0.625) running foot frame, 3/8 (0.375) running stand frame
		_cur_pose = ("step_l" if _foot_parity == 0 else "step_r") if t < 0.625 else "stand"
	elif _move_kind == "slide":
		_hop_offset_px = 0.0
		_cur_mode = "walk"
		_cur_pose = "stand"
	else:
		_hop_offset_px = 0.0
		_cur_mode = "walk"
		# Exact Emerald walking split: 8/16 (0.5) foot frame, 8/16 (0.5) stand frame
		_cur_pose = ("step_l" if _foot_parity == 0 else "step_r") if t < 0.5 else "stand"

	_apply_sprite_visual()

func _apply_sprite_visual() -> void:
	if _sprite == null:
		return
	_sprite.offset = Vector2(0.0, -64.0 + round(_hop_offset_px))
	_refresh_sprite_texture()

func _refresh_sprite_texture() -> void:
	if _sprite == null:
		return
	_sprite.texture = PlayerSprites.resolve_texture(sprite_index, facing, _cur_mode, _cur_pose, _force_no_rom)

func _refresh_effect_textures() -> void:
	if _shadow_sprite != null:
		_shadow_sprite.texture = PlayerSprites.resolve_shadow_texture(_force_no_rom)
	if _dust_sprite != null and _dust_active:
		_dust_sprite.texture = PlayerSprites.resolve_dust_texture(_dust_frame, _force_no_rom)
