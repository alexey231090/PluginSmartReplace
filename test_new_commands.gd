extends Node2D

var health = 100
var speed = 200
var damage = 10

func _ready():
	print("Игрок готов!")



func attack():
	print("Атака!")
	return true

func die():
	print("Игрок умер!")
	queue_free() 
