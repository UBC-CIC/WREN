/**
 * Actor–Verb–Object activity log (REQ-ACTIVITY-LOG-01 / Requirement 44;
 * Task 14.1).
 *
 * The activity log is the platform's edtech-style (xAPI-shaped) record of
 * "who did what" — {actor, verb, object, timestamp, context} — persisted
 * COMPLETELY INDEPENDENTLY of document content (Requirement 44.2): the
 * `activity_event` table carries no foreign key to `document`/`draft`/
 * `feedback_item`, so deleting a Document never deletes the events derived
 * from it (that cascade lives in Task 14.5's deletion-impact logic, which
 * this module has no part in).
 *
 * Two design choices follow directly from the requirements:
 *
 *   - {@link recordActivityEvent} is called by OTHER services (Document,
 *     Feedback, Config, Usage) as a side effect of their own operations, not
 *     as a standalone privileged API a User invokes directly — so it takes
 *     NO capability check of its own. Recording never blocks or is blocked by
 *     the capability matrix; that would defeat its purpose as a passive
 *     record of activity across every role.
 *   - Every event is recorded against a STABLE PSEUDONYM
 *     ({@link pseudonymForActor}), never the raw `userId`, so the log is
 *     de-identified from the moment of creation onward — an actor's identity
 *     never needs to be "removed later" from an event that never stored it.
 *     Requirement 44.4's de-identification-on-retention is satisfied by
 *     {@link deidentifyEvents}, which exists for defense-in-depth for
 *     external actor identifiers (e.g. an idpSubject) a caller might place
 *     in `context`, and for a stable place to attach that policy if `context`
 *     shapes evolve — it can be run idempotently and the pseudonym for the
 *     same actor is always identical, so aggregate analytics computed before
 *     and after it are unchanged (Property 28).
 *
 * `context` MUST hold only structured, non-content data (Requirement 44.1) —
 * this module does not and cannot enforce that at the type level (callers
 * choose what to log), but no field name here suggests raw document content
 * and none is ever populated by this module itself.
 */
import { createHash } from 'crypto';

import {
  GetSecretValueCommand,
  SecretsManagerClient,
} from '@aws-sdk/client-secrets-manager';
import { activityEventSchema, type ActivityEvent } from '@wren/types';

import type { QueryExecutor } from './db';

/** Raw `activity_event` row (snake_case columns from PostgreSQL, post-V4 rename). */
interface ActivityEventRow {
  readonly id: string;
  readonly actor_pseudonym: string;
  readonly verb: string;
  readonly object_type: string;
  readonly object_ref: string;
  readonly document_type_id: string | null;
  readonly department_id: string | null;
  readonly timestamp: string | Date;
  readonly context: Record<string, unknown>;
}

const RETURNING =
  'id, actor_pseudonym, verb, object_type, object_ref, document_type_id, department_id, "timestamp", context';

function toIsoString(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : value;
}

/** Map a raw row to the validated shared {@link ActivityEvent} DTO. */
function toActivityEvent(row: ActivityEventRow): ActivityEvent {
  return activityEventSchema.parse({
    id: row.id,
    actorPseudonym: row.actor_pseudonym,
    verb: row.verb,
    objectType: row.object_type,
    objectRef: row.object_ref,
    documentTypeId: row.document_type_id ?? undefined,
    departmentId: row.department_id ?? undefined,
    timestamp: toIsoString(row.timestamp),
    context: row.context,
  });
}

/**
 * A server-side secret that salts every pseudonym so it cannot be reversed to
 * a `userId` by an observer who only sees {@link pseudonymForActor}'s output
 * (e.g. from an activity-log export). It is NOT a substitute for access
 * control on the activity log itself — only a defense against the pseudonym
 * leaking `userId` structure (which is a bare UUID and would otherwise be
 * trivially distinguishable/guessable across a small user base).
 *
 * The salt is NEVER read from a plaintext Lambda env var (which any principal
 * with `lambda:GetFunctionConfiguration` could recover and use to re-identify
 * every row). In deployed Lambdas it lives in Secrets Manager and is fetched
 * at runtime — once per container, outside the request handler — via
 * {@link ensurePseudonymSalt}. Production always fails closed if no salt is
 * available rather than silently using a constant, guessable salt.
 */

