# Глобальные настройки

extends Node
# Переменные игрока
var player_health = 100
var player_speed = 5.0
var givmy_lol_pass = 34.2

func _ready():
	print(34)

# Двигает игрока в заданном направлении
func move_player(direction, speed):
		var velocity = direction * speed
		print("Player moved!", velocity)
		
func foo(a, b, c, d, e):
	print(a, b, c, d, e)

# Описание функции
func test_function():
	var condition = 4 < 8
	if condition:
		print("True")
	else:
		print("False")

# Новая тестовая функция (ещё раз)

#Изменённая тестовая функция
func test_function_2():
		print("Это ещё раз изменённая тестовая функция!")
		return false
func get_script_info():
	print("Script path: ", self.script.resource_path)
	print("Script name: ", self.script.name)

# Новая функция
func test_function_3():
	pass

# Супер тестовая функция
func super_test():
		print("Это супер тестовая функция!")

# Тестовая функция для проверки
func test_function_test():
		print("Это тестовая функция для теста!")
		return true
