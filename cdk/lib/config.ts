import type { App } from "aws-cdk-lib";
import type { Environment } from "aws-cdk-lib";
import { parseAllowedEmailDomains } from "./signupEmailDomains.js";

import {
  resolveLambdaConcurrency,
  type LambdaConcurrencyConfig,
} from "./lambdaConcurrency.js";
import { parseCorsAllowedOrigins } from "./corsOrigins.js";

/**
 * Single-source defaults for the CDK application.
 *
 * The project/codebase identity is WREN: all stack, resource, and table names
 * derive from {@link DEFAULT_PROJECT_NAME} (`wren`), never from the display
 * name. The configurable application *display* name is decoupled from infra
 * naming (REQ-NFR-APPNAME-01) and is surfaced only through the SSM app-name
 * parameter the frontend reads.
 */

/**
 * The configurable application DISPLAY name (REQ-NFR-APPNAME-01).
 *
 * This is the SOLE permitted occurrence of the brand literal in the entire
 * codebase. It feeds only the SSM app-name parameter (the runtime display
 * name); it MUST NOT drive any stack/resource/table naming. The display name is
 * overridden purely through configuration (CDK context or, at runtime, SSM) —
 * never by editing other source. See REQ-NFR-APPNAME-01 and the design's
 * Infrastructure section.
 */
export const DEFAULT_APP_NAME = "LEON";

/**
 * The project identifier that drives ALL stack/resource/table naming.
 *
 * Decoupled from {@link DEFAULT_APP_NAME} so the display name never leaks into
 * infrastructure names. `stackPrefix` defaults to `${projectName}-${environmentName}`
 * (e.g. `wren-dev`).
 */
export const DEFAULT_PROJECT_NAME = "wren";
export const DEFAULT_ENVIRONMENT_NAME = "dev";

/**
 * Single-source default for the Bedrock model identifier (REQ-NFR-MODEL-01).
 *
 * Model invocation is model-agnostic (via `langchain-aws`); this is only a
 * *default* and is overridden at synth time with `-c bedrockModelId=...` or at
 * runtime via the SSM parameter published by the `Config` stack. No backend
 * code hardcodes a model id - it is resolved from configuration. Changing the
 * model is therefore a configuration edit, not a code change.
 */
export const DEFAULT_BEDROCK_MODEL_ID = "us.anthropic.claude-sonnet-4-6";

/**
 * Data residency: all persistent stores live in ca-central-1 (design:
 * "all in `ca-central-1`", REQ 46.x). Used as the region fallback when
 * CDK_DEFAULT_REGION is not supplied by the environment.
 */
export const DEFAULT_REGION = "ca-central-1";

/**
 * Prompt-cache configuration (prompt-cache plan §15/§16).
 *
 * These drive the runtime cache DECISION layer through Lambda environment
 * variables (`CACHE_MODE` / `CACHE_TTL` / `CACHE_ENABLED_WORKLOADS`). The safe
 * production defaults keep explicit caching effectively OFF: `mode=observe`,
 * `ttl=5m`, and NO workloads enabled — so no explicit cache markers are ever
 * emitted until an operator opts in per environment. `mode=off` is the tested
 * rollback that fully disables cache decisions at runtime.
 */
export type CacheMode = "off" | "observe" | "explicit";
export type CacheTtl = "5m" | "1h";

/** Plan §14 workload tokens. Canonical (underscore) form used for env output. */
export const CACHE_WORKLOADS = [
  "ask_wren",
  "feedback_primary",
  "strength_fill",
  "quote_fill",
  "resolution_judge",
] as const;
export type CacheWorkload = (typeof CACHE_WORKLOADS)[number];

/** Plan §15 initial posture: caching effectively OFF. */
export const DEFAULT_CACHE_MODE: CacheMode = "observe";
export const DEFAULT_CACHE_TTL: CacheTtl = "5m";

/**
 * Resolved, immutable configuration shared by every stack in the app.
 */
