Perform a thorough code review of the current changes.

$ARGUMENTS

If $ARGUMENTS contains a PR number (e.g., `42`), fetch the PR diff via GitHub MCP and post the review as a PR comment at the end.

---

### Step 1 — Gather the diff

```bash
BASE=${BASE:-main}
git diff $BASE...HEAD
git diff $BASE...HEAD --stat
git log $BASE..HEAD --oneline
```

If $ARGUMENTS specifies a PR number, use the GitHub MCP `get_pull_request_files` tool to get the list of changed files, and `get_pull_request` to get context.

---

### Step 2 — Review each changed file

Go through each changed file systematically. Apply the relevant checks below based on file type.

#### TypeScript — all files
- [ ] No `any` types — strict TypeScript throughout
- [ ] No unused variables, imports, or parameters
- [ ] Error handling uses `catch (error: unknown)` — never `catch (error: any)`
- [ ] No hardcoded values that belong in constants or env vars
- [ ] Interfaces/types are explicit and well-named

#### Architecture — SolidJS files (`.tsx`, `.ts` in `src/`)
- [ ] Logic flows correctly: Context → Store → Hooks → Components
- [ ] No business logic in components (belongs in hooks or services)
- [ ] No direct store manipulation from components (use hooks)
- [ ] New hooks check: does an existing hook already cover this need?
- [ ] Lucide icons imported individually (`lucide-solid/icons/name`), never from package root

#### SolidJS reactivity
- [ ] Signals accessed as functions (`session()`, not `session`)
- [ ] Reactive computations use `createMemo`, not plain variables
- [ ] `Show` used for conditional rendering (no JSX ternaries)
- [ ] `For` used for lists (no `.map()` in JSX)
- [ ] No reactive state mutations from outside `createSignal` setters

#### API calls (files in `src/services/api/`)
- [ ] `credentials: 'include'` present on every `fetch`
- [ ] Response unwrapped correctly (`response.data`, not `response`)
- [ ] HTTP errors throw with `throw new Error(...)`
- [ ] `buildApiUrl(path)` used — no hardcoded localhost URLs

#### Architecture — NestJS files (API repo)
- [ ] DTO validation decorators present (`@IsString()`, `@IsOptional()`, etc.)
- [ ] Response wrapped in `{ data: T }` format
- [ ] Guards applied appropriately (`@Auth()`, `@Roles()`)
- [ ] Service does not directly call repositories it doesn't own
- [ ] New endpoint has a corresponding `.bru` file in `bruno/`

#### Tests
- [ ] New features have corresponding test files
- [ ] Tests follow `it('should [behavior] when [condition]')` naming
- [ ] Mock factories used for complex objects (no inline object literals)
- [ ] Tests are isolated (no shared mutable state between `it()` blocks)
- [ ] No snapshot tests

#### Security & Performance
- [ ] No sensitive data in console logs or error messages
- [ ] Heavy computations delegated to Web Workers (not main thread)
- [ ] No synchronous file I/O or blocking operations

---

### Step 3 — Write the structured review

Format your review output **exactly** as follows:

---

## Code Review

**Branch:** `[branch]` → `main`
**Files changed:** [n] | **Commits:** [n]
**Overall:** ✅ LGTM | ⚠️ Minor issues | ❌ Changes required

### Strengths
- [what is done particularly well]

### Issues

| Severity | File | Issue | Suggestion |
|----------|------|-------|------------|
| 🔴 Critical | `path/to/file.ts` | [issue description] | [how to fix] |
| 🟡 Warning | `path/to/file.ts` | [issue description] | [how to fix] |
| 🔵 Suggestion | `path/to/file.ts` | [improvement idea] | [how to improve] |

_If no issues: "No issues found."_

### Summary
[2–3 sentence overall assessment — quality, risks, readiness to merge]

---

### Step 4 — Post as PR comment (if PR number provided)

If $ARGUMENTS contains a PR number, use the GitHub MCP `add_issue_comment` tool to post the review content as a comment on that PR.

Report: "Review posted on PR #[number]" with the PR URL.
