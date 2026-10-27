import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
const require = createRequire(new URL('../apps/api/package.json', import.meta.url));
const { Pool } = require('pg');
const { createClient } = require('redis');
const { Queue, Worker, QueueEvents } = require('bullmq');
const db = new Pool({ connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 3000 });
const redis = createClient({ url: process.env.REDIS_URL, socket: { connectTimeout: 3000, reconnectStrategy: false } });
redis.on('error', () => {});
const url = new URL(process.env.REDIS_URL);
const connection = { host: url.hostname, port: Number(url.port || 6379), maxRetriesPerRequest: null };
const name = `smoke-${randomUUID()}`;
let queue, worker, events;
try {
  const result = await db.query("SELECT extversion, '[1,2,3]'::vector <-> '[1,2,3]'::vector AS distance FROM pg_extension WHERE extname='vector'");
  assert.equal(result.rows[0]?.distance, 0);
  console.log(`PASS PostgreSQL + pgvector ${result.rows[0].extversion}: vector distance = 0`);
  await redis.connect();
  assert.equal(await redis.ping(), 'PONG');
  console.log('PASS Redis PING');
  queue = new Queue(name, { connection });
  events = new QueueEvents(name, { connection });
  worker = new Worker(name, async job => job.data.value * 2, { connection });
  await events.waitUntilReady();
  const job = await queue.add('probe', { value: 21 }, { removeOnComplete: true, removeOnFail: true });
  assert.equal(await job.waitUntilFinished(events, 10000), 42);
  console.log('PASS BullMQ enqueue → worker → result');
  const api = await fetch(`http://127.0.0.1:${process.env.API_PORT || 3001}/health`, { signal: AbortSignal.timeout(5000) });
  assert.equal(api.status, 200);
  assert.equal((await api.json()).status, 'ok');
  console.log('PASS NestJS /health');
  const web = await fetch(process.env.WEB_ORIGIN, { signal: AbortSignal.timeout(30000) });
  assert.equal(web.status, 200);
  const html = await web.text();
  assert.ok(html.includes('AI RAG Chatbot') && html.includes('Connected'));
  console.log('PASS Next.js + server-side API connection');
} finally {
  if (worker) await worker.close();
  if (events) await events.close();
  if (queue) { await queue.obliterate({ force: true }); await queue.close(); }
  await db.end();
  if (redis.isOpen) await redis.quit();
}
