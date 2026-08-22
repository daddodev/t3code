import { useEffect, useRef } from "react";
import { useNavigate } from "@tanstack/react-router";

import { APP_DISPLAY_NAME } from "../branding";
import { useClientSettings } from "../hooks/useSettings";
import { useThreadShells } from "../state/entities";

/** Emits one system notification per observed completed turn, never for initial data hydration. */
export function BrowserCompletionNotifications() {
  const navigate = useNavigate();
  const { browserCompletionNotifications } = useClientSettings();
  const threads = useThreadShells();
  const observedCompletionKeys = useRef(new Set<string>());
  const hydrated = useRef(false);

  useEffect(() => {
    const completedThreads = threads.flatMap((thread) => {
      const completedAt = thread.latestTurn?.completedAt;
      return completedAt
        ? [
            {
              key: `${thread.environmentId}:${thread.id}:${completedAt}`,
              title: thread.title,
              environmentId: thread.environmentId,
              threadId: thread.id,
            },
          ]
        : [];
    });

    if (!hydrated.current) {
      for (const completedThread of completedThreads)
        observedCompletionKeys.current.add(completedThread.key);
      hydrated.current = true;
      return;
    }

    for (const completedThread of completedThreads) {
      if (observedCompletionKeys.current.has(completedThread.key)) continue;
      observedCompletionKeys.current.add(completedThread.key);
      if (
        !browserCompletionNotifications ||
        document.visibilityState === "visible" ||
        typeof Notification === "undefined" ||
        Notification.permission !== "granted"
      ) {
        continue;
      }
      const notification = new Notification(APP_DISPLAY_NAME, {
        body: `${completedThread.title} has finished.`,
        tag: completedThread.key,
      });
      notification.addEventListener("click", () => {
        window.focus();
        void navigate({
          to: "/$environmentId/$threadId",
          params: {
            environmentId: completedThread.environmentId,
            threadId: completedThread.threadId,
          },
        });
      });
    }
  }, [browserCompletionNotifications, navigate, threads]);

  return null;
}
