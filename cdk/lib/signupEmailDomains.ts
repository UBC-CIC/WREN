/**
 * Signup email-domain allowlist helpers for CDK synth/deploy.
 *
 * Keep in sync with `types/src/signupEmailDomains.ts`. Duplicated here so CDK
 * Jest/tsc stay inside this package (ts-jest cannot compile files outside
 * `cdk/` as part of this project). Runtime matching for Cognito and the
 * frontend still lives in `@wren/types`.
 */

const LABEL = "[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?";
const HOSTNAME = new RegExp(`^(?:${LABEL}\\.)+${LABEL}$`);

export function isAllowedEmailDomainHostname(domain: string): boolean {
  return domain.length <= 253 && HOSTNAME.test(domain);
}

export function parseAllowedEmailDomains(
  raw: string | undefined,
  sourceName = "Allowed email domains",
): string[] {
  if (raw === undefined) return [];
  const result: string[] = [];
  for (const token of raw.split(/[,\s]+/)) {
    const domain = token.trim();
    if (domain.length === 0) continue;
    if (!isAllowedEmailDomainHostname(domain)) {
      throw new Error(
        `${sourceName} must be bare lowercase hostnames like 'ubc.ca' (no scheme, path, or trailing dot).`,
      );
    }
    if (!result.includes(domain)) result.push(domain);
  }
  return result;
}

export function emailHostname(email: string): string | undefined {
  const at = email.lastIndexOf("@");
  if (at <= 0 || at === email.length - 1) return undefined;
  return email.slice(at + 1).toLowerCase();
}

export function isSignupEmailDomainAllowed(
  email: string,
  allowedDomains: readonly string[],
): boolean {
  if (allowedDomains.length === 0) return false;
  const host = emailHostname(email);
  if (host === undefined) return false;
  return allowedDomains.includes(host);
}

export function allowedEmailDomainsEnv(domains: readonly string[]): string {
  return domains.join(",");
}
