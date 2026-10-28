import { describe, expect, it } from "vite-plus/test";
import type { OrchestrationV2ProviderFailure } from "@t3tools/contracts";
import { providerFailureTitle, threadErrorSummary } from "./orchestrationV2ThreadError.ts";

const cooldown: OrchestrationV2ProviderFailure = {
  class: "usage_limit",
  code: "model_cooldown",
  message: "Claude temporarily rate limited. All eligible credentials are cooling down.",
  retryable: true,
  resetAt: "2033-05-19T07:20:00.000Z",
};

describe("provider cooldown presentation", () => {
  it("carries the cooldown code and deadline into shell and client summaries", () => {
    const summary = threadErrorSummary(cooldown, cooldown.message);
    expect(summary).toMatchObject({
      lastErrorCode: "model_cooldown",
      usageLimitResetAt: cooldown.resetAt,
    });
    expect(
      providerFailureTitle({ class: summary.lastErrorClass, code: summary.lastErrorCode }),
    ).toBe("Temporarily rate limited");
    expect(providerFailureTitle({ ...cooldown, code: "api_error_429" })).toBe(
      "Usage limit reached",
    );
  });

  it("drops cooldown metadata when the session reports another failure", () => {
    const summary = threadErrorSummary(cooldown, "Connection closed");
    expect(summary.lastErrorCode).toBeNull();
    expect(summary.usageLimitResetAt).toBeNull();
    expect(
      providerFailureTitle({ class: summary.lastErrorClass, code: summary.lastErrorCode }),
    ).toBe("Provider error");
  });
});
