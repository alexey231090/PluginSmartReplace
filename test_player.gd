extends CharacterBody2D

var speed = 300
var health = 100

func _ready():
	print("Player ready")

func _process(delta):
	pass

# Тестовая функция для теста плагина
func theta_plugin_test():
		print("Theta plugin test function called!")

# Проверяет, жив ли игрок
func is_alive():
		return health > 0