export interface AppConfig {
  /**
   * Configurable application DISPLAY name; defaults to {@link DEFAULT_APP_NAME}.
   * Used SOLELY for the SSM app-name value — never for resource naming.
   */
  readonly appName: string;
  /**
   * Project identifier that drives all stack/resource naming; defaults to
   * {@link DEFAULT_PROJECT_NAME} (`wren`). Decoupled from {@link appName}.
   */
  readonly projectName: string;
  /** Deployment environment name (e.g. `dev`, `staging`, `prod`). */
  readonly environmentName: string;
  /**
   * Configurable Bedrock model identifier (REQ-NFR-MODEL-01). Resolved from
   * configuration (CDK context for synth, SSM at runtime); never hardcoded in
   * backend orchestration logic. Defaults to {@link DEFAULT_BEDROCK_MODEL_ID}.
   */
  readonly bedrockModelId: string;
  /**
   * ECR image reference the Feedback Engine Lambda is pinned to, passed to
   * `Code.fromEcrImage`'s `tagOrDigest`. The deploy workflow supplies the
   * immutable image **digest** (`sha256:...`) recorded for the deployed
   * revision; a tag (e.g. `bootstrap`) is accepted for direct-CDK use.
   */
  readonly feedbackEngineImageTag: string;
  /**
   * Whether Compute creates the audit pseudonym salt or reuses a salt retained
   * by a previous protected teardown.
   */
  readonly auditPseudonymSaltOwnership: "managed" | "external";
  /**
   * Optional exact Cognito subject allowed to receive TechnicalAdmin during its
   * first application-side provisioning. Absent by default, disabling bootstrap.
   */
  readonly technicalAdminBootstrapSubject?: string;
  /**
   * Optional recipient for CloudWatch alarm notifications. The SNS email
   * subscription remains pending until the recipient confirms it in AWS.
   */
  readonly alarmEmail?: string;
  /**
   * Prompt-cache mode (plan §15). Defaults to {@link DEFAULT_CACHE_MODE}
   * (`observe`). Propagated to the feedback Lambdas as `CACHE_MODE`. `off` is
   * the rollback that disables cache decisions at runtime; `explicit` is the
   * only mode that can ever cache.
   */
  readonly cacheMode: CacheMode;
  /**
   * Prompt-cache write TTL (plan §7/§10). Defaults to {@link DEFAULT_CACHE_TTL}
   * (`5m`). Propagated as `CACHE_TTL`.
   */
  readonly cacheTtl: CacheTtl;
  /**
   * Workloads for which explicit caching is enabled (plan §14/§15). Defaults to
   * an EMPTY set (no workloads). Propagated as `CACHE_ENABLED_WORKLOADS` (a
   * comma-separated list; empty string when none). Unknown tokens are rejected
   * at synth so a typo can never silently mis-configure the runtime.
   */
  readonly cacheEnabledWorkloads: readonly CacheWorkload[];
  /**
   * Prefix that drives all stack/resource naming: `${StackPrefix}-<Concern>`.
   * Defaults to `${projectName}-${environmentName}` when not explicitly
   * provided — it derives from the project name, never from {@link appName}.
   */
  readonly stackPrefix: string;
  /**
   * Reserved-concurrency policy for the Compute Lambdas (authorizer throttling
   * remediation). Floors protect the authorizers on the critical path; caps
   * bound the long-running feedback-engine/document functions so a burst cannot
   * starve the shared account concurrency pool. Validated at synth time by
   * {@link resolveLambdaConcurrency}. See
   * `docs/authorizer-throttling-remediation.md`.
   */
  readonly lambdaConcurrency: LambdaConcurrencyConfig;
  /**
   * Optional custom domain (e.g. `example.com`) for the Amplify-hosted
   * frontend. When present, the Amplify stack maps the production branch to the
   * domain root and its `www` subdomain. Absent by default, in which case the
   * frontend is reachable only via the Amplify default `*.amplifyapp.com`
   * domain. No domain is ever hard-coded.
   */
  readonly customDomain?: string;
  /**
   * Exact email hostnames allowed for new Cognito self-signups. Empty by
   * default (unrestricted). Set with `-c allowedEmailDomains=ubc.ca`.
   * Subdomains are not implied: `ubc.ca` does not allow `law.ubc.ca`.
   * In `prod`, this must be non-empty. Matching is exact: subdomains
   * must be listed separately.
   */
  readonly allowedEmailDomains: readonly string[];
  /**
   * Extra exact browser origins for API/S3 CORS (scheme://host[:port]).
   * Local Vite (`http://localhost:5173`, `http://127.0.0.1:5173`) and
   * {@link customDomain} (plus `www`) are always included. Amplify default
   * hosts are matched separately (`*.amplifyapp.com`). Override with
   * `-c corsAllowedOrigins=https://a.example,https://b.example`.
   */
  readonly corsAllowedOrigins: readonly string[];
  /** Account/region passed to every stack. */
  readonly env: Required<Pick<Environment, "region">> & Environment;
}

