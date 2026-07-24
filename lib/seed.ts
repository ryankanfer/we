import type { Insight, InsightRecord, Person, Reflection } from "./types";
import { initialState } from "./consent";

export const PEOPLE: Record<string, Person> = {
  ry: { id: "ry", name: "Ry", hue: "burgundy" },
  dylan: { id: "dylan", name: "Dylan", hue: "sage" },
};

const INSIGHTS: Insight[] = [
  {
    id: "saturday-errands",
    kind: "logistical",
    domain: "life",
    present: true,
    title: "Three errands are competing for Saturday.",
    body: "The pharmacy pickup, the hardware return, and the grocery run are all pointing at the same morning. Folded together, they are one loop that ends by noon.",
    evidence: "Three open tasks reference Saturday, and the last two Saturdays both filled up by 10 AM.",
    source: "Task list · recent Saturdays",
    options: ["Fold them into one plan", "Split them between us", "Leave Saturday open"],
  },
  {
    id: "evening-together",
    kind: "relational",
    domain: "us",
    present: true,
    title: "You haven’t had an evening that belonged only to you two in eleven days.",
    body: "Nothing is wrong. The calendar has simply been full of everything else. Tomorrow is open after 7:30.",
    evidence: "Eleven days since the last shared evening with nothing scheduled around it.",
    source: "Shared calendar · time-together pattern",
    options: ["Take tomorrow, after 7:30", "Pick another night this week", "Let this week pass"],
  },
  {
    id: "august-trip",
    kind: "unresolved",
    domain: "life",
    present: false,
    title: "The August trip question keeps returning.",
    body: "It has been set aside twice, each time with the same words: “let’s decide later.” Later keeps arriving. It might be lighter to hold it once, together, than to keep carrying it separately.",
    evidence: "Postponed twice over three weeks, most recently nine days ago.",
    source: "Decisions · postponement pattern",
    options: ["Keep it", "Change it", "Let this go together"],
  },
  {
    id: "unhurried-time",
    kind: "relational",
    domain: "us",
    present: false,
    title: "It’s been a while since you were together with nowhere to be.",
    body: "Not a plan, not an occasion — just unhurried time. Those hours have quietly thinned out over the last few weeks.",
    evidence: "No unscheduled time together, longer than an hour, in the last two weeks.",
    source: "Shared calendar · rhythm of unplanned time",
    options: ["Make a little room this week", "Leave space for it to happen", "Let this pass"],
  },
];

export function seedRecords(): InsightRecord[] {
  return INSIGHTS.map((insight) => ({ insight, state: initialState("shared") }));
}

export const REFLECTIONS: Reflection[] = [
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
    id: "dylan-r1",
    owner: "dylan",
    domain: "us",
    kind: "reflection",
    text: "The week felt long. Nothing specific — just long. A quiet night would help more than a plan would.",
  },
  {
    id: "dylan-s1",
    owner: "dylan",
    domain: "life",
    kind: "suggestion",
    text: "Ry has mentioned the trip twice this week without asking anything. When you’re ready, a small opening is probably all it needs.",
  },
];
