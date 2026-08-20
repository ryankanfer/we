import { SynthesisResult, validateSynthesis } from "./synthesis.ts";

const assertEquals = (actual: unknown, expected: unknown) => {
  if (actual !== expected) {
    throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
  }
};

const source = {
  question: "What shape should the cabin weekend take?",
  evidence: ["The cabin weekend is coming up."],
  responses: [
    { choice: "Mostly rest", note: "I need a quiet morning" },
    { choice: "Leave room to wander", note: null },
  ],
};

const result = (overrides: Partial<SynthesisResult> = {}): SynthesisResult => ({
  status: "proposed",
  summary: "Leave the cabin weekend spacious.",
  rationale: "The weekend can begin gently and keep its shape open.",
  proposed_actions: [],
  ...overrides,
});

Deno.test("accepts grounded copy without exposing private answers", () => {
  assertEquals(validateSynthesis(result(), source), null);
});

Deno.test("rejects a private answer quotation", () => {
  assertEquals(
    validateSynthesis(result({ summary: "Choose mostly rest." }), source),
    "private_quote",
  );
});

Deno.test("rejects comparisons and invented numbers", () => {
  assertEquals(
    validateSynthesis(result({ summary: "You both chose a gentle start." }), source),
    "comparison",
  );
  assertEquals(
    validateSynthesis(result({ summary: "Keep 2 hours open." }), source),
    "invented_number",
  );
});

Deno.test("rejects more than three actions", () => {
  const action = {
    id: "move",
    kind: "lifeItem" as const,
    title: "Shape the cabin weekend",
    category: "trips",
    detail: null,
    due_on: null,
  };
  assertEquals(
    validateSynthesis(
      result({ proposed_actions: [action, action, action, action] }),
      source,
    ),
    "action_count",
  );
});

Deno.test("rejects a due date absent from frozen shared evidence", () => {
  assertEquals(
    validateSynthesis(
      result({
        proposed_actions: [{
          id: "move",
          kind: "lifeItem",
          title: "Shape the cabin weekend",
          category: "trips",
          detail: null,
          due_on: "2027-02-04",
        }],
      }),
      source,
    ),
    "invented_date",
  );
});

// ---------------------------------------------------------------------------
// Adversarial coverage for `docs/PRIVATE_TO_SHARED_CONTRACT.md` §3.
//
// These are the vectors the contract forbids. They are written against
// handcrafted model output rather than live calls, so they run offline and
// deterministically in CI. Where the validator cannot catch a vector, the test
// says so out loud rather than asserting a false guarantee.
// ---------------------------------------------------------------------------

/// A note long enough that no output could ever quote it whole — which is
/// exactly why the old whole-value containment check never fired.
const longNote =
  "I have been carrying the planning for every trip we take and I would " +
  "like one morning where nothing is scheduled and I do not have to be " +
  "the person who decides what happens next for all of us";

const longSource = {
  question: "What shape should the cabin weekend take?",
  evidence: ["The cabin weekend is coming up."],
  responses: [
    { choice: "Mostly rest", note: longNote },
    { choice: "Leave room to wander", note: null },
  ],
};

Deno.test("rejects a partial quotation lifted from a long private note", () => {
  // Six words taken verbatim from the middle of the note. Under the previous
  // containment check this passed, because the whole note never appears.
  assertEquals(
    validateSynthesis(
      result({
        summary: "Let there be one morning where nothing is scheduled.",
      }),
      longSource,
    ),
    "private_quote",
  );
});

Deno.test("rejects a short private choice quoted verbatim", () => {
  // Below the shingle window, so the containment fallback has to carry it.
  assertEquals(
    validateSynthesis(
      result({ summary: "Leave room to wander together." }),
      longSource,
    ),
    "private_quote",
  );
});

Deno.test("accepts copy that shares only ordinary phrasing with a note", () => {
  // The guard must not fail closed on language two people could each reach
  // independently. A validator that rejects everything protects nothing,
  // because the safe path stops carrying information.
  assertEquals(validateSynthesis(result(), longSource), null);
});

