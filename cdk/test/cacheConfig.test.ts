import { App } from "aws-cdk-lib";
import {
  cacheEnabledWorkloadsEnv,
  resolveAppConfig,
  type AppConfig,
} from "../lib/config.js";

/**
 * Prompt-cache configuration resolution (plan §15). These tests prove the SAFE
 * defaults (observe / 5m / none), explicit overrides, and that invalid values
 * fail fast at synth so a typo can never mis-configure the runtime.
 */

function resolve(context: Record<string, string> = {}): AppConfig {
  const app = new App({ context });
  return resolveAppConfig(app);
}

describe("resolveAppConfig — prompt-cache defaults", () => {
  it("defaults to the safe observe/5m/none posture with no context", () => {
    const config = resolve();

    expect(config.cacheMode).toBe("observe");
    expect(config.cacheTtl).toBe("5m");
    expect(config.cacheEnabledWorkloads).toEqual([]);
    expect(cacheEnabledWorkloadsEnv(config)).toBe("");
  });
});

describe("resolveAppConfig — prompt-cache explicit overrides", () => {
  it("resolves explicit mode, 1h ttl, and a workload allowlist", () => {
    const config = resolve({
      cacheMode: "explicit",
      cacheTtl: "1h",
      cacheEnabledWorkloads: "ask-wren, feedback_primary",
    });

    expect(config.cacheMode).toBe("explicit");
    expect(config.cacheTtl).toBe("1h");
    // Both hyphen and underscore spellings normalize to canonical underscore.
    expect(config.cacheEnabledWorkloads).toEqual(["ask_wren", "feedback_primary"]);
    expect(cacheEnabledWorkloadsEnv(config)).toBe("ask_wren,feedback_primary");
  });

  it("de-duplicates repeated workloads", () => {
    const config = resolve({ cacheEnabledWorkloads: "ask_wren ask-wren ask_wren" });
    expect(config.cacheEnabledWorkloads).toEqual(["ask_wren"]);
  });

  it("resolves the off rollback mode", () => {
    expect(resolve({ cacheMode: "off" }).cacheMode).toBe("off");
  });
});

describe("resolveAppConfig — prompt-cache validation", () => {
  it("rejects an unknown cacheMode", () => {
    expect(() => resolve({ cacheMode: "on" })).toThrow(/cacheMode/);
  });

  it("rejects an unsupported cacheTtl", () => {
    expect(() => resolve({ cacheTtl: "10m" })).toThrow(/cacheTtl/);
  });

  it("rejects an unknown workload token instead of silently ignoring it", () => {
    expect(() => resolve({ cacheEnabledWorkloads: "ask_wren, bogus_workload" })).toThrow(
      /unknown workload/,
    );
  });
});

describe("resolveAppConfig — optional custom domain", () => {
  it("is undefined when no customDomain context is provided", () => {
    expect(resolve().customDomain).toBeUndefined();
  });

  it("maps the customDomain context key into AppConfig", () => {
    expect(resolve({ customDomain: "cloud-inov.com" }).customDomain).toBe("cloud-inov.com");
  });

  it("defaults allowedEmailDomains to ubc.ca and maps context", () => {
    expect(resolve().allowedEmailDomains).toEqual(["ubc.ca"]);
    expect(resolve({ allowedEmailDomains: "ubc.ca, alumni.ubc.ca" }).allowedEmailDomains).toEqual([
      "ubc.ca",
      "alumni.ubc.ca",
    ]);
  });

  it("rejects a malformed allowedEmailDomains context value", () => {
    expect(() => resolve({ allowedEmailDomains: "UBC.CA" })).toThrow("allowedEmailDomains");
  });

  it("parses corsAllowedOrigins and defaults to none", () => {
    expect(resolve().corsAllowedOrigins).toEqual([]);
    expect(
      resolve({ corsAllowedOrigins: "https://a.example, https://b.example" }).corsAllowedOrigins,
    ).toEqual(["https://a.example", "https://b.example"]);
  });
});
