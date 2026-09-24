/**
 * Cognito PreSignUp trigger — exact email-domain allowlist for new accounts.
 *
 * Empty `ALLOWED_EMAIL_DOMAINS` is a no-op (unrestricted signup). A non-empty
 * list rejects sign-ups whose hostname is not an exact, case-insensitive match.
 * Sign-in and password reset do not invoke this trigger.
 */
import type { PreSignUpTriggerEvent, PreSignUpTriggerHandler } from 'aws-lambda';
import {
  isSignupEmailDomainAllowed,
  parseAllowedEmailDomains,
  SIGNUP_EMAIL_DOMAIN_DENIED,
} from '@wren/types/signupEmailDomains';

export function evaluatePreSignUp(
  event: PreSignUpTriggerEvent,
  allowedDomainsRaw: string | undefined,
): PreSignUpTriggerEvent {
  const allowed = parseAllowedEmailDomains(allowedDomainsRaw, 'ALLOWED_EMAIL_DOMAINS');
  if (allowed.length === 0) {
    throw new Error(SIGNUP_EMAIL_DOMAIN_DENIED);
  }
  const email = event.request.userAttributes['email'] ?? event.userName;
  if (!isSignupEmailDomainAllowed(email, allowed)) {
    throw new Error(SIGNUP_EMAIL_DOMAIN_DENIED);
  }
  return event;
}

export const handler: PreSignUpTriggerHandler = async (event) =>
  evaluatePreSignUp(event, process.env.ALLOWED_EMAIL_DOMAINS);
