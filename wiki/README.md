# wiki/

Source for the docs site at <https://wombat164.github.io/claude-flight/>.

The Quartz framework is **not vendored here**. This directory holds only our
config and content; `.github/workflows/deploy-wiki.yml` fetches Quartz v4 at a
pinned commit, overlays these files, and builds. That keeps the repo free of
`node_modules` and a framework we do not maintain.

```
wiki/
  quartz.config.ts     site config (title, baseUrl, theme, plugins)
  quartz.layout.ts     layout; only the footer is customised
  content/             the pages, laid out by Diataxis
    index.md
    tutorials/         learning-oriented: get it running
    how-to/            task-oriented: solve one problem
    reference/         information-oriented: look something up
    explanation/       understanding-oriented: why it is built this way
```

Page frontmatter is minimal -- a `title:` is enough:

```markdown
---
title: Configuration
---
```

## Working on it locally

```bash
git clone --depth 1 https://github.com/jackyzha0/quartz .quartz-build
cp wiki/quartz.config.ts wiki/quartz.layout.ts .quartz-build/
rm -rf .quartz-build/content && cp -r wiki/content .quartz-build/content
cd .quartz-build && npm ci && npx quartz build --serve
```

`.quartz-build/` is gitignored.

## Keeping it honest

The docs site restates what the README, `SECURITY.md` and the script comments
already say. When they disagree, **the script wins** -- fix the docs. Anything
describing behaviour should be traceable to a line in `bin/flight-doctor.sh` or
an assertion in the test suites.
