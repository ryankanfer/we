"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { InsightRecord, PersonId } from "./types";
import {
  acceptReveal,
  declineReveal,
  dismissSuggestion,
  requestReveal,
  resolve,
  saveDraft,
  submitResponse,
  withdrawReveal,
} from "./consent";
import { seedRecords } from "./seed";

interface WeStore {
  /** Which partner this device is currently experiencing. Demo control only. */
  viewer: PersonId;
  /** Demo clock, in hours since the session began. */
  clock: number;
  records: InsightRecord[];
  /** First-run onboarding: the contract WE makes before showing anything. */
  onboarded: boolean;
  /** Screen-reader announcement channel (aria-live). */
  announcement: string;

  setViewer: (p: PersonId) => void;
  completeOnboarding: (p: PersonId) => void;
  advanceClock: (hours: number) => void;
  announce: (msg: string) => void;
  reset: () => void;

  request: (id: string) => void;
  accept: (id: string) => void;
  decline: (id: string) => void;
  withdraw: (id: string) => void;
  draft: (id: string, choice: string, note?: string) => void;
  submit: (id: string, choice: string, note?: string) => void;
  settle: (id: string, type: "settled" | "released" | "leftOpen", choice?: string) => void;
  dismiss: (id: string) => void;
}

function update(
  records: InsightRecord[],
  id: string,
  fn: (r: InsightRecord) => InsightRecord
): InsightRecord[] {
  return records.map((r) => (r.insight.id === id ? fn(r) : r));
}

export const useWeStore = create<WeStore>()(
  persist(
    (set, get) => ({
      viewer: "ry",
      clock: 0,
      records: seedRecords(),
      onboarded: false,
      announcement: "",

      setViewer: (p) => set({ viewer: p }),
      completeOnboarding: (p) =>
        set({
          viewer: p,
          onboarded: true,
          announcement: "Welcome in. Here’s what needs the two of you.",
        }),
      advanceClock: (hours) => set((s) => ({ clock: s.clock + hours })),
      announce: (msg) => set({ announcement: msg }),
      reset: () =>
        set({
          viewer: "ry",
          clock: 0,
          records: seedRecords(),
          onboarded: false,
          announcement: "Demo reset.",
        }),

      request: (id) =>
        set((s) => ({
          records: update(s.records, id, (r) => ({
            ...r,
            state: requestReveal(r.state, s.viewer, s.clock),
          })),
          announcement: "Brought to your partner. Waiting, without pressure.",
        })),
      accept: (id) =>
        set((s) => ({
          records: update(s.records, id, (r) => ({
            ...r,
            state: acceptReveal(r.state, s.viewer, s.clock),
          })),
          announcement: "Opened together. This now lives between you.",
        })),
      decline: (id) =>
        set((s) => ({
          records: update(s.records, id, (r) => ({
            ...r,
            state: declineReveal(r.state, s.viewer),
          })),
          announcement: "Held for later. Your partner will not be notified.",
        })),
      withdraw: (id) =>
        set((s) => ({
          records: update(s.records, id, (r) => ({
            ...r,
            state: withdrawReveal(r.state, s.viewer),
          })),
          announcement: "Withdrawn. No record remains.",
        })),
      draft: (id, choice, note) =>
        set((s) => ({
          records: update(s.records, id, (r) => ({
            ...r,
            state: saveDraft(r.state, s.viewer, choice, note),
          })),
        })),
      submit: (id, choice, note) =>
        set((s) => {
          const records = update(s.records, id, (r) => ({
            ...r,
            state: submitResponse(r.state, s.viewer, choice, note),
          }));
          const rec = records.find((r) => r.insight.id === id)!;
          const revealed = rec.state.responses[s.viewer].status === "revealed";
          return {
            records,
            announcement: revealed
              ? "Both answers are in. Revealed together."
              : "Your answer is in. It stays private until both of you have answered.",
          };
        }),
      settle: (id, type, choice) =>
        set((s) => ({
          records: update(s.records, id, (r) => ({
            ...r,
            state: resolve(r.state, type, s.clock, choice),
          })),
          announcement:
            type === "leftOpen" ? "Left open. Nothing has been decided." : "Settled together.",
        })),
      dismiss: (id) =>
        set((s) => ({
          records: update(s.records, id, (r) => ({
            ...r,
            state: dismissSuggestion(r.state, s.viewer),
          })),
          announcement: "Suggestion dismissed, just for you.",
        })),
    }),
    { name: "we-demo-v2" }
  )
);