Deno.test("rejects attribution to one person", () => {
  for (
    const summary of [
      "One of you needs a slower start.",
      "The other person would rather keep moving.",
    ]
  ) {
    assertEquals(
      validateSynthesis(result({ summary }), source),
      "comparison",
      );
  }
});

Deno.test("rejects answer-equality and answer-difference signals", () => {
  for (
    const summary of [
      "You both chose a gentle start.",
      "Your answers differed on this one.",
      "The same answer came back twice.",
    ]
  ) {
    const verdict = validateSynthesis(result({ summary }), source);
    if (verdict === null) {
      throw new Error(`Answer-equality signal passed validation: ${summary}`);
    }
  }
});

Deno.test("rejects an action grounded in almost nothing shared", () => {
  // Exactly one supported word ("cabin"). The previous rule accepted this;
  // the contract does not, because the rest is invented.
  assertEquals(
    validateSynthesis(
      result({
        proposed_actions: [{
          id: "move",
          kind: "lifeItem",
          title: "Book a cabin massage appointment downtown",
          category: "trips",
          detail: "Confirm therapist availability beforehand",
          due_on: null,
        }],
      }),
      source,
    ),
    "unsupported_action",
  );
});

Deno.test("accepts an action mostly grounded in shared material", () => {
  assertEquals(
    validateSynthesis(
      result({
        proposed_actions: [{
          id: "move",
          kind: "lifeItem",
          title: "Shape the cabin weekend",
          category: "trips",
          detail: null,
          due_on: null,
        }],
      }),
      source,
    ),
    null,
  );
});

// ---------------------------------------------------------------------------
// The exhaustive cross-product sweep.
//
// This is the descendant of the on-device 4 x 4 matrix test that used to gate
// every PR (`sharedDirectionCannotRevealAnswerContentOrEquality`). It moved
// here when synthesis moved server-side, and it is cheap to run exhaustively
// because `submit_response` constrains a choice to `any(i.options)` — a small
// server-generated set, not free text.
// ---------------------------------------------------------------------------

/// A real option set, verbatim from the candidate CTE in
/// `20260808120000_shared_journeys_v1.sql`.
const options = [
  "Make room for this",
  "Shape it differently",
  "Let it rest",
];

const pairSource = (choiceA: string, choiceB: string) => ({
  question: "Does the cabin weekend belong in the season ahead?",
  evidence: ["The cabin weekend is coming up."],
  responses: [
    { choice: choiceA, note: "a private note that never reaches a model" },
    { choice: choiceB, note: null },
  ],
});

Deno.test("no choice pairing lets its own text through", () => {
  for (const choiceA of options) {
    for (const choiceB of options) {
      for (const quoted of new Set([choiceA, choiceB])) {
        const verdict = validateSynthesis(
          result({ summary: `${quoted} this season.` }),
          pairSource(choiceA, choiceB),
        );
        if (verdict !== "private_quote") {
          throw new Error(
            `Quoting "${quoted}" passed for pairing ` +
              `(${choiceA} / ${choiceB}): ${String(verdict)}`,
          );
        }
      }
    }
  }
});

Deno.test("the verdict on safe copy does not vary with the answers", () => {
  // The side-channel check, and the reason this sweep exists. If a fixed piece
  // of safe copy were accepted for some pairings and rejected for others, the
  // verdict itself would carry information about what the two people chose —
  // the couple would see "Let this rest" exactly when their answers took a
  // particular shape. The guard has to be blind to the pairing.
  const safe = result({
    summary: "Leave the season ahead spacious.",
    rationale: "The weekend can begin gently and keep its shape open.",
  });
  for (const choiceA of options) {
    for (const choiceB of options) {
      const verdict = validateSynthesis(safe, pairSource(choiceA, choiceB));
      if (verdict !== null) {
        throw new Error(
          `Safe copy rejected for pairing (${choiceA} / ${choiceB}): ` +
            String(verdict),
        );
      }
    }
  }
});