function readContext(app: App, key: string): string | undefined {
  const value = app.node.tryGetContext(key) as unknown;
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

/**
 * Resolve the prompt-cache mode from `cacheMode` context, defaulting to the
 * safe `observe` posture. An unrecognized value is rejected (fail-fast at synth)
 * so a typo can never silently enable — or fail to disable — caching.
 */
function resolveCacheMode(raw: string | undefined): CacheMode {
  if (raw === undefined) return DEFAULT_CACHE_MODE;
  const v = raw.toLowerCase();
  if (v === "off" || v === "observe" || v === "explicit") return v;
  throw new Error("cacheMode must be one of: off, observe, explicit");
}

/** Resolve the cache TTL from `cacheTtl` context, defaulting to `5m`. */
function resolveCacheTtl(raw: string | undefined): CacheTtl {
  if (raw === undefined) return DEFAULT_CACHE_TTL;
  const v = raw.toLowerCase();
  if (v === "5m" || v === "1h") return v;
  throw new Error("cacheTtl must be one of: 5m, 1h");
}

/**
 * Resolve the enabled-workload allowlist from `cacheEnabledWorkloads` context.
 *
 * Accepts a comma/whitespace-separated list; both hyphen (`ask-wren`) and
 * underscore (`ask_wren`) spellings normalize to the canonical underscore
 * token. An empty/absent value yields NO workloads (the safe default). Unknown
 * tokens are rejected at synth — unlike the runtime parser (which fails closed
 * by ignoring them), infrastructure config fails LOUD so a mistyped workload is
 * caught before deploy.
 */
function resolveCacheEnabledWorkloads(raw: string | undefined): CacheWorkload[] {
  if (raw === undefined) return [];
  const result: CacheWorkload[] = [];
  const known = new Set<string>(CACHE_WORKLOADS);
  for (const rawToken of raw.split(/[,\s]+/)) {
    const token = rawToken.trim().toLowerCase().replace(/-/g, "_");
    if (token.length === 0) continue;
    if (!known.has(token)) {
      throw new Error(
        `cacheEnabledWorkloads contains unknown workload '${rawToken}'. ` +
          `Allowed: ${CACHE_WORKLOADS.join(", ")}`,
      );
    }
    if (!result.includes(token as CacheWorkload)) {
      result.push(token as CacheWorkload);
    }
  }
  return result;
}

/**
 * Resolve the application configuration from CDK context with sensible
 * defaults, and the deployment account/region from the standard CDK
 * environment variables.
 *
 * Context keys (all optional):
 *   - `appName`         -> defaults to `LEON` (display name only)
 *   - `projectName`     -> defaults to `wren` (drives resource naming)
 *   - `environmentName` -> defaults to `dev`
 *   - `bedrockModelId`  -> defaults to DEFAULT_BEDROCK_MODEL_ID
 *   - `feedbackEngineImageTag` -> defaults to `bootstrap` for direct-CDK compatibility
 *   - `technicalAdminBootstrapSubject` -> optional exact Cognito sub; absent disables bootstrap
 *   - `alarmEmail`      -> optional SNS email recipient for CloudWatch alarms
 *   - `cacheMode`       -> `off|observe|explicit`, defaults to `observe`
 *   - `cacheTtl`        -> `5m|1h`, defaults to `5m`
 *   - `cacheEnabledWorkloads` -> comma-separated workloads, defaults to none
 *   - `stackPrefix`     -> defaults to `${projectName}-${environmentName}`
 *   - `corsAllowedOrigins` -> extra exact CORS origins, comma-separated
 *   - `allowedEmailDomains` -> exact signup email hostnames, comma-separated
 *
 * Override at synth/deploy time, e.g.:
 *   cdk synth -c appName="My Coach" -c environmentName=prod
 *   cdk synth -c bedrockModelId=anthropic.claude-3-5-haiku-20241022-v1:0
 */
export function resolveAppConfig(app: App): AppConfig {
  const appName = readContext(app, "appName") ?? DEFAULT_APP_NAME;
  const projectName = readContext(app, "projectName") ?? DEFAULT_PROJECT_NAME;
  const environmentName = readContext(app, "environmentName") ?? DEFAULT_ENVIRONMENT_NAME;
  const bedrockModelId = readContext(app, "bedrockModelId") ?? DEFAULT_BEDROCK_MODEL_ID;
  const feedbackEngineImageTag = readContext(app, "feedbackEngineImageTag") ?? "bootstrap";
  const auditPseudonymSaltOwnership = readContext(app, "auditPseudonymSaltOwnership") ?? "managed";
  if (auditPseudonymSaltOwnership !== "managed" && auditPseudonymSaltOwnership !== "external") {
    throw new Error("auditPseudonymSaltOwnership must be 'managed' or 'external'");
  }
  const technicalAdminBootstrapSubject = readContext(app, "technicalAdminBootstrapSubject");
  const alarmEmail = readContext(app, "alarmEmail");
  const cacheMode = resolveCacheMode(readContext(app, "cacheMode"));
  const cacheTtl = resolveCacheTtl(readContext(app, "cacheTtl"));
  const cacheEnabledWorkloads = resolveCacheEnabledWorkloads(
    readContext(app, "cacheEnabledWorkloads"),
  );
  const stackPrefix = readContext(app, "stackPrefix") ?? `${projectName}-${environmentName}`;
  const lambdaConcurrency = resolveLambdaConcurrency((key) => readContext(app, key));
  const customDomain = readContext(app, "customDomain");
  const allowedEmailDomains = parseAllowedEmailDomains(
    readContext(app, "allowedEmailDomains"),
    "allowedEmailDomains",
  );
  if (environmentName === "prod" && allowedEmailDomains.length === 0) {
    throw new Error(
      "allowedEmailDomains must be non-empty in prod; use -c allowedEmailDomains=example.com",
    );
  }
  const corsAllowedOrigins = parseCorsAllowedOrigins(readContext(app, "corsAllowedOrigins"));

  // Data residency (REQ 46.x): persistent stores MUST live in ca-central-1.
  // The region is resolved from the `region` context key and otherwise pinned
  // to ca-central-1 — deliberately NOT read from CDK_DEFAULT_REGION, so a
  // deployer's ambient AWS profile region can never silently place resources
  // outside the residency boundary. Override explicitly with `-c region=...`.
  const region = readContext(app, "region") ?? DEFAULT_REGION;

  return {
    appName,
    projectName,
    environmentName,
    bedrockModelId,
    feedbackEngineImageTag,
    auditPseudonymSaltOwnership,
    ...(technicalAdminBootstrapSubject ? { technicalAdminBootstrapSubject } : {}),
    ...(alarmEmail ? { alarmEmail } : {}),
    cacheMode,
    cacheTtl,
    cacheEnabledWorkloads,
    stackPrefix,
    lambdaConcurrency,
    ...(customDomain ? { customDomain } : {}),
    allowedEmailDomains,
    corsAllowedOrigins,
    env: {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region,
    },
  };
}

/**
 * Build the conventional stack id for a concern: `${StackPrefix}-<Concern>`
 * (e.g. `wren-dev-Vpc`). Later tasks (2.1+) use this to name concern stacks.
 */
export function stackName(config: AppConfig, concern: string): string {
  return `${config.stackPrefix}-${concern}`;
}

/**
 * Serialize the enabled-workload allowlist to the `CACHE_ENABLED_WORKLOADS`
 * env value the runtime cache policy reads: a comma-separated list of canonical
 * tokens, or the empty string when no workloads are enabled (the safe default).
 */
export function cacheEnabledWorkloadsEnv(config: AppConfig): string {
  return config.cacheEnabledWorkloads.join(",");
}

/**
 * SSM Parameter Store path for the runtime application name (REQ-NFR-APPNAME-01).
 *
 * Backend Lambdas read the application name from this parameter at runtime
 * instead of from any source literal. The path is scoped to `StackPrefix`
 * only and carries no separate brand literal.
 */
export function appNameParameterName(config: AppConfig): string {
  return `/${config.stackPrefix}/config/app-name`;
}

/**
 * SSM Parameter Store path for the runtime Bedrock model id (REQ-NFR-MODEL-01).
 *
 * Backend Lambdas resolve the model id from this parameter at runtime so the
 * model can change with no code change beyond configuration.
 */
export function bedrockModelIdParameterName(config: AppConfig): string {
  return `/${config.stackPrefix}/config/bedrock-model-id`;
}

/**
 * Cross-stack SSM parameter paths.
 *
 * Per the CDK steering, foundational stacks publish their resource identifiers
 * to SSM Parameter Store rather than via CloudFormation cross-stack exports, so
 * downstream stacks (Api / Compute / ...) can resolve them without tight
 * coupling. Every path is scoped to `${StackPrefix}` only and carries no brand
 * literal.
 */
export const ssmParameterNames = {
  /** VPC id published by the `Vpc` stack. */
  vpcId: (config: AppConfig): string => `/${config.stackPrefix}/network/vpc-id`,
  /** RDS Proxy endpoint hostname published by the `Database` stack. */
  databaseProxyEndpoint: (config: AppConfig): string =>
    `/${config.stackPrefix}/database/proxy-endpoint`,
  /** ARN of the Secrets Manager secret holding DB admin credentials. */
  databaseSecretArn: (config: AppConfig): string =>
    `/${config.stackPrefix}/database/secret-arn`,
  /** ARN of the Secrets Manager secret for a per-Lambda Postgres role. */
  databaseRoleSecretArn: (config: AppConfig, role: string): string =>
    `/${config.stackPrefix}/database/${role}/secret-arn`,
  /** Name of the S3 bucket holding submitted document bytes. */
  documentsBucketName: (config: AppConfig): string =>
    `/${config.stackPrefix}/storage/documents-bucket-name`,
  /** Name of the S3 bucket holding Reference Material bytes. */
  referenceBucketName: (config: AppConfig): string =>
    `/${config.stackPrefix}/storage/reference-bucket-name`,
  /** Name of the DynamoDB conversation/session-state table. */
  conversationTableName: (config: AppConfig): string =>
    `/${config.stackPrefix}/storage/conversation-table-name`,
  /** Cognito User Pool ID published by the `Cognito` stack. */
  userPoolId: (config: AppConfig): string => `/${config.stackPrefix}/auth/user-pool-id`,
  /** Cognito User Pool Client ID published by the `Cognito` stack. */
  userPoolClientId: (config: AppConfig): string => `/${config.stackPrefix}/auth/client-id`,
  /**
   * Exact Cognito `sub` armed for first-admin TechnicalAdmin elevation.
   * Written by the deploy workflow (not CloudFormation) so pipeline synths
   * can re-pass it after the operator-guided setup.
   */
  technicalAdminBootstrapSubject: (config: { readonly stackPrefix: string }): string =>
    `/${config.stackPrefix}/auth/technical-admin-bootstrap-subject`,
} as const;

/**
 * Conventional name for the DynamoDB conversation/session-state table.
 *
 * Scoped to `${StackPrefix}` only (e.g. `wren-dev-ConversationHistory`) — it
 * carries NO display/brand literal. The prefix derives from the project name
 * (`wren`), per the design's Storage stack note.
 */
export function conversationTableName(config: AppConfig): string {
  return `${config.stackPrefix}-ConversationHistory`;
}
