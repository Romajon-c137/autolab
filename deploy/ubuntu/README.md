# Ubuntu production deploy

This setup runs:

- Django backend on `127.0.0.1:8000` via Gunicorn and systemd
- PaddleOCR VIN service on `127.0.0.1:8765` via systemd
- Next.js web on `127.0.0.1:3000` via systemd
- nginx as the public entrypoint
- `/api/`, `/admin/`, `/media/`, `/static/` routed to Django
- all other paths routed to Next.js

## 1. Install packages

```bash
sudo apt update
sudo apt install -y python3-venv python3-pip nodejs npm nginx
```

For PostgreSQL:

```bash
sudo apt install -y postgresql
sudo -u postgres createuser autolab
sudo -u postgres createdb autolab -O autolab
sudo -u postgres psql -c "ALTER USER autolab WITH PASSWORD 'strong-password';"
```

## 2. Place project

Recommended path:

```bash
sudo mkdir -p /opt/autolab
sudo chown -R "$USER":"$USER" /opt/autolab
rsync -a --delete ./backend /opt/autolab/
rsync -a --delete ./web /opt/autolab/
rsync -a --delete ./deploy /opt/autolab/
```

Do not copy local `node_modules`, `.next`, `.venv`, `server.pid`, `server.log`, or test databases.

## 3. Backend

```bash
cd /opt/autolab/backend
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python manage.py migrate
python manage.py collectstatic --noinput
python manage.py check --deploy
sudo chown -R www-data:www-data /opt/autolab/backend
```

Edit `/opt/autolab/backend/.env` before starting services:

- `DJANGO_SECRET_KEY`
- `DJANGO_ALLOWED_HOSTS`
- `DJANGO_CSRF_TRUSTED_ORIGINS`
- `DJANGO_CORS_ALLOWED_ORIGINS`
- `DATABASE_URL`
- `VIN_OCR_SERVICE_URL=http://127.0.0.1:8765/recognize-vin`

## 4. VIN OCR

VIN recognition is handled by a separate PaddleOCR runtime. Do not install
`paddleocr` or `paddlepaddle` into the main Django `.venv`.

For a CPU without AVX, use the server-proven runtime:

```bash
sudo mkdir -p /opt/autolab/paddleocr-home
sudo chown -R www-data:www-data /opt/autolab/paddleocr-home

# Runtime already prepared on the production server:
# /opt/autolab/paddleocr-venv
# /opt/autolab/paddleocr-venv/bin/python
# Python 3.8.20
# paddlepaddle==2.4.2 no-avx
# paddleocr==2.10.0
```

The service entrypoint is:

```bash
/opt/autolab/paddleocr-venv/bin/python /opt/autolab/backend/ocr_service.py
```

## 5. Web

```bash
cd /opt/autolab/web
npm ci
cp .env.example .env
npm run build
sudo chown -R www-data:www-data /opt/autolab/web
```

If nginx serves frontend and backend on the same domain, keep `NEXT_PUBLIC_API_URL=` empty.

## 6. systemd

```bash
sudo cp /opt/autolab/deploy/ubuntu/autolab-ocr.service /etc/systemd/system/
sudo cp /opt/autolab/deploy/ubuntu/autolab-backend.service /etc/systemd/system/
sudo cp /opt/autolab/deploy/ubuntu/autolab-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now autolab-ocr autolab-backend autolab-web
sudo systemctl status autolab-ocr autolab-backend autolab-web
```

Check OCR directly:

```bash
curl http://127.0.0.1:8765/health
```

## 7. nginx

```bash
sudo cp /opt/autolab/deploy/ubuntu/nginx-autolab.conf /etc/nginx/sites-available/autolab
sudo ln -sf /etc/nginx/sites-available/autolab /etc/nginx/sites-enabled/autolab
sudo nginx -t
sudo systemctl reload nginx
```

Replace `auto.example.com` and `SERVER_IP` in the nginx config with the real domain/IP.

## 8. HTTPS

After DNS points to the server:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d auto.example.com
```

Then set in backend `.env`:

```env
DJANGO_SECURE_SSL_REDIRECT=True
DJANGO_SESSION_COOKIE_SECURE=True
DJANGO_CSRF_COOKIE_SECURE=True
DJANGO_CSRF_TRUSTED_ORIGINS=https://auto.example.com
DJANGO_CORS_ALLOWED_ORIGINS=https://auto.example.com
```

Restart:

```bash
sudo systemctl restart autolab-ocr autolab-backend autolab-web
```

## 9. Mobile APK for production server

Build with server URL baked as default:

```bash
cd /opt/autolab/mobile
flutter build apk --release --dart-define=SERVER_URL=https://auto.example.com
```

The server field in the app remains editable.
