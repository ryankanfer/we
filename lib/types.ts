export type PersonId = "ry" | "dylan";

export interface Person {
  id: PersonId;
  name: string;
  /** Relational identity color token: "burgundy" | "sage" */
  hue: "burgundy" | "sage";
}

export type InsightKind = "logistical" | "relational" | "unresolved";

/**
 * The lenses WE organizes intelligence around. These are facets of one shared
 * life, never ownership boundaries — "Us" is the relationship, not "your space."
 *   life — the life the two of you are building and running
 *   us   — the two of you: closeness, time, attention
 * "Today" is not a domain; it is the present cross-section (see `present`).
 */
export type Domain = "life" | "us";

/** Content of a surfaced card. Immutable; state lives in InsightState. */
export interface Insight {
  id: string;
  kind: InsightKind;
  /** Which lens of the shared life this belongs to. */
  domain: Domain;
  /** Whether it is live right now — surfaces under the "Today" lens. */
  present: boolean;
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

/**
 * A private reflection belonging to one person. Never projected to the partner.
 * Privacy is a property, not a place: these surface inline within the shared
 * continuity — under the same lens — visible only to their owner.
 */
export interface Reflection {
  id: string;
  owner: PersonId;
  domain: Domain;
  text: string;
  kind: "reflection" | "suggestion";
}
