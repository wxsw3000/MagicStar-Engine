# editor/ui/components/hotspot_box.gd
# 场景搜证画板中的交互式热区矩形控件（支持拖拽移动、缩放句柄、高亮选择）
class_name HotspotBox
extends Control

signal selected(box: HotspotBox)
signal rect_modified(box: HotspotBox, normalized_rect: Array)
signal delete_requested(box: HotspotBox)

var hotspot_id: String = ""
var hotspot_data: Dictionary = {}
var is_selected: bool = false
var parent_canvas_size: Vector2 = Vector2(1920, 1080)

# 拖拽状态
var is_dragging: bool = false
var is_resizing: bool = false
var drag_start_mouse: Vector2 = Vector2.ZERO
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_start_size: Vector2 = Vector2.ZERO

const HANDLE_SIZE: float = 14.0
const MIN_SIZE: float = 24.0

func _init(id: String = "", data: Dictionary = {}, canvas_size: Vector2 = Vector2(1920, 1080)) -> void:
	hotspot_id = id
	hotspot_data = data
	parent_canvas_size = canvas_size
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready() -> void:
	update_from_data()
	queue_redraw()

func set_canvas_size(new_size: Vector2) -> void:
	parent_canvas_size = new_size
	update_from_data()

func update_from_data() -> void:
	var rect_arr = hotspot_data.get("rect", [0.1, 0.1, 0.2, 0.2])
	if rect_arr.size() >= 4:
		var nx = float(rect_arr[0])
		var ny = float(rect_arr[1])
		var nw = float(rect_arr[2])
		var nh = float(rect_arr[3])
		position = Vector2(nx * parent_canvas_size.x, ny * parent_canvas_size.y)
		size = Vector2(max(MIN_SIZE, nw * parent_canvas_size.x), max(MIN_SIZE, nh * parent_canvas_size.y))
	queue_redraw()

func get_normalized_rect() -> Array:
	if parent_canvas_size.x <= 0 or parent_canvas_size.y <= 0:
		return [0.0, 0.0, 0.1, 0.1]
	var nx = clamp(position.x / parent_canvas_size.x, 0.0, 1.0)
	var ny = clamp(position.y / parent_canvas_size.y, 0.0, 1.0)
	var nw = clamp(size.x / parent_canvas_size.x, 0.01, 1.0)
	var nh = clamp(size.y / parent_canvas_size.y, 0.01, 1.0)
	return [snapped(nx, 0.001), snapped(ny, 0.001), snapped(nw, 0.001), snapped(nh, 0.001)]

func set_selected(val: bool) -> void:
	is_selected = val
	queue_redraw()

func _draw() -> void:
	var bg_color = Color(0.2, 0.7, 1.0, 0.25) if not is_selected else Color(1.0, 0.85, 0.2, 0.35)
	var border_color = Color(0.3, 0.8, 1.0, 0.9) if not is_selected else Color(1.0, 0.9, 0.1, 1.0)
	var border_width = 2.0 if not is_selected else 3.0
	
	# 绘制填充矩形
	draw_rect(Rect2(Vector2.ZERO, size), bg_color, true)
	# 绘制边框
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, border_width)
	
	# 绘制标题与标签
	var label_text = hotspot_data.get("name", hotspot_id)
	var trigger = hotspot_data.get("trigger", {})
	var act_type = trigger.get("action", "")
	var desc = "%s (%s)" % [label_text, act_type]
	var font = ThemeDB.fallback_font
	var font_size = 14
	draw_string(font, Vector2(6, 18), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
	
	# 如果选中，绘制右下角缩放手柄
	if is_selected:
		var handle_rect = Rect2(size.x - HANDLE_SIZE, size.y - HANDLE_SIZE, HANDLE_SIZE, HANDLE_SIZE)
		draw_rect(handle_rect, Color(1.0, 0.9, 0.1, 1.0), true)
		draw_rect(handle_rect, Color.BLACK, false, 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			selected.emit(self)
			var local_mouse = event.position
			var handle_rect = Rect2(size.x - HANDLE_SIZE, size.y - HANDLE_SIZE, HANDLE_SIZE, HANDLE_SIZE)
			if is_selected and handle_rect.has_point(local_mouse):
				is_resizing = true
				drag_start_mouse = get_global_mouse_position()
				drag_start_size = size
			else:
				is_dragging = true
				drag_start_mouse = get_global_mouse_position()
				drag_start_pos = position
			accept_event()
		else:
			if is_dragging or is_resizing:
				is_dragging = false
				is_resizing = false
				var norm = get_normalized_rect()
				hotspot_data["rect"] = norm
				rect_modified.emit(self, norm)
				accept_event()
				
	elif event is InputEventMouseMotion:
		if is_resizing:
			var delta = get_global_mouse_position() - drag_start_mouse
			size = Vector2(max(MIN_SIZE, drag_start_size.x + delta.x), max(MIN_SIZE, drag_start_size.y + delta.y))
			queue_redraw()
			accept_event()
		elif is_dragging:
			var delta = get_global_mouse_position() - drag_start_mouse
			var new_pos = drag_start_pos + delta
			# 限制在画布范围内
			new_pos.x = clamp(new_pos.x, 0, parent_canvas_size.x - size.x)
			new_pos.y = clamp(new_pos.y, 0, parent_canvas_size.y - size.y)
			position = new_pos
			queue_redraw()
			accept_event()
		else:
			# 更新光标形状
			var handle_rect = Rect2(size.x - HANDLE_SIZE, size.y - HANDLE_SIZE, HANDLE_SIZE, HANDLE_SIZE)
			if is_selected and handle_rect.has_point(event.position):
				mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
			else:
				mouse_default_cursor_shape = Control.CURSOR_MOVE
