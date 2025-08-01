@tool
extends EditorPlugin

# ===== GEMINI API НАСТРОЙКИ =====
const GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent"
var gemini_api_key: String = ""  # Будет загружаться из настроек
const CHAT_HISTORY_FILE = "res://chat_history.json"

# История чата для контекста
var chat_history = []

# Ссылка на текущий диалог
var current_dialog = null

# Флаг для предотвращения множественных запросов
var is_requesting = false

# Функция для сохранения истории чата
func save_chat_history():
	var file = FileAccess.open(CHAT_HISTORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(chat_history))
		file.close()

# Функция для загрузки истории чата
func load_chat_history():
	if FileAccess.file_exists(CHAT_HISTORY_FILE):
		var file = FileAccess.open(CHAT_HISTORY_FILE, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			var parse_result = json.parse(content)
			if parse_result == OK:
				chat_history = json.data
			else:
				chat_history = []
		else:
			chat_history = []
	else:
		chat_history = []

# Функция для загрузки истории чата в интерфейс
func load_chat_to_ui(chat_history_edit: RichTextLabel):
	chat_history_edit.text = ""
	for entry in chat_history:
		var color = "blue" if entry.role == "user" else "green"
		var sender = "Вы" if entry.role == "user" else "AI"
		var formatted_message = "[color=" + color + "][b]" + sender + ":[/b][/color] " + entry.content + "\n\n"
		chat_history_edit.append_text(formatted_message)
	
	# Прокручиваем к концу
	chat_history_edit.scroll_to_line(chat_history_edit.get_line_count())

var smart_replace_button: Button

func _enter_tree():
	# Загружаем API ключ
	load_api_key()
	
	# Загружаем историю чата
	load_chat_history()
	
	# Тестируем соединение
	test_connection()
	
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

# ===== INI ПАРСЕР ФУНКЦИИ =====

func execute_ini_command(ini_text: String):
	if ini_text.strip_edges() == "":
		print("INI команда не может быть пустой!")
		return
	
	# Парсим INI текст
	var commands = parse_ini_text(ini_text)
	if commands.is_empty():
		print("Не удалось распарсить INI команды!")
		return
	
	# Выполняем команды
	var all_success = true
	for cmd in commands:
		var ok = execute_ini_single(cmd)
		if not ok:
			all_success = false
	
	if all_success:
		print("Все INI команды выполнены успешно!")
	else:
		print("Некоторые INI команды завершились с ошибкой!")

func parse_ini_text(ini_text: String) -> Array:
	var commands = []
	var lines = ini_text.split("\n")
	var current_command = {}
	var current_section = ""
	var in_command_block = false
	var in_code_block = false
	var current_code_lines = []
	
	for i in range(lines.size()):
		var line = lines[i]
		var stripped_line = line.strip_edges()
		
		# Проверяем маркеры начала и конца команды
		if stripped_line == "=[command]=":
			# Начало блока команд
			in_command_block = true
			in_code_block = false
			current_code_lines.clear()
			continue
		elif stripped_line == "=[end]=":
			# Конец блока команд
			if in_code_block and current_code_lines.size() > 0:
				# Нормализуем отступы перед сохранением кода
				var normalized_code = normalize_indentation(current_code_lines)
				current_command["code"] = "\n".join(normalized_code)
			if not current_command.is_empty():
				commands.append(current_command)
			in_command_block = false
			in_code_block = false
			current_command = {}
			current_code_lines.clear()
			continue
		
		# Если не в блоке команд, пропускаем
		if not in_command_block:
			continue
		
		if stripped_line.is_empty() or stripped_line.begins_with("#"):
			continue
		
		# Новая секция [action]
		if stripped_line.begins_with("[") and stripped_line.ends_with("]"):
			# Сохраняем предыдущую команду
			if in_code_block and current_code_lines.size() > 0:
				# Нормализуем отступы перед сохранением кода
				var normalized_code = normalize_indentation(current_code_lines)
				current_command["code"] = "\n".join(normalized_code)
			if not current_command.is_empty():
				commands.append(current_command)
			
			# Начинаем новую команду
			current_section = stripped_line.substr(1, stripped_line.length() - 2)
			current_command = {"action": current_section}
			in_code_block = false
			current_code_lines.clear()
			continue
		
		# Проверяем маркеры кода
		if stripped_line == "<cod>":
			in_code_block = true
			continue
		elif stripped_line == "<end_cod>":
			in_code_block = false
			if current_code_lines.size() > 0:
				# Нормализуем отступы перед сохранением кода
				var normalized_code = normalize_indentation(current_code_lines)
				current_command["code"] = "\n".join(normalized_code)
			current_code_lines.clear()
			continue
		
		# Если в блоке кода, добавляем строку
		if in_code_block:
			current_code_lines.append(line)
			continue
		
		# Параметр = значение (только если не в блоке кода)
		if "=" in stripped_line:
			var parts = stripped_line.split("=", true, 1)
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges()
			
			# Обрабатываем экранированные символы
			value = value.replace("\\n", "\n")
			value = value.replace("\\t", "\t")
			value = value.replace("\\\"", "\"")
			
			current_command[key] = value
	
	# Добавляем последнюю команду
	if in_code_block and current_code_lines.size() > 0:
		# Нормализуем отступы перед сохранением кода
		var normalized_code = normalize_indentation(current_code_lines)
		current_command["code"] = "\n".join(normalized_code)
	if not current_command.is_empty():
		commands.append(current_command)
	
	return commands

func execute_ini_single(data: Dictionary) -> bool:
	if not data.has("action"):
		print("INI команда должна содержать секцию [action]!")
		return false
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
			return false
	if success:
		print("INI команда выполнена успешно!")
	else:
		print("Ошибка при выполнении INI команды!")
	return success



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
	var function_data = {}
	if data.has("signature"):
		function_data = find_function_by_signature(data.signature)
	elif data.has("name"):
		function_data = find_function_by_name(data.name)
	else:
		print("Для замены функции нужно поле 'signature' или 'name'!")
		return false
	if function_data.is_empty():
		print("Функция не найдена!")
		return false
	if not data.has("code"):
		print("Для замены функции нужно поле 'code'!")
		return false
	var code = data.code
	var comment = data.get("comment", "")
	var new_signature = data.get("new_signature", "")
	if new_signature.strip_edges() != "":
		smart_replace_function_with_new_signature(function_data, code, comment, new_signature)
	else:
		smart_replace_function_with_comment(function_data, code, comment)
	return true

func handle_delete_function(data: Dictionary) -> bool:
	var function_data = {}
	if data.has("signature"):
		function_data = find_function_by_signature(data.signature)
	elif data.has("name"):
		function_data = find_function_by_name(data.name)
	else:
		print("Для удаления функции нужно поле 'signature' или 'name'!")
		return false
	if function_data.is_empty():
		print("Функция не найдена!")
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
	if not data.has("lines"):
		print("Для удаления кода нужно поле 'lines' с номерами строк!")
		return false
	
	var lines_param = data.lines
	delete_lines_from_file(lines_param)
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

# Новый поиск функции по имени
func find_function_by_name(name: String) -> Dictionary:
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var functions = find_functions_in_file(file_path)
			for func_data in functions:
				if func_data.signature.begins_with("func " + name + "("):
					return func_data
	return {}

func show_ini_preview(ini_text: String):
	if ini_text.strip_edges() == "":
		print("INI команда не может быть пустой!")
		return
	
	# Парсим INI текст
	var commands = parse_ini_text(ini_text)
	if commands.is_empty():
		print("Не удалось распарсить INI команды!")
		return
	
	var preview_text = ""
	for idx in range(commands.size()):
		var cmd = commands[idx]
		if not cmd.has("action"):
			preview_text += "❌ Команда #" + str(idx+1) + ": нет секции [action]\n"
			continue
		preview_text += "--- Команда #" + str(idx+1) + " ---\n"
		preview_text += generate_preview_for_single(cmd) + "\n"
	
	show_preview_dialog(preview_text, ini_text)

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
	var signature = ""
	var function_data = {}
	if data.has("signature"):
		signature = data.signature
		function_data = find_function_by_signature(signature)
	elif data.has("name"):
		function_data = find_function_by_name(data.name)
		if not function_data.is_empty():
			signature = function_data.signature
	else:
		return "❌ Ошибка: Для замены функции нужно поле 'signature' или 'name'!"
	if function_data.is_empty():
		return "❌ Функция с именем/сигнатурой '" + (data.get("name", signature)) + "' не найдена!"
	var code = data.code
	var comment = data.get("comment", "")
	var new_signature = data.get("new_signature", "")
	var preview = "🔄 ЗАМЕНИТЬ ФУНКЦИЮ:\n"
	preview += "📝 Текущая сигнатура: " + signature + "\n"
	if new_signature.strip_edges() != "":
		preview += "➡️ Новая сигнатура: " + new_signature + "\n"
	preview += "📍 Строка: " + str(function_data.line) + "\n"
	if comment.strip_edges() != "":
		preview += "💬 Новый комментарий: " + comment + "\n"
	preview += "📄 Новый код:\n"
	var code_lines = code.split("\n")
	for line in code_lines:
		if line.strip_edges() != "":
			preview += "   " + line + "\n"
		else:
			preview += "\n"
	return preview

func generate_delete_function_preview(data: Dictionary) -> String:
	var signature = ""
	var function_data = {}
	if data.has("signature"):
		signature = data.signature
		function_data = find_function_by_signature(signature)
	elif data.has("name"):
		function_data = find_function_by_name(data.name)
		if not function_data.is_empty():
			signature = function_data.signature
	else:
		return "❌ Ошибка: Для удаления функции нужно поле 'signature' или 'name'!"
	
	if function_data.is_empty():
		return "❌ Функция с именем/сигнатурой '" + (data.get("name", signature)) + "' не найдена!"
	
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
	if not data.has("lines"):
		return "❌ Ошибка: Для удаления кода нужно поле 'lines' с номерами строк!"
	
	var lines_param = data.lines
	
	var preview = "🗑️ УДАЛИТЬ СТРОКИ:\n"
	preview += "📄 Строки для удаления: " + lines_param + "\n"
	
	# Парсим и показываем какие строки будут удалены
	var parts = lines_param.split(",")
	for part in parts:
		part = part.strip_edges()
		if "-" in part:
			# Диапазон строк
			var range_parts = part.split("-")
			if range_parts.size() == 2:
				var start_line = range_parts[0].strip_edges()
				var end_line = range_parts[1].strip_edges()
				preview += "   Строки " + start_line + " - " + end_line + "\n"
		else:
			# Отдельная строка
			preview += "   Строка " + part + "\n"
	
	preview += "⚠️ Внимание: Указанные строки будут удалены!"
	return preview

func show_preview_dialog(preview_text: String, ini_text: String):
	# Закрываем все существующие диалоги
	close_all_dialogs()
	
	var dialog = AcceptDialog.new()
	dialog.title = "Предварительный просмотр изменений"
	dialog.size = Vector2(800, 700)
	
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
	
	# Проверяем отступы в коде
	var indent_issues = check_indentation_issues(ini_text)
	var indent_warning = Label.new()
	if indent_issues.length() > 0:
		indent_warning.text = "⚠️ Обнаружены проблемы с отступами в коде!"
		indent_warning.add_theme_color_override("font_color", Color.YELLOW)
		vbox.add_child(indent_warning)
		
		var indent_details = TextEdit.new()
		indent_details.text = indent_issues
		indent_details.editable = false
		indent_details.custom_minimum_size = Vector2(780, 100)
		vbox.add_child(indent_details)
	
	var buttons = HBoxContainer.new()
	vbox.add_child(buttons)
	
	var apply_button = Button.new()
	apply_button.text = "Применить изменения"
	apply_button.pressed.connect(func():
		execute_ini_command(ini_text)
		dialog.hide()
	)
	buttons.add_child(apply_button)
	
	if indent_issues.length() > 0:
		var fix_indent_button = Button.new()
		fix_indent_button.text = "Исправить отступы"
		fix_indent_button.pressed.connect(func():
			var fixed_ini = fix_indentation_in_ini(ini_text)
			show_preview_dialog(generate_preview_for_ini(fixed_ini), fixed_ini)
			dialog.hide()
		)
		buttons.add_child(fix_indent_button)
	
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

func check_indentation_issues(ini_text: String) -> String:
	var issues = []
	var lines = ini_text.split("\n")
	var in_code_block = false
	var code_lines = []
	var code_start_line = 0
	
	for i in range(lines.size()):
		var line = lines[i]
		var stripped_line = line.strip_edges()
		
		if stripped_line == "<cod>":
			in_code_block = true
			code_lines.clear()
			code_start_line = i + 1
			continue
		elif stripped_line == "<end_cod>":
			in_code_block = false
			# Проверяем код на проблемы с отступами
			var code_issues = analyze_code_indentation(code_lines, code_start_line)
			if code_issues.size() > 0:
				issues.append_array(code_issues)
			continue
		
		if in_code_block:
			code_lines.append(line)
	
	if issues.size() == 0:
		return ""
	
	return "\n".join(issues)

func analyze_code_indentation(code_lines: Array, start_line: int) -> Array:
	var issues = []
	var expected_indent = 0
	
	for i in range(code_lines.size()):
		var line = code_lines[i]
		var stripped_line = line.strip_edges()
		
		if stripped_line.is_empty():
			continue
		
		# Проверяем, начинается ли строка с правильного отступа
		var actual_indent = get_line_indent_level(line)
		
		# Если строка должна быть вложенной (после двоеточия)
		if i > 0 and code_lines[i-1].strip_edges().ends_with(":"):
			expected_indent += 1
		
		# Если строка не имеет отступа, но должна
		if actual_indent == 0 and expected_indent > 0:
			issues.append("Строка " + str(start_line + i + 1) + ": ожидается отступ " + str(expected_indent * 4) + " пробелов")
		
		# Если строка имеет отступ, но не должна
		if actual_indent > 0 and expected_indent == 0:
			issues.append("Строка " + str(start_line + i + 1) + ": лишний отступ")
		
		# Сбрасываем ожидаемый отступ для новых блоков
		if stripped_line.begins_with("if ") or stripped_line.begins_with("for ") or stripped_line.begins_with("while ") or stripped_line.begins_with("def ") or stripped_line.begins_with("func "):
			expected_indent = 0
	
	return issues

func get_line_indent_level(line: String) -> int:
	var indent = 0
	for i in range(line.length()):
		if line[i] == " ":
			indent += 1
		elif line[i] == "\t":
			indent += 4
		else:
			break
	return indent / 4

func fix_indentation_in_ini(ini_text: String) -> String:
	var lines = ini_text.split("\n")
	var result_lines = []
	var in_code_block = false
	var code_lines = []
	var code_start_index = 0
	
	for i in range(lines.size()):
		var line = lines[i]
		var stripped_line = line.strip_edges()
		
		if stripped_line == "<cod>":
			in_code_block = true
			code_lines.clear()
			code_start_index = result_lines.size()
			result_lines.append(line)
			continue
		elif stripped_line == "<end_cod>":
			in_code_block = false
			# Нормализуем отступы (заменяем табуляции на пробелы)
			var normalized_code = normalize_indentation(code_lines)
			# Исправляем отступы в коде
			var fixed_code = fix_code_indentation(normalized_code)
			result_lines.append_array(fixed_code)
			result_lines.append(line)
			continue
		
		if in_code_block:
			code_lines.append(line)
		else:
			result_lines.append(line)
	
	return "\n".join(result_lines)

func normalize_indentation(code_lines: Array) -> Array:
	var result = []
	for line in code_lines:
		var normalized_line = ""
		var in_indent = true
		var indent_count = 0
		
		for i in range(line.length()):
			var char = line[i]
			if in_indent:
				if char == " ":
					indent_count += 1
				elif char == "\t":
					indent_count += 4
				else:
					in_indent = false
					# Добавляем нормализованный отступ
					for j in range(indent_count):
						normalized_line += " "
					normalized_line += char
			else:
				normalized_line += char
		
		# Если строка состояла только из отступов
		if in_indent:
			for j in range(indent_count):
				normalized_line += " "
		
		result.append(normalized_line)
	
	return result

func fix_code_indentation(code_lines: Array) -> Array:
	var result = []
	var indent_level = 0
	
	for line in code_lines:
		var stripped_line = line.strip_edges()
		
		if stripped_line.is_empty():
			result.append("")
			continue
		
		# Уменьшаем отступ для строк, которые не должны быть вложенными
		if stripped_line.begins_with("else:") or stripped_line.begins_with("elif "):
			indent_level = max(0, indent_level - 1)
		
		# Добавляем правильный отступ (только пробелы, без табуляций)
		var indent = ""
		for i in range(indent_level * 4):
			indent += " "
		result.append(indent + stripped_line)
		
		# Увеличиваем отступ для строк с двоеточием
		if stripped_line.ends_with(":"):
			indent_level += 1
	
	return result

func generate_preview_for_ini(ini_text: String) -> String:
	var commands = parse_ini_text(ini_text)
	if commands.is_empty():
		return "Не удалось распарсить INI команды!"
	
	var preview_text = ""
	for idx in range(commands.size()):
		var cmd = commands[idx]
		if not cmd.has("action"):
			preview_text += "❌ Команда #" + str(idx+1) + ": нет секции [action]\n"
			continue
		preview_text += "--- Команда #" + str(idx+1) + " ---\n"
		preview_text += generate_preview_for_single(cmd) + "\n"
	
	return preview_text

func show_smart_replace_dialog_v2():
	# Закрываем предыдущий диалог, если он есть
	if current_dialog:
		current_dialog.queue_free()
	
	var dialog = AcceptDialog.new()
	dialog.title = "Smart Replace - Умная замена функций"
	dialog.size = Vector2(1000, 800)
	
	# Сохраняем ссылку на диалог
	current_dialog = dialog
	
	# Добавляем обработчик закрытия диалога
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			current_dialog = null
	)
	
	# Создаем основной контейнер
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	# Создаем вкладки
	var tab_container = TabContainer.new()
	tab_container.custom_minimum_size = Vector2(980, 700)
	vbox.add_child(tab_container)
	
	# ===== ВКЛАДКА 1: INI =====
	var ini_tab = VBoxContainer.new()
	tab_container.add_child(ini_tab)
	tab_container.set_tab_title(0, "INI")
	
	# Заголовок для INI вкладки
	var ini_label = Label.new()
	ini_label.text = "Вставьте INI команду от ИИ:"
	ini_tab.add_child(ini_label)
	
	# Поле для INI
	var ini_edit = TextEdit.new()
	ini_edit.placeholder_text = '# Вставьте ответ от ИИ с INI командами в блоках:\n\n# Пример ответа ИИ:\nЯ добавлю функцию для движения игрока и переменную скорости.\n\n=[command]=\n[add_function]\nname=move_player\nparameters=direction, speed\n<cod>\nposition += direction * speed * delta\n<end_cod>\n=[end]=\n\n# Или несколько блоков:\n=[command]=\n[add_code]\n<cod>\nvar player_speed = 5.0\n<end_cod>\nposition_type=after_extends\n=[end]=\n\n=[command]=\n[add_function]\nname=move_player\nparameters=direction\n<cod>\nposition += direction * player_speed * delta\n<end_cod>\n=[end]=\n\n# Удаление строк:\n=[command]=\n[delete_code]\nlines=5, 10-15, 23\n=[end]=\n\n# Многострочный код с отступами:\n=[command]=\n[add_function]\nname=complex_function\n<cod>\nif condition:\n    print("True")\nelse:\n    print("False")\n<end_cod>\n=[end]=\n\n# Парсер автоматически найдет и выполнит команды между =[command]= и =[end]='
	ini_edit.custom_minimum_size = Vector2(960, 600)
	ini_tab.add_child(ini_edit)
	
	# Кнопки для INI вкладки
	var ini_buttons = HBoxContainer.new()
	ini_tab.add_child(ini_buttons)
	
	var preview_button = Button.new()
	preview_button.text = "Предварительный просмотр"
	preview_button.pressed.connect(func():
		var ini_text = ini_edit.text
		show_ini_preview(ini_text)
	)
	ini_buttons.add_child(preview_button)
	
	var execute_ini_button = Button.new()
	execute_ini_button.text = "Выполнить INI"
	execute_ini_button.pressed.connect(func():
		var ini_text = ini_edit.text
		execute_ini_command(ini_text)
	)
	ini_buttons.add_child(execute_ini_button)
	
	var clear_ini_button = Button.new()
	clear_ini_button.text = "Очистить"
	clear_ini_button.pressed.connect(func():
		ini_edit.text = ""
	)
	ini_buttons.add_child(clear_ini_button)
	
	# ===== ВКЛАДКА 2: РУЧНАЯ РАБОТА =====
	var manual_tab = VBoxContainer.new()
	tab_container.add_child(manual_tab)
	tab_container.set_tab_title(1, "Ручная работа")
	
	# ===== ВКЛАДКА 3: AI ЧАТ =====
	var ai_tab = VBoxContainer.new()
	tab_container.add_child(ai_tab)
	tab_container.set_tab_title(2, "AI Чат")
	
	# Заголовок для AI чата
	var ai_label = Label.new()
	ai_label.text = "AI Чат - общайтесь с Google Gemini и автоматически редактируйте код:"
	ai_tab.add_child(ai_label)
	
	# Область чата
	var chat_area = VBoxContainer.new()
	chat_area.custom_minimum_size = Vector2(960, 400)
	ai_tab.add_child(chat_area)
	
	# Поле для отображения истории чата
	var chat_history_edit = RichTextLabel.new()
	chat_history_edit.custom_minimum_size = Vector2(960, 350)
	chat_history_edit.bbcode_enabled = true
	chat_history_edit.scroll_following = true
	chat_area.add_child(chat_history_edit)
	
	# Загружаем историю чата в интерфейс
	load_chat_to_ui(chat_history_edit)
	
	# Контейнер для ввода сообщения
	var input_container = HBoxContainer.new()
	ai_tab.add_child(input_container)
	
	# Поле для ввода сообщения
	var message_edit = LineEdit.new()
	message_edit.placeholder_text = "Введите ваше сообщение для AI..."
	message_edit.custom_minimum_size = Vector2(800, 30)
	message_edit.text_submitted.connect(func(text):
		send_message_to_ai(text)
	)
	input_container.add_child(message_edit)
	
	# Кнопка отправки
	var send_button = Button.new()
	send_button.text = "Отправить"
	send_button.pressed.connect(func():
		var message = message_edit.text
		if message.strip_edges() != "":
			send_message_to_ai(message)
			message_edit.text = ""
	)
	input_container.add_child(send_button)
	
	# Поле для API ключа
	var api_key_container = HBoxContainer.new()
	ai_tab.add_child(api_key_container)
	
	var api_key_label = Label.new()
	api_key_label.text = "API ключ Google Gemini:"
	api_key_container.add_child(api_key_label)
	
	var api_key_edit = LineEdit.new()
	api_key_edit.placeholder_text = "AIza... (введите ваш Google Gemini API ключ)"
	api_key_edit.secret = true
	api_key_edit.custom_minimum_size = Vector2(400, 30)
	api_key_edit.text = gemini_api_key if gemini_api_key != null else ""  # Показываем текущий ключ
	api_key_container.add_child(api_key_edit)
	
	var save_api_button = Button.new()
	save_api_button.text = "Сохранить ключ"
	save_api_button.pressed.connect(func():
		gemini_api_key = api_key_edit.text
		save_api_key()
		print("API ключ сохранен!")
	)
	api_key_container.add_child(save_api_button)
	
	# Кнопки управления
	var control_buttons = HBoxContainer.new()
	ai_tab.add_child(control_buttons)
	
	var clear_chat_button = Button.new()
	clear_chat_button.text = "Очистить чат"
	clear_chat_button.pressed.connect(func():
		chat_history.clear()
		chat_history_edit.text = ""
		save_chat_history()  # Сохраняем пустую историю
	)
	control_buttons.add_child(clear_chat_button)
	
	# Поле для отображения извлеченных команд (скрыто по умолчанию)
	var extracted_commands_label = Label.new()
	extracted_commands_label.text = "Извлеченные INI команды (для отладки):"
	extracted_commands_label.visible = false
	ai_tab.add_child(extracted_commands_label)
	
	var extracted_commands_edit = TextEdit.new()
	extracted_commands_edit.placeholder_text = "Здесь будут показаны извлеченные команды"
	extracted_commands_edit.custom_minimum_size = Vector2(960, 150)
	extracted_commands_edit.visible = false
	ai_tab.add_child(extracted_commands_edit)
	
	# Кнопка для показа/скрытия команд (для отладки)
	var show_commands_button = Button.new()
	show_commands_button.text = "Показать извлеченные команды"
	show_commands_button.pressed.connect(func():
		var is_visible = extracted_commands_label.visible
		extracted_commands_label.visible = !is_visible
		extracted_commands_edit.visible = !is_visible
		show_commands_button.text = "Скрыть извлеченные команды" if !is_visible else "Показать извлеченные команды"
	)
	control_buttons.add_child(show_commands_button)
	
	# Сохраняем ссылки на элементы AI чата для доступа из других функций
	ai_tab.set_meta("chat_history_edit", chat_history_edit)
	ai_tab.set_meta("message_edit", message_edit)
	ai_tab.set_meta("extracted_edit", extracted_commands_edit)
	
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
	
	# Удаление строк
	var delete_code_label = Label.new()
	delete_code_label.text = "Удаление строк:"
	code_tab.add_child(delete_code_label)
	
	var delete_code_edit = LineEdit.new()
	delete_code_edit.placeholder_text = "Введите номера строк (например: 5, 10-15, 23)"
	delete_code_edit.custom_minimum_size = Vector2(960, 30)
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
	delete_code_button.text = "Удалить строки"
	delete_code_button.pressed.connect(func():
		delete_lines_from_file(delete_code_edit.text)
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
				pass
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
					result_lines.append(indent + "    " + code_line)  # 4 пробела вместо табуляции
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
					func_lines.append("    " + code_line)  # 4 пробела вместо табуляции
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
			pass

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
				pass
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
				pass
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
			lines.append("    " + code_line)  # 4 пробела вместо табуляции
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

func generate_preview_for_single(data: Dictionary) -> String:
	if not data.has("action"):
		return "❌ Нет поля 'action'!"
	var action = data.action
	match action:
		"add_function":
			return generate_add_function_preview(data)
		"replace_function":
			return generate_replace_function_preview(data)
		"delete_function":
			return generate_delete_function_preview(data)
		"add_code":
			return generate_add_code_preview(data)
		"delete_code":
			return generate_delete_code_preview(data)
		_:
			return "Неизвестное действие: " + action 

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
			else:
				print("Ошибка при добавлении кода!")

func delete_lines_from_file(lines_param: String):
	if lines_param.strip_edges() == "":
		print("Номера строк для удаления не могут быть пустыми!")
		return
	
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = remove_lines_from_file(file_path, lines_param)
			if success:
				print("Строки успешно удалены!")
			else:
				print("Ошибка при удалении строк!") 

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

func remove_lines_from_file(file_path: String, lines_param: String) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false

	var content = file.get_as_text()
	file.close()

	# Удаляем строки
	var new_content = remove_lines_from_text(content, lines_param)
	if new_content == content:
		return false  # Строки не найдены

	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false

	file.store_string(new_content)
	file.close()

	return true

func remove_lines_from_text(content: String, lines_param: String) -> String:
	var lines = content.split("\n")
	var lines_to_remove = []
	
	# Парсим параметр lines
	var parts = lines_param.split(",")
	for part in parts:
		part = part.strip_edges()
		if "-" in part:
			# Диапазон строк (например: "23-40")
			var range_parts = part.split("-")
			if range_parts.size() == 2:
				var start_line = range_parts[0].strip_edges().to_int()
				var end_line = range_parts[1].strip_edges().to_int()
				for i in range(start_line, end_line + 1):
					if i > 0 and i <= lines.size():
						lines_to_remove.append(i - 1)  # Конвертируем в индекс (начиная с 0)
		else:
			# Отдельная строка
			var line_num = part.to_int()
			if line_num > 0 and line_num <= lines.size():
				lines_to_remove.append(line_num - 1)  # Конвертируем в индекс (начиная с 0)
	
	# Сортируем номера строк в обратном порядке для удаления с конца
	lines_to_remove.sort()
	lines_to_remove.reverse()
	
	# Удаляем строки
	for line_index in lines_to_remove:
		if line_index >= 0 and line_index < lines.size():
			lines.remove_at(line_index)
	
	return "\n".join(lines)

func find_extends_line(lines: Array) -> int:
	# Ищем строку с extends
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.begins_with("extends "):
			return i
	return -1  # extends не найден 

func smart_replace_function_with_new_signature(function_data: Dictionary, new_code: String, comment: String, new_signature: String):
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = replace_function_content_with_new_signature(file_path, function_data, new_code, comment, new_signature)
			if success:
				print("Функция успешно заменена с новой сигнатурой!")
			else:
				print("Ошибка при замене функции!")

func replace_function_content_with_new_signature(file_path: String, function_data: Dictionary, new_code: String, comment: String, new_signature: String) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	var content = file.get_as_text()
	file.close()
	# Заменяем содержимое функции и сигнатуру
	var new_content = replace_function_content_with_new_signature_in_text(content, function_data, new_code, comment, new_signature)
	if new_content == content:
		return false
	# Записываем обновленный контент
	file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(new_content)
	file.close()
	return true

func replace_function_content_with_new_signature_in_text(content: String, function_data: Dictionary, new_code: String, comment: String, new_signature: String) -> String:
	var lines = content.split("\n")
	var result_lines = []
	var i = 0
	while i < lines.size():
		if i == function_data.start_index:
			# Проверяем, есть ли комментарий над функцией
			var comment_start = i
			if i > 0 and lines[i-1].strip_edges().begins_with("#"):
				comment_start = i - 1
				if comment_start > 0 and lines[comment_start-1].strip_edges() == "":
					comment_start = i - 2
			# Добавляем новый комментарий (если есть)
			if comment.strip_edges() != "":
				result_lines.append("")
				result_lines.append("#" + comment)
			# Добавляем новую сигнатуру функции
			result_lines.append(new_signature)
			# Добавляем новый код с правильными отступами
			var indent = get_indentation(new_signature)
			var new_code_lines = new_code.split("\n")
			for code_line in new_code_lines:
				if code_line.strip_edges() != "":
					result_lines.append(indent + "    " + code_line)  # 4 пробела вместо табуляции
				else:
					result_lines.append("")
			# Пропускаем старое содержимое функции и комментарий
			i = function_data.end_index
		else:
			result_lines.append(lines[i])
			i += 1
	return "\n".join(result_lines) 

# ===== AI ЧАТ ФУНКЦИИ =====

func send_message_to_ai(message: String):
	print("send_message_to_ai вызвана с сообщением: ", message)
	
	if message.strip_edges() == "":
		return
	
	# Проверяем, не выполняется ли уже запрос
	if is_requesting:
		add_message_to_chat("Система", "Подождите, предыдущий запрос еще выполняется...", "system")
		return
	
	# Проверяем API ключ
	if gemini_api_key == "":
		print("API ключ не найден, показываем диалог настроек")
		show_api_key_dialog()
		return
	
	print("Добавляем сообщение в чат...")
	# Добавляем сообщение пользователя в чат
	add_message_to_chat("Вы", message, "user")
	
	# Получаем текущий код файла для контекста
	var current_code = get_current_file_content()
	print("Текущий код файла получен, длина: ", current_code.length())
	
	# Формируем промпт для AI
	var prompt = create_chat_prompt(message, current_code)
	print("Промпт сформирован, отправляем запрос к OpenAI...")
	
	# Устанавливаем флаг выполнения запроса
	is_requesting = true
	
	# Отправляем запрос к Gemini
	call_gemini_api(prompt)

func add_message_to_chat(sender: String, message: String, type: String):
	print("add_message_to_chat вызвана: ", sender, " - ", message)
	
	# Добавляем сообщение в историю для API
	var history_entry = {
		"role": type,
		"content": message
	}
	chat_history.append(history_entry)
	
	# Сохраняем историю в файл
	save_chat_history()
	
	# Используем сохраненную ссылку на диалог
	if not current_dialog:
		print("Текущий диалог не найден!")
		return
	
	# Проверяем, что диалог видимый
	if not current_dialog.visible:
		print("Диалог найден, но не видимый!")
		return
	
	print("Диалог найден, ищем VBoxContainer...")
	var vbox = current_dialog.get_child(0)
	if not vbox or vbox.get_child_count() == 0:
		print("VBoxContainer не найден!")
		return
	
	print("VBoxContainer найден, ищем TabContainer...")
	var tab_container = vbox.get_child(0)
	if not tab_container or tab_container.get_child_count() < 3:
		print("TabContainer не найден или недостаточно вкладок! Количество вкладок: ", tab_container.get_child_count() if tab_container else 0)
		return
	
	print("TabContainer найден, ищем AI вкладку...")
	var ai_tab = tab_container.get_child(2)  # AI Чат вкладка
	if not ai_tab:
		print("AI вкладка не найдена!")
		return
	
	print("AI вкладка найдена, ищем chat_history_edit в метаданных...")
	var chat_history_edit = ai_tab.get_meta("chat_history_edit")
	if not chat_history_edit:
		print("chat_history_edit не найден в метаданных!")
		print("Доступные метаданные: ", ai_tab.get_meta_list())
		return
	
	print("chat_history_edit найден, добавляем сообщение...")
	var color = "blue" if type == "user" else "green"
	var formatted_message = "[color=" + color + "][b]" + sender + ":[/b][/color] " + message + "\n\n"
	chat_history_edit.append_text(formatted_message)
	
	# Прокручиваем к концу
	chat_history_edit.scroll_to_line(chat_history_edit.get_line_count())
	print("Сообщение добавлено успешно!")

func get_current_file_content() -> String:
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var file = FileAccess.open(file_path, FileAccess.READ)
			if file:
				var content = file.get_as_text()
				file.close()
				return content
	return ""

func create_chat_prompt(message: String, current_code: String) -> String:
	var system_prompt = """Ты - эксперт по GDScript и плагину Smart Replace для Godot. 

Твоя задача - помогать пользователю редактировать код в GDScript файлах. Когда пользователь просит изменить код, ты должен:

1. Ответить на естественном языке
2. Скрыто вставить INI команды для выполнения изменений между маркерами =[command]= и =[end]=
3. Пользователь не должен видеть эти команды, только твой текстовый ответ

ТЕКУЩИЙ КОД ФАЙЛА:
```
{current_code}
```

ИСТОРИЯ ЧАТА:
{chat_history}

ПОЛЬЗОВАТЕЛЬ: {message}

Помни: отвечай естественно, как обычный помощник, но скрыто добавляй INI команды для выполнения изменений."""
	
	# Формируем историю чата для контекста
	var history_text = ""
	for i in range(max(0, chat_history.size() - 6), chat_history.size()):  # Последние 6 сообщений
		var msg = chat_history[i]
		history_text += msg.role + ": " + msg.content + "\n"
	
	return system_prompt.format({
		"current_code": current_code,
		"chat_history": history_text,
		"message": message
	})

func call_gemini_api(prompt: String):
	print("call_gemini_api вызвана с промптом длиной: ", prompt.length())
	
	# Создаем HTTP запрос
	var http = HTTPRequest.new()
	http.timeout = 30  # 30 секунд таймаут
	add_child(http)
	
	# Формируем JSON для запроса Gemini
	var request_data = {
		"contents": [
			{
				"parts": [
					{
						"text": prompt
					}
				]
			}
		],
		"generationConfig": {
			"temperature": 0.1,
			"maxOutputTokens": 2000
		}
	}
	
	var json_string = JSON.stringify(request_data)
	
	# Формируем URL с API ключом
	var url = GEMINI_API_URL + "?key=" + gemini_api_key
	
	# Настраиваем заголовки
	var headers = [
		"Content-Type: application/json"
	]
	
	# Отправляем запрос
	print("Отправляем запрос на URL: ", url)
	print("Длина JSON данных: ", json_string.length())
	var error = http.request(url, headers, HTTPClient.METHOD_POST, json_string)
	if error != OK:
		print("Ошибка при отправке HTTP запроса: ", error)
		print("Коды ошибок: 0=OK, 1=RESULT_CHUNKED_BODY_SIZE_MISMATCH, 2=RESULT_CANT_RESOLVE, 3=RESULT_CANT_RESOLVE_PROXY, 4=RESULT_CANT_CONNECT, 5=RESULT_CANT_CONNECT_PROXY, 6=RESULT_SSL_HANDSHAKE_ERROR, 7=RESULT_CANT_ACCEPT, 8=RESULT_TIMEOUT")
		http.queue_free()
		return
	
	# Подключаем сигнал завершения
	http.request_completed.connect(func(result, response_code, headers, body):
		handle_gemini_response(result, response_code, headers, body)
		http.queue_free()
	)

func handle_gemini_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("handle_gemini_response вызвана с кодом: ", response_code)
	
	# Сбрасываем флаг выполнения запроса
	is_requesting = false
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("Ошибка HTTP запроса: ", result)
		add_message_to_chat("Система", "Ошибка соединения с Google Gemini API", "system")
		return
	
	if response_code != 200:
		print("Ошибка API: ", response_code)
		var response_text = body.get_string_from_utf8()
		print("Ответ: ", response_text)
		
		# Обрабатываем конкретные ошибки
		var error_message = "Ошибка API: " + str(response_code)
		
		match response_code:
			400:
				error_message = "Ошибка запроса (400). Проверьте правильность API ключа Google Gemini."
			401:
				error_message = "Ошибка аутентификации (401). Проверьте правильность API ключа Google Gemini."
			404:
				error_message = "Модель не найдена (404). Проверьте доступность модели Gemini."
			429:
				error_message = "Слишком много запросов (429). Подождите немного и попробуйте снова."
			500:
				error_message = "Ошибка сервера Google (500). Попробуйте позже."
			503:
				error_message = "Сервис Google Gemini временно недоступен (503). Попробуйте позже."
			_:
				error_message = "Ошибка API: " + str(response_code) + ". Проверьте интернет-соединение и API ключ."
		
		add_message_to_chat("Система", error_message, "system")
		return
	
	# Парсим JSON ответ
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		print("Ошибка парсинга JSON: ", parse_result)
		add_message_to_chat("Система", "Ошибка обработки ответа", "system")
		return
	
	var response_data = json.data
	
	# Извлекаем ответ AI (структура Gemini отличается от OpenAI)
	if response_data.has("candidates") and response_data.candidates.size() > 0:
		var candidate = response_data.candidates[0]
		if candidate.has("content") and candidate.content.has("parts") and candidate.content.parts.size() > 0:
			var ai_response = candidate.content.parts[0].text
			process_ai_response(ai_response)
		else:
			print("Неожиданная структура ответа AI")
			add_message_to_chat("Система", "Неожиданная структура ответа AI", "system")
	else:
		print("Пустой ответ от AI")
		add_message_to_chat("Система", "Пустой ответ от AI", "system")

func process_ai_response(ai_response: String):
	# Сбрасываем флаг выполнения запроса
	is_requesting = false
	
	# Извлекаем INI команды из ответа AI
	var ini_commands = extract_ini_commands(ai_response)
	
	# Убираем INI команды из текстового ответа для пользователя
	var text_response = remove_ini_commands_from_text(ai_response)
	
	# Добавляем ответ AI в чат
	add_message_to_chat("Gemini", text_response, "ai")
	
	# Если есть команды, выполняем их
	if ini_commands != "":
		# Показываем извлеченные команды в отладочном поле
		show_extracted_commands(ini_commands)
		
		# Выполняем команды
		print("Выполняю команды из ответа AI...")
		execute_ini_command(ini_commands)
		print("Команды AI выполнены!")

func remove_ini_commands_from_text(text: String) -> String:
	# Удаляем все блоки команд между =[command]= и =[end]=
	var lines = text.split("\n")
	var result_lines = []
	var in_command = false
	
	for line in lines:
		if line.strip_edges() == "=[command]=":
			in_command = true
		elif line.strip_edges() == "=[end]=":
			in_command = false
		elif not in_command:
			result_lines.append(line)
	
	return "\n".join(result_lines)

func show_api_key_dialog():
	# Показываем сообщение пользователю
	print("Для использования AI чата необходимо настроить API ключ Google Gemini.")
	print("Введите API ключ в поле выше и нажмите 'Сохранить ключ'.")
	
	# Добавляем сообщение в чат
	add_message_to_chat("Система", "Для использования AI чата необходимо настроить API ключ Google Gemini. Введите ключ в поле выше и нажмите 'Сохранить ключ'.", "system")

func save_api_key():
	# Сохраняем API ключ в настройках проекта
	var config = ConfigFile.new()
	config.set_value("smart_replace", "gemini_api_key", gemini_api_key)
	config.save("res://smart_replace_config.ini")

func load_api_key():
	# Загружаем API ключ из настроек
	var config = ConfigFile.new()
	var error = config.load("res://smart_replace_config.ini")
	if error == OK:
		gemini_api_key = config.get_value("smart_replace", "gemini_api_key", "")
	else:
		# Если файл не существует, оставляем пустую строку
		gemini_api_key = ""

# Функция для тестирования соединения
func test_connection():
	print("Тестируем соединение с Google...")
	var http = HTTPRequest.new()
	http.timeout = 10
	add_child(http)
	
	var error = http.request("https://www.google.com", [], HTTPClient.METHOD_GET)
	if error != OK:
		print("Ошибка соединения с Google: ", error)
	else:
		print("Соединение с Google успешно")
	
	http.request_completed.connect(func(result, response_code, headers, body):
		print("Тест соединения завершен: код ", response_code)
		http.queue_free()
	)

func show_extracted_commands(ini_commands: String):
	# Используем сохраненную ссылку на диалог
	if not current_dialog:
		print("Текущий диалог не найден в show_extracted_commands!")
		return
	
	var vbox = current_dialog.get_child(0)
	if not vbox or vbox.get_child_count() == 0:
		print("VBoxContainer не найден в show_extracted_commands!")
		return
	
	var tab_container = vbox.get_child(0)
	if not tab_container or tab_container.get_child_count() < 3:
		print("TabContainer не найден в show_extracted_commands!")
		return
	
	var ai_tab = tab_container.get_child(2)  # AI Чат вкладка
	if not ai_tab:
		print("AI вкладка не найдена в show_extracted_commands!")
		return
	
	# Получаем элементы через метаданные
	var extracted_edit = ai_tab.get_meta("extracted_edit")
	if not extracted_edit:
		print("extracted_edit не найден в метаданных!")
		return
	
	extracted_edit.text = ini_commands
	print("INI команды извлечены и показаны в отладочном поле")

func extract_ini_commands(ai_response: String) -> String:
	# Ищем блоки команд между =[command]= и =[end]=
	var commands = []
	var lines = ai_response.split("\n")
	var in_command = false
	var current_command = []
	
	for line in lines:
		if line.strip_edges() == "=[command]=":
			in_command = true
			current_command = [line]
		elif line.strip_edges() == "=[end]=":
			if in_command:
				current_command.append(line)
				commands.append("\n".join(current_command))
				in_command = false
		elif in_command:
			current_command.append(line)
	
	return "\n\n".join(commands)

	
