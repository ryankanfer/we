export type PersonId = "ry" | "dylan";

export interface Person {
  id: PersonId;
  name: string;
  /** Relational identity color token: "burgundy" | "sage" */
  hue: "burgundy" | "sage";
}

export type InsightKind = "logistical" | "relational" | "unresolved";

/** Content of a surfaced card. Immutable; state lives in InsightState. */
export interface Insight {
  id: string;
  kind: InsightKind;
  /** The editorial observation, set in serif. */
  title: string;
  body: string;
  /** Why WE noticed this — always shown, never hidden. */
  evidence: string;
  source: string;
  /** The choice set answered privately once the insight is mutually open. */
  options: string[];
}

/** Mine is private. Ours is known. Between Us is mutually opened. */
export type Visibility = "private" | "shared" | "mutual";

/** Lifecycle of the reveal request itself. */
export type Readiness = "idle" | "requested" | "accepted" | "declined" | "withdrawn";

/** Lifecycle of one person's private answer. */
export type ResponseStatus = "none" | "draft" | "submitted" | "revealed";

export interface PersonResponse {
  status: ResponseStatus;
  choice?: string;
  note?: string;
}

export interface Resolution {
  type: "settled" | "released" | "leftOpen";
  choice?: string;
  /** Demo-clock hours. */
  at: number;
}

export interface InsightState {
  visibility: Visibility;
  /** Set only while visibility is "private" — whose Mine space holds it. */
  owner?: PersonId;
  readiness: Readiness;
  initiator?: PersonId;
  /** Demo-clock hours. */
  requestedAt?: number;
  acceptedAt?: number;
  responses: Record<PersonId, PersonResponse>;
  /** Individual, quiet dismissals of WE's suggestion. */
  dismissedBy: PersonId[];
  resolution?: Resolution;
}

export interface InsightRecord {
  insight: Insight;
  state: InsightState;
}

/** A private reflection living in one person's Mine space. Never projected to the partner. */
export interface Reflection {
  id: string;
  owner: PersonId;
  text: string;
  kind: "reflection" | "suggestion";
}
