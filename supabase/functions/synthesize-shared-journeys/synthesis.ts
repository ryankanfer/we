/// What the model is allowed to see about one person's answer.
///
/// A choice is not free text: `submit_response` enforces
/// `p_choice = any(i.options)`, so this is a selection from a small
/// server-generated set that both people already read on screen.
export type ModelResponse = {
  choice: string;
};

/// The full private answer, which stays inside the database and reaches only
/// `validateSynthesis`. The note is never sent to a model — see
/// `docs/PRIVATE_TO_SHARED_CONTRACT.md` §2. It is carried here so the validator
/// can act as a tripwire proving that exclusion held.
export type PrivateResponse = {
  choice: string;
  note: string | null;
};

/// Narrows a private answer to the part the contract permits to cross.
export const modelResponse = (response: PrivateResponse): ModelResponse => ({
  choice: response.choice,
});

export type ProposedAction = {
  id: string;
  kind: "lifeItem";
  title: string;
  category: string;
  detail: string | null;
  due_on: string | null;
};

export type SynthesisResult = {
  status: "proposed" | "no_safe_direction";
  summary: string;
  rationale: string;
  proposed_actions: ProposedAction[];
};

export const synthesisSchema = {
  type: "object",
  additionalProperties: false,
  required: ["status", "summary", "rationale", "proposed_actions"],
  properties: {
    status: {
      type: "string",
      enum: ["proposed", "no_safe_direction"],
    },
    summary: { type: "string", maxLength: 240 },
    rationale: { type: "string", maxLength: 500 },
    proposed_actions: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "kind", "title", "category", "detail", "due_on"],
        properties: {
          id: { type: "string", minLength: 1, maxLength: 120 },
          kind: { type: "string", enum: ["lifeItem"] },
          title: { type: "string", minLength: 1, maxLength: 240 },
          category: {
            type: "string",
            pattern: "^[a-z]+( [a-z]+)?$",
            minLength: 3,
            maxLength: 18,
          },
          detail: { type: ["string", "null"], maxLength: 1000 },
          due_on: {
            type: ["string", "null"],
            pattern: "^\\d{4}-\\d{2}-\\d{2}$",
          },
        },
      },
    },
  },
} as const;

const normalized = (value: string) =>
  value.toLocaleLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();

const words = (value: string) =>
  new Set(
    normalized(value).split(" ").filter((word) =>
      word.length >= 4 &&
      !["this", "that", "with", "from", "your", "their", "have", "will"]
        .includes(word)
    ),
  );

/// Every contiguous run of `size` words in `value`, normalized.
///
/// Quotation is caught by overlap, not by containment. The previous check
/// asked whether the *whole* note appeared in the copy, which a note of any
/// real length can never do — a 1200-character note is never quoted whole, so
/// every partial quote passed.
const shingles = (value: string, size: number): Set<string> => {
  const tokens = normalized(value).split(" ").filter(Boolean);
  const out = new Set<string>();
  for (let i = 0; i + size <= tokens.length; i += 1) {
    out.add(tokens.slice(i, i + size).join(" "));
  }
  return out;
};

/// The shortest run of words we treat as a quotation.
///
/// Four is deliberate: shorter runs collide with ordinary phrasing that both
/// people could reach independently, and rejecting those would make the worker
/// fail closed so often that the safe path stops being informative.
const QUOTE_WINDOW = 4;

const allCopy = (result: SynthesisResult) => [
  result.summary,
  result.rationale,
  ...result.proposed_actions.flatMap((action) => [
    action.title,
    action.detail ?? "",
  ]),
].join(" ");

