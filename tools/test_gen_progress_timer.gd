# tools/test_gen_progress_timer.gd
extends Control

const AIAssetTabClass = preload("res://editor/ui/tabs/ai_asset_tab.gd")

func _ready() -> void:
	print("--- 开始生成进度计时与耗时计算自动化测试 ---")
	call_deferred("run_tests")

func run_tests() -> void:
	await get_tree().create_timer(0.05).timeout

	print("[1] 实例化 AIAssetTab 控件")
	var tab = AIAssetTabClass.new()
	add_child(tab)
	await get_tree().create_timer(0.1).timeout

	print("[2] 测试防异常机制：未启动生成或 gen_start_time 为 0 时触发 tick")
	tab.is_generating = true
	tab.gen_start_time_ms = 0
	tab.gen_start_time = 0.0
	# 模拟调用 tick (此时 progress 文件可能存在或不存在)
	tab._on_progress_timer_tick()
	print("    当前状态文本: ", tab.lbl_gen_status.text)
	assert(not tab.lbl_gen_status.text.contains("17"), "状态文本绝不能包含 17 亿秒级的 Epoch 异常大数！")
	assert(tab.lbl_gen_status.text.contains("已耗时 0.0s") or tab.lbl_gen_status.text.contains("已耗时 0.1s"), "异常兜底必须重置并从 0 秒开始计时")
	print("    ✅ 未初始化或 0 毫秒启动的防御机制测试通过！")

	print("[3] 测试单项生成模式耗时与进度条驱动")
	tab.is_batch_running = false
	tab.gen_start_time_ms = Time.get_ticks_msec()
	await get_tree().create_timer(0.3).timeout
	# 创建模拟临时进度文件
	var prog_path = ProjectSettings.globalize_path(tab.PROGRESS_FILE_PATH)
	var f = FileAccess.open(prog_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"stage": "sampling",
		"percent": 45,
		"text": "正在采样去噪...",
		"timestamp": Time.get_unix_time_from_system()
	}))
	f.close()

	tab._on_progress_timer_tick()
	print("    单项生图状态文本: ", tab.lbl_gen_status.text)
	assert(tab.progress_bar.value == 45, "单项进度条应为 45")
	assert(tab.lbl_gen_status.text.contains("45%"), "应显示 45%")
	assert(tab.lbl_gen_status.text.contains("0.3s") or tab.lbl_gen_status.text.contains("0.4s"), "耗时应为 0.3s ~ 0.4s")
	print("    ✅ 单项生成耗时与进度显示校验通过！")

	print("[4] 测试单项完成回调耗时计算")
	var dummy_item = {"id": "test_sprite", "name": "沈策 测试立绘", "type": "character", "status": "pending"}
	tab._on_single_gen_finished(dummy_item, {"success": true})
	print("    完成状态文本: ", tab.lbl_gen_status.text)
	assert(tab.lbl_gen_status.text.contains("生成成功: 沈策 测试立绘 (耗时"), "完成状态应包含耗时")
	assert(not tab.lbl_gen_status.text.contains("17"), "完成状态绝不能包含 17 亿秒异常值")
	assert(tab.gen_start_time_ms == 0, "完成后 gen_start_time_ms 应清零")
	print("    ✅ 单项生成完成回调耗时展示验证通过！")

	print("[5] 测试批量生成模式：进度平滑连续驱动与单项独立耗时")
	tab.is_generating = true
	tab.is_batch_running = true
	tab.batch_current_label = "沈策全部立绘"
	tab.batch_total_count = 5
	tab.batch_current_index = 2
	tab.batch_start_time_ms = Time.get_ticks_msec()
	tab.gen_start_time_ms = Time.get_ticks_msec()
	await get_tree().create_timer(0.4).timeout

	# 更新临时进度文件为第 2 项的 60%
	var f2 = FileAccess.open(prog_path, FileAccess.WRITE)
	f2.store_string(JSON.stringify({
		"stage": "sampling",
		"percent": 60,
		"text": "深度绘制中...",
		"timestamp": Time.get_unix_time_from_system()
	}))
	f2.close()

	tab._on_progress_timer_tick()
	print("    批量生成状态文本: ", tab.lbl_gen_status.text)
	print("    批量进度条数值: %f / %f" % [tab.progress_bar.value, tab.progress_bar.max_value])
	assert(tab.progress_bar.max_value == 500, "批量进度条上限应为 500 (5 * 100)")
	# 第 2 项完成 60% => (2-1)*100 + 60 = 160
	assert(tab.progress_bar.value == 160, "第 2 项 60% 对应的总体进度应为 160/500")
	assert(tab.lbl_gen_status.text.contains("[2/5]"), "应显示当前项与总项数 [2/5]")
	assert(tab.lbl_gen_status.text.contains("0.3s") or tab.lbl_gen_status.text.contains("0.4s") or tab.lbl_gen_status.text.contains("0.5s"), "当前项耗时应显示 0.3s ~ 0.5s")
	print("    ✅ 批量生成连续进度条与当前项耗时验证通过！")

	print("[6] 测试批量生成全案完成回调与总体耗时汇总")
	tab._on_batch_all_finished(5)
	print("    批量完成状态文本: ", tab.lbl_gen_status.text)
	assert(tab.lbl_gen_status.text.contains("总耗时"), "批量完成应报告总耗时")
	assert(tab.lbl_gen_status.text.contains("0.3s") or tab.lbl_gen_status.text.contains("0.4s") or tab.lbl_gen_status.text.contains("0.5s"), "总耗时应为 0.3s ~ 0.5s")
	assert(not tab.lbl_gen_status.text.contains("17"), "批量完成绝不能包含 17 亿秒异常值")
	print("    ✅ 批量生成总体耗时汇总与状态重置验证通过！")

	# 清理临时文件
	if FileAccess.file_exists(prog_path):
		DirAccess.remove_absolute(prog_path)

	tab.queue_free()
	print("\n🎉🎉🎉 生成进度与耗时计算所有测试用例 100% 通过！")
	get_tree().quit(0)
