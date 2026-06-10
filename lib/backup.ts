import type { Visit } from "./types";

/** Everything the app persists, in one portable JSON document. */
export type BackupData = {
  version: 1;
  exportedAt: string;
  visits: Visit[];
  visitedBars: string[];
  badgeDates: Record<string, string>;
};

export function buildBackup(
  visits: Visit[],
  visitedBars: string[],
  badgeDates: Record<string, string>,
): BackupData {
  return {
    version: 1,
    exportedAt: new Date().toISOString(),
    visits,
    visitedBars,
    badgeDates,
  };
}

/** Parse and validate a backup JSON string; throws with a readable message. */
export function parseBackup(json: string): BackupData {
  let data: unknown;
  try {
    data = JSON.parse(json);
  } catch {
    throw new Error("That file isn't valid JSON.");
  }
  if (typeof data !== "object" || data === null) {
    throw new Error("That file isn't a backup.");
  }
  const b = data as Record<string, unknown>;
  if (b.version !== 1) {
    throw new Error("Unsupported backup version.");
  }
  if (!Array.isArray(b.visits)) {
    throw new Error("Backup is missing its visits list.");
  }
  for (const v of b.visits as unknown[]) {
    const visit = v as Record<string, unknown>;
    if (
      typeof visit?.id !== "string" ||
      typeof visit?.barId !== "string" ||
      typeof visit?.date !== "string" ||
      !Array.isArray(visit?.drinks)
    ) {
      throw new Error("Backup contains a malformed visit entry.");
    }
  }
  const visitedBars = Array.isArray(b.visitedBars)
    ? (b.visitedBars as unknown[]).filter((x): x is string => typeof x === "string")
    : [];
  const badgeDates: Record<string, string> = {};
  if (typeof b.badgeDates === "object" && b.badgeDates !== null) {
    for (const [k, v] of Object.entries(b.badgeDates)) {
      if (typeof v === "string") badgeDates[k] = v;
    }
  }
  return {
    version: 1,
    exportedAt: typeof b.exportedAt === "string" ? b.exportedAt : "",
    visits: b.visits as Visit[],
    visitedBars,
    badgeDates,
  };
}
