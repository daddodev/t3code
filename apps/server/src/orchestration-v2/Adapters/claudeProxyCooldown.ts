import * as DateTime from "effect/DateTime";
import { field, text } from "../unknownField.ts";

const proxyCooldownMarker =
  /^(?:API Error:[^\r\n]*?)?\[CLIProxyAPI model_cooldown(?: retry_at=([^\]\s]+))?\] ([^\r\n]+)$/;

function retryTimestamp(value: unknown): string | null {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(value)
  )
    return null;
  const millis = Date.parse(value);
  if (!Number.isFinite(millis)) return null;
  const iso = DateTime.formatIso(DateTime.makeUnsafe(millis));
  return iso.slice(0, 19) === value.slice(0, 19) ? iso : null;
}

export function claudeProxyCooldown(result: string, apiErrorParams: unknown) {
  const structured = field(apiErrorParams, "error") ?? apiErrorParams;
  if (field(structured, "code") === "model_cooldown") {
    const message =
      text(field(structured, "message")) ?? "All eligible credentials are cooling down.";
    return {
      message: proxyCooldownMarker.exec(message)?.[2] ?? message,
      resetAt: retryTimestamp(field(structured, "retry_at")),
    };
  }
  // Claude's CLI omits headers and error metadata from SDK results, but retains this marker.
  const marker = proxyCooldownMarker.exec(result.trim());
  return marker === null ? null : { message: marker[2]!, resetAt: retryTimestamp(marker[1]) };
}
