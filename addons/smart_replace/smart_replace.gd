@tool
extends EditorPlugin

var smart_replace_button: Button

func _enter_tree():
	# Создаем кнопку в панели инструментов
	add_control_to_container(CONTAINER_TOOLBAR, create_toolbar_button())

func _exit_tree():
	# Удаляем кнопку из панели инструментов
	remove_control_from_container(CONTAINER_TOOLBAR, smart_replace_button)

func create_toolbar_button() -> Button:
	smart_replace_button = Button.new()
	smart_replace_button.text = "Smart Replace"
	smart_replace_button.tooltip_text = "Умная замена функций"
	smart_replace_button.pressed.connect(_on_smart_replace_pressed)
	return smart_replace_button

func _on_smart_replace_pressed():
	print("Кнопка нажата!")
	show_smart_replace_dialog_v2()

# ===== JSON ПАРСЕР ФУНКЦИИ =====

func execute_json_command(json_text: String):
	if json_text.strip_edges() == "":
		print("JSON команда не может быть пустой!")
		return
	
	# Очищаем JSON от комментариев и лишних символов
	var clean_json = clean_json_text(json_text)
	
	var json = JSON.new()
	var parse_result = json.parse(clean_json)
	
	if parse_result != OK:
		print("Ошибка парсинга JSON: ", json.get_error_message())
		print("Проверьте синтаксис JSON!")
		return
	
	var data = json.data
	if not data.has("action"):
		print("JSON должен содержать поле 'action'!")
		return
	
	var action = data.action
	var success = false
	
	match action:
		"add_function":
			success = handle_add_function(data)
		"replace_function":
			success = handle_replace_function(data)
		"delete_function":
			success = handle_delete_function(data)
		"add_code":
			success = handle_add_code(data)
		"delete_code":
			success = handle_delete_code(data)
		_:
			print("Неизвестное действие: ", action)
			return
	
	if success:
		print("JSON команда выполнена успешно!")
	else:
		print("Ошибка при выполнении JSON команды!")

func handle_add_function(data: Dictionary) -> bool:
	if not data.has("name") or not data.has("code"):
		print("Для добавления функции нужны поля 'name' и 'code'!")
		return false
	
	var name = data.name
	var args = data.get("parameters", "")
	var code = data.code
	var comment = data.get("comment", "")
	
	add_new_function_with_comment(name, args, code, comment)
	return true

func handle_replace_function(data: Dictionary) -> bool:
	if not data.has("signature") or not data.has("code"):
		print("Для замены функции нужны поля 'signature' и 'code'!")
		return false
	
	var signature = data.signature
	var code = data.code
	var comment = data.get("comment", "")  # Новый комментарий (пустой = удалить старый)
	
	var function_data = find_function_by_signature(signature)
	if function_data.is_empty():
		print("Функция с сигнатурой '", signature, "' не найдена!")
		return false
	
	smart_replace_function_with_comment(function_data, code, comment)
	return true

func handle_delete_function(data: Dictionary) -> bool:
	if not data.has("signature"):
		print("Для удаления функции нужно поле 'signature'!")
		return false
	
	var signature = data.signature
	var function_data = find_function_by_signature(signature)
	if function_data.is_empty():
		print("Функция с сигнатурой '", signature, "' не найдена!")
		return false
	
	delete_function(function_data)
	return true

func handle_add_code(data: Dictionary) -> bool:
	if not data.has("code"):
		print("Для добавления кода нужно поле 'code'!")
		return false
	
	var code = data.code
	var position = data.get("position", 0)  # По умолчанию в конец
	var line_number = data.get("line_number", 1)
	
	# Поддержка текстовых значений позиции
	if data.has("position_type"):
		var position_type = data.position_type
		match position_type:
			"end":
				position = 0
			"start":
				position = 1
			"after_extends":
				position = 2
			"before_extends":
				position = 3
			"specific_line":
				position = 4
				if data.has("line_number"):
					line_number = data.line_number
	
	add_code_to_file(code, position, line_number)
	return true

func handle_delete_code(data: Dictionary) -> bool:
	if not data.has("code"):
		print("Для удаления кода нужно поле 'code'!")
		return false
	
	var code = data.code
	delete_code_from_file(code)
	return true

func find_function_by_signature(signature: String) -> Dictionary:
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var functions = find_functions_in_file(file_path)
			
			for func_data in functions:
				if func_data.signature.strip_edges() == signature.strip_edges():
					return func_data
	
	# Возвращаем пустой Dictionary вместо null
	return {}

