extends RefCounted

# Touch ownership is decided at press time. GUI touches never enter this set.
signal rotated(delta: Vector2)
signal panned(delta: Vector2)
signal pinched(factor: float)
signal tapped(position: Vector2)
signal held(position: Vector2)
signal hold_finished

const DRAG_THRESHOLD = 10.0
const HOLD_SECONDS = 0.45
const MIN_PINCH_SPAN = 12.0

var points: Dictionary = {}
var origin = Vector2.ZERO
var last_position = Vector2.ZERO
var last_center = Vector2.ZERO
var last_span = 0.0
var motion_scale = 1.0
var dragging = false
var multi_touch = false
var holding = false
var elapsed = 0.0

func handle(event: InputEvent, on_canvas: bool) -> bool:
	if event is InputEventScreenTouch:
		if event.canceled:
			if not points.has(event.index):
				return false
			cancel()
			return true
		if event.pressed:
			if not on_canvas:
				return false
			flush_motion()
			if points.is_empty():
				origin = event.position
				dragging = false
				multi_touch = false
				elapsed = 0.0
			points[event.index] = event.position
			if points.size() > 1:
				multi_touch = true
				finish_hold()
			rebase()
			return true
		if not points.has(event.index):
			return false
		move_point(event.index, event.position)
		flush_motion()
		if not dragging and not multi_touch and not holding and on_canvas:
			tapped.emit(event.position)
		finish_hold()
		points.erase(event.index)
		rebase()
		return true
	if event is InputEventScreenDrag and points.has(event.index):
		move_point(event.index, event.position)
		return true
	return false

func move_point(index: int, position: Vector2) -> void:
	points[index] = position
	if points.size() == 1 and not multi_touch and not holding:
		if origin.distance_to(position) * motion_scale >= DRAG_THRESHOLD:
			dragging = true

func update(dt: float, allow_hold: bool) -> void:
	# Apply both fingers together once per frame: separate OS drag events must
	# not turn a symmetric pinch into an unintended pan.
	flush_motion()
	if points.size() == 1 and not multi_touch and not dragging and not holding:
		elapsed += dt
		if allow_hold and elapsed >= HOLD_SECONDS:
			holding = true
			held.emit(points.values()[0])

func flush_motion() -> void:
	var positions = points.values()
	if positions.size() == 1 and dragging and not multi_touch and not holding:
		rotated.emit((positions[0] - last_position) * motion_scale)
	elif positions.size() == 2:
		var center: Vector2 = (positions[0] + positions[1]) * 0.5
		var span: float = positions[0].distance_to(positions[1])
		panned.emit((center - last_center) * motion_scale)
		if minf(span, last_span) * motion_scale >= MIN_PINCH_SPAN:
			pinched.emit(last_span / span)
	# Three or more fingers, or the last finger of a multi-touch gesture, wait
	# without rotating. Rebase on every contact change to avoid camera jumps.
	if positions.size() != 1 or dragging or multi_touch or holding:
		rebase()

func rebase() -> void:
	var positions = points.values()
	if not positions.is_empty():
		last_position = positions[0]
	if positions.size() == 2:
		last_center = (positions[0] + positions[1]) * 0.5
		last_span = positions[0].distance_to(positions[1])

func finish_hold() -> void:
	if holding:
		holding = false
		hold_finished.emit()

func cancel() -> void:
	finish_hold()
	points.clear()
	dragging = false
	multi_touch = false
	elapsed = 0.0
