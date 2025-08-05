extends Node2D

var health = 100
var speed = 200

func _ready():
	print("Игрок готов!")

func move(delta):
	if health > 0:
		position.x += speed * delta

func attack():
	print("Атака!")
	return true

func take_damage(amount):
	health -= amount
	if health <= 0:
		die()

func die():
	print("Игрок умер!")
	queue_free() 