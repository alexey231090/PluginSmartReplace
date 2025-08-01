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
	print("Player moved!")

#Теперь функция foo принимает 5 параметров
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
		print("Это изменённая тестовая функция!")
		return true

# Функция для вывода информации о скрипте
func get_script_info():
		print("Script path: ", self.script.resource_path)
		print("Script name: ", self.script.name)