func clean_json_text(json_text: String) -> String:
	# Удаляем комментарии и лишние символы
	var lines = json_text.split("\n")
	var clean_lines = []
	
	for line in lines:
		var clean_line = line.strip_edges()
		# Пропускаем пустые строки и комментарии
		if clean_line != "" and not clean_line.begins_with("//"):
			clean_lines.append(clean_line)
	
	return "\n".join(clean_lines)

func show_json_preview(json_text: String):
	if json_text.strip_edges() == "":
		print("JSON команда не может быть пустой!")
		return
	
	# Очищаем JSON от комментариев и лишних символов
	var clean_json = clean_json_text(json_text)
	
	var json = JSON.new()
	var parse_result = json.parse(clean_json)
	
	if parse_result != OK:
		print("Ошибка парсинга JSON: ", json.get_error_message())
		print("Проверьте синтаксис JSON!")
		return
	
	var data = json.data
	if not data.has("action"):
		print("JSON должен содержать поле 'action'!")
		return
	
	var action = data.action
	var preview_text = ""
	
	match action:
		"add_function":
			preview_text = generate_add_function_preview(data)
		"replace_function":
			preview_text = generate_replace_function_preview(data)
		"delete_function":
			preview_text = generate_delete_function_preview(data)
		"add_code":
			preview_text = generate_add_code_preview(data)
		"delete_code":
			preview_text = generate_delete_code_preview(data)
		_:
			preview_text = "Неизвестное действие: " + action
	
	show_preview_dialog(preview_text, json_text)

func generate_add_function_preview(data: Dictionary) -> String:
	if not data.has("name") or not data.has("code"):
		return "❌ Ошибка: Для добавления функции нужны поля 'name' и 'code'!"
	
	var name = data.name
	var args = data.get("parameters", "")
	var code = data.code
	var comment = data.get("comment", "")
	
	var signature = "func " + name + "(" + args + "):" if args != "" else "func " + name + "():"
	
	var preview = "➕ ДОБАВИТЬ ФУНКЦИЮ:\n"
	preview += "📝 Сигнатура: " + signature + "\n"
	
	if comment.strip_edges() != "":
		preview += "💬 Комментарий: " + comment + "\n"
	
	preview += "📄 Код:\n"
	
	var code_lines = code.split("\n")
	for line in code_lines:
		if line.strip_edges() != "":
			preview += "   " + line + "\n"
		else:
			preview += "\n"
	
	preview += "📍 Место: в конец файла"
	return preview

func generate_replace_function_preview(data: Dictionary) -> String:
	if not data.has("signature") or not data.has("code"):
		return "❌ Ошибка: Для замены функции нужны поля 'signature' и 'code'!"
	
	var signature = data.signature
	var code = data.code
	var comment = data.get("comment", "")
	var function_data = find_function_by_signature(signature)
	
	if function_data.is_empty():
		return "❌ Функция с сигнатурой '" + signature + "' не найдена!"
	
	var preview = "🔄 ЗАМЕНИТЬ ФУНКЦИЮ:\n"
	preview += "📝 Сигнатура: " + signature + "\n"
	preview += "📍 Строка: " + str(function_data.line) + "\n"
	
	if comment.strip_edges() != "":
		preview += "💬 Новый комментарий: " + comment + "\n"
	else:
		preview += "🗑️ Старый комментарий будет удален\n"
	
	preview += "📄 Новый код:\n"
	
	var code_lines = code.split("\n")
	for line in code_lines:
		if line.strip_edges() != "":
			preview += "   " + line + "\n"
		else:
			preview += "\n"
	
	return preview

func generate_delete_function_preview(data: Dictionary) -> String:
	if not data.has("signature"):
		return "❌ Ошибка: Для удаления функции нужно поле 'signature'!"
	
	var signature = data.signature
	var function_data = find_function_by_signature(signature)
	
	if function_data.is_empty():
		return "❌ Функция с сигнатурой '" + signature + "' не найдена!"
	
	var preview = "🗑️ УДАЛИТЬ ФУНКЦИЮ:\n"
	preview += "📝 Сигнатура: " + signature + "\n"
	preview += "📍 Строка: " + str(function_data.line) + "\n"
	preview += "⚠️ Внимание: Функция и комментарий над ней будут удалены!"
	
	return preview

func generate_add_code_preview(data: Dictionary) -> String:
	if not data.has("code"):
		return "❌ Ошибка: Для добавления кода нужно поле 'code'!"
	
	var code = data.code
	var position = data.get("position", 0)
	var line_number = data.get("line_number", 1)
	
	# Поддержка текстовых значений позиции
	if data.has("position_type"):
		var position_type = data.position_type
		match position_type:
			"end":
				position = 0
			"start":
				position = 1
			"after_extends":
				position = 2
			"before_extends":
				position = 3
			"specific_line":
				position = 4
				if data.has("line_number"):
					line_number = data.line_number
	
	var position_names = ["в конец файла", "в начало файла", "после extends", "перед extends", "на строку " + str(line_number)]
	
	var preview = "➕ ДОБАВИТЬ КОД:\n"
	preview += "📍 Место: " + position_names[position] + "\n"
	preview += "📄 Код:\n"
	
	var code_lines = code.split("\n")
	for line in code_lines:
		if line.strip_edges() != "":
			preview += "   " + line + "\n"
		else:
			preview += "\n"
	
	return preview

