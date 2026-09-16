import { PGlite } from '@electric-sql/pglite';
import { Pool, PoolClient } from 'pg';

export interface SQL {
  query<T = Record<string, any>>(text: string, values?: any[]): Promise<{ rows: T[] }>;
}

const schema = `
CREATE TABLE IF NOT EXISTS users (
 id TEXT PRIMARY KEY, phone_hash TEXT UNIQUE NOT NULL, phone_encrypted TEXT NOT NULL,
 name TEXT NOT NULL DEFAULT '', timezone TEXT NOT NULL DEFAULT 'Europe/Istanbul',
 schedule_minute INTEGER NOT NULL DEFAULT 540, grace_minutes INTEGER NOT NULL DEFAULT 240,
 enabled BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS schedules (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 minute INTEGER NOT NULL CHECK(minute BETWEEN 0 AND 1439),
 grace INTEGER NOT NULL CHECK(grace BETWEEN 30 AND 720), effective_date TEXT NOT NULL,
 CHECK(minute + grace < 1440), UNIQUE(user_id,effective_date)
);
CREATE TABLE IF NOT EXISTS sessions (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 access_hash TEXT UNIQUE NOT NULL, refresh_hash TEXT UNIQUE NOT NULL, family_id TEXT NOT NULL,
 device_name TEXT NOT NULL, access_expires TIMESTAMPTZ NOT NULL, refresh_expires TIMESTAMPTZ NOT NULL,
 revoked BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS otp_challenges (
 id TEXT PRIMARY KEY, phone_hash TEXT NOT NULL, phone_encrypted TEXT NOT NULL, code_hash TEXT NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, used BOOLEAN NOT NULL DEFAULT false,
 created_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS rate_limits (
 key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS relationships (
 id TEXT PRIMARY KEY, subject_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 viewer_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE, label TEXT NOT NULL,
 active BOOLEAN NOT NULL DEFAULT true, authorized_at TIMESTAMPTZ NOT NULL,
 CHECK(subject_id <> viewer_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS active_relationship ON relationships(subject_id,viewer_id) WHERE active;
CREATE TABLE IF NOT EXISTS invitations (
 id TEXT PRIMARY KEY, creator_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 subject_id TEXT REFERENCES users ON DELETE CASCADE, recipient_id TEXT REFERENCES users ON DELETE CASCADE,
 token_hash TEXT UNIQUE NOT NULL, label TEXT NOT NULL, status TEXT NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS occurrences (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 local_date TEXT NOT NULL, due_at TIMESTAMPTZ NOT NULL, deadline_at TIMESTAMPTZ NOT NULL,
 closes_at TIMESTAMPTZ NOT NULL, state TEXT NOT NULL CHECK(state IN ('pending','reminded','completed','overdue','alerted','cancelled')),
 completed_at TIMESTAMPTZ, UNIQUE(user_id,local_date)
);
CREATE INDEX IF NOT EXISTS occurrence_due ON occurrences(deadline_at) WHERE state IN ('pending','reminded','overdue');
CREATE TABLE IF NOT EXISTS checkins (
 id TEXT PRIMARY KEY, occurrence_id TEXT UNIQUE NOT NULL REFERENCES occurrences ON DELETE CASCADE,
 actor_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE, source TEXT NOT NULL,
 received_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS idempotency (
 user_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE, key TEXT NOT NULL, fingerprint TEXT NOT NULL,
 response JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL, PRIMARY KEY(user_id,key)
);
CREATE TABLE IF NOT EXISTS reminders (
 occurrence_id TEXT NOT NULL REFERENCES occurrences ON DELETE CASCADE, step INTEGER NOT NULL,
 created_at TIMESTAMPTZ NOT NULL, PRIMARY KEY(occurrence_id,step)
);
CREATE TABLE IF NOT EXISTS notifications (
 id TEXT PRIMARY KEY, occurrence_id TEXT REFERENCES occurrences ON DELETE CASCADE,
 recipient_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 relationship_id TEXT REFERENCES relationships ON DELETE CASCADE, type TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'queued', created_at TIMESTAMPTZ NOT NULL, opened_at TIMESTAMPTZ,
 attempts INTEGER NOT NULL DEFAULT 0, available_at TIMESTAMPTZ NOT NULL,
 UNIQUE(occurrence_id,recipient_id,type)
);
CREATE TABLE IF NOT EXISTS preferences (
 user_id TEXT PRIMARY KEY REFERENCES users ON DELETE CASCADE, success BOOLEAN NOT NULL DEFAULT true,
 missed BOOLEAN NOT NULL DEFAULT true, analytics BOOLEAN NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS devices (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 token_encrypted TEXT, permission TEXT NOT NULL, updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_logs (
 id TEXT PRIMARY KEY, user_id TEXT REFERENCES users ON DELETE CASCADE,
 action TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS consent_records (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
 purpose TEXT NOT NULL, version TEXT NOT NULL, granted BOOLEAN NOT NULL, created_at TIMESTAMPTZ NOT NULL
);
`;

