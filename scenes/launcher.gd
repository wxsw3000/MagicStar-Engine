# scenes/launcher.gd
# 启动选择器：可在创作模式 (AVG Studio) 与玩家试玩模式间自由切换
extends Control

func _ready() -> void:
	DisplayServer.window_set_title("MagicStar AVG Engine - 模式选择")

func _on_btn_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://editor/ui/editor_main.tscn")

func _on_btn_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
