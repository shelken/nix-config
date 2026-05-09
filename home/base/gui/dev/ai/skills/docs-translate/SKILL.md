---
name: docs-translate
description:
  Translate documents in place while preserving original copy. Use when user provides document
  path/name and asks to translate, convert language, localize, or sync suffixed translated documents
  back to original documents.
---

# Docs Translate

## Trigger

User provides document path/name and asks to translate, convert language, localize document, or sync
original document from a language-suffixed version.

## Default behavior

- No language suffix: when user gives original document like `guide.md` / `GUIDE.md`, translate
  original document to target language. If target language is unspecified, translate to English.
- Has language suffix and no extra instruction: when user gives suffixed version like `guide_cn.md`
  / `GUIDE_CN.md`, update unsuffixed original document to be semantically consistent with suffixed
  version.
- Language suffix: placed before extension, format `[original name]_[language code].[extension]`;
  language code casing is determined only by original name casing and must not be mixed arbitrarily.
- Same language: in translation mode, if target language equals source language, say conversion is
  unnecessary and stop.
- Content and structure consistency: during sync/translation, check both content and structure;
  deletions must be deleted, additions added, changes changed; do not only check headings/lists or
  other structure.
- Preserve structure: keep heading levels, lists, tables, code blocks, links, Front Matter,
  placeholders, variable names.
- Do not translate: code, commands, paths, URLs, config keys, API names, brand/product proper nouns,
  unless user explicitly asks.

## Workflow

1. Locate document
   - User gives path: use it directly.
   - User gives name: search current repo for same or approximate file name; if multiple results,
     ask user to choose.

2. Identify mode
   - No language suffix: enter translation mode.
   - Has language suffix and user gives no extra instruction: enter sync-original mode.
   - Has language suffix and user explicitly asks to translate/change language: follow user
     instruction.

3. Translation mode
   - Read unsuffixed original document.
   - Detect source language; if target language equals source language, say conversion is
     unnecessary and stop.
   - Suffix code casing must be determined by “original name stem”; see “Language code casing
     rules”.
   - Copy original document to `[original name]_[source language code].[extension]`; if already
     exists, stop and ask to avoid overwrite.
   - Translate original document to target language and write back to original path.
   - Compare source and translated document paragraph by paragraph; confirm body content is fully
     translated with no missing paragraphs, sentences, or table cells.
   - Ensure translated document and original document have exactly consistent content and structure;
     every deletion, addition, and change must correspond item by item.

4. Sync-original mode
   - Parse original document path from suffixed file name: `guide_cn.md` → `guide.md`; `GUIDE_CN.md`
     → `GUIDE.md`.
   - Suffix code casing must be validated by “original name stem”: `guide_CN.md` and `GUIDE_cn.md`
     are mismatched names; ask user to rename or confirm.
   - Read suffixed version and original document.
   - When comparing two files, must use `git diff --no-index original suffixed-version` to locate
     content that needs syncing.
   - Must read every added, deleted, and modified block in diff; cannot only inspect structural
     changes.
   - Use suffixed version as source of truth, update original document to same semantics; keep
     original document target language and format.
   - Ensure original document and suffixed version have exactly consistent content and structure;
     every deletion, addition, and change must be synced item by item.
   - Do not create new language backup; this is sync update, not translation backup.

5. Read content
   - Use `read` for text files.
   - For PDF/DOCX/PPTX/XLSX/images and other non-plain-text formats, first use `liteparse` skill to
     extract content.

6. Verify
   - Re-read written file and confirm it exists and is non-empty.
   - Compare source document/suffixed version and written file paragraph by paragraph again; confirm
     content is complete, semantically consistent, and structurally consistent.
   - For Markdown/Nix/JSON/YAML and other checkable formats, run corresponding format/syntax checks;
     if no checker, at least confirm content and structure are exactly consistent.

## Language code casing rules

- First get original name stem: remove directory and final extension; for example, original name
  stem of `docs/GUIDE.md` is `GUIDE`, and original name stem of `docs/api.v1.md` is `api.v1`.
- If original name stem consists only of uppercase letters/digits/separators, language code must be
  all uppercase: `GUIDE.md` → `GUIDE_CN.md`, `API-V1.md` → `API-V1_EN.md`.
- In all other cases, language code must be all lowercase: `guide.md` → `guide_cn.md`, `Guide.md` →
  `Guide_cn.md`, `api.v1.md` → `api.v1_en.md`.
- “All uppercase” only checks letters in original name stem; no lowercase letters means all
  uppercase.
- In sync mode, suffixed file must follow same rule; stop and report naming mismatch when it does
  not.

## Translation rules

- Faithfulness first, polish second.
- Short headings can be naturalized, but meaning must not change.
- Keep technical terminology consistent.
- Preserve Markdown link targets; translate only link text.
- Preserve code blocks exactly; inline code outside code blocks also stays unchanged.
- In Front Matter, translate only visible copy fields; preserve keys and structure.

## File naming examples

- `GUIDE.md` Chinese to English: original name stem `GUIDE` is all uppercase, back up as
  `GUIDE_CN.md`, write English into `GUIDE.md`.
- `guide.md` Chinese to English: original name stem `guide` is not all uppercase, back up as
  `guide_cn.md`, write English into `guide.md`.
- `Guide.md` Chinese to English: original name stem `Guide` is not all uppercase, back up as
  `Guide_cn.md`, write English into `Guide.md`.
- `docs/spec.yaml` English to Japanese: original name stem `spec` is not all uppercase, back up as
  `docs/spec_en.yaml`, write Japanese into `docs/spec.yaml`.
- `guide_cn.md` with no extra instruction: use `git diff --no-index guide.md guide_cn.md` to
  compare, update `guide.md` to same semantics.
- `GUIDE_CN.md` with no extra instruction: use `git diff --no-index GUIDE.md GUIDE_CN.md` to
  compare, update `GUIDE.md` to same semantics.

## Failure handling

- Document not found: explain search scope and matches, ask for exact path.
- Multiple candidates: list paths and wait for user choice.
- Backup name conflict: stop; do not overwrite.
- Binary format cannot be safely written back: explain limitation first, suggest Markdown output or
  ask user to confirm target format.