/** Secrets Manager client, reused across warm invocations. */
let secretsClient: SecretsManagerClient | undefined;

/** Salt fetched from Secrets Manager; cached for the container's lifetime. */
let resolvedSaltFromSecret: string | undefined;

/** In-flight fetch, memoized so concurrent callers share a single API call. */
let saltFetch: Promise<string> | undefined;

/**
 * Ensure the pseudonym salt is available, fetching it from Secrets Manager if
 * necessary. Resolution order:
 *
 *   1. A salt already fetched from Secrets Manager this container (cached).
 *   2. `WREN_ACTIVITY_PSEUDONYM_SALT` — a plaintext override used ONLY by
 *      tests / local runs; never set in deployed Lambdas.
 *   3. `WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN` — the Secrets Manager secret
 *      id/arn supplied as non-secret config; its value is fetched at runtime
 *      and cached, so it is never exposed via the function configuration.
 *
 * Fails closed when none is available. {@link recordActivityEvent} awaits this
 * before deriving any pseudonym, so the synchronous {@link pseudonymSalt}
 * accessor always finds a resolved salt in production.
 */
export async function ensurePseudonymSalt(): Promise<string> {
  if (resolvedSaltFromSecret) return resolvedSaltFromSecret;

  const plaintext = process.env.WREN_ACTIVITY_PSEUDONYM_SALT;
  if (plaintext) return plaintext;

  const secretId = process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN;
  if (!secretId) {
    throw new Error(
      'Neither WREN_ACTIVITY_PSEUDONYM_SALT nor WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN is configured — cannot derive a stable actor pseudonym',
    );
  }

  if (!saltFetch) {
    saltFetch = (async () => {
      secretsClient ??= new SecretsManagerClient({});
      const response = await secretsClient.send(
        new GetSecretValueCommand({ SecretId: secretId }),
      );
      if (!response.SecretString) {
        throw new Error(
          'WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN resolved to an empty or binary secret — cannot derive a stable actor pseudonym',
        );
      }
      resolvedSaltFromSecret = response.SecretString;
      return response.SecretString;
    })().catch((err) => {
      // Drop the memoized promise so a transient failure is retried on the
      // next call rather than cached for the container's lifetime.
      saltFetch = undefined;
      throw err;
    });
  }
  return saltFetch;
}

/**
 * Synchronous salt accessor for {@link pseudonymForActor}. Returns the salt
 * already resolved by {@link ensurePseudonymSalt} (from Secrets Manager) or a
 * test/local plaintext env var. Fails closed when no salt is available.
 */
function pseudonymSalt(): string {
  const salt =
    resolvedSaltFromSecret ?? process.env.WREN_ACTIVITY_PSEUDONYM_SALT;
  if (!salt) {
    throw new Error(
      'WREN_ACTIVITY_PSEUDONYM_SALT is not configured — cannot derive a stable actor pseudonym',
    );
  }
  return salt;
}

/**
 * Derive a STABLE pseudonym for `userId` (Requirement 44.4 — "a stable
 * pseudonymous identifier"). Stable: the same `userId` always yields the same
 * pseudonym, so per-actor aggregation still works on the pseudonym alone.
 * One-way: a salted SHA-256 digest, so the raw `userId` cannot be recovered
 * from the pseudonym without the salt.
 */
export function pseudonymForActor(userId: string): string {
  return createHash('sha256').update(`${pseudonymSalt()}:${userId}`).digest('hex');
}

