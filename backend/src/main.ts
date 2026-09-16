import 'reflect-metadata';
import { All, Controller, Inject, Module, Req, Res } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { Request, Response, json } from 'express';
import { createHash } from 'node:crypto';
import { ZodError } from 'zod';
import { Database } from './database';
import { APIError, Service } from './service';
import { APNsTransport, NotificationWorker } from './notifications';

@Controller('v1')
class APIController {
  constructor(@Inject(Service) private service: Service) {}
  @All('*path')
  async handle(@Req() request: Request, @Res() response: Response) {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      const data = await this.service.request(request.method, request.path.replace(/^\/v1/, ''), request.body,
        request.headers.authorization?.replace(/^Bearer /, '') ?? '', request.header('Idempotency-Key') ?? '', request.ip ?? 'unknown');
      response.json(data);
    } catch (error) {
      if (error instanceof APIError) response.status(error.status).json({ code: error.code, message: error.message });
      else if (error instanceof ZodError) response.status(400).json({ code: 'invalid_input', message: 'Bilgileri kontrol edip yeniden deneyin.' });
      else {
        console.error('request_failed', error instanceof Error ? error.constructor.name : 'unknown');
        response.status(500).json({ code: 'internal_error', message: 'İşlem tamamlanamadı. Yeniden deneyin.' });
      }
    }
  }
}

async function main() {
  const production = process.env.NODE_ENV === 'production';
  if (production && (!process.env.DATABASE_URL || !process.env.DATA_ENCRYPTION_KEY || !process.env.LOOKUP_KEY)) throw new Error('Production requires database and encryption configuration');
  const pushEnabled = process.env.APNS_ENABLED === 'true';
  if (pushEnabled && (!production || !process.env.APNS_KEY_ID || !process.env.APNS_TEAM_ID || !process.env.APNS_PRIVATE_KEY || !process.env.APNS_TOPIC)) throw new Error('APNs requires explicit production credentials');
  const database = new Database(process.env.DATABASE_URL, process.env.DATABASE_URL ? undefined : (process.env.LOCAL_DATABASE_PATH ?? '.data'));
  console.log('database_initializing');
  await database.initialize();
  console.log('database_ready');
  const schedulerMode = process.env.SCHEDULER_MODE ?? (production ? 'external' : 'internal');
  if (production && schedulerMode === 'external' && !process.env.TICK_SECRET) throw new Error('Production external scheduler requires TICK_SECRET');
  const service = new Service(database, {
    mode: production ? 'production' : 'development',
    pushConfigured: pushEnabled,
    tickSecret: process.env.TICK_SECRET,
    encryptionKey: production ? Buffer.from(process.env.DATA_ENCRYPTION_KEY!, 'hex') : createHash('sha256').update('local-development-only-not-a-secret').digest(),
    lookupKey: production ? process.env.LOOKUP_KEY! : 'local-development-only-lookup'
  });
  @Module({ controllers: [APIController], providers: [{ provide: Service, useValue: service }] })
  class AppModule {}
  const app = await NestFactory.create(AppModule, { logger: ['error', 'warn'], bodyParser: false });
  app.use(json({ limit: '16kb' }));
  const host = process.env.HOST ?? (production ? '0.0.0.0' : '127.0.0.1');
  await app.listen(Number(process.env.PORT ?? 3000), host);
  const worker = pushEnabled ? new NotificationWorker(database, new APNsTransport({
    keyId: process.env.APNS_KEY_ID!, teamId: process.env.APNS_TEAM_ID!, privateKey: process.env.APNS_PRIVATE_KEY!,
    topic: process.env.APNS_TOPIC!, sandbox: process.env.APNS_SANDBOX === 'true'
  }), value => service.decrypt(value)) : null;
  let ticking = false;
  const timer = schedulerMode === 'internal'
    ? setInterval(async () => {
        if (ticking) return;
        ticking = true;
        try { await service.tick(); if (worker) await worker.run(); } catch { console.error('scheduler_failed'); } finally { ticking = false; }
      }, 15000)
    : null;
  const shutdown = async () => { if (timer) clearInterval(timer); await app.close(); await database.close(); process.exit(0); };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
  console.log(`API ready on ${host}:${process.env.PORT ?? 3000}; mode=${production ? 'production' : 'local-test'}; auth=device-account; scheduler=${schedulerMode}; APNs=${pushEnabled ? 'enabled' : 'disabled'}`);
}
main().catch(() => { console.error('startup_failed'); process.exitCode = 1; });
