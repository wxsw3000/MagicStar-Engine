# engine/systems/reasoning_manager.gd
# 疑问驱动的证据出示与逻辑推理管理器
extends Node

var current_reasoning_id: String = ""
var current_reasoning_data: Dictionary = {}

func _ready() -> void:
	EventBus.reasoning_submitted.connect(verify_reasoning)

func start_reasoning(reasoning_id: String) -> void:
	var data = DataManager.get_reasoning_data(reasoning_id)
	if data.is_empty():
		push_error("[ReasoningManager] 推理配置不存在: %s" % reasoning_id)
		return
		
	current_reasoning_id = reasoning_id
	current_reasoning_data = data
	print("[ReasoningManager] 开启逻辑推理: %s (%s)" % [reasoning_id, data.get("question", "")])
	EventBus.reasoning_requested.emit(reasoning_id, data)

func verify_reasoning(selected_clue_ids: Array) -> void:
	var required_clues: Array = current_reasoning_data.get("required_clues", [])
	
	# 检查是否满足所有必须证据
	var is_correct = true
	if selected_clue_ids.size() != required_clues.size():
		is_correct = false
	else:
		for req in required_clues:
			if not req in selected_clue_ids:
				is_correct = false
				break
				
	if is_correct:
		print("[ReasoningManager] ✅ 推理成功！证据吻合！")
		# 自动获得推导出的新线索结论（如果有）
		if current_reasoning_data.has("conclusion_clue"):
			GameState.obtain_clue(current_reasoning_data["conclusion_clue"])
			
		EventBus.reasoning_succeeded.emit(current_reasoning_id, current_reasoning_data)
		EventBus.notification_requested.emit("推理成功！逻辑闭合！", "success")
	else:
		# 寻找针对特定错误线索的专属提示
		var error_hints: Dictionary = current_reasoning_data.get("error_hints", {})
		var feedback_hint: String = ""
		for sel in selected_clue_ids:
			if error_hints.has(sel):
				feedback_hint = error_hints[sel]
				break
				
		if feedback_hint.is_empty():
			feedback_hint = current_reasoning_data.get("default_fail_hint", "出示的线索与疑问无法形成逻辑闭环，再仔细思考一下...")
			
		print("[ReasoningManager] ❌ 推理未通过: %s" % feedback_hint)
		EventBus.reasoning_failed.emit(current_reasoning_id, feedback_hint)
		EventBus.notification_requested.emit(feedback_hint, "warning")
