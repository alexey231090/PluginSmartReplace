# Руководство по тестированию AI редактора

## 🧪 Тестирование плагина

### 1. Подготовка к тестированию

1. **Установите плагин:**
   - Скопируйте папку `addons/smart_replace` в ваш проект Godot
   - Включите плагин в Project Settings → Plugins

2. **Настройте AI:**
   - Получите доступ к любому AI (DeepSeek, ChatGPT, Claude и т.д.)
   - Дайте AI инструкции по использованию INI команд
   - AI должен отвечать с скрытыми командами

### 2. Тестирование AI редактора

#### Шаг 1: Откройте тестовый файл
- Откройте файл `test_ai_demo.gd` в редакторе Godot
- Убедитесь, что файл содержит код для тестирования

#### Шаг 2: Запустите AI редактор
- Нажмите кнопку "Smart Replace" в панели инструментов
- Перейдите на вкладку "AI Редактор"

#### Шаг 3: Подготовьте ответ от AI
- Получите ответ от AI с скрытыми INI командами
- Убедитесь, что команды используют правильные маркеры
- Скопируйте весь ответ AI

#### Шаг 4: Протестируйте ответы AI

**Тест 1: Добавление функции**
```
Я добавлю функцию для атаки с параметрами damage и range.

=[command]=
[add_function]
name=attack_enemy
comment=Атака врага с уроном
<cod>
    if enemy and enemy.has_method("take_damage"):
        enemy.take_damage(damage)
        play_attack_animation()
<end_cod>
=[end]=

Теперь у вас есть функция атаки!
```

**Тест 2: Добавление констант**
```
Я добавлю игровые константы для лучшей организации кода.

=[command]=
[add_code]
position=2
<cod>
# Игровые константы
const MAX_HEALTH = 100
const ATTACK_DAMAGE = 25
<end_cod>
=[end]=

Константы добавлены и готовы к использованию.
```

**Тест 3: Замена логики**
```
Я улучшу функцию движения игрока, добавив плавное ускорение.

=[command]=
[replace_function]
name=handle_movement
comment=Плавное движение с ускорением
<cod>
    var direction = Vector2.ZERO
    if Input.is_action_pressed("ui_right"):
        direction.x += 1
    # ... остальные направления
    velocity = velocity.lerp(direction * speed, 0.1)
    move_and_slide()
<end_cod>
=[end]=

Движение теперь стало более плавным!
```

**Тест 4: Удаление кода**
```
Я удалю неиспользуемую функцию die.

=[command]=
[delete_function]
name=die
=[end]=

Функция удалена, код стал чище.
```

### 3. Проверка результатов

После каждого ответа AI проверьте:

1. **Извлечение команд:** Плагин должен найти INI команды в ответе
2. **Предварительный просмотр:** Нажмите "Предварительный просмотр" для проверки изменений
3. **Выполнение команд:** Нажмите "Выполнить команды AI" для применения
4. **Результат в коде:** Проверьте, что изменения применились корректно

### 4. Ожидаемые результаты

#### Для теста 1 (добавление функции атаки):
```gdscript
func attack_enemy(damage: int, range: float):
    # Код функции атаки
    if enemy and enemy.has_method("take_damage"):
        enemy.take_damage(damage)
```

#### Для теста 2 (добавление констант):
```gdscript
# Игровые константы
const MAX_HEALTH = 100
const ATTACK_SPEED = 1.5
```

#### Для теста 3 (замена логики движения):
```gdscript
func handle_movement(delta):
    var direction = Vector2.ZERO
    
    if Input.is_action_pressed("ui_right"):
        direction.x += 1
    # ... остальные направления
    
    # Плавное движение с ускорением
    velocity = velocity.lerp(direction * speed, 0.1)
    move_and_slide()
```

### 5. Устранение проблем

#### AI не генерирует команды:
- Проверьте, что AI получил инструкции по использованию INI команд
- Убедитесь, что AI использует правильные маркеры
- Попробуйте переформулировать запрос к AI

#### Команды извлекаются неправильно:
- Проверьте синтаксис команд в ответе AI
- Используйте "Предварительный просмотр" перед применением
- При необходимости отредактируйте команды вручную

#### Ошибки при применении:
- Проверьте, что файл открыт в редакторе
- Убедитесь, что команды синтаксически корректны
- Проверьте логи Godot для деталей ошибок

### 6. Дополнительные тесты

#### Тест производительности:
- Попробуйте несколько запросов подряд
- Проверьте время ответа AI
- Убедитесь, что плагин не замедляет редактор

#### Тест сложных ответов AI:
```
Я создам систему инвентаря с возможностью добавления и удаления предметов.

=[command]=
[add_code]
position=2
<cod>
# Система инвентаря
var inventory = []
var max_inventory_size = 20
<end_cod>
=[end]=

=[command]=
[add_function]
name=add_item
args=item
comment=Добавляет предмет в инвентарь
<cod>
    if inventory.size() < max_inventory_size:
        inventory.append(item)
        return true
    return false
<end_cod>
=[end]=

=[command]=
[add_function]
name=remove_item
args=item
comment=Удаляет предмет из инвентаря
<cod>
    var index = inventory.find(item)
    if index >= 0:
        inventory.remove_at(index)
        return true
    return false
<end_cod>
=[end]=

Система инвентаря готова к использованию!
```

```
Я создам систему сохранения прогресса игрока в файл.

=[command]=
[add_function]
name=save_game
comment=Сохраняет прогресс игрока в файл
<cod>
    var save_data = {
        "health": health,
        "position": position,
        "inventory": inventory
    }
    var file = FileAccess.open("user://savegame.save", FileAccess.WRITE)
    file.store_string(JSON.stringify(save_data))
    file.close()
<end_cod>
=[end]=

=[command]=
[add_function]
name=load_game
comment=Загружает прогресс игрока из файла
<cod>
    if FileAccess.file_exists("user://savegame.save"):
        var file = FileAccess.open("user://savegame.save", FileAccess.READ)
        var save_data = JSON.parse_string(file.get_as_text())
        file.close()
        health = save_data.health
        position = save_data.position
        inventory = save_data.inventory
<end_cod>
=[end]=

Система сохранения готова!
```

### 7. Отчет о тестировании

После тестирования заполните:

- [ ] AI редактор запускается без ошибок
- [ ] API ключ сохраняется корректно
- [ ] Запросы обрабатываются успешно
- [ ] INI команды генерируются правильно
- [ ] Предварительный просмотр работает
- [ ] Изменения применяются корректно
- [ ] Интерфейс удобен в использовании

## 🎯 Критерии успешного тестирования

1. **Функциональность:** Все основные функции работают
2. **Производительность:** Плагин не замедляет редактор
3. **Удобство:** Интерфейс интуитивно понятен
4. **Надежность:** Ошибки обрабатываются корректно
5. **Безопасность:** API ключ защищен

---

**Удачного тестирования! 🚀** 