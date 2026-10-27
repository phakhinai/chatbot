import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomBytes } from 'node:crypto';
mkdirSync('.rehearsal', { recursive: true, mode: 0o700 });
const file = '.rehearsal/production.env';
if (existsSync(file)) {
  console.log('Reusing existing isolated rehearsal environment.');
} else {
  let text = readFileSync('.env.production.example', 'utf8');
  const values = {
    COMPOSE_PROJECT_NAME: 'rag-chatbot-rehearsal',
    POSTGRES_PASSWORD: randomBytes(24).toString('hex'),
    REDIS_PASSWORD: randomBytes(24).toString('hex'),
    SITE_ADDRESS: 'http://localhost', WEB_ORIGIN: 'http://localhost:8080',
    HTTP_BIND: '127.0.0.1', HTTP_PORT: '8080', HTTPS_PORT: '8443',
    API_IMAGE: process.env.API_IMAGE || 'rag-chatbot-api:rehearsal',
    WEB_IMAGE: process.env.WEB_IMAGE || 'rag-chatbot-web:rehearsal',
    BACKUP_DIR: resolve('.rehearsal/backups'),
  };
  for (const [key, value] of Object.entries(values)) text = text.replace(new RegExp(`^${key}=.*$`, 'm'), `${key}=${value}`);
  writeFileSync(file, text, { mode: 0o600 });
  console.log('Created isolated rehearsal environment; secrets hidden.');
}