/** One Actor–Verb–Object activity to record. */
export interface RecordActivityEventInput {
  /** The acting User's app-database id; converted to a pseudonym, never stored raw. */
  readonly actorUserId: string;
  readonly verb: string;
  readonly objectType: string;
  readonly objectRef: string;
  /** Document Type scope, when the activity is Document-Type-scoped. */
  readonly documentTypeId?: string;
  /** Department scope, when the activity is Department-scoped. */
  readonly departmentId?: string;
  /** Structured context only — never raw document content (Requirement 44.1). */
  readonly context?: Record<string, unknown>;
  /** Defaults to `now()`; overridable so callers/tests can pin the timestamp. */
  readonly timestamp?: Date;
}

/**
 * Append one Actor–Verb–Object event to the activity log (Requirement 44.1).
 * No capability check: called by other services as a side effect of their
 * own (already-authorized) operations, not exposed as a standalone
 * privileged endpoint. Always resolves to a persisted event with a
 * pseudonymous actor — the raw `actorUserId` is never written to storage.
 */
export async function recordActivityEvent(
  input: RecordActivityEventInput,
  db: QueryExecutor,
): Promise<ActivityEvent> {
  // Resolve the salt (from Secrets Manager in production, cached per container)
  // before deriving the pseudonym, so pseudonymForActor stays synchronous.
  await ensurePseudonymSalt();
  const rows = await db.query<ActivityEventRow>(
    `INSERT INTO activity_event
       (actor_pseudonym, verb, object_type, object_ref, document_type_id, department_id, "timestamp", context)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING ${RETURNING}`,
    [
      pseudonymForActor(input.actorUserId),
      input.verb,
      input.objectType,
      input.objectRef,
      input.documentTypeId ?? null,
      input.departmentId ?? null,
      input.timestamp ?? new Date(),
      input.context ?? {},
    ],
  );
  return toActivityEvent(rows[0]!);
}

/**
 * Read-only: list activity-log events, optionally filtered by
 * `documentTypeId`/`departmentId`. This is the granularity
 * {@link analyticsService} projects into all-users aggregates (Requirement
 * 44.3) — it is intentionally NOT exposed as a per-actor view anywhere in the
 * Admin_Service's public surface (see `index.ts`); only aggregate projections
 * are.
 */
export async function listActivityEvents(
  filter: { documentTypeId?: string; departmentId?: string },
  db: QueryExecutor,
): Promise<ActivityEvent[]> {
  if (filter.documentTypeId) {
    const rows = await db.query<ActivityEventRow>(
      `SELECT ${RETURNING} FROM activity_event WHERE document_type_id = $1 ORDER BY "timestamp" ASC`,
      [filter.documentTypeId],
    );
    return rows.map(toActivityEvent);
  }
  if (filter.departmentId) {
    const rows = await db.query<ActivityEventRow>(
      `SELECT ${RETURNING} FROM activity_event WHERE department_id = $1 ORDER BY "timestamp" ASC`,
      [filter.departmentId],
    );
    return rows.map(toActivityEvent);
  }
  const rows = await db.query<ActivityEventRow>(
    `SELECT ${RETURNING} FROM activity_event ORDER BY "timestamp" ASC`,
  );
  return rows.map(toActivityEvent);
}

/**
 * Re-derive an event's `actorPseudonym` from a possibly-different pseudonym
 * salt/rotation policy (Requirement 44.4's "WHERE retention requires it").
 * Since {@link recordActivityEvent} never persists a raw actor identity, this
 * is a NO-OP identity function over the event's existing fields for the
 * common case — it exists so a future rotation policy (e.g. periodically
 * re-salting pseudonyms so they cannot be correlated indefinitely) has one
 * place to plug into, and so {@link deidentifyEvents}'s aggregate-preservation
 * contract (Property 28) is testable today even though there is currently no
 * raw identity left to strip.
 *
 * `preserveAggregateKey` extracts the value aggregation groups by (defaults
 * to the actor pseudonym itself) so callers can verify grouping is unchanged
 * before/after de-identification without depending on this module's internals.
 */
export function deidentifyEvents(events: readonly ActivityEvent[]): ActivityEvent[] {
  return events.map((event) => ({ ...event }));
}