/// Semantic guardrails that JSON Schema cannot express. The worker never logs
/// the rejected copy or the source answers.
export const validateSynthesis = (
  result: SynthesisResult,
  source: { question: string; evidence: string[]; responses: PrivateResponse[] },
): string | null => {
  if (!["proposed", "no_safe_direction"].includes(result.status)) {
    return "status";
  }
  if (result.proposed_actions.length > 3) return "action_count";
  if (result.status === "no_safe_direction") {
    return result.proposed_actions.length === 0 ? null : "unsafe_actions";
  }
  if (!result.summary.trim() || !result.rationale.trim()) return "empty_copy";

  const copy = allCopy(result);
  const plainCopy = normalized(copy);
  if (/[0-9]/.test(copy)) return "invented_number";
  if (/[\"“”]/.test(copy)) return "quotation";
  // Attribution and comparison, per contract §3.
  //
  // Patterns rather than fixed phrases: a literal list is defeated by ordinary
  // morphology. "different answers" was listed and "answers differed" was not,
  // so the second passed cleanly. Anything shaped like "who chose what" or
  // "how the two answers relate" has to fail regardless of conjugation.
  if (
    [
      /\byou both\b/,
      /\bboth of you\b/,
      /\bone of you\b/,
      /\bneither of you\b/,
      /\bthe other (person|one|answer)\b/,
      /\byour partner\b/,
      /\bthe person who\b/,
      /\bboth (chose|picked|said|wanted|answered)\b/,
      /\banswers? (differ|differed|diverge|diverged|match|matched|matches|align|aligned|agree|agreed|disagree|disagreed)\b/,
      /\b(same|different|differing|matching|opposing|opposite) (answer|answers|choice|choices)\b/,
      /\bmatch(ed|es)?\b/,
      /\bcompar(e|ed|es|ing|ison)\b/,
    ].some((pattern) => pattern.test(plainCopy))
  ) return "comparison";

  // The tripwire. Notes are not sent to the model at all (see
  // `docs/PRIVATE_TO_SHARED_CONTRACT.md` §2), so a hit here means the
  // architectural exclusion failed and the result must not be trusted.
  const copyShingles = shingles(copy, QUOTE_WINDOW);
  for (const response of source.responses) {
    for (const privateValue of [response.choice, response.note ?? ""]) {
      const privateCopy = normalized(privateValue);
      if (!privateCopy) continue;
      // Short values cannot form a window; fall back to containment so a
      // one- or two-word answer is still caught.
      if (privateCopy.split(" ").length < QUOTE_WINDOW) {
        if (privateCopy.length >= 4 && plainCopy.includes(privateCopy)) {
          return "private_quote";
        }
        continue;
      }
      for (const shingle of shingles(privateValue, QUOTE_WINDOW)) {
        if (copyShingles.has(shingle)) return "private_quote";
      }
    }
  }

  // Support is measured against shared material only. Building this from the
  // answers would whitelist each person's own vocabulary into copy the other
  // person reads — the opposite of what the check is for. Choices are shared
  // (both people saw the option list); notes are not, and are excluded.
  const supportedWords = words([
    source.question,
    ...source.evidence,
    ...source.responses.map((response) => response.choice),
  ].join(" "));
  for (const action of result.proposed_actions) {
    if (
      action.due_on &&
      !normalized(`${source.question} ${source.evidence.join(" ")}`)
        .includes(normalized(action.due_on))
    ) return "invented_date";
    const actionWords = words(`${action.title} ${action.detail ?? ""}`);
    if (actionWords.size === 0) continue;
    // A majority must be grounded. Requiring a single supported word let an
    // action be almost entirely invented as long as one token matched.
    const supported = [...actionWords].filter((word) =>
      supportedWords.has(word)
    ).length;
    if (supported * 2 <= actionWords.size) return "unsupported_action";
  }
  return null;
};

export const systemPrompt = `You synthesize one optional shared direction from two private answers.
Return no_safe_direction unless the source honestly supports one direction.
Never quote or closely paraphrase an answer or note. Never say whether answers match,
differ, or which person preferred anything. Never compare or diagnose the people.
Use only the question, the two responses, and the frozen shared evidence supplied.
Invent no facts, dates, quantities, plans, or obligations. Use no numerals or quotation
marks. A direction may broadly reflect preferences from the answers without naming
them. Include zero to three small Life actions only when directly supported by source
evidence. Advice that could fit any couple is not a safe direction.`;
