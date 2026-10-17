# Working on the docs

The site is [MkDocs Material](https://squidfunk.github.io/mkdocs-material/)
built from this folder and published to GitHub Pages by
`.github/workflows/docs.yml` on every push to `main` that touches `docs/`,
`mkdocs.yml` or the generated-reference inputs.

## Preview locally

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r docs/requirements.txt
mkdocs serve            # http://127.0.0.1:8000, live reload
mkdocs build --strict   # what CI runs: fails on broken links
```

## Conventions

- One idea per page. Concepts explain *why*; tutorials are linear; recipes are
  standalone; reference pages are tables.
- Prefer a table or diagram to a paragraph when you're listing or comparing.
- Diagrams are [Mermaid](https://mermaid.js.org/) fenced blocks — they render on
  GitHub and on the site.
- Link to other docs with relative `.md` paths. Links that leave `docs/`
  (to source files or package READMEs) are rewritten to GitHub URLs
  at build time by `hooks/repo_links.py`, so they work in both places.
- Callouts use `!!! note|tip|warning` admonitions.

## Code samples must be real

- Turn-based samples are executed by
  `packages/engine_strategy/test/doc_examples_test.dart` and
  `packages/engine_core/test/agent_turn_based_test.dart`. When you change a
  sample, change the test in the same commit (and vice versa).
- For other samples, check the signature against the source before committing.
- Never use `const` with `Position`, `Velocity` or `Collider` — their
  constructors aren't const.

## Regenerating the component reference

`docs/reference/components.md` is generated from `engine_schema`:

```bash
cd packages/engine_schema
dart run tool/gen_component_docs.dart > ../../docs/reference/components.md
```

A test fails if the committed file is stale.
