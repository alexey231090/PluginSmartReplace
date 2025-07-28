extends CharacterBody2D

var speed = 300
var health = 100

func _ready():
	print("Player ready")

func _process(delta):
	handle_movement(delta)

func handle_movement(delta):
	if Input.is_action_pressed("ui_right"):
		position.x += speed * delta
	if Input.is_action_pressed("ui_left"):
		position.x -= speed * delta

func take_damage(amount):
	health -= amount
	if health <= 0:
		queue_free()

func heal(amount):
	health = min(100, health + amount) 