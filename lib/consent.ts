import type {
  InsightState,
  PersonId,
  PersonResponse,
  Readiness,
  ResponseStatus,
} from "./types";

/**
 * The consent state machine. Three independent axes:
 *   visibility: private → shared → mutual   (who may know this exists)
 *   readiness:  idle → requested → accepted (whether both are ready to engage)
 *   response:   none → draft → submitted → revealed   (each person's private answer)
 *
 * Invariants this module must never break:
 *  - One partner's draft or submitted answer is never visible to the other
 *    until BOTH have submitted (then both become revealed together).
 *  - A withdrawn request leaves no trace on the partner's side.
 *  - A decline is private: the initiator's projection of "declined" is
 *    indistinguishable from quiet waiting. "Not ready" is safe.
 *  - Private (Mine) items are never projected to the non-owner.
 */

export const partnerOf = (p: PersonId): PersonId => (p === "ry" ? "dylan" : "ry");

export function initialState(
  visibility: "private" | "shared" = "shared",
  owner?: PersonId
): InsightState {
  return {
    visibility,
    owner: visibility === "private" ? owner : undefined,
    readiness: "idle",
    responses: {
      ry: { status: "none" },
      dylan: { status: "none" },
    },
    dismissedBy: [],
  };
}

class TransitionError extends Error {}

function fail(msg: string): never {
  throw new TransitionError(msg);
}

/** Bring it back gently: ask the partner to open this together. */
export function requestReveal(s: InsightState, by: PersonId, at: number): InsightState {
  if (s.resolution) fail("already resolved");
  if (!(s.readiness === "idle" || s.readiness === "withdrawn")) fail("reveal already in motion");
  if (s.visibility === "private" && s.owner !== by) fail("cannot request someone else's private item");
  return {
    ...s,
    // Requesting exposes the topic and the sender — nothing more.
    visibility: s.visibility === "mutual" ? "mutual" : "shared",
    owner: undefined,
    readiness: "requested",
    initiator: by,
    requestedAt: at,
  };
}

/** "I'm ready to engage" — not "I consent to learn this exists." */
export function acceptReveal(s: InsightState, by: PersonId, at: number): InsightState {
  if (!(s.readiness === "requested" || s.readiness === "declined")) fail("nothing to accept");
  if (by === s.initiator) fail("initiator cannot accept their own request");
  return { ...s, readiness: "accepted", visibility: "mutual", acceptedAt: at };
}

/** Private "not yet". The initiator's view does not change. */
export function declineReveal(s: InsightState, by: PersonId): InsightState {
  if (s.readiness !== "requested") fail("nothing to decline");
  if (by === s.initiator) fail("initiator cannot decline their own request");
  return { ...s, readiness: "declined" };
}

/** The initiator takes it back. No record remains on the partner's side. */
export function withdrawReveal(s: InsightState, by: PersonId): InsightState {
  if (!(s.readiness === "requested" || s.readiness === "declined")) fail("nothing to withdraw");
  if (by !== s.initiator) fail("only the initiator can withdraw");
  return {
    ...s,
    readiness: "withdrawn",
    initiator: undefined,
    requestedAt: undefined,
  };
}

function withResponse(s: InsightState, by: PersonId, r: PersonResponse): InsightState {
  return { ...s, responses: { ...s.responses, [by]: r } };
}

/** Answers are drafted privately inside Between Us. */
export function saveDraft(s: InsightState, by: PersonId, choice: string, note?: string): InsightState {
  if (s.visibility !== "mutual") fail("answers happen only in Between Us");
  const mine = s.responses[by].status;
  if (mine === "submitted" || mine === "revealed") fail("already submitted");
  return withResponse(s, by, { status: "draft", choice, note });
}

/**
 * Submit a private answer. When both have submitted, both are revealed
 * together — never one before the other.
 */
export function submitResponse(s: InsightState, by: PersonId, choice: string, note?: string): InsightState {
  if (s.visibility !== "mutual") fail("answers happen only in Between Us");
  const mine = s.responses[by].status;
  if (mine === "submitted" || mine === "revealed") fail("already submitted");
  let next = withResponse(s, by, { status: "submitted", choice, note });
  const other = partnerOf(by);
  if (next.responses[other].status === "submitted") {
    next = {
      ...next,
      responses: {
        ry: { ...next.responses.ry, status: "revealed" },
        dylan: { ...next.responses.dylan, status: "revealed" },
      },
    };
  }
  return next;
}

