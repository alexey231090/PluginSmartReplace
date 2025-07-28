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

# Уменьшает здоровье игрока