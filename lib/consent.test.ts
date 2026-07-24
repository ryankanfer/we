import { describe, expect, it } from "vitest";
import {
  acceptReveal,
  answersMatch,
  declineReveal,
  dismissSuggestion,
  initialState,
  projectFor,
  requestReveal,
  resolve,
  saveDraft,
  submitResponse,
  withdrawReveal,
} from "./consent";

describe("consent state machine", () => {
  it("walks the happy path: request → accept → both answer privately → mutual reveal", () => {
    let s = initialState();
    s = requestReveal(s, "ry", 1);
    expect(s.readiness).toBe("requested");
    expect(projectFor(s, "ry")?.phase).toBe("waiting");
    expect(projectFor(s, "dylan")?.phase).toBe("invited");

    s = acceptReveal(s, "dylan", 2);
    expect(s.visibility).toBe("mutual");

    s = submitResponse(s, "ry", "Keep it", "I want the time away with you.");
    // Privacy invariant: Dylan cannot see Ry's submitted answer yet.
    const dylanView = projectFor(s, "dylan")!;
    expect(dylanView.partnerResponse).toBeUndefined();
    expect(dylanView.phase).toBe("answering");
    expect(projectFor(s, "ry")!.phase).toBe("held");

    s = submitResponse(s, "dylan", "Keep it");
    expect(s.responses.ry.status).toBe("revealed");
    expect(s.responses.dylan.status).toBe("revealed");
    expect(answersMatch(s)).toBe(true);
    expect(projectFor(s, "dylan")!.partnerResponse?.note).toBe("I want the time away with you.");
  });

  it("surfaces a mismatch without deciding anything", () => {
    let s = initialState();
    s = requestReveal(s, "ry", 0);
    s = acceptReveal(s, "dylan", 1);
    s = submitResponse(s, "ry", "Keep it");
    s = submitResponse(s, "dylan", "Change it");
    expect(answersMatch(s)).toBe(false);
    expect(s.resolution).toBeUndefined();
    s = resolve(s, "leftOpen", 2);
    expect(s.resolution?.type).toBe("leftOpen");
  });

  it("never reveals one answer before both are submitted", () => {
    let s = initialState();
    s = requestReveal(s, "dylan", 0);
    s = acceptReveal(s, "ry", 1);
    s = saveDraft(s, "ry", "Change it", "a private draft");
    expect(projectFor(s, "dylan")!.partnerResponse).toBeUndefined();
    s = submitResponse(s, "ry", "Change it", "a private note");
    expect(projectFor(s, "dylan")!.partnerResponse).toBeUndefined();
  });

  it("keeps a decline private: initiator sees quiet waiting either way", () => {
    let s = initialState();
    s = requestReveal(s, "ry", 0);
    const beforeDecline = projectFor(s, "ry")!;
    s = declineReveal(s, "dylan");
    const afterDecline = projectFor(s, "ry")!;
    expect(afterDecline.phase).toBe(beforeDecline.phase); // indistinguishable
    expect(afterDecline.phase).toBe("waiting");
    // Dylan can still accept later, without penalty.
    s = acceptReveal(s, "dylan", 5);
    expect(s.visibility).toBe("mutual");
  });

  it("leaves no trace after a withdrawal", () => {
    let s = initialState();
    s = requestReveal(s, "ry", 0);
    s = withdrawReveal(s, "ry");
    const dylanView = projectFor(s, "dylan")!;
    expect(dylanView.phase).toBe("open");
    expect(dylanView.initiator).toBeUndefined();
    expect(dylanView.requestedAt).toBeUndefined();
  });

  it("never projects a private (Mine) item to the non-owner", () => {
    const s = initialState("private", "ry");
    expect(projectFor(s, "dylan")).toBeNull();
    expect(projectFor(s, "ry")).not.toBeNull();
  });

  it("guards transitions", () => {
    let s = initialState();
    expect(() => acceptReveal(s, "dylan", 0)).toThrow();
    expect(() => submitResponse(s, "ry", "Keep it")).toThrow();
    s = requestReveal(s, "ry", 0);
    expect(() => acceptReveal(s, "ry", 1)).toThrow(); // cannot accept own request
    expect(() => withdrawReveal(s, "dylan")).toThrow(); // only initiator withdraws
    expect(() => dismissSuggestion(s, "dylan")).toThrow(); // cannot dismiss once in motion
  });

  it("dismissal is individual and quiet", () => {
    let s = initialState();
    s = dismissSuggestion(s, "ry");
    expect(projectFor(s, "ry")!.dismissed).toBe(true);
    expect(projectFor(s, "dylan")!.dismissed).toBe(false);
  });
});
