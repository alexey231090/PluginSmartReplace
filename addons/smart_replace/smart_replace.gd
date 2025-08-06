@tool
extends EditorPlugin

# ===== API НАСТРОЙКИ =====
const GEMINI_API_BASE_URL = "https://generativelanguage.googleapis.com/v1/models/"
const OPENROUTER_API_BASE_URL = "https://openrouter.ai/api/v1/chat/completions"

var gemini_api_key: String = ""  # Будет загружаться из настроек
var openrouter_api_key: String = ""  # Будет загружаться из настроек

# Выбор провайдера AI
var current_provider: String = "gemini"  # "gemini" или "openrouter"

# Доступные модели Gemini (бесплатные)
var available_models = {
	"gemini-1.5-flash": {
		"name": "🚀 Gemini Flash",
		"description": "Быстрая модель для быстрых ответов (бесплатно)",
		"max_tokens": 2000,
		"daily_limit": 50,
		"provider": "gemini"
	}
}

# Доступные модели OpenRouter (бесплатные)
var openrouter_models = {
	"openai/gpt-4o-mini": {
		"name": "🤖 GPT-4o Mini",
		"description": "Быстрая и эффективная модель OpenAI (бесплатно)",
		"max_tokens": 4000,
		"daily_limit": 500,
		"provider": "openrouter"
	},
	"deepseek/deepseek-r1:free": {
		"name": "💻 DeepSeek R1",
		"description": "Мощная модель для программирования и логики (бесплатно)",
		"max_tokens": 8000,
		"daily_limit": 1000,
		"provider": "openrouter"
	},
	"meta-llama/llama-3.1-8b-instruct": {
		"name": "🦙 Llama 3.1 8B",
		"description": "Легкая и быстрая модель Meta (бесплатно)",
		"max_tokens": 3000,
		"daily_limit": 1000,
		"provider": "openrouter"
	}
}

# Текущая выбранная модель
var current_model: String = "openai/gpt-4o-mini"  # По умолчанию используем OpenRouter (бесплатная модель)
const CHAT_HISTORY_FILE = "res://chat_history.json"

# История чата для контекста
var chat_history = []

# Ссылка на текущий диалог
var current_dialog = null

# Массив для отслеживания всех открытых диалогов
var open_dialogs = []

# Глобальный список системных сообщений Godot
var system_messages = []

# Флаг для предотвращения множественных запросов
var is_requesting = false

# Счетчики запросов для каждой модели
var daily_requests_counts: Dictionary = {}
var daily_requests_file: String = "user://daily_requests.json"
var last_request_date: String = ""

# Текущие извлеченные команды для применения
var current_extracted_commands = ""

# История извлеченных команд
var extracted_commands_history = []
const EXTRACTED_COMMANDS_HISTORY_FILE = "res://extracted_commands_history.json"

# История выполненных команд для предотвращения дублирования
var executed_commands_history = []
const EXECUTED_COMMANDS_HISTORY_FILE = "res://executed_commands_history.json"

# Флаг для отслеживания первого сообщения в сессии
var is_first_message_in_session = true

# Информация о текущем скрипте для кэширования
var current_script_info = {"path": "", "filename": "", "node_path": "", "hierarchy": ""}

# ===== СИСТЕМА ЛОГИРОВАНИЯ ДЛЯ ДИАГНОСТИКИ =====
var debug_log_file: String = "user://smart_replace_debug.log"
var debug_log_enabled: bool = true

