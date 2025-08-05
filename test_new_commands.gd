extends Node2D

var health = 100
var speed = 200
var damage = 10

func _ready():
	print("Игрок готов!")

func move(delta):
	if health > 0:
		position.x += speed * delta

func attack():
	print("Атака!")
	return true

func die():
	print("Игрок умер!")
	queue_free() 
