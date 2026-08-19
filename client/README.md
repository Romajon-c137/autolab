# Autolab Client

Клиентская часть для заполнения заявки на проведение технического осмотра.

## Local development

```bash
npm install
npm run dev
```

По умолчанию dev-сервер запускается на `http://localhost:3100`.

## Production

Нужные переменные окружения:

```bash
OPENAI_API_KEY=
OPENAI_TECH_PASSPORT_MODEL=gpt-4o-mini
BACKEND_URL=https://autolab.glasscenter.kg
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
```

Сборка:

```bash
npm ci
npm run build
```

Запуск обычный:

```bash
npm run start
```

Standalone-выход после сборки:

```bash
node .next/standalone/server.js
```

На сервере нужен Chromium, потому что PDF заявки генерируется через Playwright.
