# Примеры новых команд для тестирования

## Тестовый файл: test_new_commands.gd

### Исходный код:
```gdscript
extends Node2D

var health = 100
var speed = 200

func _ready():
	print("Игрок готов!")

func move():
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
```

## Примеры команд для тестирования

### 1. Добавление кода
```
[++3@ var mana = 50]
```
**Результат:** Добавит `var mana = 50` в строку 3, сдвинув остальные строки вниз.

### 2. Замена функции (умная замена)
```
[+++7@ func attack():\n    if mana >= 10:\n        print("Магическая атака!")\n        mana -= 10\n        return true\n    else:\n        print("Недостаточно маны!")\n        return false]
```
**Результат:** Заменит функцию `attack()` целиком с новой логикой.

### 3. Удаление переменной
```
[--2@]
```
**Результат:** Удалит строку `var health = 100`.

### 4. Глубокое удаление функции
```
[---7@]
```
**Результат:** Удалит функцию `attack()` целиком.

### 5. Добавление в конец файла
```
[++15@ func heal(amount):\n    health = min(health + amount, 100)\n    print("Восстановлено здоровья: ", amount)]
```
**Результат:** Добавит новую функцию в конец файла.

## Комбинированный пример

```
Обновляю код игрока:

[++3@ var mana = 50]
[+++7@ func attack():\n    if mana >= 10:\n        print("Магическая атака!")\n        mana -= 10\n        return true\n    else:\n        print("Недостаточно маны!")\n        return false]
[--2@]
[++15@ func heal(amount):\n    health = min(health + amount, 100)\n    print("Восстановлено здоровья: ", amount)]

Теперь у вас есть система маны и лечения!
```

## Ожидаемый результат после выполнения команд:

```gdscript
extends Node2D

var mana = 50
var speed = 200

func _ready():
	print("Игрок готов!")

func move():
	if health > 0:
		position.x += speed * delta

func attack():
	if mana >= 10:
		print("Магическая атака!")
		mana -= 10
		return true
	else:
		print("Недостаточно маны!")
		return false

func take_damage(amount):
	health -= amount
	if health <= 0:
		die()

func die():
	print("Игрок умер!")
	queue_free()

func heal(amount):
	health = min(health + amount, 100)
	print("Восстановлено здоровья: ", amount)
```

## Тестирование в плагине

1. Откройте файл `test_new_commands.gd` в Godot
2. Нажмите кнопку "Smart Replace"
3. Перейдите на вкладку "INI"
4. Вставьте команды из примеров выше
5. Нажмите "Выполнить INI"
6. Проверьте результат в предварительном просмотре 