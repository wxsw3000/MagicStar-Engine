# engine/core/event_bus.gd
# 全局事件总线（纯解耦：引擎各系统和UI通过信号通信，不产生直接依赖）
extends Node

# 对话与剧情信号
signal dialogue_started(dialogue_id: String, dialogue_data: Dictionary)
signal dialogue_line_displayed(line_data: Dictionary)
signal dialogue_choices_requested(choices: Array)
signal dialogue_choice_selected(choice_index: int)
signal dialogue_topics_requested(topics: Array)
signal dialogue_topic_selected(topic_id: String)
signal dialogue_ended(next_target: String)

# 搜证与线索信号
signal clue_obtained(clue_id: String, clue_data: Dictionary)
signal clue_notebook_toggle_requested(is_open: bool)

# 探索信号
signal scene_changed(scene_id: String, scene_data: Dictionary)
signal explore_point_clicked(point_id: String, point_data: Dictionary)
signal explore_mode_changed(is_exploring: bool)

# 任务系统信号
signal task_started(task_id: String, task_data: Dictionary)
signal task_completed(task_id: String, task_data: Dictionary)

# 节点与流程信号
signal node_changed(node_id: String, node_data: Dictionary)
signal time_phase_changed(phase_id: String, phase_data: Dictionary)
signal ending_triggered(ending_id: String, ending_data: Dictionary)

# 推理与指认信号
signal reasoning_requested(reasoning_id: String, reasoning_data: Dictionary)
signal reasoning_submitted(selected_clue_ids: Array)
signal reasoning_succeeded(reasoning_id: String, success_data: Dictionary)
signal reasoning_failed(reasoning_id: String, hint_text: String)

# 角色状态信号
signal character_state_changed(character_id: String, state_key: String, new_value: Variant)

# 系统 UI 提示与回溯信号
signal notification_requested(message: String, type: String)
signal milestone_created(milestone_id: String, title: String)
signal request_rewind_to_milestone(snapshot: Dictionary)
