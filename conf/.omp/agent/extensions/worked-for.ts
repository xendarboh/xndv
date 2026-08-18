import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const WIDGET_KEY = "worked-for";

function formatDuration(milliseconds: number): string {
  let seconds = Math.max(0, Math.round(milliseconds / 1000));

  const hours = Math.floor(seconds / 3600);
  seconds %= 3600;

  const minutes = Math.floor(seconds / 60);
  seconds %= 60;

  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

export default function workedFor(pi: ExtensionAPI): void {
  let startedAt: number | undefined;

  pi.on("agent_start", (_event, ctx) => {
    // Preserve the original start across automatic continuations.
    if (startedAt !== undefined) return;

    startedAt = performance.now();

    if (ctx.hasUI) {
      ctx.ui.setWidget(WIDGET_KEY, undefined);
    }
  });

  pi.on("agent_end", (event, ctx) => {
    // Auto-retries and other scheduled continuations are not the visible end.
    if (event.willContinue || startedAt === undefined) return;

    const elapsed = performance.now() - startedAt;
    startedAt = undefined;

    if (ctx.hasUI) {
      ctx.ui.setWidget(
        WIDGET_KEY,
        [`✻ Worked for ${formatDuration(elapsed)}`],
        { placement: "aboveEditor" },
      );
    }
  });

  pi.on("session_shutdown", () => {
    startedAt = undefined;
  });
}