# Функция для записи в лог
func write_debug_log(message: String, level: String = "INFO"):
	if not debug_log_enabled:
		return
	
	var timestamp = Time.get_datetime_string_from_system()
	var log_entry = "[%s] [%s] %s" % [timestamp, level, message]
	
	var file = FileAccess.open(debug_log_file, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(log_entry)
		file.close()
	else:
		# Если не удалось открыть файл, создаем новый
		file = FileAccess.open(debug_log_file, FileAccess.WRITE)
		if file:
			file.store_line(log_entry)
			file.close()
	
	# Также выводим в консоль для отладки
	print(log_entry)

# Функция для очистки лога
func clear_debug_log():
	var file = FileAccess.open(debug_log_file, FileAccess.WRITE)
	if file:
		file.close()
		print("Лог очищен")

# Функция для получения содержимого лога
func get_debug_log() -> String:
	if not FileAccess.file_exists(debug_log_file):
		return "Лог файл не найден"
	
	var file = FileAccess.open(debug_log_file, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		return content
	return "Не удалось прочитать лог файл"

# ===== OPENROUTER API ФУНКЦИИ =====

# Функция для загрузки API ключа OpenRouter
func load_openrouter_api_key():
	var config_file = "user://smart_replace_config.ini"
	if FileAccess.file_exists(config_file):
		var file = FileAccess.open(config_file, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var lines = content.split("\n")
			for line in lines:
				if line.begins_with("openrouter_api_key="):
					openrouter_api_key = line.split("=", true, 1)[1].strip_edges()
					write_debug_log("OpenRouter API ключ загружен", "INFO")
					return
	write_debug_log("OpenRouter API ключ не найден", "WARNING")

# Функция для сохранения API ключа OpenRouter
func save_openrouter_api_key():
	var config_file = "user://smart_replace_config.ini"
	var content = ""
	
	# Читаем существующий файл
	if FileAccess.file_exists(config_file):
		var file = FileAccess.open(config_file, FileAccess.READ)
		if file:
			content = file.get_as_text()
			file.close()
	
	# Обновляем или добавляем OpenRouter ключ
	var lines = content.split("\n")
	var found = false
	for i in range(lines.size()):
		if lines[i].begins_with("openrouter_api_key="):
			lines[i] = "openrouter_api_key=" + openrouter_api_key
			found = true
			break
	
	if not found:
		lines.append("openrouter_api_key=" + openrouter_api_key)
	
	# Сохраняем файл
	var file = FileAccess.open(config_file, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()
		write_debug_log("OpenRouter API ключ сохранен", "INFO")

# Функция для получения текущей модели с учетом провайдера
func get_current_model_info() -> Dictionary:
	if current_provider == "gemini":
		return available_models.get(current_model, {})
	else:
		return openrouter_models.get(current_model, {})

# Функция для получения лимита запросов текущей модели
func get_current_model_limit() -> int:
	var model_info = get_current_model_info()
	return model_info.get("daily_limit", 50)

# Функция для показа диалога с логом
func show_debug_log_dialog():
	write_debug_log("Открываем диалог просмотра лога", "INFO")
	
	var log_dialog = AcceptDialog.new()
	log_dialog.title = "Лог плагина Smart Replace"
	log_dialog.size = Vector2(1000, 700)
	
	var vbox = VBoxContainer.new()
	log_dialog.add_child(vbox)
	
	var log_label = Label.new()
	log_label.text = "Лог плагина (для диагностики проблем):"
	log_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(log_label)
	
	var log_edit = TextEdit.new()
	log_edit.text = get_debug_log()
	log_edit.editable = false
	log_edit.custom_minimum_size = Vector2(980, 500)
	log_edit.add_theme_font_size_override("font_size", 12)
	vbox.add_child(log_edit)
	
	var buttons = HBoxContainer.new()
	vbox.add_child(buttons)
	
	var refresh_button = Button.new()
	refresh_button.text = "Обновить лог"
	refresh_button.custom_minimum_size = Vector2(150, 40)
	refresh_button.add_theme_font_size_override("font_size", 14)
	refresh_button.pressed.connect(func():
		log_edit.text = get_debug_log()
	)
	buttons.add_child(refresh_button)
	
	var clear_log_button = Button.new()
	clear_log_button.text = "Очистить лог"
	clear_log_button.custom_minimum_size = Vector2(150, 40)
	clear_log_button.add_theme_font_size_override("font_size", 14)
	clear_log_button.pressed.connect(func():
		clear_debug_log()
		log_edit.text = get_debug_log()
	)
	buttons.add_child(clear_log_button)
	
	var copy_log_button = Button.new()
	copy_log_button.text = "Копировать лог"
	copy_log_button.custom_minimum_size = Vector2(150, 40)
	copy_log_button.add_theme_font_size_override("font_size", 14)
	copy_log_button.pressed.connect(func():
		DisplayServer.clipboard_set(log_edit.text)
		print("Лог скопирован в буфер обмена")
	)
	buttons.add_child(copy_log_button)
	
	var close_button = Button.new()
	close_button.text = "Закрыть"
	close_button.custom_minimum_size = Vector2(100, 40)
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.pressed.connect(func(): log_dialog.hide())
	buttons.add_child(close_button)
	
	get_editor_interface().get_base_control().add_child(log_dialog)
	log_dialog.popup_centered()

# Функция для сохранения истории чата
func save_chat_history():
	# Проверяем, что узел в дереве
	if not is_inside_tree():
		print("Узел не в дереве, отменяем сохранение истории")
		return
	
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

# Функция для сохранения истории извлеченных команд
func save_extracted_commands_history():
	var file = FileAccess.open(EXTRACTED_COMMANDS_HISTORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(extracted_commands_history))
		file.close()

# Функция для загрузки истории извлеченных команд
func load_extracted_commands_history():
	if FileAccess.file_exists(EXTRACTED_COMMANDS_HISTORY_FILE):
		var file = FileAccess.open(EXTRACTED_COMMANDS_HISTORY_FILE, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			var parse_result = json.parse(content)
			if parse_result == OK:
				extracted_commands_history = json.data
			else:
				extracted_commands_history = []
		else:
			extracted_commands_history = []
	else:
		extracted_commands_history = []

# Функции для работы со счетчиками запросов
func save_daily_requests():
	var data = {
		"counts": daily_requests_counts,
		"date": last_request_date
	}
	var file = FileAccess.open(daily_requests_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func load_daily_requests():
	if FileAccess.file_exists(daily_requests_file):
		var file = FileAccess.open(daily_requests_file, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			var parse_result = json.parse(content)
			if parse_result == OK:
				daily_requests_counts = json.data.get("counts", {})
				last_request_date = json.data.get("date", "")
			else:
				daily_requests_counts = {}
				last_request_date = ""
		else:
			daily_requests_counts = {}
			last_request_date = ""
	else:
		daily_requests_counts = {}
		last_request_date = ""

func check_and_update_daily_requests():
	var current_date = Time.get_datetime_string_from_system().split("T")[0]  # Получаем только дату
	
	if last_request_date != current_date:
		# Новый день, сбрасываем все счетчики
		daily_requests_counts.clear()
		last_request_date = current_date
		save_daily_requests()
		print("Счетчики запросов сброшены для нового дня: ", current_date)
	
	# Инициализируем счетчик для текущей модели если его нет
	if not daily_requests_counts.has(current_model):
		daily_requests_counts[current_model] = 0
	
	return daily_requests_counts.get(current_model, 0)

func increment_daily_requests():
	if not daily_requests_counts.has(current_model):
		daily_requests_counts[current_model] = 0
	
	daily_requests_counts[current_model] += 1
	save_daily_requests()
	
	var current_count = daily_requests_counts[current_model]
	var model_info = get_current_model_info()
	var model_limit = model_info.get("daily_limit", 50)
	
	print("Запросов сегодня для ", current_model, ": ", current_count, "/", model_limit)
	
	# Обновляем счетчик в интерфейсе
	update_requests_counter()
	
	# Предупреждение при приближении к лимиту
	if current_count >= model_limit * 0.9:  # 90% от лимита
		print("⚠️ ВНИМАНИЕ: Приближаетесь к лимиту запросов для ", current_model, "! (", current_count, "/", model_limit, ")")
	
	if current_count >= model_limit:
		print("🚫 ДОСТИГНУТ ЛИМИТ ЗАПРОСОВ для ", current_model, "! (", current_count, "/", model_limit, ")")

func update_requests_counter():
	if current_dialog:
		var vbox = current_dialog.get_child(0)
		if vbox and vbox.get_child_count() > 0:
			var tab_container = vbox.get_child(0)
			if tab_container and tab_container.get_child_count() > 0:
				var ai_tab = tab_container.get_child(0)
				if ai_tab:
					var requests_label = ai_tab.get_meta("requests_label")
					if requests_label:
						var current_count = daily_requests_counts.get(current_model, 0)
						var model_info = get_current_model_info()
						var model_limit = model_info.get("daily_limit", 50)
						var model_name = model_info.get("name", current_model)
						
						requests_label.text = model_name + ": " + str(current_count) + "/" + str(model_limit)
						
						# Меняем цвет при приближении к лимиту
						if current_count >= model_limit * 0.9:  # 90% от лимита
							requests_label.modulate = Color.YELLOW
						elif current_count >= model_limit:
							requests_label.modulate = Color.RED
						else:
							requests_label.modulate = Color.WHITE

# Функция для обновления интерфейса API ключей
func update_api_key_interface():
	if current_dialog:
		var vbox = current_dialog.get_child(0)
		if vbox and vbox.get_child_count() > 0:
			var tab_container = vbox.get_child(0)
			if tab_container and tab_container.get_child_count() > 0:
				var ai_tab = tab_container.get_child(0)
				if ai_tab:
					# Обновляем видимость контейнеров API ключей
					var gemini_container = ai_tab.get_meta("gemini_api_container")
					var openrouter_container = ai_tab.get_meta("openrouter_api_container")
					
					if gemini_container:
						gemini_container.visible = current_provider == "gemini"
					if openrouter_container:
						openrouter_container.visible = current_provider == "openrouter"
					
					# Обновляем список моделей
					var update_model_list = ai_tab.get_meta("update_model_list")
					if update_model_list:
						update_model_list.call()
					
					# Обновляем счетчик запросов
					update_requests_counter()

# Функция для добавления команды в историю
func add_to_extracted_commands_history(commands: String, timestamp: String = ""):
	if commands.strip_edges() == "":
		print("Попытка добавить пустые команды в историю")
		return
	
	if timestamp == "":
		timestamp = Time.get_datetime_string_from_system()
	
	var entry = {
		"timestamp": timestamp,
		"commands": commands
	}
	
	print("Добавляем в историю команд: '", commands, "'")
	extracted_commands_history.append(entry)
	print("Размер истории команд: ", extracted_commands_history.size())
	save_extracted_commands_history()
	print("История команд сохранена")

# Функция для обновления цвета кнопки "Применить"
func update_apply_button_color(button: Button):
	if current_extracted_commands.strip_edges() != "":
		# Зеленый цвет для кнопки, если есть команды для применения
		button.modulate = Color(0.2, 0.8, 0.2)  # Зеленый
	else:
		# Обычный цвет, если нет команд
		button.modulate = Color(1, 1, 1)  # Белый (обычный)

# Функция для обновления списка истории команд
func refresh_history_list(history_list: ItemList):
	history_list.clear()
	
	# Добавляем команды в обратном порядке (новые сверху)
	for i in range(extracted_commands_history.size() - 1, -1, -1):
		var entry = extracted_commands_history[i]
		var display_text = entry.timestamp + " - " + entry.commands.substr(0, 100)
		if entry.commands.length() > 100:
			display_text += "..."
		history_list.add_item(display_text)

# Функция для обновления списка истории команд (для новой вкладки)
func refresh_commands_history_list(commands_history_list: ItemList):
	commands_history_list.clear()
	
	# Добавляем команды в обратном порядке (новые сверху)
	for i in range(extracted_commands_history.size() - 1, -1, -1):
		var entry = extracted_commands_history[i]
		var display_text = entry.timestamp + " - " + entry.commands.substr(0, 100)
		if entry.commands.length() > 100:
			display_text += "..."
		commands_history_list.add_item(display_text)

var smart_replace_button: Button

func _enter_tree():
	write_debug_log("Плагин Smart Replace инициализируется", "INFO")
	
	# Загружаем API ключи
	write_debug_log("Загружаем API ключи", "INFO")
	load_api_key()
	load_openrouter_api_key()
	
	# Загружаем историю чата
	write_debug_log("Загружаем историю чата", "INFO")
	load_chat_history()
	
	# Загружаем историю извлеченных команд
	write_debug_log("Загружаем историю извлеченных команд", "INFO")
	load_extracted_commands_history()
	
	# Загружаем историю выполненных команд
	write_debug_log("Загружаем историю выполненных команд", "INFO")
	load_executed_commands_history()
	
	# Загружаем счетчик запросов
	write_debug_log("Загружаем счетчик запросов", "INFO")
	load_daily_requests()
	check_and_update_daily_requests()
	
	# Инициализируем информацию о текущем скрипте
	write_debug_log("Инициализируем информацию о текущем скрипте", "INFO")
	current_script_info = get_current_script_info()
	
	# Тестируем соединение
	write_debug_log("Тестируем соединение", "INFO")
	test_connection()
	
	# Создаем кнопку в панели инструментов
	write_debug_log("Создаем кнопку в панели инструментов", "INFO")
	add_control_to_container(CONTAINER_TOOLBAR, create_toolbar_button())
	
	write_debug_log("Плагин Smart Replace успешно инициализирован", "INFO")

func _exit_tree():
	write_debug_log("Плагин Smart Replace завершает работу", "INFO")
	
	# Закрываем все диалоги перед выходом
	write_debug_log("Закрываем все диалоги", "INFO")
	close_all_dialogs()
	
	# Удаляем кнопку из панели инструментов
	write_debug_log("Удаляем кнопку из панели инструментов", "INFO")
	remove_control_from_container(CONTAINER_TOOLBAR, smart_replace_button)
	
	write_debug_log("Плагин Smart Replace успешно завершил работу", "INFO")

func create_toolbar_button() -> Button:
	smart_replace_button = Button.new()
	smart_replace_button.text = "Smart Replace"
	smart_replace_button.tooltip_text = "Умная замена функций"
	smart_replace_button.custom_minimum_size = Vector2(150, 30)  # Увеличиваем размер кнопки для мобильного
	smart_replace_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	smart_replace_button.pressed.connect(_on_smart_replace_pressed)
	return smart_replace_button

func _on_smart_replace_pressed():
	write_debug_log("Нажата кнопка Smart Replace", "INFO")
	
	# Проверяем, не открыт ли уже диалог
	if current_dialog and is_instance_valid(current_dialog) and current_dialog.visible:
		write_debug_log("Диалог уже открыт, фокусируемся на нем", "INFO")
		print("Диалог уже открыт, фокусируемся на нем")
		current_dialog.grab_focus()
		return
	
	# Закрываем все другие диалоги перед открытием нового
	write_debug_log("Закрываем все другие диалоги", "INFO")
	close_all_dialogs()
	
	write_debug_log("Открываем диалог Smart Replace", "INFO")
	show_smart_replace_dialog_v2()

# ===== INI ПАРСЕР ФУНКЦИИ =====

func execute_ini_command(ini_text: String):
	if ini_text.strip_edges() == "":
		print("Команды не могут быть пустыми!")
		return
	
	# Выполняем новые команды
	print("Выполняем команды...")
	execute_new_commands_directly(ini_text)
	
	# Добавляем команды в историю выполненных ПОСЛЕ выполнения
	print("=== ДОБАВЛЕНИЕ В ИСТОРИЮ ===")
	print("Исходный текст: '", ini_text, "'")
	var commands_list = ini_text.split("\n")
	for cmd in commands_list:
		cmd = cmd.strip_edges()
		if cmd != "" and (cmd.begins_with("[++") or cmd.begins_with("[--") or cmd.begins_with("[-+")):
			if cmd not in executed_commands_history:
				executed_commands_history.append(cmd)
				print("Добавлена в историю выполненных: '", cmd, "'")
	
	# Сохраняем историю выполненных команд
	save_executed_commands_history()
	
	# Добавляем в историю команд
	print("Вызываем add_to_extracted_commands_history с: '", ini_text, "'")
	add_to_extracted_commands_history(ini_text)
	print("Команды добавлены в историю!")

func execute_new_commands_directly(commands_text: String):
	print("=== ОТЛАДКА: Начинаем выполнение команд ===")
	print("Команды: ", commands_text)
	
	# Получаем текущий открытый файл
	var editor_interface = get_editor_interface()
	if not editor_interface:
		print("ОШИБКА: Не удалось получить интерфейс редактора!")
		return
	
	var script_editor = editor_interface.get_script_editor()
	if not script_editor:
		print("ОШИБКА: Не удалось получить редактор скриптов!")
		return
	
	var current_script = script_editor.get_current_script()
	if not current_script:
		print("ОШИБКА: Нет открытого скрипта!")
		return
	
	print("Файл: ", current_script.resource_path)
	
	# Получаем текущий код
	var current_code = current_script.source_code
	print("Текущий код (длина): ", current_code.length())
	
	# Извлекаем команды из текста (для вкладки "Команды")
	var extracted_commands = extract_new_commands(commands_text)
	print("Извлеченные команды: '", extracted_commands, "'")
	
	# Выполняем новые команды
	var new_code = execute_new_commands(extracted_commands, current_code)
	print("Новый код (длина): ", new_code.length())
	
	# Применяем изменения
	if new_code != current_code:
		print("Код изменился, применяем...")
		# Применяем изменения напрямую
		current_script.source_code = new_code
		
		# Принудительно обновляем редактор
		# Сохраняем файл на диск, чтобы Godot обновил его
		print("🔄 Сохраняем файл на диск...")
		var file = FileAccess.open(current_script.resource_path, FileAccess.WRITE)
		if file:
			file.store_string(new_code)
			file.close()
			print("💾 Файл сохранен на диск")
		else:
			print("❌ Ошибка сохранения файла")
		
		print("✅ Новые команды применены успешно!")
		print("📝 Файл обновлен в редакторе")
		print("💡 Если изменения не видны, попробуйте переключиться на другую вкладку и обратно")
	else:
		print("❌ Код не изменился после выполнения команд")

func generate_preview_for_new_commands(old_code: String, new_code: String) -> String:
	var preview = "=== ПРЕДВАРИТЕЛЬНЫЙ ПРОСМОТР КОМАНД ===\n\n"
	
	# Парсим команды из текста (предполагаем, что команды переданы в old_code как исходные команды)
	var commands = old_code.split("\n")
	var valid_commands = []
	
	for command in commands:
		command = command.strip_edges()
		if command != "" and (command.begins_with("[++") or command.begins_with("[--") or command.begins_with("[-+")):
			valid_commands.append(command)
	
	if valid_commands.size() == 0:
		preview += "Команды не найдены.\n"
	else:
		preview += "Найдено команд: %d\n\n" % valid_commands.size()
		
		for command in valid_commands:
			var parsed = parse_new_command(command)
			if parsed.has("type") and parsed.has("line"):
				preview += "Команда: %s\n" % command
				preview += "  Действие: "
				
				match parsed.type:
					"insert":
						preview += "Добавить код в строку %d\n" % parsed.line
						preview += "  Код: %s\n" % parsed.code
					"insert_by_element":
						if parsed.direction == "end":
							preview += "Добавить код в конец файла\n"
						elif parsed.direction != "":
							if parsed.target_function != "":
								preview += "Добавить код %s функции '%s'\n" % [parsed.direction, parsed.target_function]
							else:
								if parsed.direction == "up":
									preview += "Добавить код выше первой функции\n"
								else:
									preview += "Добавить код в конец файла\n"
						elif parsed.element_name != "":
							if parsed.indent_level > 0:
								preview += "Добавить код в %s '%s' на уровень %d\n" % [parsed.element_type, parsed.element_name, parsed.indent_level]
							else:
								preview += "Добавить код в %s '%s' на 0 уровень\n" % [parsed.element_type, parsed.element_name]
						elif parsed.element_position > 0:
							preview += "Добавить код выше %s-го элемента '%s'\n" % [parsed.element_position, parsed.element_type]
						else:
							preview += "Добавить код в конец файла\n"
						preview += "  Код: %s\n" % parsed.code
					"replace_deep":
						preview += "Заменить блок в строке %d\n" % parsed.line
						preview += "  Новый код: %s\n" % parsed.code
					"delete_and_insert":
						preview += "Заменить блок в строке %d (удалить блок + вставить новый код)\n" % parsed.line
						preview += "  Новый код: %s\n" % parsed.code
					"delete_and_insert_single":
						preview += "Заменить строку %d (удалить строку + вставить новый код)\n" % parsed.line
						preview += "  Новый код: %s\n" % parsed.code
					"insert_with_level":
						preview += "Вставить код в структуру '%s' выше строки %d\n" % [parsed.structure, parsed.line]
						preview += "  Код: %s\n" % parsed.code
					"delete_by_name":
						preview += "Удалить %s '%s'\n" % [parsed.element_type, parsed.element_name]
					"delete":
						preview += "Удалить строку %d\n" % parsed.line
					"delete_deep":
						preview += "Удалить блок в строке %d\n" % parsed.line
				
				preview += "\n"
	
	return preview

func show_preview_dialog(preview_text: String, callback: Callable):
	# Закрываем все существующие диалоги
	close_all_dialogs()
	
	var dialog = AcceptDialog.new()
	dialog.title = "Предварительный просмотр изменений"
	dialog.size = Vector2(800, 700)
	dialog.exclusive = false
	
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
		callback.call()
		dialog.hide()
	)
	buttons.add_child(apply_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Отмена"
	cancel_button.pressed.connect(func(): dialog.hide())
	buttons.add_child(cancel_button)
	
	# Добавляем диалог в массив открытых диалогов
	open_dialogs.append(dialog)
	
	# Добавляем обработчик горячих клавиш для диалога
	# Используем Input singleton для глобальных горячих клавиш
	# Горячие клавиши будут работать через кнопки в интерфейсе
	
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()

# Старые функции INI парсера удалены - теперь используется только новый парсер команд



# Старые функции обработки INI команд удалены - теперь используется только новый парсер

# Функция find_function_by_signature удалена - больше не нужна

# Функция find_function_by_name удалена - больше не нужна

func get_current_file_code() -> String:
	var editor_interface = get_editor_interface()
	if not editor_interface:
		return ""
	
	var script_editor = editor_interface.get_script_editor()
	if not script_editor:
		return ""
	
	var current_script = script_editor.get_current_script()
	if not current_script:
		return ""
	
	return current_script.source_code

func show_ini_preview(ini_text: String):
	if ini_text.strip_edges() == "":
		print("Команды не могут быть пустыми!")
		return
	
	# Показываем предварительный просмотр команд
	var preview = generate_preview_for_new_commands(ini_text, "")
	show_preview_dialog(preview, func():
		execute_new_commands_directly(ini_text)
	)

# Старые функции предварительного просмотра удалены - теперь используется новый парсер

# Дублирующаяся функция show_preview_dialog удалена - используется версия с callback

func close_all_dialogs():
	write_debug_log("Начинаем закрытие диалогов плагина", "INFO")
	
	# Закрываем только диалоги из нашего массива
	var our_dialog_count = 0
	for dialog in open_dialogs:
		if is_instance_valid(dialog):
			write_debug_log("Закрываем наш диалог: " + str(dialog), "INFO")
			dialog.hide()
			dialog.queue_free()
			our_dialog_count += 1
	
	write_debug_log("Закрыто наших диалогов: " + str(our_dialog_count), "INFO")
	
	# Очищаем массив открытых диалогов
	open_dialogs.clear()
	current_dialog = null
	
	write_debug_log("Диалоги плагина закрыты", "INFO")
	print("Диалоги плагина закрыты")

# Функция для принудительного закрытия всех диалогов (для отладки)
func force_close_all_dialogs():
	write_debug_log("Принудительное закрытие всех диалогов...", "WARNING")
	print("Принудительное закрытие всех диалогов...")
	close_all_dialogs()

# Функция для добавления системного сообщения
func add_system_message(message: String, type: String = "INFO"):
	var formatted_message = "%s: %s" % [type, message]
	system_messages.append(formatted_message)
	print("Добавлено системное сообщение: ", formatted_message)

# Функция для получения всех системных сообщений
func get_system_messages() -> Array:
	return system_messages.duplicate()

# Старые функции проверки отступов и предварительного просмотра удалены - больше не нужны

func show_smart_replace_dialog_v2():
	write_debug_log("Начинаем создание диалога Smart Replace", "INFO")
	
	# Проверяем, не открыт ли уже диалог
	if current_dialog and is_instance_valid(current_dialog) and current_dialog.visible:
		write_debug_log("Диалог уже открыт!", "WARNING")
		print("Диалог уже открыт!")
		current_dialog.grab_focus()
		return
	
	# Закрываем только наши предыдущие диалоги
	write_debug_log("Закрываем предыдущие диалоги плагина", "INFO")
	close_all_dialogs()
	
	write_debug_log("Создаем новый диалог", "INFO")
	var dialog = AcceptDialog.new()
	dialog.title = "Smart Replace - Умная замена функций"
	dialog.size = Vector2(1200, 900)  # Увеличиваем размер для мобильного использования
	dialog.exclusive = false  # Делаем диалог неэксклюзивным
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN  # Центрируем на главном окне
	write_debug_log("Диалог создан как неэксклюзивный", "INFO")
	
	# Сохраняем ссылку на диалог
	current_dialog = dialog
	open_dialogs.append(dialog)
	write_debug_log("Диалог добавлен в массив open_dialogs, размер: " + str(open_dialogs.size()), "INFO")
	
	# Добавляем обработчик закрытия диалога
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			write_debug_log("Диалог стал невидимым, очищаем ссылки", "INFO")
			current_dialog = null
			open_dialogs.erase(dialog)
			write_debug_log("Размер open_dialogs после удаления: " + str(open_dialogs.size()), "INFO")
	)
	
	# Создаем основной контейнер
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	# Создаем вкладки
	var tab_container = TabContainer.new()
	tab_container.custom_minimum_size = Vector2(1180, 800)  # Увеличиваем размер для мобильного использования
	vbox.add_child(tab_container)
	
	# ===== ВКЛАДКА 1: AI ЧАТ =====
	var ai_tab = VBoxContainer.new()
	tab_container.add_child(ai_tab)
	tab_container.set_tab_title(0, "AI Чат")
	
	# ===== КОЛОНКА ЧАТА (МОБИЛЬНАЯ ВЕРСИЯ) =====
	var chat_column = VBoxContainer.new()
	chat_column.custom_minimum_size = Vector2(1160, 500)  # Увеличиваем размер
	ai_tab.add_child(chat_column)
	
	# Заголовок для AI чата
	var ai_label = Label.new()
	ai_label.text = "AI Чат - общайтесь с Google Gemini и автоматически редактируйте код:"
	ai_label.add_theme_font_size_override("font_size", 16)  # Увеличиваем размер шрифта
	chat_column.add_child(ai_label)
	
	# ===== ПОЛЕ ВВОДА СООБЩЕНИЙ В ВЕРХНЕЙ ЧАСТИ =====
	var input_container = HBoxContainer.new()
	input_container.custom_minimum_size = Vector2(1140, 50)  # Увеличиваем высоту для мобильного использования
	chat_column.add_child(input_container)
	
	# Поле для ввода сообщения (больше для мобильного)
	var message_edit = LineEdit.new()
	message_edit.placeholder_text = "Введите ваше сообщение для AI..."
	message_edit.custom_minimum_size = Vector2(800, 40)  # Увеличиваем размер для мобильного
	message_edit.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	message_edit.text_submitted.connect(func(text):
		if text.strip_edges() != "" and not is_requesting:
			send_message_to_ai(text)
	)
	input_container.add_child(message_edit)
	
	# Кнопка отправки (больше для мобильного)
	var send_button = Button.new()
	send_button.text = "Отправить"
	send_button.custom_minimum_size = Vector2(120, 40)  # Увеличиваем размер кнопки
	send_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	send_button.pressed.connect(func():
		var message = message_edit.text
		if message.strip_edges() != "":
			# Отключаем кнопку на время запроса
			send_button.disabled = true
			send_button.text = "Отправляется..."
			send_message_to_ai(message)
			message_edit.text = ""
	)
	input_container.add_child(send_button)
	
	# Счетчик запросов (больше для мобильного)
	var requests_label = Label.new()
	var current_count = daily_requests_counts.get(current_model, 0)
	var model_info = get_current_model_info()
	var model_limit = model_info.get("daily_limit", 50)
	var model_name = model_info.get("name", current_model)
	requests_label.text = model_name + ": " + str(current_count) + "/" + str(model_limit)
	requests_label.tooltip_text = "Счетчик запросов к " + ("Google Gemini API" if current_provider == "gemini" else "OpenRouter API")
	requests_label.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	requests_label.custom_minimum_size = Vector2(200, 40)  # Увеличиваем размер
	input_container.add_child(requests_label)
	
	# Область чата
	var chat_area = VBoxContainer.new()
	chat_area.custom_minimum_size = Vector2(1140, 400)  # Увеличиваем размер
	chat_column.add_child(chat_area)
	
	# Поле для отображения истории чата (больше для мобильного)
	var chat_history_edit = RichTextLabel.new()
	chat_history_edit.custom_minimum_size = Vector2(1140, 350)  # Увеличиваем размер
	chat_history_edit.bbcode_enabled = true
	chat_history_edit.scroll_following = true
	chat_history_edit.selection_enabled = true  # Включаем выделение текста
	chat_history_edit.context_menu_enabled = true  # Включаем контекстное меню
	chat_history_edit.shortcut_keys_enabled = true  # Включаем горячие клавиши (Ctrl+C, Ctrl+A)
	chat_area.add_child(chat_history_edit)
	
	# Загружаем историю чата в интерфейс
	load_chat_to_ui(chat_history_edit)
	
	# Кнопки для работы с текстом чата
	var chat_buttons_container = HBoxContainer.new()
	chat_buttons_container.custom_minimum_size = Vector2(1140, 40)
	chat_area.add_child(chat_buttons_container)
	
	var copy_selected_button = Button.new()
	copy_selected_button.text = "Копировать выделенное"
	copy_selected_button.custom_minimum_size = Vector2(200, 35)
	copy_selected_button.add_theme_font_size_override("font_size", 12)
	copy_selected_button.pressed.connect(func():
		var selected_text = chat_history_edit.get_selected_text()
		if selected_text != "":
			DisplayServer.clipboard_set(selected_text)
			print("Выделенный текст скопирован в буфер обмена")
		else:
			print("Нет выделенного текста")
	)
	chat_buttons_container.add_child(copy_selected_button)
	
	var copy_all_button = Button.new()
	copy_all_button.text = "Копировать весь чат"
	copy_all_button.custom_minimum_size = Vector2(200, 35)
	copy_all_button.add_theme_font_size_override("font_size", 12)
	copy_all_button.pressed.connect(func():
		var all_text = chat_history_edit.get_text()
		DisplayServer.clipboard_set(all_text)
		print("Весь текст чата скопирован в буфер обмена")
	)
	chat_buttons_container.add_child(copy_all_button)
	
	var clear_chat_button = Button.new()
	clear_chat_button.text = "Очистить чат"
	clear_chat_button.custom_minimum_size = Vector2(150, 35)
	clear_chat_button.add_theme_font_size_override("font_size", 12)
	clear_chat_button.pressed.connect(func():
		chat_history.clear()
		chat_history_edit.clear()
		print("Чат очищен")
	)
	chat_buttons_container.add_child(clear_chat_button)
	
	# Счетчик запросов уже добавлен выше в input_container
	

	

	
	# ===== ВЫБОР ПРОВАЙДЕРА =====
	var provider_container = HBoxContainer.new()
	provider_container.custom_minimum_size = Vector2(1140, 50)  # Увеличиваем высоту
	ai_tab.add_child(provider_container)
	
	var provider_label = Label.new()
	provider_label.text = "Провайдер AI:"
	provider_label.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	provider_container.add_child(provider_label)
	
	var provider_option = OptionButton.new()
	provider_option.custom_minimum_size = Vector2(300, 40)  # Увеличиваем размер для мобильного
	provider_option.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	
	# Добавляем провайдеры
	provider_option.add_item("Google Gemini")
	provider_option.add_item("OpenRouter.ai")
	
	# Устанавливаем текущий провайдер
	provider_option.selected = 0 if current_provider == "gemini" else 1
	
	provider_option.item_selected.connect(func(index):
		var new_provider = "gemini" if index == 0 else "openrouter"
		if new_provider != current_provider:
			current_provider = new_provider
			print("Переключен провайдер на: ", current_provider)
			save_api_key()  # Сохраняем выбор провайдера
			update_requests_counter()  # Обновляем счетчик для нового провайдера
			update_api_key_interface()  # Обновляем интерфейс API ключей
	)
	provider_container.add_child(provider_option)
	
	# ===== API КЛЮЧИ =====
	# Контейнер для Gemini API ключа
	var gemini_api_container = HBoxContainer.new()
	gemini_api_container.custom_minimum_size = Vector2(1140, 50)  # Увеличиваем высоту
	gemini_api_container.visible = current_provider == "gemini"
	ai_tab.add_child(gemini_api_container)
	
	var gemini_api_label = Label.new()
	gemini_api_label.text = "API ключ Google Gemini:"
	gemini_api_label.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	gemini_api_container.add_child(gemini_api_label)
	
	var gemini_api_edit = LineEdit.new()
	gemini_api_edit.placeholder_text = "AIza... (введите ваш Google Gemini API ключ)"
	gemini_api_edit.secret = true
	gemini_api_edit.custom_minimum_size = Vector2(600, 40)  # Увеличиваем размер для мобильного
	gemini_api_edit.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	gemini_api_edit.text = gemini_api_key if gemini_api_key != null else ""  # Показываем текущий ключ
	gemini_api_container.add_child(gemini_api_edit)
	
	var save_gemini_button = Button.new()
	save_gemini_button.text = "Сохранить ключ"
	save_gemini_button.custom_minimum_size = Vector2(150, 40)  # Увеличиваем размер кнопки
	save_gemini_button.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	save_gemini_button.pressed.connect(func():
		gemini_api_key = gemini_api_edit.text
		save_api_key()
		print("Gemini API ключ сохранен!")
	)
	gemini_api_container.add_child(save_gemini_button)
	
	# Контейнер для OpenRouter API ключа
	var openrouter_api_container = HBoxContainer.new()
	openrouter_api_container.custom_minimum_size = Vector2(1140, 50)  # Увеличиваем высоту
	openrouter_api_container.visible = current_provider == "openrouter"
	ai_tab.add_child(openrouter_api_container)
	
	var openrouter_api_label = Label.new()
	openrouter_api_label.text = "API ключ OpenRouter:"
	openrouter_api_label.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	openrouter_api_container.add_child(openrouter_api_label)
	
	var openrouter_api_edit = LineEdit.new()
	openrouter_api_edit.placeholder_text = "sk-or-v1-... (введите ваш OpenRouter API ключ)"
	openrouter_api_edit.secret = true
	openrouter_api_edit.custom_minimum_size = Vector2(600, 40)  # Увеличиваем размер для мобильного
	openrouter_api_edit.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	openrouter_api_edit.text = openrouter_api_key if openrouter_api_key != null else ""  # Показываем текущий ключ
	openrouter_api_container.add_child(openrouter_api_edit)
	
	var save_openrouter_button = Button.new()
	save_openrouter_button.text = "Сохранить ключ"
	save_openrouter_button.custom_minimum_size = Vector2(150, 40)  # Увеличиваем размер кнопки
	save_openrouter_button.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	save_openrouter_button.pressed.connect(func():
		openrouter_api_key = openrouter_api_edit.text
		save_openrouter_api_key()
		print("OpenRouter API ключ сохранен!")
	)
	openrouter_api_container.add_child(save_openrouter_button)
	
	# Сохраняем ссылки на контейнеры API для обновления видимости
	ai_tab.set_meta("gemini_api_container", gemini_api_container)
	ai_tab.set_meta("openrouter_api_container", openrouter_api_container)
	ai_tab.set_meta("provider_option", provider_option)
	
	# Селектор модели (мобильная версия)
	var model_container = HBoxContainer.new()
	model_container.custom_minimum_size = Vector2(1140, 50)  # Увеличиваем высоту
	ai_tab.add_child(model_container)
	
	var model_label = Label.new()
	model_label.text = "Модель:"
	model_label.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	model_container.add_child(model_label)
	
	var model_option = OptionButton.new()
	model_option.custom_minimum_size = Vector2(400, 40)  # Увеличиваем размер для мобильного
	model_option.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	
	# Функция для обновления списка моделей
	var update_model_list = func():
		model_option.clear()
		var models_to_show = available_models if current_provider == "gemini" else openrouter_models
		
		for model_id in models_to_show.keys():
			var model_data = models_to_show[model_id]
			var display_text = model_data.get("name", model_id) + " - " + model_data.get("description", "")
			model_option.add_item(display_text)
			model_option.set_item_metadata(model_option.get_item_count() - 1, model_id)
		
		# Устанавливаем текущую модель
		for i in range(model_option.get_item_count()):
			if model_option.get_item_metadata(i) == current_model:
				model_option.selected = i
				break
	
	# Инициализируем список моделей
	update_model_list.call()
	
	model_option.item_selected.connect(func(index):
		var selected_model = model_option.get_item_metadata(index)
		if selected_model != current_model:
			current_model = selected_model
			print("Переключена модель на: ", current_model)
			save_api_key()  # Сохраняем выбор модели
			update_requests_counter()  # Обновляем счетчик для новой модели
	)
	model_container.add_child(model_option)
	
	# Сохраняем ссылки для обновления
	ai_tab.set_meta("model_option", model_option)
	ai_tab.set_meta("update_model_list", update_model_list)
	
	# Кнопки управления (мобильная версия)
	var control_buttons = HBoxContainer.new()
	control_buttons.custom_minimum_size = Vector2(1140, 60)  # Увеличиваем высоту для мобильного
	ai_tab.add_child(control_buttons)
	
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
	
	# Кнопка применения команд (мобильная версия)
	var apply_commands_button = Button.new()
	apply_commands_button.text = "Применить команды"
	apply_commands_button.custom_minimum_size = Vector2(180, 50)  # Увеличиваем размер кнопки
	apply_commands_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	apply_commands_button.pressed.connect(func():
		if current_extracted_commands.strip_edges() != "":
			execute_ini_command(current_extracted_commands)
			
			# Сохраняем команды в историю выполненных ПОСЛЕ выполнения
			var commands_list = current_extracted_commands.split("\n")
			for cmd in commands_list:
				cmd = cmd.strip_edges()
				if cmd != "" and cmd not in executed_commands_history:
					executed_commands_history.append(cmd)
					print("Добавлена в историю выполненных: '", cmd, "'")
			
			# Сохраняем историю выполненных команд
			save_executed_commands_history()
			
			add_to_extracted_commands_history(current_extracted_commands)
			current_extracted_commands = ""
			update_apply_button_color(apply_commands_button)
			extracted_commands_edit.text = ""
			print("Команды применены и добавлены в историю!")
		else:
			print("Нет команд для применения!")
	)
	control_buttons.add_child(apply_commands_button)
	
	# Кнопка для показа/скрытия команд (для отладки) - мобильная версия
	var show_commands_button = Button.new()
	show_commands_button.text = "Показать извлеченные команды"
	show_commands_button.custom_minimum_size = Vector2(200, 50)  # Увеличиваем размер кнопки
	show_commands_button.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	show_commands_button.pressed.connect(func():
		var is_visible = extracted_commands_label.visible
		extracted_commands_label.visible = !is_visible
		extracted_commands_edit.visible = !is_visible
		show_commands_button.text = "Скрыть извлеченные команды" if !is_visible else "Показать извлеченные команды"
	)
	control_buttons.add_child(show_commands_button)
	
	# Кнопка очистки чата (мобильная версия)
	var clear_chat_control_button = Button.new()
	clear_chat_control_button.text = "Очистить чат"
	clear_chat_control_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	clear_chat_control_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	clear_chat_control_button.pressed.connect(func():
		chat_history.clear()
		chat_history_edit.text = ""
		save_chat_history()  # Сохраняем пустую историю
		is_first_message_in_session = true  # Сбрасываем флаг для новой сессии
		
		# Очищаем извлеченные команды и обновляем цвет кнопки
		current_extracted_commands = ""
		extracted_commands_edit.text = ""
		update_apply_button_color(apply_commands_button)
		
		# Очищаем историю выполненных команд
		executed_commands_history.clear()
		save_executed_commands_history()
		print("История выполненных команд очищена")
	)
	control_buttons.add_child(clear_chat_control_button)
	
	# Кнопка просмотра лога (для диагностики)
	var view_log_button = Button.new()
	view_log_button.text = "Просмотр лога"
	view_log_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	view_log_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	view_log_button.pressed.connect(func():
		show_debug_log_dialog()
	)
	control_buttons.add_child(view_log_button)
	
	# Сохраняем ссылки на элементы AI чата для доступа из других функций
	ai_tab.set_meta("chat_history_edit", chat_history_edit)
	ai_tab.set_meta("message_edit", message_edit)
	ai_tab.set_meta("extracted_edit", extracted_commands_edit)
	ai_tab.set_meta("send_button", send_button)
	ai_tab.set_meta("requests_label", requests_label)
	ai_tab.set_meta("apply_button", apply_commands_button)
	
	# Сохраняем ссылку на диалог для доступа из других функций
	current_dialog = dialog
	
	# ===== ВКЛАДКА 2: INI =====
	var ini_tab = VBoxContainer.new()
	tab_container.add_child(ini_tab)
	tab_container.set_tab_title(1, "Команды")
	
	# Заголовок для команд (мобильная версия)
	var ini_label = Label.new()
	ini_label.text = "Вставьте команды от ИИ:"
	ini_label.add_theme_font_size_override("font_size", 16)  # Увеличиваем размер шрифта
	ini_tab.add_child(ini_label)
	
	# Поле для команд (мобильная версия)
	var ini_edit = TextEdit.new()
	ini_edit.placeholder_text = '# Вставьте ответ от ИИ с новыми командами:\n\n# Пример ответа ИИ:\nЯ добавлю функцию для движения игрока и переменную скорости.\n\n[++3@ var player_speed = 5.0]\n[+++7@ func move_player(direction):\n    position += direction * player_speed * delta]\n\n# Удаление строк:\n[--5@]\n[---2@]  # Удалить функцию целиком\n\n# Многострочный код:\n[++10@ func complex_function():\n    if condition:\n        print("True")\n    else:\n        print("False")]\n\n# Парсер автоматически найдет и выполнит команды формата [++N@], [--N@] и т.д.'
	ini_edit.custom_minimum_size = Vector2(1160, 650)  # Увеличиваем размер для мобильного
	ini_edit.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	ini_tab.add_child(ini_edit)
	
	# Кнопки для INI вкладки (мобильная версия)
	var ini_buttons = HBoxContainer.new()
	ini_buttons.custom_minimum_size = Vector2(1160, 60)  # Увеличиваем высоту для мобильного
	ini_tab.add_child(ini_buttons)
	
	var preview_button = Button.new()
	preview_button.text = "Предварительный просмотр"
	preview_button.custom_minimum_size = Vector2(200, 50)  # Увеличиваем размер кнопки
	preview_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	preview_button.pressed.connect(func():
		var ini_text = ini_edit.text
		show_ini_preview(ini_text)
	)
	ini_buttons.add_child(preview_button)
	
	var execute_ini_button = Button.new()
	execute_ini_button.text = "Выполнить команды"
	execute_ini_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	execute_ini_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	execute_ini_button.pressed.connect(func():
		var ini_text = ini_edit.text
		execute_ini_command(ini_text)
	)
	ini_buttons.add_child(execute_ini_button)
	
	var clear_ini_button = Button.new()
	clear_ini_button.text = "Очистить"
	clear_ini_button.custom_minimum_size = Vector2(120, 50)  # Увеличиваем размер кнопки
	clear_ini_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	clear_ini_button.pressed.connect(func():
		ini_edit.text = ""
	)
	ini_buttons.add_child(clear_ini_button)
	
	# ===== ВКЛАДКА 3: ОШИБКИ =====
	var errors_tab = VBoxContainer.new()
	tab_container.add_child(errors_tab)
	tab_container.set_tab_title(2, "Ошибки")
	
	# Заголовок для ошибок (мобильная версия)
	var errors_tab_label = Label.new()
	errors_tab_label.text = "Ошибки Godot (копируйте и отправляйте в чат):"
	errors_tab_label.add_theme_font_size_override("font_size", 16)  # Увеличиваем размер шрифта
	errors_tab.add_child(errors_tab_label)
	
	# Список ошибок (мобильная версия)
	var errors_tab_list = ItemList.new()
	errors_tab_list.custom_minimum_size = Vector2(1140, 550)  # Увеличиваем размер для мобильного
	errors_tab_list.allow_reselect = true
	errors_tab_list.allow_rmb_select = true
	errors_tab_list.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	errors_tab_list.item_selected.connect(func(index):
		var error_text = errors_tab_list.get_item_text(index)
		DisplayServer.clipboard_set(error_text)
		print("Ошибка скопирована в буфер обмена: ", error_text)
	)
	errors_tab.add_child(errors_tab_list)
	
	# Кнопки управления ошибками (мобильная версия)
	var errors_tab_buttons = HBoxContainer.new()
	errors_tab_buttons.custom_minimum_size = Vector2(1140, 60)  # Увеличиваем высоту для мобильного
	errors_tab.add_child(errors_tab_buttons)
	
	# Кнопка копирования ошибки (мобильная версия)
	var copy_error_tab_button = Button.new()
	copy_error_tab_button.text = "Копировать"
	copy_error_tab_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	copy_error_tab_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	copy_error_tab_button.pressed.connect(func():
		var selected_items = errors_tab_list.get_selected_items()
		if selected_items.size() > 0:
			var error_text = errors_tab_list.get_item_text(selected_items[0])
			DisplayServer.clipboard_set(error_text)
			print("Ошибка скопирована в буфер обмена!")
	)
	errors_tab_buttons.add_child(copy_error_tab_button)
	
	# Кнопка отправки ошибки в чат (мобильная версия)
	var send_error_tab_button = Button.new()
	send_error_tab_button.text = "Отправить в чат"
	send_error_tab_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	send_error_tab_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	send_error_tab_button.pressed.connect(func():
		var selected_items = errors_tab_list.get_selected_items()
		if selected_items.size() > 0:
			var error_text = errors_tab_list.get_item_text(selected_items[0])
			# Находим поле сообщения в AI чате
			if current_dialog:
				var dialog_vbox = current_dialog.get_child(0)
				if dialog_vbox and dialog_vbox.get_child_count() > 0:
					var dialog_tab_container = dialog_vbox.get_child(0)
					if dialog_tab_container and dialog_tab_container.get_child_count() > 0:
						var dialog_ai_tab = dialog_tab_container.get_child(0)
						if dialog_ai_tab:
							var dialog_message_edit = dialog_ai_tab.get_meta("message_edit")
							if dialog_message_edit:
								dialog_message_edit.text = "Ошибка: " + error_text
								# Переключаемся на вкладку AI чата
								dialog_tab_container.current_tab = 0
								print("Ошибка добавлена в поле сообщения и переключено на AI чат!")
	)
	errors_tab_buttons.add_child(send_error_tab_button)
	
	# Кнопка обновления списка ошибок (мобильная версия)
	var refresh_errors_tab_button = Button.new()
	refresh_errors_tab_button.text = "Обновить"
	refresh_errors_tab_button.custom_minimum_size = Vector2(120, 50)  # Увеличиваем размер кнопки
	refresh_errors_tab_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	refresh_errors_tab_button.pressed.connect(func():
		update_errors_list(errors_tab_list)
	)
	errors_tab_buttons.add_child(refresh_errors_tab_button)
	
	# Кнопка добавления ошибки вручную (мобильная версия)
	var add_error_tab_button = Button.new()
	add_error_tab_button.text = "Добавить ошибку"
	add_error_tab_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	add_error_tab_button.add_theme_font_size_override("font_size", 14)  # Увеличиваем размер шрифта
	add_error_tab_button.pressed.connect(func():
		show_add_error_dialog(errors_tab_list)
	)
	errors_tab_buttons.add_child(add_error_tab_button)
	
	# Кнопка добавления системных сообщений (мобильная версия)
	var add_system_tab_button = Button.new()
	add_system_tab_button.text = "Добавить системное"
	add_system_tab_button.tooltip_text = "Добавить системное сообщение Godot"
	add_system_tab_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	add_system_tab_button.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	add_system_tab_button.pressed.connect(func():
		add_system_message("--- Debug adapter server started on port 6006 ---", "INFO")
		add_system_message("--- GDScript language server started on port 6005 ---", "INFO")
		add_system_message("UID duplicate detected between res://plugin/icon.svg and res://addons/smart_replace/plugin/icon.svg.", "WARNING")
		update_errors_list(errors_tab_list)
		print("Добавлены системные сообщения Godot!")
	)
	errors_tab_buttons.add_child(add_system_tab_button)
	
	# Кнопка очистки системных сообщений (мобильная версия)
	var clear_system_tab_button = Button.new()
	clear_system_tab_button.text = "Очистить системные"
	clear_system_tab_button.tooltip_text = "Очистить все системные сообщения"
	clear_system_tab_button.custom_minimum_size = Vector2(150, 50)  # Увеличиваем размер кнопки
	clear_system_tab_button.add_theme_font_size_override("font_size", 12)  # Увеличиваем размер шрифта
	clear_system_tab_button.pressed.connect(func():
		system_messages.clear()
		update_errors_list(errors_tab_list)
		print("Системные сообщения очищены!")
	)
	errors_tab_buttons.add_child(clear_system_tab_button)
	
	# Обновляем список ошибок
	update_errors_list(errors_tab_list)
	
	# ===== ВКЛАДКА 4: ИСТОРИЯ КОМАНД =====
	var commands_history_tab = VBoxContainer.new()
	tab_container.add_child(commands_history_tab)
	tab_container.set_tab_title(3, "История команд")
	
	# Заголовок
	var commands_history_label = Label.new()
	commands_history_label.text = "История извлеченных и примененных INI команд:"
	commands_history_tab.add_child(commands_history_label)
	
	# Список истории команд
	var commands_history_list = ItemList.new()
	commands_history_list.custom_minimum_size = Vector2(940, 300)
	commands_history_list.allow_reselect = true
	commands_history_list.allow_rmb_select = true
	commands_history_tab.add_child(commands_history_list)
	
	# Поле для отображения деталей выбранной команды
	var commands_details_label = Label.new()
	commands_details_label.text = "Детали выбранной команды:"
	commands_history_tab.add_child(commands_details_label)
	
	var commands_details_edit = TextEdit.new()
	commands_details_edit.custom_minimum_size = Vector2(940, 200)
	commands_details_edit.editable = false
	commands_history_tab.add_child(commands_details_edit)
	
	# Кнопки для работы с историей команд
	var commands_history_buttons = HBoxContainer.new()
	commands_history_tab.add_child(commands_history_buttons)
	
	var refresh_commands_history_button = Button.new()
	refresh_commands_history_button.text = "Обновить список"
	refresh_commands_history_button.pressed.connect(func():
		refresh_commands_history_list(commands_history_list)
	)
	commands_history_buttons.add_child(refresh_commands_history_button)
	
	var copy_command_button = Button.new()
	copy_command_button.text = "Копировать команду"
	copy_command_button.pressed.connect(func():
		var selected_items = commands_history_list.get_selected_items()
		if selected_items.size() > 0:
			var index = selected_items[0]
			if index >= 0 and index < extracted_commands_history.size():
				var entry = extracted_commands_history[index]
				DisplayServer.clipboard_set(entry.commands)
				print("Команда скопирована в буфер обмена!")
	)
	commands_history_buttons.add_child(copy_command_button)
	
	var copy_to_ini_button = Button.new()
	copy_to_ini_button.text = "Копировать в INI"
	copy_to_ini_button.tooltip_text = "Копирует команду в INI вкладку для применения"
	copy_to_ini_button.pressed.connect(func():
		var selected_items = commands_history_list.get_selected_items()
		if selected_items.size() > 0:
			var index = selected_items[0]
			if index >= 0 and index < extracted_commands_history.size():
				var entry = extracted_commands_history[index]
				# Находим INI поле и копируем туда команду
				if current_dialog:
					var copy_vbox = current_dialog.get_child(0)
					if copy_vbox and copy_vbox.get_child_count() > 0:
						var copy_tab_container = copy_vbox.get_child(0)
						if copy_tab_container and copy_tab_container.get_child_count() > 1:
							var copy_ini_tab = copy_tab_container.get_child(1)  # INI вкладка
							if copy_ini_tab and copy_ini_tab.get_child_count() > 1:
								var copy_ini_edit = copy_ini_tab.get_child(1)  # TextEdit для INI
								if copy_ini_edit:
									copy_ini_edit.text = entry.commands
									# Переключаемся на INI вкладку
									copy_tab_container.current_tab = 1
									print("Команда скопирована в INI вкладку!")
	)
	commands_history_buttons.add_child(copy_to_ini_button)
	
	var clear_commands_history_button = Button.new()
	clear_commands_history_button.text = "Очистить историю"
	clear_commands_history_button.pressed.connect(func():
		extracted_commands_history.clear()
		save_extracted_commands_history()
		refresh_commands_history_list(commands_history_list)
		commands_details_edit.text = ""
	)
	commands_history_buttons.add_child(clear_commands_history_button)
	
	# Подключаем обработчик выбора команды
	commands_history_list.item_selected.connect(func(index):
		if index >= 0 and index < extracted_commands_history.size():
			var entry = extracted_commands_history[index]
			commands_details_edit.text = "Время: " + entry.timestamp + "\n\nКоманды:\n" + entry.commands
	)
	
	# Загружаем историю в список
	refresh_commands_history_list(commands_history_list)
	
	# Старый интерфейс для ручной работы удален - теперь используется новый парсер команд
	
	# Старый интерфейс для работы с кодом удален - теперь используется новый парсер команд
	
	# Показываем диалог
	write_debug_log("Добавляем диалог в base_control", "INFO")
	get_editor_interface().get_base_control().add_child(dialog)
	
	# Проверяем, что диалог успешно добавлен
	if dialog.get_parent():
		write_debug_log("Диалог успешно добавлен в дерево", "INFO")
		# Показываем диалог с проверкой
		dialog.popup_centered()
		write_debug_log("Диалог показан", "INFO")
	else:
		write_debug_log("ОШИБКА: Диалог не был добавлен в дерево", "ERROR")

# Функция load_functions_list удалена - больше не нужна

# Функции find_functions_in_file и find_function_end удалены - больше не нужны

# Функции для замены функций удалены - больше не нужны

# Функции для замены функций в файле удалены - больше не нужны

# Все старые функции для работы с функциями удалены - теперь используется новый парсер команд 

# Функция generate_preview_for_single удалена - больше не нужна 

# Старые функции работы с файлами удалены - теперь используется новый парсер

# Остальные старые функции для работы с функциями удалены - теперь используется новый парсер команд 

# ===== AI ЧАТ ФУНКЦИИ =====

func send_message_to_ai(message: String):
	write_debug_log("Начинаем отправку сообщения к AI: " + message.substr(0, 100) + "...", "INFO")
	
	if message.strip_edges() == "":
		write_debug_log("Сообщение пустое, отменяем отправку", "WARNING")
		return
	
	# Проверяем, не выполняется ли уже запрос
	if is_requesting:
		write_debug_log("Предыдущий запрос еще выполняется", "WARNING")
		add_message_to_chat("Система", "Подождите, предыдущий запрос еще выполняется...", "system")
		return
	
	# Проверяем лимиты запросов
	write_debug_log("Проверяем лимиты запросов", "INFO")
	var current_count = check_and_update_daily_requests()
	var model_limit = get_current_model_limit()
	
	if current_count >= model_limit:
		write_debug_log("Достигнут дневной лимит запросов: " + str(current_count) + "/" + str(model_limit), "WARNING")
		var model_info = get_current_model_info()
		var model_name = model_info.get("name", current_model)
		add_message_to_chat("Система", "🚫 Достигнут дневной лимит запросов для " + model_name + " (" + str(current_count) + "/" + str(model_limit) + "). Попробуйте другую модель или завтра.", "system")
		return
	
	if current_count >= model_limit * 0.9:  # 90% от лимита
		write_debug_log("Приближаемся к лимиту запросов: " + str(current_count) + "/" + str(model_limit), "WARNING")
		var model_info = get_current_model_info()
		var model_name = model_info.get("name", current_model)
		add_message_to_chat("Система", "⚠️ Внимание: Приближаетесь к лимиту запросов для " + model_name + "! (" + str(current_count) + "/" + str(model_limit) + ")", "system")
	
	# Проверяем API ключ
	if gemini_api_key == "":
		write_debug_log("API ключ не найден, показываем диалог настроек", "ERROR")
		print("API ключ не найден, показываем диалог настроек")
		show_api_key_dialog()
		return
	
	write_debug_log("Добавляем сообщение в чат", "INFO")
	print("Добавляем сообщение в чат...")
	# Добавляем сообщение пользователя в чат
	add_message_to_chat("Вы", message, "user")
	
	# Получаем текущий код файла для контекста (принудительно из редактора)
	write_debug_log("Получаем актуальный код файла из редактора", "INFO")
	var current_code = get_current_file_content()
	write_debug_log("Текущий код файла получен, длина: " + str(current_code.length()), "INFO")
	print("Текущий код файла получен, длина: ", current_code.length())
	
	# Добавляем информацию о количестве строк для отладки
	var lines = current_code.split("\n")
	write_debug_log("Количество строк в файле: " + str(lines.size()), "INFO")
	print("Количество строк в файле: ", lines.size())
	
	# Проверяем, есть ли несохраненные изменения
	var script_editor = get_editor_interface().get_script_editor()
	if script_editor and script_editor.get_current_script():
		var current_script = script_editor.get_current_script()
		if current_script.has_meta("modified"):
			print("⚠️ ВНИМАНИЕ: Файл содержит несохраненные изменения! Сохраните файл для получения актуального кода.")
			write_debug_log("Файл содержит несохраненные изменения", "WARNING")
	
	# Формируем промпт для AI
	write_debug_log("Формируем промпт для AI", "INFO")
	var prompt = create_chat_prompt(message, current_code)
	write_debug_log("Промпт сформирован, отправляем запрос к Gemini", "INFO")
	print("Промпт сформирован, отправляем запрос к OpenAI...")
	
	# Устанавливаем флаг выполнения запроса
	is_requesting = true
	write_debug_log("Устанавливаем флаг is_requesting = true", "INFO")
	
	# Отключаем поле ввода на время запроса
	write_debug_log("Отключаем поле ввода на время запроса", "INFO")
	if current_dialog:
		var vbox = current_dialog.get_child(0)
		if vbox and vbox.get_child_count() > 0:
			var tab_container = vbox.get_child(0)
			if tab_container and tab_container.get_child_count() > 0:
				var ai_tab = tab_container.get_child(0)
				if ai_tab:
					var message_edit = ai_tab.get_meta("message_edit")
					if message_edit:
						message_edit.editable = false
						message_edit.placeholder_text = "Подождите, запрос выполняется..."
	
	# Сбрасываем флаг первого сообщения после отправки
	is_first_message_in_session = false
	
	# Отправляем запрос к выбранному провайдеру
	write_debug_log("Вызываем API для провайдера: " + current_provider, "INFO")
	if current_provider == "gemini":
		call_gemini_api(prompt)
	else:
		call_openrouter_api(prompt)

func add_message_to_chat(sender: String, message: String, type: String):
	print("add_message_to_chat вызвана: ", sender, " - ", message)
	
	# Проверяем, что узел в дереве
	if not is_inside_tree():
		print("Узел не в дереве, отменяем добавление сообщения")
		return
	
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
	var ai_tab = tab_container.get_child(0)  # AI Чат вкладка (теперь первая)
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
			# Читаем код с диска (убедитесь, что файл сохранен!)
			var file_path = current_script.resource_path
			var file = FileAccess.open(file_path, FileAccess.READ)
			if file:
				var content = file.get_as_text()
				file.close()
				write_debug_log("Получен код с диска, длина: " + str(content.length()), "INFO")
				
				# Проверяем, есть ли несохраненные изменения
				if script_editor.get_current_script().has_meta("modified"):
					write_debug_log("ВНИМАНИЕ: Файл может содержать несохраненные изменения!", "WARNING")
					print("⚠️ ВНИМАНИЕ: Сохраните файл перед отправкой к AI для получения актуального кода!")
				
				return content
			else:
				write_debug_log("Не удалось открыть файл для чтения", "ERROR")
		else:
			write_debug_log("Текущий скрипт не найден", "WARNING")
	else:
		write_debug_log("Редактор скриптов не найден", "WARNING")
	return ""

# Функция для получения информации о текущем скрипте и узле
func get_current_script_info() -> Dictionary:
	var info = {
		"path": "",
		"filename": "",
		"node_path": "",
		"hierarchy": ""
	}
	
	print("=== ПОЛУЧЕНИЕ ИНФОРМАЦИИ О СКРИПТЕ ===")
	
	var editor_interface = get_editor_interface()
	var script_editor = editor_interface.get_script_editor()
	if script_editor:
		var current_script = script_editor.get_current_script()
		if current_script:
			info.path = current_script.resource_path
			info.filename = current_script.resource_path.get_file()
			print("Найден скрипт: ", info.path)
			print("Имя файла: ", info.filename)
			
			# Пытаемся найти узел, на котором висит этот скрипт
			# Используем открытую сцену
			var edited_scene_root = editor_interface.get_edited_scene_root()
			if edited_scene_root:
				print("Открытая сцена найдена: ", edited_scene_root.name)
				print("Путь сцены: ", edited_scene_root.get_path())
				
				# Проверяем, что это не узел редактора
				var scene_path = str(edited_scene_root.get_path())
				if not scene_path.begins_with("/root/@EditorNode"):
					var found_node = find_node_with_script(edited_scene_root, current_script)
					if found_node:
						info.node_path = found_node.get_path()
						info.hierarchy = get_node_hierarchy(found_node)
						print("Скрипт найден в сцене: ", info.node_path)
					else:
						print("Скрипт НЕ найден в открытой сцене")
				else:
					print("Это узел редактора, пропускаем")
			else:
				print("Открытая сцена НЕ найдена")
		else:
			print("Текущий скрипт НЕ найден")
	else:
		print("Редактор скриптов НЕ найден")
	
	print("Результат: ", info)
	print("=== КОНЕЦ ПОЛУЧЕНИЯ ИНФОРМАЦИИ ===")
	return info

# Функция для поиска узла с определенным скриптом
func find_node_with_script(node: Node, script: Script) -> Node:
	if node.get_script() == script:
		return node
	
	for child in node.get_children():
		var found = find_node_with_script(child, script)
		if found:
			return found
	
	return null

# Функция для получения иерархии узлов
func get_node_hierarchy(node: Node) -> String:
	var hierarchy = []
	var current = node
	
	while current != null:
		hierarchy.append(current.name)
		current = current.get_parent()
	
	# Переворачиваем массив для правильного порядка (от корня к узлу)
	hierarchy.reverse()
	return "/".join(hierarchy)



func create_chat_prompt(message: String, current_code: String) -> String:
	var instructions = ""
	
	# Всегда обновляем информацию о скрипте при каждом сообщении
	current_script_info = get_current_script_info()
	
	# Добавляем оптимизированные инструкции при каждом сообщении
	instructions = """Ты - эксперт по GDScript и плагину Smart Replace для Godot v2.3.

## ФОРМАТ КОМАНД

### Вставка по именам функций
```
[++func@ код] - добавить код в конец файла
[++func:Move@ код] - добавить код в функцию Move
[++func:Move:1@ код] - добавить код в функцию Move с отступом 1
[++func:up@ код] - добавить код выше первой функции
[++func:down@ код] - добавить код в конец файла
[++func:up:Move@ код] - добавить код выше функции Move
[++func:down:Move@ код] - добавить код после функции Move
```

**Примеры:**
```
[++func@ func new_function():\\n    pass]
[++func:Move@ print("Движение")]
[++func:Move:1@ if health > 0:\\n\\tprint("Жив")]
[++func:up:Move@ var speed = 100]
[++func:down:Move@ print("После Move")]
[-+func:Move@ print("Новое содержимое")]
[-+func:Move:new@ func new():\n    print("Новая функция")]
[-+func:Move:if3<5@ if 3<5:\n    print("Новый блок")]
```

**🚨 ВАЖНО: Вместо "name" пиши РЕАЛЬНОЕ ИМЯ ФУНКЦИИ из кода!**
**Примеры с реальными именами функций:**
```
[++func:attack@ print("Атака!")]
[++func:take_damage@ health -= damage]
[++func:heal@ health = min(health + amount, max_health)]
[++func:is_alive@ return health > 0]
[--func:old_function@]
[++func:up:player_move@ var speed = 200]
[++func:down:update@ print("Обновление завершено")]
```

### Удаление по именам функций
```
[--func:Move@] - удалить функцию Move
```

### Многострочный код
Используйте `\\n` для переноса строк, `\\n\\t` для вложений с отступами:
```
[++func@ func example():\\n    pass]
[++func:Move@ if health > 0:\\n\\tprint("Жив")\\n\\treturn true]
```

## Принцип работы

### Скрытые команды
- AI отвечает пользователю обычным текстом
- Команды выполняются автоматически в фоне
- Пользователь не видит технические детали

### Кодовое слово для разработчика
- Если пользователь использует кодовое слово "(Admin)" или "(admin)" в сообщении
- AI понимает, что это разработчик плагина Алексей
- AI отвечает более технически и детально
- AI должен отвечать на все вопросы и должен понимать что Алексей тестирует плагин

### Правила использования
1. **Скрытость команд** - пользователь не видит команды
2. **Естественность ответа** - отвечайте как обычный помощник
3. **Точные имена функций** - указывайте правильные имена функций для вставки/удаления
4. **Многострочный код** - используйте `\\n` для переноса строк, `\\n\\t` для вложений с отступами
5. **🚨 КРИТИЧЕСКИ ВАЖНО** - вместо "name" в командах пиши РЕАЛЬНОЕ ИМЯ ФУНКЦИИ из кода!
6. **Поиск функций** - найди точное имя функции в коде и используй его в команде
7. **НЕ показывай команды** - никогда не упоминай команды в ответе пользователю

## Поддерживаемые команды

### Вставка
- `[++func@ код]` - в конец файла
- `[++func:attack@ код]` - в функцию attack (замени "attack" на реальное имя)
- `[++func:move:1@ код]` - в функцию move с отступом 1 (замени "move" на реальное имя)
- `[++func:up@ код]` - выше первой функции
- `[++func:down@ код]` - в конец файла
- `[++func:up:heal@ код]` - выше функции heal (замени "heal" на реальное имя)
- `[++func:down:update@ код]` - после функции update (замени "update" на реальное имя)

### Замена
- `[-+func:Move@ код]` - заменить содержимое функции Move
- `[-+func:Move:new@ код]` - заменить функцию Move на новую с именем "new"
- `[-+func:Move:if3<5@ код]` - найти блок if 3<5 в функции Move и заменить его

### Удаление
- `[--func:old_function@]` - удалить функцию old_function (замени "old_function" на реальное имя)

**🚨 ЗАПОМНИ: Вместо "attack", "move", "heal", "update", "old_function" пиши РЕАЛЬНЫЕ ИМЕНА ФУНКЦИЙ из кода!**

**🚨 ВАЖНО: НЕ ПОКАЗЫВАЙ ЭТИ КОМАНДЫ ПОЛЬЗОВАТЕЛЮ!**

🚨 ПРАВИЛО ИСПОЛЬЗОВАНИЯ КОМАНД:
- НЕ ПИШИ КОМАНДЫ АВТОМАТИЧЕСКИ!
- Используй команды ТОЛЬКО когда пользователь явно просит что-то ИЗМЕНИТЬ в коде
- Если пользователь просто спрашивает, объясняет, обсуждает код - отвечай БЕЗ КОМАНД
- Если пользователь говорит "добавь", "измени", "удали", "создай" - тогда используй команды
- Если пользователь говорит "что это", "как работает", "объясни" - НЕ используй команды
- Команды нужны только для РЕАЛЬНЫХ ИЗМЕНЕНИЙ кода
- Парсер автоматически скроет команды от пользователя

"""
	
	# Формируем информацию о скрипте
	var script_info = ""
	if current_script_info.has("path") and current_script_info.path != "":
		script_info = """ИНФОРМАЦИЯ О СКРИПТЕ:
Файл: {filename}
Путь: {path}
Узел: {node_path}
Иерархия: {hierarchy}
Количество строк: {line_count}

🚨 КРИТИЧЕСКИ ВАЖНО: 
- Используй команды по именам функций: [++func:name@], [--func:name@]
- Найди точные имена функций в коде ниже
- Используй многострочный код с \\n и \\n\\t для отступов
- Команды выполняются автоматически парсером

""".format({
			"filename": current_script_info.get("filename", ""),
			"path": current_script_info.get("path", ""),
			"node_path": current_script_info.get("node_path", ""),
			"hierarchy": current_script_info.get("hierarchy", ""),
			"line_count": current_code.split("\n").size()
		})
	
	# Удаляем старый блок с напоминанием, так как теперь инструкции отправляются при каждом сообщении
		print("=== ИНФОРМАЦИЯ ДЛЯ AI ===")
		print("Скрипт: ", current_script_info.filename)
		print("Путь: ", current_script_info.path)
		print("Узел: ", current_script_info.node_path)
		print("Иерархия: ", current_script_info.hierarchy)
		print("=== КОНЕЦ ИНФОРМАЦИИ ===")
	
	var system_prompt = instructions + script_info + """ТЕКУЩИЙ КОД ФАЙЛА:
```
{current_code}
```

ИСТОРИЯ ЧАТА (для контекста):
{chat_history}

ПОЛЬЗОВАТЕЛЬ: {message}

Помни: отвечай естественно, как обычный помощник.

🚨 КОГДА ИСПОЛЬЗОВАТЬ КОМАНДЫ:
- ТОЛЬКО когда пользователь явно просит ИЗМЕНИТЬ код
- Скрыто добавляй команды формата [++func:name@ код], [--func:name@]
- НЕ ДУБЛИРУЙ команды из предыдущих сообщений!

🚨 КОГДА НЕ ИСПОЛЬЗОВАТЬ КОМАНДЫ:
- Когда пользователь просто спрашивает или обсуждает код
- Когда пользователь просит объяснить что-то
- Когда пользователь не просит изменений
- Когда пользователь говорит "молодец", "хорошо", "спасибо" - отвечай БЕЗ КОМАНД

🚨 ВАЖНО: НЕ ПОКАЗЫВАЙ ПОЛЬЗОВАТЕЛЮ КОМАНДЫ И ТЕХНИЧЕСКИЕ ДЕТАЛИ!
- Отвечай естественно, как обычный помощник
- НЕ упоминай команды в ответе
- НЕ показывай технические детали парсера
- НЕ пиши "Вот ответ на последнее сообщение"

🚨 ВАЖНО: В командах вместо "name" используй РЕАЛЬНОЕ ИМЯ ФУНКЦИИ из кода!
Примеры: [++func:attack@], [--func:old_function@], [++func:player_move@]

🚨 ВАЖНО: НЕ ПОКАЗЫВАЙ КОМАНДЫ ПОЛЬЗОВАТЕЛЮ! Отвечай естественно!"""
	
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
	write_debug_log("=== НАЧАЛО call_gemini_api ===", "INFO")
	write_debug_log("Длина промпта: " + str(prompt.length()), "INFO")
	write_debug_log("is_requesting: " + str(is_requesting), "INFO")
	write_debug_log("Текущее время: " + Time.get_time_string_from_system(), "INFO")
	
	print("=== НАЧАЛО call_gemini_api ===")
	print("Длина промпта: ", prompt.length())
	print("is_requesting: ", is_requesting)
	print("Текущее время: ", Time.get_time_string_from_system())
	
	# Увеличиваем счетчик запросов
	write_debug_log("Увеличиваем счетчик запросов", "INFO")
	increment_daily_requests()
	
	# Создаем HTTP запрос с улучшенной обработкой ошибок
	write_debug_log("Создаем HTTP запрос", "INFO")
	var http = HTTPRequest.new()
	http.timeout = 30  # 30 секунд таймаут
	
	# Проверяем, что узел все еще существует перед добавлением
	if not is_inside_tree():
		write_debug_log("Узел не в дереве, отменяем запрос", "ERROR")
		print("Узел не в дереве, отменяем запрос")
		return
	
	write_debug_log("Добавляем HTTP запрос как дочерний узел", "INFO")
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
	
	# Формируем URL с API ключом и текущей моделью
	var url = GEMINI_API_BASE_URL + current_model + ":generateContent?key=" + gemini_api_key
	
	# Настраиваем заголовки
	var headers = [
		"Content-Type: application/json"
	]
	
	# Отправляем запрос
	write_debug_log("Отправляем запрос на URL: " + url, "INFO")
	write_debug_log("Длина JSON данных: " + str(json_string.length()), "INFO")
	write_debug_log("=== ОТПРАВКА HTTP ЗАПРОСА ===", "INFO")
	print("Отправляем запрос на URL: ", url)
	print("Длина JSON данных: ", json_string.length())
	print("=== ОТПРАВКА HTTP ЗАПРОСА ===")
	var error = http.request(url, headers, HTTPClient.METHOD_POST, json_string)
	if error != OK:
		write_debug_log("Ошибка при отправке HTTP запроса: " + str(error), "ERROR")
		print("Ошибка при отправке HTTP запроса: ", error)
		print("Коды ошибок: 0=OK, 1=RESULT_CHUNKED_BODY_SIZE_MISMATCH, 2=RESULT_CANT_RESOLVE, 3=RESULT_CANT_RESOLVE_PROXY, 4=RESULT_CANT_CONNECT, 5=RESULT_CANT_CONNECT_PROXY, 6=RESULT_SSL_HANDSHAKE_ERROR, 7=RESULT_CANT_ACCEPT, 8=RESULT_TIMEOUT")
		http.queue_free()
		return
	
	# Подключаем сигнал завершения с защитой
	if http and is_instance_valid(http):
		http.request_completed.connect(func(result, response_code, headers, body):
			handle_gemini_response(result, response_code, headers, body)
			if http and is_instance_valid(http):
				http.queue_free()
		)

func handle_gemini_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	write_debug_log("=== НАЧАЛО handle_gemini_response ===", "INFO")
	write_debug_log("Код ответа: " + str(response_code), "INFO")
	write_debug_log("is_requesting до сброса: " + str(is_requesting), "INFO")
	write_debug_log("Текущее время: " + Time.get_time_string_from_system(), "INFO")
	
	print("=== НАЧАЛО handle_gemini_response ===")
	print("Код ответа: ", response_code)
	print("is_requesting до сброса: ", is_requesting)
	print("Текущее время: ", Time.get_time_string_from_system())
	
	# Включаем кнопку и поле ввода обратно
	if current_dialog:
		var vbox = current_dialog.get_child(0)
		if vbox and vbox.get_child_count() > 0:
			var tab_container = vbox.get_child(0)
			if tab_container and tab_container.get_child_count() > 0:
				var ai_tab = tab_container.get_child(0)
				if ai_tab:
					var send_button = ai_tab.get_meta("send_button")
					if send_button:
						send_button.disabled = false
						send_button.text = "Отправить"
					
					var message_edit = ai_tab.get_meta("message_edit")
					if message_edit:
						message_edit.editable = true
						message_edit.placeholder_text = "Введите ваше сообщение для AI..."
	
	# Флаг is_requesting будет сброшен в process_ai_response
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("Ошибка HTTP запроса: ", result)
		print("Сбрасываем is_requesting = false из-за ошибки HTTP")
		is_requesting = false
		
		# Безопасно добавляем сообщение об ошибке
		if is_inside_tree():
			add_message_to_chat("Система", "Ошибка соединения с Google Gemini API. Проверьте интернет-соединение.", "system")
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
				error_message = "Лимит запросов исчерпан (429). Возможно, превышен дневной лимит или лимит запросов в минуту. Попробуйте позже или перейдите на платный план Google AI Studio."
			500:
				error_message = "Ошибка сервера Google (500). Попробуйте позже."
			503:
				error_message = "Сервис Google Gemini временно недоступен (503). Попробуйте позже."
			_:
				error_message = "Ошибка API: " + str(response_code) + ". Проверьте интернет-соединение и API ключ."
		
		print("Сбрасываем is_requesting = false из-за ошибки API")
		is_requesting = false
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

# Функция для вызова OpenRouter API
func call_openrouter_api(prompt: String):
	write_debug_log("=== НАЧАЛО call_openrouter_api ===", "INFO")
	write_debug_log("Длина промпта: " + str(prompt.length()), "INFO")
	write_debug_log("is_requesting: " + str(is_requesting), "INFO")
	write_debug_log("Текущее время: " + Time.get_time_string_from_system(), "INFO")
	
	print("=== НАЧАЛО call_openrouter_api ===")
	print("Длина промпта: ", prompt.length())
	print("is_requesting: ", is_requesting)
	print("Текущее время: ", Time.get_time_string_from_system())
	
	# Увеличиваем счетчик запросов
	write_debug_log("Увеличиваем счетчик запросов", "INFO")
	increment_daily_requests()
	
	# Создаем HTTP запрос
	write_debug_log("Создаем HTTP запрос", "INFO")
	var http = HTTPRequest.new()
	http.timeout = 30  # 30 секунд таймаут
	
	# Проверяем, что узел все еще существует перед добавлением
	if not is_inside_tree():
		write_debug_log("Узел не в дереве, отменяем запрос", "ERROR")
		print("Узел не в дереве, отменяем запрос")
		return
	
	write_debug_log("Добавляем HTTP запрос как дочерний узел", "INFO")
	add_child(http)
	
	# Формируем JSON для запроса OpenRouter
	var request_data = {
		"model": current_model,
		"messages": [
			{
				"role": "user",
				"content": prompt
			}
		],
		"max_tokens": get_current_model_info().get("max_tokens", 2000),
		"temperature": 0.1
	}
	
	var json_string = JSON.stringify(request_data)
	
	# Настраиваем заголовки для OpenRouter
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + openrouter_api_key,
		"HTTP-Referer: https://godot-engine.org",
		"X-Title: Smart Replace Plugin"
	]
	
	# Отправляем запрос
	write_debug_log("Отправляем запрос на OpenRouter API", "INFO")
	write_debug_log("Длина JSON данных: " + str(json_string.length()), "INFO")
	print("Отправляем запрос на OpenRouter API")
	print("Длина JSON данных: ", json_string.length())
	
	var error = http.request(OPENROUTER_API_BASE_URL, headers, HTTPClient.METHOD_POST, json_string)
	if error != OK:
		write_debug_log("Ошибка при отправке HTTP запроса: " + str(error), "ERROR")
		print("Ошибка при отправке HTTP запроса: ", error)
		http.queue_free()
		return
	
	# Подключаем сигнал завершения с защитой
	if http and is_instance_valid(http):
		http.request_completed.connect(func(result, response_code, headers, body):
			handle_openrouter_response(result, response_code, headers, body)
			if http and is_instance_valid(http):
				http.queue_free()
		)

# Функция для обработки ответа OpenRouter
func handle_openrouter_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	write_debug_log("=== НАЧАЛО handle_openrouter_response ===", "INFO")
	write_debug_log("Код ответа: " + str(response_code), "INFO")
	write_debug_log("is_requesting до сброса: " + str(is_requesting), "INFO")
	write_debug_log("Текущее время: " + Time.get_time_string_from_system(), "INFO")
	
	print("=== НАЧАЛО handle_openrouter_response ===")
	print("Код ответа: ", response_code)
	print("is_requesting до сброса: ", is_requesting)
	print("Текущее время: ", Time.get_time_string_from_system())
	
	# Включаем кнопку и поле ввода обратно
	if current_dialog:
		var vbox = current_dialog.get_child(0)
		if vbox and vbox.get_child_count() > 0:
			var tab_container = vbox.get_child(0)
			if tab_container and tab_container.get_child_count() > 0:
				var ai_tab = tab_container.get_child(0)
				if ai_tab:
					var send_button = ai_tab.get_meta("send_button")
					if send_button:
						send_button.disabled = false
						send_button.text = "Отправить"
					
					var message_edit = ai_tab.get_meta("message_edit")
					if message_edit:
						message_edit.editable = true
						message_edit.placeholder_text = "Введите ваше сообщение для AI..."
	
	# Флаг is_requesting будет сброшен в process_ai_response
	
	if result != HTTPRequest.RESULT_SUCCESS:
		write_debug_log("Ошибка HTTP запроса: " + str(result), "ERROR")
		print("Ошибка HTTP запроса: ", result)
		write_debug_log("Сбрасываем is_requesting = false из-за ошибки HTTP", "INFO")
		is_requesting = false
		
		# Безопасно добавляем сообщение об ошибке
		var error_message = "❌ Ошибка сети при обращении к OpenRouter API.\n\n💡 Возможные причины:\n• Проблемы с интернет-соединением\n• Неправильный API ключ\n• Модель недоступна"
		if is_inside_tree():
			add_message_to_chat("Система", error_message, "system")
		return
	
	# Проверяем код ответа HTTP
	if response_code != 200:
		write_debug_log("HTTP код ответа: " + str(response_code), "ERROR")
		print("HTTP код ответа: ", response_code)
		
		var error_message = "❌ Ошибка OpenRouter API (HTTP " + str(response_code) + ")"
		
		match response_code:
			401:
				error_message += "\n\n💡 Неверный API ключ. Проверьте правильность ключа."
			402:
				error_message += "\n\n💡 Недостаточно средств на балансе OpenRouter."
			404:
				error_message += "\n\n💡 Модель не найдена. Попробуйте другую модель."
			429:
				error_message += "\n\n💡 Превышен лимит запросов. Подождите немного."
			500, 502, 503:
				error_message += "\n\n💡 Проблемы на стороне OpenRouter. Попробуйте позже."
			_:
				error_message += "\n\n💡 Неизвестная ошибка сервера."
		
		is_requesting = false
		if is_inside_tree():
			add_message_to_chat("Система", error_message, "system")
		return
	
	# Парсим JSON ответ
	var response_text = body.get_string_from_utf8()
	write_debug_log("Тело ответа OpenRouter: " + response_text, "INFO")
	
	var json = JSON.new()
	var parse_result = json.parse(response_text)
	
	if parse_result != OK:
		write_debug_log("Ошибка парсинга JSON ответа: " + str(parse_result), "ERROR")
		print("Ошибка парсинга JSON ответа: ", parse_result)
		write_debug_log("Сырой ответ: " + response_text, "ERROR")
		is_requesting = false
		if is_inside_tree():
			add_message_to_chat("Система", "❌ Ошибка при обработке ответа от OpenRouter API.\n\n💡 Возможные причины:\n• Неправильный формат ответа\n• Проблемы с кодировкой\n• Сервер вернул не-JSON ответ", "system")
		return
	
	var response_data = json.data
	
	# Проверяем наличие ошибки в ответе
	if response_data.has("error"):
		var error_info = response_data.error
		var error_message = "Неизвестная ошибка"
		var error_type = "error"
		
		if error_info.has("message"):
			error_message = str(error_info.message)
		elif error_info.has("type"):
			error_type = str(error_info.type)
		
		write_debug_log("OpenRouter API вернул ошибку: " + str(error_info), "ERROR")
		print("OpenRouter API вернул ошибку: ", error_info)
		
		# Формируем понятное сообщение об ошибке
		var user_message = "❌ Ошибка OpenRouter API: " + error_message
		
			# Добавляем рекомендации в зависимости от типа ошибки
		if error_message.contains("quota") or error_message.contains("limit"):
			user_message += "\n\n💡 Рекомендации:\n• Проверьте баланс на OpenRouter\n• Попробуйте другую модель"
		elif error_message.contains("model") or error_message.contains("provider"):
			user_message += "\n\n💡 Рекомендации:\n• Модель может быть временно недоступна\n• Попробуйте другую модель (GPT-4o Mini, DeepSeek R1, Llama 3.1 8B)"
		elif error_message.contains("key") or error_message.contains("auth"):
			user_message += "\n\n💡 Рекомендации:\n• Проверьте правильность API ключа\n• Убедитесь, что ключ активен"
		else:
			user_message += "\n\n💡 Рекомендации:\n• Попробуйте другую модель\n• Проверьте API ключ\n• Убедитесь в наличии средств на балансе"
		
		is_requesting = false
		if is_inside_tree():
			add_message_to_chat("Система", user_message, "system")
		return
	
	# Извлекаем ответ AI
	var ai_response = ""
	if response_data.has("choices") and response_data.choices.size() > 0:
		var choice = response_data.choices[0]
		if choice.has("message") and choice.message.has("content"):
			ai_response = choice.message.content
	
	if ai_response.strip_edges() == "":
		write_debug_log("Пустой ответ от OpenRouter API", "WARNING")
		print("Пустой ответ от OpenRouter API")
		is_requesting = false
		if is_inside_tree():
			add_message_to_chat("Система", "⚠️ Получен пустой ответ от OpenRouter API.", "system")
		return
	
	write_debug_log("Получен ответ от OpenRouter API, длина: " + str(ai_response.length()), "INFO")
	print("Получен ответ от OpenRouter API, длина: ", ai_response.length())
	
	# Обрабатываем ответ AI
	process_ai_response(ai_response)

func process_ai_response(ai_response: String):
	print("=== НАЧАЛО process_ai_response ===")
	print("is_requesting до сброса: ", is_requesting)
	# Сбрасываем флаг выполнения запроса
	is_requesting = false
	print("Сбрасываем is_requesting = false в process_ai_response")
	
	# Извлекаем новые команды из ответа AI
	var new_commands = extract_new_commands(ai_response)
	
	# ВРЕМЕННО: Показываем полный ответ AI без скрытия команд
	print("=== ОТЛАДКА: Обработка ответа AI ===")
	print("Исходный ответ AI: '", ai_response, "'")
	
	# Показываем полный ответ AI (временно)
	var text_response = ai_response
	print("Показываем полный ответ AI: '", text_response, "'")
	
	# Получаем имя текущей модели для отображения в чате
	var model_info = get_current_model_info()
	var model_name = model_info.get("name", current_model)
	
	# Добавляем ответ AI в чат с именем модели
	add_message_to_chat(model_name, text_response, "ai")
	
	# Если есть команды, показываем их для применения
	if new_commands != "":
		# Показываем извлеченные команды в отладочном поле
		show_extracted_commands(new_commands)
		print("Команды извлечены и готовы к применению. Нажмите 'Применить команды' для их выполнения.")
	else:
		# Очищаем предыдущие команды
		current_extracted_commands = ""
		# Обновляем цвет кнопки
		if current_dialog:
			var vbox = current_dialog.get_child(0)
			if vbox and vbox.get_child_count() > 0:
				var tab_container = vbox.get_child(0)
				if tab_container and tab_container.get_child_count() > 0:
					var ai_tab = tab_container.get_child(0)  # AI Чат вкладка (первая)
					if ai_tab:
						var apply_button = ai_tab.get_meta("apply_button")
						if apply_button:
							update_apply_button_color(apply_button)

func remove_commands_from_text(text: String) -> String:
	# Удаляем команды формата [++func:name@ код], [--func:name@], [-+func:name@ код] из текста
	var regex = RegEx.new()
	regex.compile("\\[\\+\\+[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:[a-zA-Z_]+:[0-9]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:up@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:down@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:up:[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:down:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\-[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+:[a-zA-Z_]+:[^@]*@[^\\]]*\\]")
	
	print("Удаляем команды из текста длиной: ", text.length())
	print("Исходный текст: '", text, "'")
	
	# Находим все команды
	var results = regex.search_all(text)
	var commands_found = []
	for result in results:
		commands_found.append(result.get_string())
	
	print("Найдено команд: ", commands_found.size())
	for cmd in commands_found:
		print("Команда: '", cmd, "'")
	
	# Заменяем каждую команду на пробел
	var result = text
	for cmd in commands_found:
		result = result.replace(cmd, " ")
	
	# Очищаем лишние пробелы
	result = result.replace("  ", " ")  # Убираем двойные пробелы
	result = result.strip_edges()  # Убираем лишние пробелы в начале и конце
	
	print("Текст после удаления команд: '", result, "'")
	print("Текст после удаления команд длиной: ", result.length())
	return result

func show_api_key_dialog():
	# Показываем сообщение пользователю
	print("Для использования AI чата необходимо настроить API ключ Google Gemini.")
	print("Введите API ключ в поле выше и нажмите 'Сохранить ключ'.")
	
	# Добавляем сообщение в чат
	add_message_to_chat("Система", "Для использования AI чата необходимо настроить API ключ Google Gemini. Введите ключ в поле выше и нажмите 'Сохранить ключ'.", "system")

func save_api_key():
	# Сохраняем API ключ, модель и провайдер в настройках проекта
	var config = ConfigFile.new()
	config.set_value("smart_replace", "gemini_api_key", gemini_api_key)
	config.set_value("smart_replace", "current_model", current_model)
	config.set_value("smart_replace", "current_provider", current_provider)
	config.save("res://smart_replace_config.ini")

func load_api_key():
	# Загружаем API ключ, модель и провайдер из настроек
	var config = ConfigFile.new()
	var error = config.load("res://smart_replace_config.ini")
	if error == OK:
		gemini_api_key = config.get_value("smart_replace", "gemini_api_key", "")
		current_model = config.get_value("smart_replace", "current_model", "openai/gpt-4o-mini")
		current_provider = config.get_value("smart_replace", "current_provider", "openrouter")
	else:
		# Если файл не существует, оставляем пустые значения и настройки по умолчанию (только бесплатные модели)
		gemini_api_key = ""
		current_model = "openai/gpt-4o-mini"  # Бесплатная модель OpenRouter
		current_provider = "openrouter"

# Функция для тестирования соединения
func test_connection():
	print("Тестируем соединение с Google...")
	
	# Проверяем, что узел в дереве
	if not is_inside_tree():
		print("Узел не в дереве, отменяем тест соединения")
		return
	
	var http = HTTPRequest.new()
	http.timeout = 10
	add_child(http)
	
	var error = http.request("https://www.google.com", [], HTTPClient.METHOD_GET)
	if error != OK:
		print("Ошибка соединения с Google: ", error)
	else:
		print("Соединение с Google успешно")
	
	# Безопасно подключаем сигнал
	if http and is_instance_valid(http):
		http.request_completed.connect(func(result, response_code, headers, body):
			print("Тест соединения завершен: код ", response_code)
			if http and is_instance_valid(http):
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
	
	var ai_tab = tab_container.get_child(0)  # AI Чат вкладка (теперь первая)
	if not ai_tab:
		print("AI вкладка не найдена в show_extracted_commands!")
		return
	
	# Получаем элементы через метаданные
	var extracted_edit = ai_tab.get_meta("extracted_edit")
	if not extracted_edit:
		print("extracted_edit не найден в метаданных!")
		return
	
	var apply_button = ai_tab.get_meta("apply_button")
	if not apply_button:
		print("apply_button не найден в метаданных!")
		return
	
	# Сохраняем команды для применения
	current_extracted_commands = ini_commands
	
	# Показываем команды в отладочном поле
	extracted_edit.text = ini_commands
	
	# Обновляем цвет кнопки
	update_apply_button_color(apply_button)
	
	print("INI команды извлечены и готовы к применению")

# ===== НОВЫЙ ПАРСЕР КОМАНД =====

func extract_ini_commands(ai_response: String) -> String:
	# Ищем новые команды формата [++N@], [+++N@], [--N@], [---N@]
	var new_commands = extract_new_commands(ai_response)
	return new_commands

func extract_new_commands(ai_response: String) -> String:
	# Ищем новые команды в тексте
	var commands = []
	var regex = RegEx.new()
	regex.compile("\\[\\+\\+[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:[a-zA-Z_]+:[0-9]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:up@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:down@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:up:[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:down:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\-[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+:[a-zA-Z_]+:[^@]*@[^\\]]*\\]")
	
	var results = regex.search_all(ai_response)
	print("Парсер нашел команд: ", results.size())
	
	# Убираем дублирующиеся команды и уже выполненные
	var unique_commands = []
	for result in results:
		var command = result.get_string()
		print("Найдена команда: '", command, "'")
		if command not in unique_commands and command not in executed_commands_history:
			unique_commands.append(command)
			commands.append(command)
		elif command in unique_commands:
			print("Дублирующаяся команда пропущена: '", command, "'")
		elif command in executed_commands_history:
			print("Уже выполненная команда пропущена: '", command, "'")
	
	var result = "\n".join(commands)
	print("Итоговые команды (без дубликатов): '", result, "'")
	return result

func parse_new_command(command: String) -> Dictionary:
	print("=== ПАРСИНГ КОМАНДЫ ===")
	print("Команда для парсинга: '", command, "'")
	
	# Парсим новую команду формата [++func:N@ код], [++for:N@ код], [--N@] и т.д.
	var result = {
		"type": "",
		"code": "",
		"element_type": "",
		"element_name": "",
		"indent_level": 0,
		"direction": "",
		"target_function": "",
		"old_function_name": "",
		"block_search": ""
	}
	
	# Убираем внешние скобки
	var clean_command = command.substr(1, command.length() - 2)
	
	# Определяем тип команды
	if clean_command.begins_with("++"):
		# Новые команды [++func:N@], [++func:name@], [++func:name:level@] и т.д.
		result.type = "insert_by_element"  # Все команды ++ обрабатываем как insert_by_element
		clean_command = clean_command.substr(2)
	elif clean_command.begins_with("--"):
		# Команды удаления по имени [--func:name@]
		result.type = "delete_by_name"
		clean_command = clean_command.substr(2)
	elif clean_command.begins_with("-+"):
		# Новые команды замены [-+func:name@], [-+func:name:new@], [-+func:name:block@]
		result.type = "replace_function"
		clean_command = clean_command.substr(2)
	
	# Извлекаем параметры и код
	var parts = clean_command.split("@", true, 1)
	print("Парсим команду: '", clean_command, "'")
	print("Части после @: ", parts)
	
	if parts.size() >= 1:
		var param_part = parts[0]
		print("Параметры: '", param_part, "'")
		# Проверяем новые команды [++func@], [++func:up@], [++func:down@], [++func:up:Move@] и т.д.
		if param_part.contains(":"):
			var element_parts = param_part.split(":", true, 1)
			print("Элементы параметров: ", element_parts)
			if element_parts.size() >= 1:
				result.element_type = element_parts[0]  # func, for, if, while
				print("Тип элемента: ", result.element_type)
			if element_parts.size() >= 2:
				# Проверяем, есть ли еще двоеточие в оставшейся части
				var remaining_part = element_parts[1]
				if remaining_part.contains(":"):
					# Команда вида [++func:down:Move@] - разбираем дальше
					var sub_parts = remaining_part.split(":", true, 1)
					if sub_parts.size() >= 1:
						if sub_parts[0] == "up" or sub_parts[0] == "down":
							result.direction = sub_parts[0]
							print("Направление: ", result.direction)
							if sub_parts.size() >= 2:
								result.target_function = sub_parts[1]
								print("Целевая функция: ", result.target_function)
				else:
					# Проверяем направление (up/down) или имя функции
					if remaining_part == "up" or remaining_part == "down":
						result.direction = remaining_part
						print("Направление: ", result.direction)
					else:
						# Команды с именами или уровнями отступов
							result.element_name = remaining_part
							print("Имя элемента: ", result.element_name)
							# Проверяем, есть ли уровень отступов [++func:name:level@]
							if element_parts.size() >= 3:
								result.indent_level = int(element_parts[2])
								print("Уровень отступов: ", result.indent_level)
		else:
			# Команды без параметров [++func@] - в конец файла
			result.element_type = param_part
			# Устанавливаем флаг для команды без параметров
			result.direction = "end"
	
	if parts.size() >= 2:
		result.code = parts[1].strip_edges()
		# Обрабатываем экранированные символы
		result.code = result.code.replace("\\n", "\n")
		result.code = result.code.replace("\\t", "\t")
	
	# Дополнительная обработка для команд замены [-+func:name@]
	if result.type == "replace_function":
		var param_part = ""
		if parts.size() >= 1:
			param_part = parts[0]
		
		print("=== ОТЛАДКА ПАРСИНГА ЗАМЕНЫ ===")
		print("param_part: '", param_part, "'")
		
		if param_part.contains(":"):
			var element_parts = param_part.split(":", true, 1)
			print("element_parts: ", element_parts)
			if element_parts.size() >= 1:
				result.element_type = element_parts[0]  # func
			if element_parts.size() >= 2:
				var remaining_part = element_parts[1]
				print("remaining_part: '", remaining_part, "'")
				# Проверяем, есть ли еще двоеточие в remaining_part
				if remaining_part.contains(":"):
					# Команда [-+func:Go:new@] - заменить функцию Go на новую с именем new
					var sub_parts = remaining_part.split(":", true, 1)
					if sub_parts.size() >= 1:
						result.old_function_name = sub_parts[0]  # Go
						print("Установлен old_function_name: ", result.old_function_name)
					if sub_parts.size() >= 2:
						if sub_parts[1] == "new":
							result.element_name = "new"
							print("Установлен element_name: ", result.element_name)
						else:
							# Команда [-+func:Go:if3<5@] - искать блок if 3<5 в функции Go
							result.block_search = sub_parts[1]
				elif remaining_part == "new":
					# Команда [-+func:Move:new@] - заменить функцию на "new"
					result.element_name = "new"
					result.old_function_name = element_parts[0]  # Move
				elif remaining_part.contains("if") or remaining_part.contains("for") or remaining_part.contains("while"):
					# Команда [-+func:Move:if3<5@] - искать блок if 3<5
					result.block_search = remaining_part
				else:
					# Команда [-+func:Move@] - заменить содержимое функции
					result.element_name = remaining_part
		else:
			# Команда [-+func@] - заменить содержимое функции
			result.element_type = param_part
	
	print("Результат парсинга: ", result)
	return result



func find_element_by_name(lines: Array, element_type: String, name: String) -> int:
	# Находим элемент по имени и возвращаем номер строки его начала
	print("Ищем элемент типа '", element_type, "' с именем '", name, "'")
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		print("Строка ", i + 1, ": '", line, "'")
		# Ищем функцию с именем (может быть с параметрами или без)
		if line.begins_with(element_type + " " + name):
			print("Найдена на строке: ", i + 1)
			return i + 1  # Возвращаем номер строки (от 1)
	
	print("Элемент не найден")
	# Если элемент не найден, возвращаем -1
	return -1

func find_insert_position_in_element(lines: Array, element_start: int, indent_level: int) -> int:
	# Находим позицию для вставки внутри элемента с указанным уровнем отступов
	if element_start <= 0 or element_start > lines.size():
		return lines.size()  # Возвращаем конец файла если позиция некорректная
		
	var element_end = find_block_end(lines, element_start - 1)
	var target_indent = indent_level * 4  # 4 пробела на уровень
	
	# Ищем подходящую позицию внутри элемента
	for i in range(element_start, element_end):
		if i >= lines.size():
			break
		var line = lines[i]
		var line_indent = get_line_indent(line)
		
		# Если находим строку с нужным отступом или большим, вставляем перед ней
		if line_indent >= target_indent:
			return i + 1  # Возвращаем номер строки (от 1)
	
	# Если не нашли подходящую позицию, вставляем перед концом элемента
	return element_end

func find_first_function_position(lines: Array) -> int:
	# Находим позицию первой функции
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.begins_with("func "):
			return i + 1  # Возвращаем номер строки (от 1)
	return lines.size()  # Если функций нет, возвращаем конец файла

func find_position_relative_to_function(lines: Array, direction: String, target_function: String) -> int:
	# Находим позицию выше или ниже указанной функции
	print("Ищем функцию: ", target_function)
	var function_pos = find_element_by_name(lines, "func", target_function)
	print("Найдена функция на позиции: ", function_pos)
	
	if function_pos > 0:
		if direction == "up":
			print("Вставляем выше функции на позиции: ", function_pos)
			return function_pos  # Вставить выше функции
		elif direction == "down":
			var function_end = find_block_end(lines, function_pos - 1)
			print("Конец функции на позиции: ", function_end, ", вставляем после на позиции: ", function_end + 1)
			return function_end + 1  # Вставить после функции
	
	print("Функция не найдена, вставляем в конец файла")
	return lines.size()  # Если функция не найдена, в конец файла

func detect_indent_type(lines: Array) -> bool:
	# Возвращает true если файл использует табы, false если пробелы
	if lines.size() > 0:
		for line in lines:
			if line.length() > 0 and line[0] == "\t":
				return true
			elif line.length() > 0 and line[0] == " ":
				return false
	return false  # По умолчанию пробелы

func create_indent(level: int, use_tabs: bool) -> String:
	# Создает отступ указанного уровня
	if use_tabs:
		return "\t".repeat(level)
	else:
		return "    ".repeat(level)

func insert_multiline_code(lines: Array, position: int, code: String):
	# Вставляет многострочный код в указанную позицию
	print("=== ВСТАВКА МНОГОСТРОЧНОГО КОДА ===")
	print("Позиция вставки: ", position)
	print("Код для вставки: '", code, "'")
	
	var code_lines = code.split("\n")
	print("Строк кода: ", code_lines.size())
	
	# Определяем тип отступов в файле (табы или пробелы)
	var use_tabs = detect_indent_type(lines)
	print("Используем табы: ", use_tabs)
	
	# Вставляем строки в обратном порядке, чтобы сохранить порядок
	for i in range(code_lines.size() - 1, -1, -1):
		var line = code_lines[i]
		print("Вставляем строку ", i + 1, ": '", line, "'")
		
		# Конвертируем отступы если нужно
		if use_tabs:
			# Заменяем 4 пробела на таб
			line = line.replace("    ", "\t")
		
		if position > 0 and position <= lines.size():
			lines.insert(position - 1, line)
			print("Вставлено на позицию: ", position - 1)
		else:
			lines.append(line)
			print("Добавлено в конец файла")

func execute_new_commands(commands: String, current_code: String) -> String:
	print("=== ОТЛАДКА: execute_new_commands ===")
	print("Входные команды: ", commands)
	
	# Выполняем новые команды
	var lines = current_code.split("\n")
	
	# Парсим команды напрямую, без проверки executed_commands_history
	var regex = RegEx.new()
	regex.compile("\\[\\+\\+[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:[a-zA-Z_]+:[0-9]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:up@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:down@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:up:[a-zA-Z_]+@[^\\]]*\\]|\\[\\+\\+[a-zA-Z_]+:down:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\-[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+:[a-zA-Z_]+@[^\\]]*\\]|\\[\\-\\+[a-zA-Z_]+:[a-zA-Z_]+:[^@]*@[^\\]]*\\]")
	
	var results = regex.search_all(commands)
	var command_list = []
	for result in results:
		var command = result.get_string()
		print("Найдена команда для выполнения: '", command, "'")
		command_list.append(command)
	
	print("Команд для выполнения: ", command_list.size())
	
	if command_list.size() == 0:
		print("Нет команд для выполнения")
		return current_code
	
	for command in command_list:
		var parsed = parse_new_command(command)
		lines = execute_single_new_command(parsed, lines)
	
	return "\n".join(lines)

func execute_single_new_command(parsed: Dictionary, lines: Array) -> Array:
	
	match parsed.type:

		
		"insert_by_element":
			# Добавляем код в указанную позицию
			if parsed.direction == "end":
				# Команда без параметров [++func@] - в конец файла
				insert_multiline_code(lines, lines.size(), parsed.code)
			elif parsed.direction != "":
				# Команды с направлениями [++func:up@], [++func:down@], [++func:up:Move@], [++func:down:Move@]
				var target_pos = 0
				if parsed.target_function != "":
					# Вставка относительно конкретной функции [++func:up:Move@], [++func:down:Move@]
					target_pos = find_position_relative_to_function(lines, parsed.direction, parsed.target_function)
				else:
					# Вставка относительно первой функции [++func:up@], [++func:down@]
					if parsed.direction == "up":
						target_pos = find_first_function_position(lines)
					else:  # down
						target_pos = lines.size()  # В конец файла
				
				# Проверяем границы перед вставкой
				if target_pos > 0 and target_pos <= lines.size():
					insert_multiline_code(lines, target_pos, parsed.code)
				else:
					# Если позиция некорректная, добавляем в конец
					insert_multiline_code(lines, lines.size(), parsed.code)
			elif parsed.element_name != "":
				# Старые команды с именами [++func:name@] или [++func:name:level@]
				var element_start = find_element_by_name(lines, parsed.element_type, parsed.element_name)
				if element_start > 0:
					if parsed.indent_level > 0:
						# Вставка с указанным уровнем отступов [++func:name:level@]
						var insert_pos = find_insert_position_in_element(lines, element_start, parsed.indent_level)
						var use_tabs = detect_indent_type(lines)
						var indent = create_indent(parsed.indent_level, use_tabs)  # Создаем отступ
						var indented_code = indent + parsed.code
						if insert_pos > 0 and insert_pos <= lines.size():
							insert_multiline_code(lines, insert_pos, indented_code)
						else:
							insert_multiline_code(lines, lines.size(), indented_code)
					else:
						# Вставка на 0 уровень [++func:name@]
						var element_end = find_block_end(lines, element_start - 1)
						if element_end >= 0 and element_end <= lines.size():
							insert_multiline_code(lines, element_end + 1, parsed.code)
						else:
							insert_multiline_code(lines, lines.size(), parsed.code)
				else:
					# Если элемент не найден, добавляем в конец
					insert_multiline_code(lines, lines.size(), parsed.code)

			else:
				# Команда без параметров [++func@] - в конец файла
				lines.append(parsed.code)
		

		
		"delete_by_name":
			# Удаляем элемент по имени
			var target_line = find_element_by_name(lines, parsed.element_type, parsed.element_name)
			if target_line > 0:
				# Находим конец элемента и удаляем весь блок
				var start_line = target_line - 1  # Конвертируем в индекс массива
				var end_line = find_block_end(lines, start_line)
				
				# Удаляем весь блок
				for i in range(start_line, end_line + 1):
					if start_line < lines.size():
						lines.remove_at(start_line)
		
		"replace_function":
			# Новые команды замены [-+func:name@], [-+func:name:new@], [-+func:name:block@]
			print("Обрабатываем команду замены функции")
			print("parsed.element_name: ", parsed.element_name)
			print("parsed.old_function_name: ", parsed.old_function_name)
			
			if parsed.element_name == "new":
				# Команда [-+func:Move:new@ код] - заменить функцию на новую с именем "new"
				print("Ищем функцию для замены: ", parsed.old_function_name)
				var target_line = find_element_by_name(lines, parsed.element_type, parsed.old_function_name)
				if target_line > 0:
					# Удаляем старую функцию
					var start_line = target_line  # Индекс строки с объявлением функции (без вычитания 1)
					var end_line = find_function_end(lines, start_line)
					print("Функция найдена на строке: ", target_line)
					print("Удаляем строки с ", start_line, " по ", end_line)
					
					# Удаляем строки в обратном порядке, чтобы индексы не сбивались
					for i in range(end_line, start_line - 1, -1):
						if i < lines.size():
							print("Удаляем строку ", i + 1, ": '", lines[i], "'")
							lines.remove_at(i)
					
					# Вставляем новый код на позицию start_line (где была функция)
					if parsed.code != "":
						print("Вставляем новый код на позицию: ", start_line)
						insert_multiline_code(lines, start_line, parsed.code)
			else:
				# Команда [-+func:Move@ код] - заменить содержимое функции
				var target_line = find_element_by_name(lines, parsed.element_type, parsed.element_name)
				if target_line > 0:
					var start_line = target_line  # Индекс строки с объявлением функции (без вычитания 1)
					var end_line = find_function_end(lines, start_line)
					print("Заменяем содержимое функции, строки с ", start_line + 1, " по ", end_line)
					
					# Сохраняем строку с объявлением функции
					var function_declaration = lines[start_line]
					
					# Удаляем содержимое функции (но не объявление) в обратном порядке
					for i in range(end_line, start_line, -1):
						if i < lines.size():
							lines.remove_at(i)
					
					# Вставляем новый код
					if parsed.code != "":
						insert_multiline_code(lines, start_line + 1, parsed.code)
	

	
	return lines

func find_block_end(lines: Array, start_line: int) -> int:
	# Находим конец блока кода (функция, if, for, while и т.д.)
	if start_line >= lines.size():
		return start_line
	
	var start_indent = get_line_indent(lines[start_line])
	var current_line = start_line + 1
	
	while current_line < lines.size():
		var line = lines[current_line]
		var line_indent = get_line_indent(line)
		
		# Если отступ меньше или равен начальному, блок закончился
		if line_indent <= start_indent and line.strip_edges() != "":
			break
		
		current_line += 1
	
	return current_line - 1

func find_function_end(lines: Array, start_line: int) -> int:
	# Находим конец функции с учетом отступов
	if start_line >= lines.size():
		return start_line
	
	var current_line = start_line  # Начинаем с самой строки объявления функции
	print("Ищем конец функции, начиная со строки: ", start_line + 1)
	
	# Получаем отступ объявления функции
	var function_declaration = lines[start_line]
	var function_indent = get_line_indent(function_declaration)
	print("Отступ объявления функции: ", function_indent)
	
	# Ищем конец функции по отступам
	while current_line < lines.size():
		var line = lines[current_line]
		var line_indent = get_line_indent(line)
		var stripped_line = line.strip_edges()
		
		print("Строка ", current_line + 1, " (отступ ", line_indent, "): '", stripped_line, "'")
		
		# Если отступ меньше или равен отступу функции И строка не пустая
		# значит функция закончилась
		if line_indent <= function_indent and stripped_line != "":
			# Проверяем, что это не продолжение многострочного выражения
			if not is_continuation_line(stripped_line):
				print("Найден конец функции на строке: ", current_line - 1)
				return current_line - 1
		
		current_line += 1
	
	print("Достигнут конец файла, конец на строке: ", lines.size() - 1)
	return lines.size() - 1

func is_continuation_line(line: String) -> bool:
	# Проверяем, является ли строка продолжением многострочного выражения
	var stripped = line.strip_edges()
	
	# Если строка заканчивается на операторы продолжения
	if stripped.ends_with("\\") or stripped.ends_with("(") or stripped.ends_with("["):
		return true
	
	# Если строка начинается с операторов продолжения
	if stripped.begins_with(")") or stripped.begins_with("]") or stripped.begins_with(","):
		return true
	
	# Если это часть многострочной строки
	if stripped.begins_with('"""') or stripped.ends_with('"""'):
		return true
	
	return false

func get_line_indent(line: String) -> int:
	# Получаем количество пробелов в начале строки
	var indent = 0
	for char in line:
		if char == " ":
			indent += 1
		elif char == "\t":
			indent += 4  # Табуляция = 4 пробела
		else:
			break
	return indent

func get_line_indent_string(line: String) -> String:
	# Получаем строку отступов из строки
	var indent = ""
	for char in line:
		if char == " ":
			indent += " "
		elif char == "\t":
			indent += "    "  # Табуляция = 4 пробела
		else:
			break
	return indent





# Функция для обновления списка ошибок Godot
func update_errors_list(errors_list: ItemList):
	errors_list.clear()
	
	# Получаем ошибки из редактора Godot
	var editor_interface = get_editor_interface()
	if not editor_interface:
		return
	
	# Массивы для разных типов проблем
	var errors = []  # Красные - критические ошибки
	var warnings = []  # Желтые - предупреждения
	var info = []  # Синие - информация
	
	# Получаем ошибки из редактора скриптов
	var script_editor = editor_interface.get_script_editor()
	if script_editor:
		# Получаем все открытые скрипты
		var open_scripts = script_editor.get_open_scripts()
		for script in open_scripts:
			if script:
				var file_path = script.resource_path
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					var content = file.get_as_text()
					file.close()
					
					# Проверяем на синтаксические ошибки
					var lines = content.split("\n")
					for i in range(lines.size()):
						var line = lines[i]
						var line_number = i + 1
						
						# Проверяем на незакрытые скобки (ОШИБКА)
						var open_brackets = line.count("(") + line.count("[") + line.count("{")
						var close_brackets = line.count(")") + line.count("]") + line.count("}")
						if open_brackets != close_brackets:
							errors.append("ОШИБКА: %s:%d - Несбалансированные скобки" % [file_path.get_file(), line_number])
						
						# Проверяем на незакрытые кавычки (ОШИБКА)
						var quotes = line.count("\"")
						if quotes % 2 != 0:
							errors.append("ОШИБКА: %s:%d - Незакрытые кавычки" % [file_path.get_file(), line_number])
						
						# Проверяем на отсутствие двоеточия после ключевых слов (ОШИБКА)
						var stripped_line = line.strip_edges()
						if stripped_line.begins_with("func ") and not stripped_line.ends_with(":"):
							errors.append("ОШИБКА: %s:%d - Отсутствует двоеточие после func" % [file_path.get_file(), line_number])
						elif stripped_line.begins_with("if ") and not stripped_line.ends_with(":"):
							errors.append("ОШИБКА: %s:%d - Отсутствует двоеточие после if" % [file_path.get_file(), line_number])
						elif stripped_line.begins_with("for ") and not stripped_line.ends_with(":"):
							errors.append("ОШИБКА: %s:%d - Отсутствует двоеточие после for" % [file_path.get_file(), line_number])
						elif stripped_line.begins_with("while ") and not stripped_line.ends_with(":"):
							errors.append("ОШИБКА: %s:%d - Отсутствует двоеточие после while" % [file_path.get_file(), line_number])
						elif stripped_line.begins_with("match ") and not stripped_line.ends_with(":"):
							errors.append("ОШИБКА: %s:%d - Отсутствует двоеточие после match" % [file_path.get_file(), line_number])
						elif stripped_line.begins_with("class_name ") and not stripped_line.ends_with(":"):
							errors.append("ОШИБКА: %s:%d - Отсутствует двоеточие после class_name" % [file_path.get_file(), line_number])
						elif stripped_line.begins_with("extends ") and not stripped_line.ends_with(":"):
							errors.append("ОШИБКА: %s:%d - Отсутствует двоеточие после extends" % [file_path.get_file(), line_number])
						
						# Проверяем на неиспользуемые переменные (ПРЕДУПРЕЖДЕНИЕ)
						if "var " in line and "=" in line:
							var var_name = line.split("var ")[1].split("=")[0].strip_edges()
							if var_name != "" and not content.contains(" " + var_name + " ") and not content.contains("(" + var_name + ")"):
								warnings.append("ПРЕДУПРЕЖДЕНИЕ: %s:%d - Возможно неиспользуемая переменная '%s'" % [file_path.get_file(), line_number, var_name])
	
	# Добавляем ошибки (красные)
	for error in errors:
		var index = errors_list.add_item(error)
		errors_list.set_item_custom_fg_color(index, Color.RED)
	
	# Добавляем предупреждения (желтые)
	for warning in warnings:
		var index = errors_list.add_item(warning)
		errors_list.set_item_custom_fg_color(index, Color.YELLOW)
	
	# Добавляем информацию (синие)
	for info_item in info:
		var index = errors_list.add_item(info_item)
		errors_list.set_item_custom_fg_color(index, Color.CYAN)
	
	# Если нет проблем, добавляем подсказку
	if errors.size() == 0 and warnings.size() == 0:
		var index = errors_list.add_item("✅ Нет обнаруженных ошибок")
		errors_list.set_item_custom_fg_color(index, Color.GREEN)
		index = errors_list.add_item("💡 Добавьте ошибку вручную через кнопку 'Добавить ошибку'")
		errors_list.set_item_custom_fg_color(index, Color.CYAN)
	
	# Добавляем системные сообщения (синие)
	for system_msg in system_messages:
		var index = errors_list.add_item(system_msg)
		errors_list.set_item_custom_fg_color(index, Color.CYAN)
	
	# Добавляем кнопку для ручного добавления
	var add_index = errors_list.add_item("➕ Добавить ошибку вручную...")
	errors_list.set_item_custom_fg_color(add_index, Color.CYAN)
	
	print("Список ошибок обновлен: %d ошибок, %d предупреждений, %d системных сообщений" % [errors.size(), warnings.size(), system_messages.size()])

# Функция для показа диалога добавления ошибки
func show_add_error_dialog(errors_list: ItemList):
	# Проверяем, не открыт ли уже диалог добавления ошибок
	for dialog in open_dialogs:
		if dialog.title == "Добавить ошибку" and dialog.visible:
			print("Диалог добавления ошибки уже открыт!")
			return
	
	var dialog = AcceptDialog.new()
	dialog.title = "Добавить ошибку"
	dialog.size = Vector2(600, 400)
	
	# Создаем контейнер
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	# Заголовок
	var label = Label.new()
	label.text = "Введите текст ошибки из консоли Godot:"
	vbox.add_child(label)
	
	# Поле для ввода ошибки
	var error_edit = TextEdit.new()
	error_edit.custom_minimum_size = Vector2(580, 250)
	error_edit.placeholder_text = "Например:\nERROR: res://test.gd:10 - Parse Error: Invalid syntax\nWARNING: res://test.gd:15 - Unused variable 'x'\nWARNING: editor/editor_file_system.cpp:1358 - UID duplicate detected\n\nСоветы:\n- Начинайте с ERROR: для красных ошибок\n- Начинайте с WARNING: для желтых предупреждений\n- Начинайте с INFO: для синей информации\n- Системные сообщения Godot тоже можно добавлять"
	vbox.add_child(error_edit)
	
	# Кнопки для быстрого добавления системных сообщений
	var quick_buttons = HBoxContainer.new()
	vbox.add_child(quick_buttons)
	
	var uid_duplicate_button = Button.new()
	uid_duplicate_button.text = "UID Duplicate"
	uid_duplicate_button.tooltip_text = "Добавить предупреждение о дублировании UID"
	uid_duplicate_button.pressed.connect(func():
		error_edit.text = "WARNING: editor/editor_file_system.cpp:1358 - UID duplicate detected between res://plugin/icon.svg and res://addons/smart_replace/plugin/icon.svg."
	)
	quick_buttons.add_child(uid_duplicate_button)
	
	var debug_server_button = Button.new()
	debug_server_button.text = "Debug Server"
	debug_server_button.tooltip_text = "Добавить сообщение о запуске debug сервера"
	debug_server_button.pressed.connect(func():
		error_edit.text = "INFO: --- Debug adapter server started on port 6006 ---"
	)
	quick_buttons.add_child(debug_server_button)
	
	var language_server_button = Button.new()
	language_server_button.text = "Language Server"
	language_server_button.tooltip_text = "Добавить сообщение о запуске language сервера"
	language_server_button.pressed.connect(func():
		error_edit.text = "INFO: --- GDScript language server started on port 6005 ---"
	)
	quick_buttons.add_child(language_server_button)
	
	# Кнопки
	var buttons = HBoxContainer.new()
	vbox.add_child(buttons)
	
	var add_button = Button.new()
	add_button.text = "Добавить"
	add_button.pressed.connect(func():
		var error_text = error_edit.text.strip_edges()
		if error_text != "":
			var index = errors_list.add_item(error_text)
			
			# Автоматически определяем цвет на основе префикса
			if error_text.begins_with("ERROR:"):
				errors_list.set_item_custom_fg_color(index, Color.RED)
			elif error_text.begins_with("WARNING:"):
				errors_list.set_item_custom_fg_color(index, Color.YELLOW)
			elif error_text.begins_with("INFO:"):
				errors_list.set_item_custom_fg_color(index, Color.CYAN)
			else:
				errors_list.set_item_custom_fg_color(index, Color.WHITE)
			
			dialog.queue_free()
			print("Ошибка добавлена в список: ", error_text)
	)
	buttons.add_child(add_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Отмена"
	cancel_button.pressed.connect(func():
		dialog.queue_free()
	)
	buttons.add_child(cancel_button)
	
	# Добавляем диалог в массив открытых диалогов
	open_dialogs.append(dialog)
	
	# Добавляем обработчик закрытия
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			open_dialogs.erase(dialog)
	)
	
	# Показываем диалог
	get_editor_interface().get_base_control().add_child(dialog)
	dialog.popup_centered()

# Функция для сохранения истории выполненных команд
func save_executed_commands_history():
	var file = FileAccess.open(EXECUTED_COMMANDS_HISTORY_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(executed_commands_history))
		file.close()

# Функция для загрузки истории выполненных команд
func load_executed_commands_history():
	if FileAccess.file_exists(EXECUTED_COMMANDS_HISTORY_FILE):
		var file = FileAccess.open(EXECUTED_COMMANDS_HISTORY_FILE, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var json = JSON.new()
			var parse_result = json.parse(content)
			if parse_result == OK:
				executed_commands_history = json.data
			else:
				executed_commands_history = []
		else:
			executed_commands_history = []
	else:
		executed_commands_history = []

	
