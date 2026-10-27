import 'reflect-metadata';
import { Controller, Get, Injectable, Module, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { Pool } from 'pg';
import { createClient } from 'redis';

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

@Injectable()
class Dependencies implements OnModuleDestroy {
  private readonly db = new Pool({ connectionString: required('DATABASE_URL'), connectionTimeoutMillis: 3000, query_timeout: 4000 });
  private readonly redis = createClient({ url: required('REDIS_URL'), disableOfflineQueue: true, socket: { connectTimeout: 3000, reconnectStrategy: retries => Math.min(100 * (retries + 1), 3000) } });
  constructor() {
    this.db.on('error', () => console.error('PostgreSQL connection error'));
    this.redis.on('error', () => console.error('Redis connection error'));
  }
  async connect() { await this.redis.connect(); }
  async check() {
    if (!this.redis.isReady) throw new ServiceUnavailableException('Redis unavailable');
    try {
      const [result, pong] = await Promise.all([
        this.db.query("SELECT extversion FROM pg_extension WHERE extname = 'vector'"),
        this.redis.withAbortSignal(AbortSignal.timeout(4000)).ping(),
      ]);
      if (!result.rowCount || pong !== 'PONG') throw new Error('Dependency unavailable');
      return { status: 'ok', postgres: 'ok', pgvector: result.rows[0].extversion, redis: 'ok' };
    } catch {
      throw new ServiceUnavailableException('Dependency health check failed');
    }
  }
  async onModuleDestroy() { await Promise.all([this.db.end(), this.redis.isOpen ? this.redis.quit() : Promise.resolve()]); }
}

@Controller('health')
class HealthController {
  constructor(private readonly dependencies: Dependencies) {}
  @Get() health() { return this.dependencies.check(); }
}
@Module({ controllers: [HealthController], providers: [Dependencies] })
class AppModule {}

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableCors({ origin: required('WEB_ORIGIN') });
  app.enableShutdownHooks();
  await app.get(Dependencies).connect();
  await app.get(Dependencies).check();
  await app.listen(Number(process.env.API_PORT || 3001), process.env.API_HOST || '127.0.0.1');
}
bootstrap().catch(() => { console.error('API startup failed. Check environment and database/Redis availability.'); process.exit(1); });
