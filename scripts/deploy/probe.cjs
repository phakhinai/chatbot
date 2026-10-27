const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { Pool } = require('pg');
const Redis = require('ioredis');
const { Queue, Worker, QueueEvents } = require('bullmq');
(async () => {
  const db = new Pool({ connectionString: process.env.DATABASE_URL, connectionTimeoutMillis: 3000 });
  const client = new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null, retryStrategy: () => null, connectTimeout: 3000 });
  const name = `deployment-check-${randomUUID()}`;
  let queue, worker, events;
  client.on('error', () => {});
  try {
    const result = await db.query("SELECT '[1,2,3]'::vector <-> '[1,2,3]'::vector AS distance");
    assert.equal(result.rows[0].distance, 0);
    assert.equal(await client.ping(), 'PONG');
    queue = new Queue(name, { connection: client });
    events = new QueueEvents(name, { connection: client });
    worker = new Worker(name, async job => job.data.value * 2, { connection: client });
    for (const emitter of [queue, events, worker]) emitter.on('error', () => {});
    await events.waitUntilReady();
    const job = await queue.add('probe', { value: 21 }, { removeOnComplete: true, removeOnFail: true });
    assert.equal(await job.waitUntilFinished(events, 10000), 42);
    console.log('PASS production PostgreSQL/pgvector, authenticated Redis, BullMQ job');
  } finally {
    if (worker) await worker.close();
    if (events) await events.close();
    if (queue) { await queue.obliterate({ force: true }); await queue.close(); }
    client.disconnect();
    await db.end();
  }
})().catch(error => { console.error(error.message); process.exit(1); });