func generate_delete_code_preview(data: Dictionary) -> String:
	if not data.has("code"):
		return "❌ Ошибка: Для удаления кода нужно поле 'code'!"
	
	var code = data.code
	
	var preview = "🗑️ УДАЛИТЬ КОД:\n"
	preview += "📄 Код для удаления:\n"
	
	var code_lines = code.split("\n")
	for line in code_lines:
		if line.strip_edges() != "":
			preview += "   " + line + "\n"
		else:
			preview += "\n"
	
	preview += "⚠️ Внимание: Точное совпадение кода будет удалено!"
	return preview

func show_preview_dialog(preview_text: String, json_text: String):
	# Закрываем все существующие диалоги
	close_all_dialogs()
	
	var dialog = AcceptDialog.new()
	dialog.title = "Предварительный просмотр изменений"
	dialog.size = Vector2(800, 600)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var preview_label = Label.new()
	preview_label.text = "Что будет изменено:"
	vbox.add_child(preview_label)
	
	var preview_edit = TextEdit.new()
	preview_edit.text = preview_text
	preview_edit.editable = false
	preview_edit.custom_minimum_size = Vector2(780, 400)
	vbox.add_child(preview_edit)
	
	var buttons = HBoxContainer.new()
	vbox.add_child(buttons)
	
	var apply_button = Button.new()
	apply_button.text = "Применить изменения"
	apply_button.pressed.connect(func():
		execute_json_command(json_text)
		dialog.hide()
	)
	buttons.add_child(apply_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Отмена"
	cancel_button.pressed.connect(func(): dialog.hide())
	buttons.add_child(cancel_button)
	
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()

func close_all_dialogs():
	# Закрываем все диалоги AcceptDialog
	var base_control = get_editor_interface().get_base_control()
	for child in base_control.get_children():
		if child is AcceptDialog:
			child.hide()

func show_smart_replace_dialog_v2():
	var dialog = AcceptDialog.new()
	dialog.title = "Smart Replace - Умная замена функций"
	dialog.size = Vector2(1000, 800)
	
	# Создаем основной контейнер
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	# Создаем вкладки
	var tab_container = TabContainer.new()
	tab_container.custom_minimum_size = Vector2(980, 700)
	vbox.add_child(tab_container)
	
	# ===== ВКЛАДКА 1: JSON =====
	var json_tab = VBoxContainer.new()
	tab_container.add_child(json_tab)
	tab_container.set_tab_title(0, "JSON")
	
	# Заголовок для JSON вкладки
	var json_label = Label.new()
	json_label.text = "Вставьте JSON команду от ИИ:"
	json_tab.add_child(json_label)
	
	# Поле для JSON
	var json_edit = TextEdit.new()
	json_edit.placeholder_text = '// Примеры JSON команд:\n\n// Добавить функцию:\n{\n  "action": "add_function",\n  "name": "move_player",\n  "parameters": "direction, speed",\n  "code": "position += direction * speed * delta"\n}\n\n// Добавить функцию с комментарием:\n{\n  "action": "add_function",\n  "name": "take_damage",\n  "parameters": "damage_amount",\n  "comment": "Уменьшает здоровье игрока на указанное количество",\n  "code": "player_health -= damage_amount\\nif player_health <= 0:\\n\\tdie()"\n}\n\n// Заменить функцию:\n{\n  "action": "replace_function",\n  "signature": "func _ready():",\n  "code": "print(\\"Game started!\\")\\nsetup_player()",\n  "comment": "Инициализация игры при запуске"\n}\n\n// Добавить код в конец файла:\n{\n  "action": "add_code",\n  "code": "var player_health = 100",\n  "position_type": "end"\n}\n\n// Добавить код в начало файла:\n{\n  "action": "add_code",\n  "code": "@tool",\n  "position_type": "start"\n}\n\n// Добавить код после extends:\n{\n  "action": "add_code",\n  "code": "var player_speed = 5.0",\n  "position_type": "after_extends"\n}\n\n// Добавить код на конкретную строку:\n{\n  "action": "add_code",\n  "code": "var test_var = 42",\n  "position_type": "specific_line",\n  "line_number": 10\n}\n\n// Удалить код:\n{\n  "action": "delete_code",\n  "code": "var old_variable = 10"\n}'
	json_edit.custom_minimum_size = Vector2(960, 600)
	json_tab.add_child(json_edit)
	
	# Кнопки для JSON вкладки
	var json_buttons = HBoxContainer.new()
	json_tab.add_child(json_buttons)
	
	var preview_button = Button.new()
	preview_button.text = "Предварительный просмотр"
	preview_button.pressed.connect(func():
		var json_text = json_edit.text
		show_json_preview(json_text)
	)
	json_buttons.add_child(preview_button)
	
	var execute_json_button = Button.new()
	execute_json_button.text = "Выполнить JSON"
	execute_json_button.pressed.connect(func():
		var json_text = json_edit.text
		execute_json_command(json_text)
	)
	json_buttons.add_child(execute_json_button)
	
	var clear_json_button = Button.new()
	clear_json_button.text = "Очистить"
	clear_json_button.pressed.connect(func():
		json_edit.text = ""
	)
	json_buttons.add_child(clear_json_button)
	
	# ===== ВКЛАДКА 2: РУЧНАЯ РАБОТА =====
	var manual_tab = VBoxContainer.new()
	tab_container.add_child(manual_tab)
	tab_container.set_tab_title(1, "Ручная работа")
	
	# Создаем подвкладки для ручной работы
	var manual_tab_container = TabContainer.new()
	manual_tab_container.custom_minimum_size = Vector2(960, 650)
	manual_tab.add_child(manual_tab_container)
	
	# ===== ПОДВКЛАДКА: РАБОТА С ФУНКЦИЯМИ =====
	var functions_tab = VBoxContainer.new()
	manual_tab_container.add_child(functions_tab)
	manual_tab_container.set_tab_title(0, "Функции")
	
	# Создаем список функций
	var function_label = Label.new()
	function_label.text = "Выберите функцию для замены или выберите 'Добавить новую функцию':"
	functions_tab.add_child(function_label)
	
	var function_list = ItemList.new()
	function_list.custom_minimum_size = Vector2(960, 200)
	functions_tab.add_child(function_list)
	
	# Загружаем список функций из текущего файла
	load_functions_list(function_list)
	var add_new_index = function_list.add_item("➕ Добавить новую функцию")
	function_list.set_item_metadata(add_new_index, {"is_new": true})
	
	# Поля для новой функции
	var new_func_name_label = Label.new()
	new_func_name_label.text = "Имя новой функции (например: my_func):"
	functions_tab.add_child(new_func_name_label)
	var new_func_name_edit = LineEdit.new()
	new_func_name_edit.placeholder_text = "my_func"
	functions_tab.add_child(new_func_name_edit)
	new_func_name_label.visible = false
	new_func_name_edit.visible = false
	
	var new_func_args_label = Label.new()
	new_func_args_label.text = "Параметры (например: a, b):"
	functions_tab.add_child(new_func_args_label)
	var new_func_args_edit = LineEdit.new()
	new_func_args_edit.placeholder_text = "a, b"
	functions_tab.add_child(new_func_args_edit)
	new_func_args_label.visible = false
	new_func_args_edit.visible = false
	
	# Поле для кода
	var new_code_label = Label.new()
	new_code_label.text = "Код функции (только содержимое):"
	functions_tab.add_child(new_code_label)
	var new_code_edit = TextEdit.new()
	new_code_edit.placeholder_text = "Вставьте только код внутри функции (без func и отступов)"
	new_code_edit.custom_minimum_size = Vector2(960, 200)
	functions_tab.add_child(new_code_edit)
	
	# Переключение видимости полей для новой функции
	function_list.item_selected.connect(func(idx):
		var is_new = function_list.get_item_metadata(idx).has("is_new")
		new_func_name_label.visible = is_new
		new_func_name_edit.visible = is_new
		new_func_args_label.visible = is_new
		new_func_args_edit.visible = is_new
	)
	
	# Кнопки для функций
	var functions_buttons = HBoxContainer.new()
	functions_tab.add_child(functions_buttons)
	
	var replace_button = Button.new()
	replace_button.text = "Применить"
	replace_button.pressed.connect(func():
		var selected_index = function_list.get_selected_items()
		if selected_index.size() > 0:
			var function_data = function_list.get_item_metadata(selected_index[0])
			if function_data.has("is_new"):
				add_new_function(new_func_name_edit.text, new_func_args_edit.text, new_code_edit.text)
			else:
				smart_replace_function(function_data, new_code_edit.text)
		dialog.hide()
	)
	functions_buttons.add_child(replace_button)
	
	var delete_button = Button.new()
	delete_button.text = "Удалить функцию"
	delete_button.pressed.connect(func():
		var selected_index = function_list.get_selected_items()
		if selected_index.size() > 0:
			var function_data = function_list.get_item_metadata(selected_index[0])
			if not function_data.has("is_new"):
				delete_function(function_data)
		dialog.hide()
	)
	functions_buttons.add_child(delete_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Отмена"
	cancel_button.pressed.connect(func(): dialog.hide())
	functions_buttons.add_child(cancel_button)
	
	# ===== ПОДВКЛАДКА: РАБОТА С КОДОМ ВНЕ ФУНКЦИЙ =====
	var code_tab = VBoxContainer.new()
	manual_tab_container.add_child(code_tab)
	manual_tab_container.set_tab_title(1, "Код вне функций")
	
	# Заголовок
	var code_label = Label.new()
	code_label.text = "Добавление кода вне функций (переменные, константы, импорты и т.д.):"
	code_tab.add_child(code_label)
	
	# Выбор места вставки
	var position_label = Label.new()
	position_label.text = "Место вставки:"
	code_tab.add_child(position_label)
	
	var position_container = HBoxContainer.new()
	code_tab.add_child(position_container)
	
	var position_option = OptionButton.new()
	position_option.add_item("В конец файла")
	position_option.add_item("В начало файла")
	position_option.add_item("В начало после extends")
	position_option.add_item("В начало перед extends")
	position_option.add_item("На конкретную строку")
	position_option.selected = 2  # По умолчанию "В начало после extends"
	position_container.add_child(position_option)
	
	var line_number_edit = SpinBox.new()
	line_number_edit.min_value = 1
	line_number_edit.max_value = 9999
	line_number_edit.value = 1
	line_number_edit.visible = false
	line_number_edit.tooltip_text = "Номер строки (начиная с 1)"
	position_container.add_child(line_number_edit)
	
	# Показываем/скрываем поле номера строки
	position_option.item_selected.connect(func(index):
		line_number_edit.visible = (index == 4)  # "На конкретную строку"
	)
	
	# Поле для кода
	var file_code_label = Label.new()
	file_code_label.text = "Код для добавления:"
	code_tab.add_child(file_code_label)
	var file_code_edit = TextEdit.new()
	file_code_edit.placeholder_text = "var my_variable = 10\nconst MY_CONSTANT = 100\n@tool\nextends Node2D"
	file_code_edit.custom_minimum_size = Vector2(960, 200)
	code_tab.add_child(file_code_edit)
	
	# Разделитель
	var separator = HSeparator.new()
	code_tab.add_child(separator)
	
	# Удаление кода
	var delete_code_label = Label.new()
	delete_code_label.text = "Удаление кода:"
	code_tab.add_child(delete_code_label)
	
	var delete_code_edit = TextEdit.new()
	delete_code_edit.placeholder_text = "Введите код для удаления (точно как в файле):\nvar my_variable = 10"
	delete_code_edit.custom_minimum_size = Vector2(960, 100)
	code_tab.add_child(delete_code_edit)
	
	# Кнопки для работы с кодом
	var code_buttons = HBoxContainer.new()
	code_tab.add_child(code_buttons)
	
	var add_code_button = Button.new()
	add_code_button.text = "Добавить код"
	add_code_button.pressed.connect(func():
		var position = position_option.selected
		var line_number = int(line_number_edit.value)
		add_code_to_file(file_code_edit.text, position, line_number)
		dialog.hide()
	)
	code_buttons.add_child(add_code_button)
	
	var delete_code_button = Button.new()
	delete_code_button.text = "Удалить код"
	delete_code_button.pressed.connect(func():
		delete_code_from_file(delete_code_edit.text)
		dialog.hide()
	)
	code_buttons.add_child(delete_code_button)
	
	var code_cancel_button = Button.new()
	code_cancel_button.text = "Отмена"
	code_cancel_button.pressed.connect(func(): dialog.hide())
	code_buttons.add_child(code_cancel_button)
	
	# Показываем диалог
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()

func load_functions_list(function_list: ItemList):
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var functions = find_functions_in_file(file_path)
			
			for func_data in functions:
				var display_text = func_data.signature + " (строка " + str(func_data.line) + ")"
				var index = function_list.add_item(display_text)
				function_list.set_item_metadata(index, func_data)
			
			if functions.size() == 0:
				function_list.add_item("Функции не найдены")

func find_functions_in_file(file_path: String) -> Array:
	var functions = []
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return functions
	
	var lines = file.get_as_text().split("\n")
	file.close()
	
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.begins_with("func "):
			var func_data = {
				"signature": line,
				"line": i + 1,
				"start_index": i,
				"end_index": find_function_end(lines, i)
			}
			functions.append(func_data)
	
	return functions

func find_function_end(lines: Array, start_index: int) -> int:
	var i = start_index + 1
	var indent_level = get_indent_level(lines[start_index])
	
	while i < lines.size():
		var line = lines[i]
		var clean_line = line.strip_edges()
		
		# Пропускаем пустые строки
		if clean_line == "":
			i += 1
			continue
		
		# Проверяем, не нашли ли мы следующую функцию или класс
		if clean_line.begins_with("func ") or clean_line.begins_with("class_name") or clean_line.begins_with("extends") or clean_line.begins_with("var ") or clean_line.begins_with("const "):
			var current_indent = get_indent_level(line)
			if current_indent <= indent_level:
				return i
		
		# Проверяем, не закончилась ли функция (меньший отступ)
		var current_indent = get_indent_level(line)
		if current_indent < indent_level:
			return i
		
		i += 1
	
	return i

func smart_replace_function(function_data: Dictionary, new_code: String):
	smart_replace_function_with_comment(function_data, new_code, "")

func smart_replace_function_with_comment(function_data: Dictionary, new_code: String, comment: String):
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = replace_function_content_with_comment(file_path, function_data, new_code, comment)
			
			if success:
				print("Функция успешно заменена!")
				# Автоматически перезагружаем файл в редакторе
				reload_script_in_editor(current_script)
			else:
				print("Ошибка при замене функции!")

func replace_function_content(file_path: String, function_data: Dictionary, new_code: String) -> bool:
	return replace_function_content_with_comment(file_path, function_data, new_code, "")

func replace_function_content_with_comment(file_path: String, function_data: Dictionary, new_code: String, comment: String) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# Заменяем содержимое функции
	var new_content = replace_function_content_with_comment_in_text(content, function_data, new_code, comment)
	if new_content == content:
		return false
	
	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(new_content)
	file.close()
	
	return true

func replace_function_content_in_text(content: String, function_data: Dictionary, new_code: String) -> String:
	return replace_function_content_with_comment_in_text(content, function_data, new_code, "")

func replace_function_content_with_comment_in_text(content: String, function_data: Dictionary, new_code: String, comment: String) -> String:
	var lines = content.split("\n")
	var result_lines = []
	var i = 0
	
	while i < lines.size():
		if i == function_data.start_index:
			# Проверяем, есть ли комментарий над функцией
			var comment_start = i
			if i > 0 and lines[i-1].strip_edges().begins_with("#"):
				comment_start = i - 1
				# Проверяем, есть ли пустая строка перед комментарием
				if comment_start > 0 and lines[comment_start-1].strip_edges() == "":
					comment_start = i - 2
			
			# Добавляем новый комментарий (если есть)
			if comment.strip_edges() != "":
				result_lines.append("")
				result_lines.append("#" + comment)
			
			# Добавляем сигнатуру функции
			result_lines.append(lines[i])
			
			# Добавляем новый код с правильными отступами
			var indent = get_indentation(lines[i])
			var new_code_lines = new_code.split("\n")
			
			for code_line in new_code_lines:
				if code_line.strip_edges() != "":
					result_lines.append(indent + "	" + code_line)
				else:
					result_lines.append("")
			
			# Пропускаем старое содержимое функции и комментарий
			i = function_data.end_index
		else:
			# Обычная строка, копируем как есть
			result_lines.append(lines[i])
			i += 1
	
	return "\n".join(result_lines)

func replace_function_in_file(file_path: String, old_signature: String, new_function: String) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# Находим и заменяем функцию
	var new_content = find_and_replace_function(content, old_signature, new_function)
	if new_content == content:
		return false
	
	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(new_content)
	file.close()
	
	return true

func find_and_replace_function(content: String, old_signature: String, new_function: String) -> String:
	var lines = content.split("\n")
	var result_lines = []
	var i = 0
	
	# Очищаем сигнатуру от лишних пробелов
	var clean_signature = old_signature.strip_edges()
	print("Ищем функцию: '", clean_signature, "'")
	
	while i < lines.size():
		var line = lines[i]
		var clean_line = line.strip_edges()
		
		# Проверяем, начинается ли строка с сигнатуры функции
		if clean_line.begins_with(clean_signature):
			print("Найдена функция на строке ", i + 1, ": '", clean_line, "'")
			
			# Нашли функцию! Пропускаем её полностью
			var indent = get_indentation(line)
			var old_end = skip_function(lines, i)
			
			# Добавляем новую функцию с правильным отступом
			var new_function_lines = new_function.split("\n")
			for func_line in new_function_lines:
				if func_line.strip_edges() != "":
					result_lines.append(indent + func_line)
				else:
					result_lines.append("")
			
			i = old_end
			print("Функция заменена!")
		else:
			# Обычная строка, копируем как есть
			result_lines.append(line)
			i += 1
	
	return "\n".join(result_lines)

func get_indentation(line: String) -> String:
	var indent = ""
	for char in line:
		if char == " " or char == "\t":
			indent += char
		else:
			break
	return indent

func skip_function(lines: Array, start_index: int) -> int:
	var i = start_index
	var indent_level = -1
	
	# Определяем уровень отступа первой строки функции
	if start_index < lines.size():
		indent_level = get_indent_level(lines[start_index])
		print("Уровень отступа функции: ", indent_level)
	
	i = start_index + 1  # Начинаем со следующей строки
	
	while i < lines.size():
		var line = lines[i]
		var clean_line = line.strip_edges()
		
		# Пропускаем пустые строки
		if clean_line == "":
			i += 1
			continue
		
		# Проверяем, не нашли ли мы следующую функцию или класс
		if clean_line.begins_with("func ") or clean_line.begins_with("class_name") or clean_line.begins_with("extends") or clean_line.begins_with("var ") or clean_line.begins_with("const "):
			# Проверяем уровень отступа
			var current_indent = get_indent_level(line)
			if current_indent <= indent_level:
				print("Найдена следующая функция/переменная на строке ", i + 1, ": '", clean_line, "'")
				return i
		
		# Проверяем, не закончилась ли функция (меньший отступ)
		var current_indent = get_indent_level(line)
		if current_indent < indent_level:
			print("Функция закончилась на строке ", i, " (меньший отступ)")
			return i
		
		i += 1
	
	print("Достигнут конец файла, функция заканчивается на строке ", i)
	return i

func get_indent_level(line: String) -> int:
	var level = 0
	for char in line:
		if char == " ":
			level += 1
		elif char == "\t":
			level += 4  # Таб = 4 пробела
		else:
			break
	return level 

func add_new_function(name: String, args: String, code: String):
	if name.strip_edges() == "":
		print("Имя функции не может быть пустым!")
		return
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var file = FileAccess.open(file_path, FileAccess.READ)
			if not file:
				print("Ошибка открытия файла!")
				return
			var content = file.get_as_text()
			file.close()
			var lines = content.split("\n")
			# Формируем функцию
			var func_header = "func " + name.strip_edges() + "(" + args.strip_edges() + "):" if args.strip_edges() != "" else "func " + name.strip_edges() + "():"
			var func_lines = [func_header]
			for code_line in code.split("\n"):
				if code_line.strip_edges() != "":
					func_lines.append("\t" + code_line)
				else:
					func_lines.append("")
			# Добавляем функцию в конец файла
			if lines.size() > 0 and lines[lines.size()-1].strip_edges() != "":
				lines.append("")
			for func_line in func_lines:
				lines.append(func_line)
			var new_content = "\n".join(lines)
			file = FileAccess.open(file_path, FileAccess.WRITE)
			if not file:
				print("Ошибка открытия файла для записи!")
				return
			file.store_string(new_content)
			file.close()
			print("Функция успешно добавлена!")
			# Автоматически перезагружаем файл в редакторе
			reload_script_in_editor(current_script)

func delete_function(function_data: Dictionary):
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = remove_function_from_file(file_path, function_data)
			
			if success:
				print("Функция успешно удалена!")
				# Автоматически перезагружаем файл в редакторе
				reload_script_in_editor(current_script)
			else:
				print("Ошибка при удалении функции!")

func remove_function_from_file(file_path: String, function_data: Dictionary) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# Удаляем функцию
	var new_content = remove_function_from_text(content, function_data)
	if new_content == content:
		return false
	
	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(new_content)
	file.close()
	
	return true

func remove_function_from_text(content: String, function_data: Dictionary) -> String:
	var lines = content.split("\n")
	var result_lines = []
	var i = 0
	
	while i < lines.size():
		if i == function_data.start_index:
			# Проверяем, есть ли комментарий над функцией
			var comment_start = i
			if i > 0 and lines[i-1].strip_edges().begins_with("#"):
				comment_start = i - 1
				# Проверяем, есть ли пустая строка перед комментарием
				if comment_start > 0 and lines[comment_start-1].strip_edges() == "":
					comment_start = i - 2
			
			# Пропускаем комментарий и функцию (от comment_start до end_index)
			i = function_data.end_index
		else:
			# Обычная строка, копируем как есть
			result_lines.append(lines[i])
			i += 1
	
	return "\n".join(result_lines) 

func reload_script_in_editor(script: Script):
	# Перезагружаем скрипт в редакторе
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		# Принудительно обновляем скрипт
		script.take_over_path(script.resource_path)
		
		# Обновляем редактор
		editor_interface.get_resource_filesystem().scan()
		
		# Файл обновлен
		pass 

func add_code_to_file(code: String, position: int = 0, line_number: int = 1):
	if code.strip_edges() == "":
		print("Код не может быть пустым!")
		return
		
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = insert_code_to_file(file_path, code, position, line_number)
			
			if success:
				print("Код успешно добавлен!")
				reload_script_in_editor(current_script)
			else:
				print("Ошибка при добавлении кода!")

func insert_code_to_file(file_path: String, code: String, position: int, line_number: int) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	var lines = content.split("\n")
	var code_lines = code.split("\n")
	var insert_index = 0
	
	# Определяем место вставки
	match position:
		0:  # В конец файла
			insert_index = lines.size()
			# Добавляем пустую строку если файл не заканчивается пустой строкой
			if lines.size() > 0 and lines[lines.size()-1].strip_edges() != "":
				lines.append("")
				insert_index += 1
		1:  # В начало файла
			insert_index = 0
		2:  # В начало после extends
			insert_index = find_extends_line(lines) + 1
			if insert_index <= 0:  # Если extends не найден, вставляем в начало
				insert_index = 0
		3:  # В начало перед extends
			insert_index = find_extends_line(lines)
			if insert_index < 0:  # Если extends не найден, вставляем в начало
				insert_index = 0
		4:  # На конкретную строку
			insert_index = line_number - 1  # Конвертируем в индекс (начиная с 0)
			if insert_index < 0:
				insert_index = 0
			elif insert_index > lines.size():
				insert_index = lines.size()
	
	# Вставляем код
	for i in range(code_lines.size()):
		lines.insert(insert_index + i, code_lines[i])
	
	var new_content = "\n".join(lines)
	
	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(new_content)
	file.close()
	
	return true 

func find_extends_line(lines: Array) -> int:
	# Ищем строку с extends
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.begins_with("extends "):
			return i
	return -1  # extends не найден

func delete_code_from_file(code_to_delete: String):
	if code_to_delete.strip_edges() == "":
		print("Код для удаления не может быть пустым!")
		return
		
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = remove_code_from_file(file_path, code_to_delete)
			
			if success:
				print("Код успешно удален!")
				reload_script_in_editor(current_script)
			else:
				print("Ошибка при удалении кода или код не найден!")

func remove_code_from_file(file_path: String, code_to_delete: String) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# Удаляем код
	var new_content = remove_code_from_text(content, code_to_delete)
	if new_content == content:
		return false  # Код не найден
	
	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(new_content)
	file.close()
	
	return true

func remove_code_from_text(content: String, code_to_delete: String) -> String:
	var lines = content.split("\n")
	var code_lines = code_to_delete.split("\n")
	
	# Ищем начало кода для удаления
	for i in range(lines.size() - code_lines.size() + 1):
		var found = true
		
		# Проверяем, совпадает ли код начиная с текущей строки
		for j in range(code_lines.size()):
			if i + j >= lines.size() or lines[i + j].strip_edges() != code_lines[j].strip_edges():
				found = false
				break
		
		if found:
			# Удаляем найденный код
			var result_lines = []
			for k in range(lines.size()):
				if k < i or k >= i + code_lines.size():
					result_lines.append(lines[k])
			
			return "\n".join(result_lines)
	
	# Код не найден
	return content 

func add_new_function_with_comment(name: String, args: String, code: String, comment: String):
	if name.strip_edges() == "":
		print("Имя функции не может быть пустым!")
		return
		
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = append_function_with_comment_to_file(file_path, name, args, code, comment)
			
			if success:
				print("Функция с комментарием успешно добавлена!")
				reload_script_in_editor(current_script)
			else:
				print("Ошибка при добавлении функции!")

func append_function_with_comment_to_file(file_path: String, name: String, args: String, code: String, comment: String) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	var lines = content.split("\n")
	
	# Добавляем пустую строку если файл не заканчивается пустой строкой
	if lines.size() > 0 and lines[lines.size()-1].strip_edges() != "":
		lines.append("")
	
	# Добавляем комментарий если он есть
	if comment.strip_edges() != "":
		lines.append("# " + comment)
	
	# Формируем функцию
	var func_header = "func " + name.strip_edges() + "(" + args.strip_edges() + "):" if args.strip_edges() != "" else "func " + name.strip_edges() + "():"
	lines.append(func_header)
	
	# Добавляем код функции
	var code_lines = code.split("\n")
	for code_line in code_lines:
		if code_line.strip_edges() != "":
			lines.append("\t" + code_line)
		else:
			lines.append("")
	
	var new_content = "\n".join(lines)
	
	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(new_content)
	file.close()
	
	return true 
