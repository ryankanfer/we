"use client";

// Demo content: lets WE render fully without a backend — for design preview and
// for anyone who wants to feel the product before signing in. Real data replaces
// all of this once a couple is signed in and paired.

import type { InsightRecord, Reflection } from "./types";
import type { Member } from "./session";
import { initialState } from "./consent";

export const DEMO_MEMBERS: Member[] = [
  { id: "ry", name: "Ry", hue: "burgundy" },
  { id: "alex", name: "Alex", hue: "sage" },
];

export function demoRecords(): InsightRecord[] {
  const seed = [
    {
      id: "saturday-errands",
      kind: "logistical" as const,
      domain: "life" as const,
      present: true,
      title: "Three errands are competing for Saturday.",
      body: "The pharmacy pickup, the hardware return, and the grocery run are all pointing at the same morning. Folded together, they are one loop that ends by noon.",
      evidence: "Three open tasks reference Saturday, and the last two Saturdays both filled up by 10 AM.",
      source: "Task list · recent Saturdays",
      options: ["Fold them into one plan", "Split them between us", "Leave Saturday open"],
    },
    {
      id: "evening-together",
      kind: "relational" as const,
      domain: "us" as const,
      present: true,
      title: "You haven’t had an evening that belonged only to you two in eleven days.",
      body: "Nothing is wrong. The calendar has simply been full of everything else. Tomorrow is open after 7:30.",
      evidence: "Eleven days since the last shared evening with nothing scheduled around it.",
      source: "Shared calendar · time-together pattern",
      options: ["Take tomorrow, after 7:30", "Pick another night this week", "Let this week pass"],
    },
    {
      id: "august-trip",
      kind: "unresolved" as const,
      domain: "life" as const,
      present: false,
      title: "The August trip question keeps returning.",
      body: "It has been set aside twice, each time with the same words: “let’s decide later.” Later keeps arriving. It might be lighter to hold it once, together, than to keep carrying it separately.",
      evidence: "Postponed twice over three weeks, most recently nine days ago.",
      source: "Decisions · postponement pattern",
      options: ["Keep it", "Change it", "Let this go together"],
    },
    {
      id: "unhurried-time",
      kind: "relational" as const,
      domain: "us" as const,
      present: false,
      title: "It’s been a while since you were together with nowhere to be.",
      body: "Not a plan, not an occasion — just unhurried time. Those hours have quietly thinned out over the last few weeks.",
      evidence: "No unscheduled time together, longer than an hour, in the last two weeks.",
      source: "Shared calendar · rhythm of unplanned time",
      options: ["Make a little room this week", "Leave space for it to happen", "Let this pass"],
    },
  ];
  return seed.map((insight) => ({ insight, state: initialState("shared") }));
}

export const DEMO_REFLECTIONS: Reflection[] = [
  {
    id: "ry-r1",
    owner: "ry",
    domain: "life",
    kind: "reflection",
    text: "I keep circling the August trip without landing. I think I’m waiting to feel certain, and certainty isn’t coming.",
  },
  {
    id: "ry-s1",
    owner: "ry",
    domain: "us",
    kind: "suggestion",
    text: "You tend to bring things up late at night, when you’re both tired. Tomorrow after dinner might land more softly.",
  },
  {
    id: "alex-r1",
    owner: "alex",
    domain: "us",
    kind: "reflection",
    text: "The week felt long. Nothing specific — just long. A quiet night would help more than a plan would.",
  },
];

/* ---- Static dashboard content for the richer surfaces (Today / Plan / Home) ---- */

export const TODAY = {
  greeting: "Good evening",
  glance: [
    { icon: "calendar", label: "2 events today" },
    { icon: "check", label: "1 task together" },
    { icon: "utensils", label: "Dinner at 7:00" },
  ],
  energy: [
    { who: "ry" as const, state: "Steady" },
    { who: "alex" as const, state: "Stretched" },
  ],
  tinyMoment: { title: "Thinking of you", sub: "Send a small moment to Alex" },
  dateNight: { title: "Date night", sub: "7:00 PM · Nami", when: "Tomorrow" },
};

export const WEEK = {
  days: [
    { d: "M", n: 20 },
    { d: "T", n: 21 },
    { d: "W", n: 22 },
    { d: "T", n: 23 },
    { d: "F", n: 24 },
    { d: "S", n: 25 },
    { d: "S", n: 26 },
  ],
  today: 22,
  events: [
    { time: "8 AM", title: "Ry — Workout", who: "ry" as const },
    { time: "10 AM", title: "Team standup", who: "ry" as const },
    { time: "12 PM", title: "Alex — Client call", who: "alex" as const },
    { time: "2 PM", title: "Grocery run", who: "both" as const },
    { time: "6 PM", title: "Dinner at Nami · Date night", who: "both" as const, accent: true },
    { time: "9 PM", title: "Wind down", who: "both" as const },
  ],
};

export const HOMEBOARD = {
  upNext: [
    { title: "Buy birthday gift for Mom", who: "ry" as const },
    { title: "Call the landlord", who: "alex" as const },
    { title: "Renew passports", who: "both" as const },
    { title: "Book vet appointment", who: "alex" as const },
  ],
  smoothly: [
    { icon: "basket", label: "Groceries", sub: "On track" },
    { icon: "receipt", label: "Bills", sub: "Paid" },
    { icon: "plant", label: "Plants", sub: "Watered" },
  ],
  comingUp: [
    { title: "Car insurance", sub: "Due in 12 days" },
    { title: "Annual subscription", sub: "Due in 18 days" },
  ],
};
