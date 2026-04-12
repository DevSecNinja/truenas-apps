---
name: docs-writing
description: >
    Guide for writing and maintaining documentation in this repository. Use when
    asked to write, update, or review docs, guides, or the README.
---

## Documentation structure

| File / Path     | Rendered where | Audience                    | Notes                                                             |
| --------------- | -------------- | --------------------------- | ----------------------------------------------------------------- |
| `README.md`     | GitHub repo    | GitHub visitors, developers |                                                                   |
| `docs/index.md` | MkDocs site    | MkDocs site visitors        |                                                                   |
| `docs/*.md`     | MkDocs site    | MkDocs site visitors        |                                                                   |
| `CHANGELOG.md`  | GitHub repo    | Developers, release readers | **Auto-generated — do not edit manually.** Updated by `cog bump`. |

### README.md and docs/index.md must be kept in sync

Both files describe the same project. When you update one, always update the other:

- `README.md` may use GitHub-flavoured Markdown: `<div align="center">`, `<img>` tags, emoji, and HTML attributes like `align="center"`.
- `docs/index.md` must use **plain Markdown only** — no HTML tags, no inline `<img>` (use `![alt](path)` instead). Raw HTML is stripped by Python-Markdown unless `md_in_html` is enabled, and image paths relative to the repo root will 404 in MkDocs.
- Keep the _content_ (overview, benefits, app list, dataset list) in sync. The _style_ (emojis, HTML layout) may differ between the two.

## MkDocs nav

All new `docs/*.md` files must be added to the `nav:` block in `mkdocs.yml`. Without this, MkDocs will warn and the page will not appear in the sidebar. New guides go under `Guides:` in alphabetical order by display name.

## Markdown conventions

- **Indent**: 4 spaces for Markdown files (enforced by `.editorconfig` and `dprint`).
- **Line endings**: LF, trailing newline required.
- **Table alignment**: `dprint` auto-formats tables — run `mise exec -- dprint fmt FILE` after editing tables rather than aligning by hand.
- **Admonitions**: Use MkDocs Material admonition syntax for callouts — they render as styled boxes on the site and are readable as plain text in editors.

  ```markdown
  <!-- dprint-ignore -->
  !!! warning "Title"
      Body text indented 4 spaces under the !!! line. This is required — unindented
      text renders outside the block.

  <!-- dprint-ignore -->
  !!! note
      Note without a custom title.

  <!-- dprint-ignore -->
  !!! tip
      Tip callout.

  <!-- dprint-ignore -->
  !!! info "Credit"
      Info / attribution callout.
  ```

  **Critical**: every line of the admonition body must be indented exactly 4 spaces. Text at column 0 renders as normal paragraph text outside the box.

  **Always prefix admonitions with `<!-- dprint-ignore -->`** — dprint's Markdown plugin interprets 4-space-indented text as a code block and strips the indentation, which breaks the rendering. The ignore comment tells dprint to leave the block untouched.
  Supported types: `note`, `tip`, `warning`, `danger`, `info`, `success`, `question`, `failure`, `bug`, `example`, `quote`.

- **Code blocks**: Always specify a language for syntax highlighting (`` ```sh ``, `` ```yaml ``, `` ```text ``, etc.).
- **Links to other docs**: Use relative paths (`[Architecture](ARCHITECTURE.md)`), not absolute URLs, so they work both on GitHub and on the MkDocs site.

## docs.yml workflow

The docs CI workflow (`.github/workflows/docs.yml`) runs `mkdocs build --strict` on pull requests and deploys to GitHub Pages on push to `main`.

**`--strict` mode** means any warning (missing nav entry, broken link, etc.) is treated as an error. Always run `mkdocs build --strict` locally before pushing doc changes if MkDocs is installed.

## Formatting and linting

After editing any Markdown file, run:

```sh
mise exec -- dprint fmt docs/FILE.md   # auto-format
mise exec -- dprint check docs/FILE.md # verify
```

Or format all docs at once:

```sh
mise exec -- dprint fmt
```

## Writing pasteable shell code blocks

Shell code blocks in guides are often copy-pasted directly into a terminal. Write them defensively:

- **No inline `#` comments** — zsh disables `interactivecomments` by default, so `# comment` on its own line or after a command causes `zsh: command not found: #`. Move explanations into prose or a table above the block.
- **Explain variables in a table, not in comments.** Use a Markdown table with `Variable / Example / What to set` columns above the code block, then keep the block itself comment-free and pasteable.
- **Prefer variables over hardcoded values.** Define all configurable values as shell variables at the top of a section (a single "set variables" block). All subsequent commands reference `${VAR}`. This makes guides reusable without editing individual commands.
- **Use heredocs for generated config files** — `cat > filename << EOF … EOF` lets variable substitution happen automatically when the reader runs the block, rather than requiring manual find-and-replace in the file afterward.
- **Split local and remote steps clearly.** If a guide switches between local machine and SSH session, make the boundary explicit in prose and re-declare required variables at the start of each remote block (don't assume the reader's shell state carries over).
