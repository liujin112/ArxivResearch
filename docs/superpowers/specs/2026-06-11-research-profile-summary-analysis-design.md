# Research Profile And Abstract Analysis Design

## Context

The app already supports LLM abstract analysis, tags, deep reading, Notion sync, and paper filtering. The current abstract analysis prompt is fixed and asks for a broad JSON object, while the UI mainly uses:

- `one_sentence_summary`
- `rationale`
- `canonical_tags`
- `relevance_score`

The next iteration should make abstract analysis more personal without making every analysis prompt large or unstable.

## Goals

- Let the user define an academic profile from their own papers, papers they follow, research interests, and keywords.
- Use the configured LLM to compress that source material into a concise editable research profile.
- Use the generated profile during abstract analysis so `rationale` and `relevance_score` reflect the user's research context.
- Keep LLM output stable enough for parsing, filtering, sorting, tags, Notion sync, and future migrations.
- Show the system prompt in settings while making the locked protocol parts non-editable.
- Do not automatically reanalyze old papers after the profile changes; users can rerun analysis from the paper context menu.

## Non-Goals

- Do not add embedding search or vector retrieval in this iteration.
- Do not ingest PDFs for the user's own papers in this iteration.
- Do not localize canonical tag names; tags remain stable English kebab-case values.
- Do not automatically enqueue bulk reanalysis after profile regeneration.

## User Flow

1. The user opens Settings and goes to the analysis/profile section.
2. The user enters raw academic context:
   - published paper titles and optional abstracts,
   - papers they follow and optional abstracts,
   - research keywords,
   - free-form research direction notes.
3. The user clicks `Generate Academic Profile`.
4. The app uses the configured LLM provider to generate a concise profile.
5. The generated profile is displayed below the input and remains editable.
6. Future abstract analysis jobs include the generated profile, not the full raw input.
7. If the user updates the profile later, existing papers are not automatically reanalyzed.
8. The user can right-click any paper and choose abstract analysis again.

## Prompt Model

Abstract analysis is split into locked and editable sections.

The locked system protocol is visible in settings but cannot be edited. It defines:

- output must be compact JSON only,
- required keys are `one_sentence_summary`, `rationale`, `relevance_score`, and `canonical_tags`,
- `relevance_score` is an integer from 0 to 100,
- `canonical_tags` must be stable English kebab-case tags,
- `rationale` means a short explanation of why the paper is worth attention for this user's research profile, not hidden chain-of-thought.

The editable section lets the user control:

- summary language,
- tone and length,
- personal focus preferences,
- optional domain-specific instructions.

The app should show both sections in settings, with the locked section rendered as read-only text and the editable section as a text editor.

## Abstract Analysis JSON

The app should support this minimal schema:

```json
{
  "one_sentence_summary": "A one sentence paper summary.",
  "rationale": "Why this paper matters for the user's research profile.",
  "relevance_score": 85,
  "canonical_tags": ["representation-learning", "imitation-learning"]
}
```

The parser should remain backward-compatible with older responses that include `key_contributions`, `methods`, `results`, and `limitations`, but those fields are optional.

## Relevance Score

`relevance_score` is a personalized 0-100 score.

The scoring rubric is locked:

- High score for direct overlap with the user's research topics.
- High score for similar tasks, scenarios, datasets, or evaluation settings.
- High score for transferable methods, even when the application domain differs.
- High score for theoretical, experimental, or engineering ideas that may inspire future work.
- Low score for generic popularity alone when the paper has little connection to the user's profile.

The UI should display this as a visible score badge and allow sorting by score.

Existing stored values may be 0-1 from older analyses. The app should normalize values for display and sorting:

- values in `0...1` are treated as legacy values and displayed as `value * 100`,
- values above `1` are treated as the new 0-100 score.

## Research Profile Generation

Profile generation uses a separate prompt from abstract analysis.

Input:

- raw user academic context,
- optional existing generated profile if the user is updating it.

Output:

- concise profile text,
- preferred research themes,
- method interests,
- application/task interests,
- "look for" criteria that can guide scoring.

This output is plain text and editable. It does not need JSON because it is consumed by later prompts as context, not stored as structured paper metadata.

## UI Changes

Settings should add an `Analysis` or `Research Profile` section with:

- raw profile input editor,
- `Generate Academic Profile` button,
- generated editable profile editor,
- read-only locked abstract analysis protocol,
- editable abstract analysis instructions,
- summary language picker.

Paper list should add sorting by:

- date,
- relevance score.

Paper detail should show:

- score badge near the LLM summary,
- heading label `Why It Matters` instead of `Rationale`.

## Persistence

Runtime settings should persist:

- raw academic profile input,
- generated academic profile,
- editable abstract analysis instructions,
- summary language preference.

The existing `LLMAnalysis.relevanceScore` field can remain `Double`; semantics change to normalized display support for both legacy 0-1 and new 0-100 values.

## Job Behavior

Abstract analysis jobs should not be queued if there is no valid LLM configuration.

Profile generation should use the same validation rule as other LLM jobs:

- if no valid provider/key exists, show a clear settings message and do not enqueue a job.

Profile regeneration should not enqueue paper reanalysis.

## Testing

Tests should cover:

- profile settings persistence,
- prompt construction includes generated profile but not raw long profile input,
- locked JSON protocol remains present when custom instructions are set,
- parser accepts the minimal JSON schema,
- parser remains backward-compatible with older verbose JSON,
- relevance score normalization for legacy 0-1 and new 0-100 values,
- paper sorting by score.
