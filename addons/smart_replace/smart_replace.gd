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
	show_smart_replace_dialog()

func show_smart_replace_dialog():
	var dialog = AcceptDialog.new()
	dialog.title = "Умная замена/добавление функций"
	dialog.size = Vector2(1000, 800)
	
	# Создаем контейнер
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	# Создаем список функций
	var function_label = Label.new()
	function_label.text = "Выберите функцию для замены или выберите 'Добавить новую функцию':"
	vbox.add_child(function_label)
	
	var function_list = ItemList.new()
	function_list.custom_minimum_size = Vector2(980, 200)
	vbox.add_child(function_list)
	
	# Загружаем список функций из текущего файла
	load_functions_list(function_list)
	var add_new_index = function_list.add_item("➕ Добавить новую функцию")
	function_list.set_item_metadata(add_new_index, {"is_new": true})
	
	# Поля для новой функции
	var new_func_name_label = Label.new()
	new_func_name_label.text = "Имя новой функции (например: my_func):"
	vbox.add_child(new_func_name_label)
	var new_func_name_edit = LineEdit.new()
	new_func_name_edit.placeholder_text = "my_func"
	vbox.add_child(new_func_name_edit)
	new_func_name_label.visible = false
	new_func_name_edit.visible = false
	
	var new_func_args_label = Label.new()
	new_func_args_label.text = "Параметры (например: a, b):"
	vbox.add_child(new_func_args_label)
	var new_func_args_edit = LineEdit.new()
	new_func_args_edit.placeholder_text = "a, b"
	vbox.add_child(new_func_args_edit)
	new_func_args_label.visible = false
	new_func_args_edit.visible = false
	
	# Поле для кода
	var new_code_label = Label.new()
	new_code_label.text = "Код функции (только содержимое):"
	vbox.add_child(new_code_label)
	var new_code_edit = TextEdit.new()
	new_code_edit.placeholder_text = "Вставьте только код внутри функции (без func и отступов)"
	new_code_edit.custom_minimum_size = Vector2(980, 200)
	vbox.add_child(new_code_edit)
	
	# Переключение видимости полей для новой функции
	function_list.item_selected.connect(func(idx):
		var is_new = function_list.get_item_metadata(idx).has("is_new")
		new_func_name_label.visible = is_new
		new_func_name_edit.visible = is_new
		new_func_args_label.visible = is_new
		new_func_args_edit.visible = is_new
	)
	
	# Кнопки
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)
	var replace_button = Button.new()
	replace_button.text = "Выполнить"
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
	hbox.add_child(replace_button)
	var cancel_button = Button.new()
	cancel_button.text = "Отмена"
	cancel_button.pressed.connect(func(): dialog.hide())
	hbox.add_child(cancel_button)
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
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			var file_path = current_script.resource_path
			var success = replace_function_content(file_path, function_data, new_code)
			
			if success:
				print("Функция успешно заменена!")
			else:
				print("Ошибка при замене функции!")

func replace_function_content(file_path: String, function_data: Dictionary, new_code: String) -> bool:
	# Читаем файл
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# Заменяем содержимое функции
	var new_content = replace_function_content_in_text(content, function_data, new_code)
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
	var lines = content.split("\n")
	var result_lines = []
	var i = 0
	
	while i < lines.size():
		if i == function_data.start_index:
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
			
			# Пропускаем старое содержимое функции
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
			var func_header = "func " + name.strip_edges() + "(" + args.strip_edges() + "):" if args.strip_edges() != "" else "func " + name.strip_edges() + ":"
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