/** Do the revealed answers agree? Meaningful only once both are revealed. */
export function answersMatch(s: InsightState): boolean | undefined {
  if (s.responses.ry.status !== "revealed" || s.responses.dylan.status !== "revealed") return undefined;
  return s.responses.ry.choice === s.responses.dylan.choice;
}

/** Settle, release, or leave open — decided together after the reveal. */
export function resolve(
  s: InsightState,
  type: "settled" | "released" | "leftOpen",
  at: number,
  choice?: string
): InsightState {
  if (s.responses.ry.status !== "revealed" || s.responses.dylan.status !== "revealed")
    fail("cannot resolve before both answers are revealed");
  return { ...s, resolution: { type, choice, at } };
}

/** Individual, quiet dismissal of WE's suggestion. Affects only this person's feed. */
export function dismissSuggestion(s: InsightState, by: PersonId): InsightState {
  if (s.readiness !== "idle" && s.readiness !== "withdrawn") fail("cannot dismiss once it is between you");
  if (s.dismissedBy.includes(by)) return s;
  return { ...s, dismissedBy: [...s.dismissedBy, by] };
}

/* ------------------------------------------------------------------ */
/* Projection: what a given viewer is permitted to see.                */
/* ------------------------------------------------------------------ */

export type Phase =
  | "hidden" // not in this viewer's world at all
  | "open" // ordinary card in Ours
  | "waiting" // viewer initiated; partner has not accepted (or has privately declined)
  | "invited" // partner initiated; viewer may accept or quietly pass
  | "answering" // mutual; viewer has not yet submitted
  | "held" // mutual; viewer submitted, partner has not
  | "revealed" // both answers visible; matched or not
  | "resolved";

export interface Projection {
  phase: Phase;
  visibility: InsightState["visibility"];
  initiator?: PersonId;
  requestedAt?: number;
  myResponse: PersonResponse;
  /** Partner's answer — present ONLY when status is "revealed". */
  partnerResponse?: { choice?: string; note?: string };
  matched?: boolean;
  resolution?: InsightState["resolution"];
  dismissed: boolean;
}

export function projectFor(s: InsightState, viewer: PersonId): Projection | null {
  const other = partnerOf(viewer);

  // Mine is private: non-owners never see private items.
  if (s.visibility === "private" && s.owner !== viewer) return null;

  // A withdrawn request leaves no trace for the partner; for the initiator
  // (and everyone, once withdrawn) it is an ordinary open card again.
  const readiness: Readiness = s.readiness;

  const mine = s.responses[viewer];
  const theirs = s.responses[other];

  const myResponse: PersonResponse =
    mine.status === "revealed" || mine.status === "draft" || mine.status === "submitted" || mine.status === "none"
      ? { ...mine }
      : { status: "none" as ResponseStatus };

  const base: Projection = {
    phase: "open",
    visibility: s.visibility,
    initiator: s.initiator,
    requestedAt: s.requestedAt,
    myResponse,
    dismissed: s.dismissedBy.includes(viewer),
  };

  if (s.resolution) return { ...base, phase: "resolved", resolution: s.resolution, partnerResponse: revealedOnly(theirs), matched: answersMatch(s) };

  if (readiness === "requested" || readiness === "declined") {
    if (viewer === s.initiator) {
      // Decline is private: initiator sees quiet waiting either way.
      return { ...base, phase: "waiting" };
    }
    if (readiness === "declined") {
      // The decliner keeps the invitation available, without pressure.
      return { ...base, phase: "invited" };
    }
    return { ...base, phase: "invited" };
  }

  if (s.visibility === "mutual") {
    if (mine.status === "revealed" && theirs.status === "revealed") {
      return { ...base, phase: "revealed", partnerResponse: revealedOnly(theirs), matched: answersMatch(s) };
    }
    if (mine.status === "submitted") return { ...base, phase: "held" };
    return { ...base, phase: "answering" };
  }

  return base; // idle or withdrawn → ordinary open card
}

function revealedOnly(r: PersonResponse): { choice?: string; note?: string } | undefined {
  if (r.status !== "revealed") return undefined;
  return { choice: r.choice, note: r.note };
}
