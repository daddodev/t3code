import { describe, expect, it } from "vite-plus/test";
import { claudeProxyCooldown } from "./claudeProxyCooldown.ts";

const retryAt = "2033-05-19T07:20:00.123456789Z";
const message = "All credentials for model claude-opus-5-5 are cooling down via provider claude";
const result = `API Error: Request rejected (429) · [CLIProxyAPI model_cooldown retry_at=${retryAt}] ${message}`;

describe("Claude proxy cooldown", () => {
  it("recovers the absolute deadline from the SDK's message-only result", () => {
    expect(claudeProxyCooldown(result, undefined)).toEqual({
      message,
      resetAt: "2033-05-19T07:20:00.123Z",
    });
  });

  it("prefers structured metadata when the SDK supplies it", () => {
    expect(
      claudeProxyCooldown(result, {
        error: { code: "model_cooldown", retry_at: "2033-05-19T07:21:00Z", message },
      }),
    ).toEqual({ message, resetAt: "2033-05-19T07:21:00.000Z" });
  });

  it.each([undefined, "unknown", "Infinity", "2033-02-30T00:00:00Z", "9999999999-01-01T00:00:00Z"])(
    "keeps an unknown or invalid deadline unavailable: %s",
    (deadline) => {
      const suffix = deadline === undefined ? "" : ` retry_at=${deadline}`;
      expect(
        claudeProxyCooldown(
          `API Error: 429 [CLIProxyAPI model_cooldown${suffix}] ${message}`,
          undefined,
        ),
      ).toEqual({ message, resetAt: null });
    },
  );

  it("retains a past absolute deadline rather than moving it forward", () => {
    expect(
      claudeProxyCooldown(
        `[CLIProxyAPI model_cooldown retry_at=2000-01-01T00:00:00Z] ${message}`,
        undefined,
      )?.resetAt,
    ).toBe("2000-01-01T00:00:00.000Z");
  });

  it.each([
    "API Error: Request rejected (429) · This request would exceed your account's rate limit.",
    `Quoted text [CLIProxyAPI model_cooldown retry_at=${retryAt}] ${message}`,
    "API Error: [CLIProxyAPI model_cooldown]",
  ])("does not classify an unmarked or unrelated error: %s", (value) => {
    expect(claudeProxyCooldown(value, undefined)).toBeNull();
  });
});
