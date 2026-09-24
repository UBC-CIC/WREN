/**
 * Unit tests for the Secrets Manager salt-resolution path of
 * {@link ensurePseudonymSalt} (INFORMATION_DISCLOSURE remediation: the actor
 * pseudonym salt must be fetched from Secrets Manager at runtime, never read
 * from a plaintext Lambda env var that `lambda:GetFunctionConfiguration` could
 * expose).
 *
 * These live in a separate file from `activityLogService.test.ts` because they
 * (a) mock `@aws-sdk/client-secrets-manager` at the module level and (b) reset
 * module state between cases to exercise the per-container cache — neither of
 * which should perturb the plaintext-env-based tests in the sibling suite.
 */

// jest.mock is hoisted; the factory may only reference vars prefixed with `mock`.
const mockSend = jest.fn();

jest.mock('@aws-sdk/client-secrets-manager', () => ({
  SecretsManagerClient: jest.fn(() => ({ send: mockSend })),
  GetSecretValueCommand: jest.fn((input: unknown) => ({ input })),
}));

const SECRET_ARN =
  'arn:aws:secretsmanager:us-east-1:123456789012:secret:wren-dev/audit/pseudonym-salt-AbCdEf';

/** Re-import the module fresh so its per-container salt cache starts empty. */
async function freshEnsurePseudonymSalt() {
  jest.resetModules();
  const mod = await import('./activityLogService');
  return mod.ensurePseudonymSalt;
}

beforeEach(() => {
  mockSend.mockReset();
  delete process.env.WREN_ACTIVITY_PSEUDONYM_SALT;
  delete process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN;
});

describe('ensurePseudonymSalt — Secrets Manager resolution', () => {
  it('fetches the salt from Secrets Manager when only the secret ARN is configured', async () => {
    process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN = SECRET_ARN;
    mockSend.mockResolvedValue({ SecretString: 'salt-from-secrets-manager' });

    const ensurePseudonymSalt = await freshEnsurePseudonymSalt();
    await expect(ensurePseudonymSalt()).resolves.toBe('salt-from-secrets-manager');
    expect(mockSend).toHaveBeenCalledTimes(1);
  });

  it('caches the fetched salt for the container: subsequent calls do not re-fetch', async () => {
    process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN = SECRET_ARN;
    mockSend.mockResolvedValue({ SecretString: 'cached-salt' });

    const ensurePseudonymSalt = await freshEnsurePseudonymSalt();
    await ensurePseudonymSalt();
    await ensurePseudonymSalt();
    await ensurePseudonymSalt();

    expect(mockSend).toHaveBeenCalledTimes(1);
  });

  it('memoizes the in-flight fetch so concurrent callers share one API call', async () => {
    process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN = SECRET_ARN;
    let resolveFetch: ((v: { SecretString: string }) => void) | undefined;
    mockSend.mockReturnValue(
      new Promise((resolve) => {
        resolveFetch = resolve;
      }),
    );

    const ensurePseudonymSalt = await freshEnsurePseudonymSalt();
    const a = ensurePseudonymSalt();
    const b = ensurePseudonymSalt();
    resolveFetch?.({ SecretString: 'concurrent-salt' });

    await expect(a).resolves.toBe('concurrent-salt');
    await expect(b).resolves.toBe('concurrent-salt');
    expect(mockSend).toHaveBeenCalledTimes(1);
  });

  it('fails closed when the secret resolves to an empty/binary value', async () => {
    process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN = SECRET_ARN;
    mockSend.mockResolvedValue({ SecretString: undefined });

    const ensurePseudonymSalt = await freshEnsurePseudonymSalt();
    await expect(ensurePseudonymSalt()).rejects.toThrow(/empty or binary secret/);
  });

  it('drops the memoized promise on failure so a transient error is retried', async () => {
    process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN = SECRET_ARN;
    mockSend
      .mockRejectedValueOnce(new Error('transient Secrets Manager failure'))
      .mockResolvedValueOnce({ SecretString: 'salt-after-retry' });

    const ensurePseudonymSalt = await freshEnsurePseudonymSalt();
    await expect(ensurePseudonymSalt()).rejects.toThrow(/transient/);
    await expect(ensurePseudonymSalt()).resolves.toBe('salt-after-retry');
    expect(mockSend).toHaveBeenCalledTimes(2);
  });

  it('fails closed when neither the plaintext salt nor the secret ARN is set', async () => {
    const ensurePseudonymSalt = await freshEnsurePseudonymSalt();
    await expect(ensurePseudonymSalt()).rejects.toThrow(
      /WREN_ACTIVITY_PSEUDONYM_SALT/,
    );
    expect(mockSend).not.toHaveBeenCalled();
  });

  it('prefers the plaintext env override (tests/local) and never calls Secrets Manager', async () => {
    process.env.WREN_ACTIVITY_PSEUDONYM_SALT = 'plaintext-local-salt';
    process.env.WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN = SECRET_ARN;

    const ensurePseudonymSalt = await freshEnsurePseudonymSalt();
    await expect(ensurePseudonymSalt()).resolves.toBe('plaintext-local-salt');
    expect(mockSend).not.toHaveBeenCalled();
  });
});
