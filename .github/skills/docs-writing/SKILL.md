---
name: docs-writing
description: >
    Guide for writing and maintaining documentation in this repository. Use when
    asked to write, update, or review docs, guides, or the README.
---

## Documentation structure

| File / Path     | Rendered where | Audience                    |
| --------------- | -------------- | --------------------------- |
| `README.md`     | GitHub repo    | GitHub visitors, developers |
| `docs/index.md` | MkDocs site    | MkDocs site visitors        |
| `docs/*.md`     | MkDocs site    | MkDocs site visitors        |

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
  !!! warning "Title"
  Body text indented 4 spaces.

  !!! note
  Note without a custom title.

  !!! tip
  Tip callout.

  !!! info "Credit"
  Info / attribution callout.
  ```

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