export class Database {
  private embedded?: PGlite;
  private pool?: Pool;
  private tail: Promise<unknown> = Promise.resolve();

  constructor(url?: string, directory?: string) {
    if (url) this.pool = new Pool({ connectionString: url, ssl: url.includes('sslmode=require') ? {} : undefined });
    else this.embedded = new PGlite(directory);
  }

  async initialize(targetVersion?: number) {
    const migrations = [schema, `
      CREATE TABLE IF NOT EXISTS notification_deliveries (
        id TEXT PRIMARY KEY, notification_id TEXT NOT NULL REFERENCES notifications ON DELETE CASCADE,
        device_id TEXT NOT NULL REFERENCES devices ON DELETE CASCADE, status TEXT NOT NULL DEFAULT 'queued',
        attempts INTEGER NOT NULL DEFAULT 0, available_at TIMESTAMPTZ NOT NULL, lease_until TIMESTAMPTZ,
        accepted_at TIMESTAMPTZ, UNIQUE(notification_id,device_id)
      );
      CREATE INDEX IF NOT EXISTS delivery_pending ON notification_deliveries(available_at) WHERE status IN ('queued','retryable_failed','sending');
    `, 'ALTER TABLE devices ADD COLUMN IF NOT EXISTS session_family_id TEXT', 'ALTER TABLE users ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ; UPDATE users SET activated_at=created_at WHERE activated_at IS NULL', `
      ALTER TABLE users ALTER COLUMN phone_hash DROP NOT NULL;
      ALTER TABLE users ALTER COLUMN phone_encrypted DROP NOT NULL;
      CREATE TABLE IF NOT EXISTS account_registrations (
        secret_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users ON DELETE CASCADE,
        fingerprint TEXT NOT NULL, family_id TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL
      );
      ALTER TABLE invitations ADD COLUMN IF NOT EXISTS code_hash TEXT;
      CREATE UNIQUE INDEX IF NOT EXISTS invitation_code ON invitations(code_hash) WHERE code_hash IS NOT NULL;
    `];
    await this.transaction(async db => {
      await db.query('CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())');
      const count = targetVersion ?? migrations.length;
      if (!Number.isInteger(count) || count < 1 || count > migrations.length) throw new Error('Invalid migration version');
      for (let index = 0; index < count; index++) {
        const version = index + 1;
        if ((await db.query('SELECT version FROM schema_migrations WHERE version=$1', [version])).rows.length) continue;
        for (const statement of migrations[index].split(';').map(value => value.trim()).filter(Boolean)) await db.query(statement);
        await db.query('INSERT INTO schema_migrations(version) VALUES($1)', [version]);
      }
    });
  }

  async transaction<T>(work: (db: SQL) => Promise<T>): Promise<T> {
    if (this.pool) {
      const client: PoolClient = await this.pool.connect();
      try {
        await client.query('BEGIN');
        await client.query("SELECT pg_advisory_xact_lock(7319051)");
        const result = await work(client);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally { client.release(); }
    }
    const task = this.tail.then(() => this.embedded!.transaction(tx => work(tx)));
    this.tail = task.catch(() => undefined);
    return task;
  }

  async close() {
    await this.tail;
    if (this.pool) await this.pool.end();
    if (this.embedded) await this.embedded.close();
  }
}
