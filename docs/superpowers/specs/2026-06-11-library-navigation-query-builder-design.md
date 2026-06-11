# Library Navigation And Query Builder Design

## Context

The current app treats arXiv query profiles as the primary left-column navigation. That makes daily paper review less direct: users usually care first about all newly fetched papers, then occasionally manage the subscriptions that brought those papers in.

The current query editor is also too raw. It asks users to type arXiv syntax directly, even though the app already knows the main searchable fields and boolean operators.

Settings currently uses `Form` directly inside `TabView` pages and some tabs do not scroll, so lower controls can be hidden.

## Goals

- Make `All Papers` the default library view.
- Add first-column date navigation based on local first-added date.
- Keep query subscriptions visible but secondary.
- Support selecting a query to filter papers by that subscription.
- Replace the inline query editor with a popup/sheet.
- Add beginner-friendly segmented query configuration:
  - include all terms (`AND`),
  - include any terms (`OR` group),
  - exclude terms (`ANDNOT`),
  - categories (`cat:cs.AI` style),
  - field explanations for `all`, `ti`, `abs`, `au`, and `cat`,
  - phrase vs token matching,
  - raw query preview and advanced raw override.
- Support right-click query actions: edit, fetch now, enable/disable, delete.
- Fix Settings tabs so content scrolls.

## Non-Goals

- Do not add a full arXiv taxonomy browser in this iteration.
- Do not add remote category autocomplete.
- Do not change Notion/Zotero sync behavior.
- Do not remove raw query editing; keep it as advanced fallback.

## Date Semantics

The date navigation uses local first-added date, not arXiv publication date.

`Paper.addedAt` records the first time the paper entered the local library. When fetching an existing paper again, the app preserves its existing `addedAt`. Older stored papers that do not have this field fall back to `updatedAt ?? publishedAt`.

The sidebar shows:

- `All Papers`,
- `Today`,
- `Yesterday`,
- `This Week`,
- concrete local dates, newest first.

Selecting a date updates only the paper list filter. It does not change query subscriptions.

## Navigation Model

The left column has two sections.

`Library`:

- `All Papers`: default selection on launch.
- Date rows with paper counts.

`Subscriptions`:

- Query profile rows with name, enabled state, refresh interval, and paper count.
- Disabled subscriptions are visually de-emphasized.
- Selecting a subscription filters the center list to papers whose `queryProfileIDs` contain that profile.
- Context menu supports edit, fetch now, enable/disable, and delete.

The toolbar `Fetch Now` acts on the selected subscription if one is selected. If no subscription is selected, it should be disabled or show a clear status message.

## Query Editor Sheet

The sheet is opened from:

- `New Query` button,
- query row context menu `Edit`.

The sheet contains:

- query name,
- enabled toggle,
- refresh interval,
- segmented builder:
  - Include all terms,
  - Include any terms,
  - Exclude terms,
  - Categories,
- generated raw arXiv query preview,
- test URL preview,
- `Test Query`, `Save`, `Cancel`,
- advanced raw query override.

The builder should generate arXiv syntax using existing `ArxivQueryExpression` rendering. The raw override should be saved as-is after existing raw query normalization.

## Field Help

Field help is visible in the sheet:

- `all`: search all indexed fields.
- `ti`: title.
- `abs`: abstract.
- `au`: author.
- `cat`: arXiv category, such as `cs.AI`, `cs.LG`, `stat.ML`.

Category choices should include common defaults:

- `cs.AI`
- `cs.LG`
- `cs.CL`
- `cs.CV`
- `cs.RO`
- `stat.ML`
- `eess.SY`
- `math.OC`

Users can also type a custom category.

## Data And Filtering

Core model changes:

- `Paper.addedAt: Date?`
- `PaperFilterCriteria.queryProfileID: UUID?`
- `PaperFilterCriteria.libraryDate: PaperLibraryDateFilter`

Core query builder changes:

- `StructuredQueryTerm`
- `StructuredArxivQuery`

The UI should not hand-build arXiv strings in view code; the sheet uses these Core helpers.

## Settings Scroll Fix

Each settings tab should be independently scrollable. The content inside each tab should be wrapped in a `ScrollView` with a `Form` or form-like inner layout so all controls remain reachable at smaller window heights.

## Testing

Tests should cover:

- structured query builder renders AND, OR, ANDNOT, phrase, and categories,
- `Paper.addedAt` is encoded/decoded and old paper JSON without `addedAt` still decodes,
- filtering by query profile,
- filtering by local added date,
- existing paper fetch preserves `addedAt`,
- settings and app build compile after the scroll wrapper/UI changes.
