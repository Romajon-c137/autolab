# Auto Inspection Django + Flutter

Проект состоит из двух частей:

- `backend` - Django сервер и админка осмотров авто
- `mobile` - Flutter приложение для создания осмотра авто
- `web` - Next.js web-интерфейс для операторов и отчетов

## Запуск backend

```bash
cd backend
python3 manage.py runserver 0.0.0.0:8000
```

Проверка на ноутбуке:

```bash
curl http://127.0.0.1:8000/api/ping/
```

Узнать IP ноутбука в Wi-Fi сети:

```bash
ipconfig getifaddr en0
```

Если команда ничего не вернула, посмотрите IP в настройках Wi-Fi. Обычно он выглядит так:

```text
192.168.1.34
```

## Запуск Flutter

```bash
cd mobile
flutter run
```

## Запуск web

```bash
cd web
npm run dev
```

Web будет доступен:

```text
http://127.0.0.1:3000
```

В приложении введите адрес сервера:

```text
http://IP_НОУТБУКА:8000
```

Пример:

```text
http://192.168.1.34:8000
```

Нажмите `Проверить связь`. Если будет ошибка, приложение покажет тип ошибки и детали, которые можно прислать для диагностики.

## Создание осмотра

В приложении нужно заполнить:

Данные авто:

- гос номер
- марка авто

Данные осмотра:

- фото спереди
- фото сзади
- фото слева
- фото справа
- фото пробега
- фото VIN номера

Фото можно сделать только через камеру телефона.

Backend принимает осмотр на endpoint:

```text
POST /api/inspections/
```

Для создания осмотра пользователь должен быть авторизован. Филиал берется из профиля пользователя на backend.

Основные API endpoints:

```text
POST /api/auth/login/
POST /api/auth/logout/
GET  /api/auth/me/
GET  /api/branches/
POST /api/recognize-vin/
POST /api/inspections/
```

Логин принимает JSON:

```json
{"login": "operator", "password": "password-from-admin"}
```

`POST /api/inspections/` принимает `multipart/form-data`:

```text
plate_number
brand
front_photo
rear_photo
left_photo
right_photo
mileage_photo
vin_photo
```

## Распознавание VIN

Backend отправляет фото VIN в OpenAI Responses API. API ключ можно добавить через админку:

```text
Админка -> AI API keys -> Add AI API key
```

Нужно заполнить:

- `Название`
- `API key`
- `Модель`, например `gpt-5.6`
- `Активен`

Если активного ключа в админке нет, backend попробует взять переменные окружения `OPENAI_API_KEY` и `OPENAI_VIN_MODEL`.

Endpoint:

```text
POST /api/recognize-vin/
```

Он принимает `multipart/form-data` с полем:

```text
vin_photo
```

Фотографии сохраняются в папку:

```text
backend/uploads/
```

## Админка

```text
http://IP_НОУТБУКА:8000/admin/
```

Логин:

```text
1
```

Пароль:

```text
1
```

Осмотры доступны в разделе `Осмотры авто`.

## Частые причины ошибок

- Django запущен на `127.0.0.1:8000`, а не на `0.0.0.0:8000`
- телефон и ноутбук не в одной Wi-Fi сети
- неверный IP ноутбука
- firewall на ноутбуке блокирует порт `8000`
- сервер не запущен
