extends CharacterBody2D

# Демонстрационный файл для тестирования AI редактора
# Этот файл содержит простой код для демонстрации возможностей AI

var speed = 300
var health = 100

func _ready():
	print("Игрок готов!")

func _physics_process(delta):
	handle_movement(delta)

func handle_movement(delta):
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	
	velocity = direction * speed
	move_and_slide()

func take_damage(amount):
	health -= amount
	if health <= 0:
		die()

func die():
	print("Игрок умер!")
	queue_free() 