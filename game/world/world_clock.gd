class_name WorldClock
extends RefCounted

## game/world/world_clock.gd — World Clock, Time Bands & Real-Distance Travel Cost (Item 67)
## Contract: docs/design_travel_and_time.md §1–§2; docs/implementation_plan_travel_and_time.md §(i)

const MINUTES_PER_DAY: int = 1440
const DAWN_START_MIN: int = 300   # 05:00
const DAY_START_MIN: int = 420    # 07:00
const DUSK_START_MIN: int = 1140  # 19:00
const NIGHT_START_MIN: int = 1260 # 21:00
const DEFAULT_START_MINUTES: int = 480 # Day 1, 08:00 AM

const DEFAULT_WALL_SECONDS_PER_GAME_MINUTE: float = 2.0
const DEFAULT_WALK_SPEED_MPH: float = 15.0
const DEFAULT_BICYCLE_MULTIPLIER: float = 2.0

var game_epoch_minutes: int = DEFAULT_START_MINUTES
var _wall_accum_seconds: float = 0.0
var _running: bool = false
var _db: Variant = null

static func _get_config() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and (ml as SceneTree).root != null:
		return (ml as SceneTree).root.get_node_or_null("/root/Config")
	return null

static func wall_seconds_per_game_minute() -> float:
	var cfg := _get_config()
	if cfg != null and "wall_seconds_per_game_minute" in cfg:
		var v := float(cfg.get("wall_seconds_per_game_minute"))
		if v > 0.0:
			return v
	return DEFAULT_WALL_SECONDS_PER_GAME_MINUTE

static func walk_speed_mph() -> float:
	var cfg := _get_config()
	if cfg != null and "walk_speed_mph" in cfg:
		var v := float(cfg.get("walk_speed_mph"))
		if v > 0.0:
			return v
	return DEFAULT_WALK_SPEED_MPH

static func bicycle_speed_multiplier() -> float:
	var cfg := _get_config()
	if cfg != null and "bicycle_speed_multiplier" in cfg:
		var v := float(cfg.get("bicycle_speed_multiplier"))
		if v > 0.0:
			return v
	return DEFAULT_BICYCLE_MULTIPLIER

static func time_band_for_minute(min_of_day: int) -> String:
	var m := posmod(min_of_day, MINUTES_PER_DAY)
	if m >= DAWN_START_MIN and m < DAY_START_MIN:
		return "dawn"
	if m >= DAY_START_MIN and m < DUSK_START_MIN:
		return "day"
	if m >= DUSK_START_MIN and m < NIGHT_START_MIN:
		return "dusk"
	return "night"

static func daylight_minutes_left_for_minute(min_of_day: int) -> int:
	var m := posmod(min_of_day, MINUTES_PER_DAY)
	if m >= DAWN_START_MIN and m < DUSK_START_MIN:
		return DUSK_START_MIN - m
	return 0

static func daylight_tag_for_cost(cost_min: int, remaining_daylight_min: int) -> String:
	if remaining_daylight_min <= 0:
		return "red"
	var c := maxi(1, cost_min)
	if remaining_daylight_min >= c * 2:
		return "green"
	if remaining_daylight_min >= c:
		return "amber"
	return "red"

static func daylight_color(tag: String) -> Color:
	match tag:
		"green":
			return Color("#56e68a")
		"amber":
			return Color("#f2c14e")
		_:
			return Color("#ef6461")

static func format_route_sign_daylight(route_name: String, cost_min: int, remaining_daylight_min: int) -> Dictionary:
	var tag := daylight_tag_for_cost(cost_min, remaining_daylight_min)
	var suffix := "night ahead"
	if tag == "green":
		suffix = "round trip before dusk"
	elif tag == "amber":
		suffix = "one-way before dusk"
	return {
		"tag": tag,
		"color": daylight_color(tag),
		"text": "%s — %d min on foot (%s)" % [route_name, cost_min, suffix],
	}

static func estimate_trip_minutes(
	miles: float,
	has_bicycle: bool = false,
	walk_mph_override: float = -1.0,
	bicycle_mult_override: float = -1.0
) -> int:
	var d: float = maxf(0.0, miles)
	var base_mph: float = walk_mph_override if walk_mph_override > 0.0 else walk_speed_mph()
	var mult: float = (bicycle_mult_override if bicycle_mult_override > 0.0 else bicycle_speed_multiplier()) if has_bicycle else 1.0
	var eff_mph: float = maxf(0.0001, base_mph * maxf(0.0001, mult))
	var mins_float: float = (d / eff_mph) * 60.0
	return maxi(1, int(ceil(mins_float - 1e-9)))

func load_from_db(db_node: Variant) -> int:
	_db = db_node
	_wall_accum_seconds = 0.0
	if _db != null and _db.has_method("is_open") and _db.is_open():
		var row: Dictionary = _db.get_world_clock()
		if not row.is_empty():
			game_epoch_minutes = maxi(0, int(row.get("game_epoch_minutes", DEFAULT_START_MINUTES)))
			return game_epoch_minutes
	game_epoch_minutes = DEFAULT_START_MINUTES
	return game_epoch_minutes

func save_to_db(db_node: Variant = null) -> bool:
	var target: Variant = db_node if db_node != null else _db
	if target == null or not target.has_method("is_open") or not target.is_open():
		return false
	return target.set_world_clock_minutes(game_epoch_minutes)

func set_running(active: bool) -> void:
	_running = active
	if not _running:
		_wall_accum_seconds = 0.0

func is_running() -> bool:
	return _running

func set_minutes(mins: int, persist: bool = true) -> void:
	game_epoch_minutes = maxi(0, mins)
	_wall_accum_seconds = 0.0
	if persist:
		save_to_db()

func tick(delta_seconds: float, rate_override: float = -1.0) -> int:
	if not _running or delta_seconds <= 0.0:
		return 0
	var rate: float = rate_override if rate_override > 0.0 else wall_seconds_per_game_minute()
	_wall_accum_seconds += delta_seconds
	var advanced: int = 0
	while _wall_accum_seconds + 1e-9 >= rate:
		_wall_accum_seconds = maxf(0.0, _wall_accum_seconds - rate)
		game_epoch_minutes += 1
		advanced += 1
	if advanced > 0:
		save_to_db()
	return advanced

func advance_minutes(delta_minutes: int, persist: bool = true) -> int:
	if delta_minutes <= 0:
		return game_epoch_minutes
	game_epoch_minutes += delta_minutes
	if persist:
		save_to_db()
	return game_epoch_minutes

func charge_trip_miles(miles: float, has_bicycle: bool = false, persist: bool = true) -> int:
	var cost: int = estimate_trip_minutes(miles, has_bicycle)
	advance_minutes(cost, persist)
	return cost

func minute_of_day() -> int:
	return posmod(game_epoch_minutes, MINUTES_PER_DAY)

func day_number() -> int:
	return int(game_epoch_minutes / MINUTES_PER_DAY) + 1

func hour_of_day() -> int:
	return int(minute_of_day() / 60)

func minute_of_hour() -> int:
	return minute_of_day() % 60

func format_hhmm() -> String:
	return "%02d:%02d" % [hour_of_day(), minute_of_hour()]

func time_band() -> String:
	return time_band_for_minute(minute_of_day())

func daylight_minutes_left() -> int:
	return daylight_minutes_left_for_minute(minute_of_day())

func daylight_tag(cost_min: int) -> String:
	return daylight_tag_for_cost(cost_min, daylight_minutes_left())
