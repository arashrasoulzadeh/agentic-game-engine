"""MkDocs hook: publish /llms.txt, an index of every page for AI agents.

Built from the nav at build time so it cannot drift from the site. Each line
is `- [title](url): first sentence of the page`.
"""

import os
import re

SITE_NAME = "ZARVAN"
SUMMARY = (
    "An agent-native, simulation-first game engine built with Dart. "
    "World state is JSON, content is data, agents act through a sandbox."
)


def _first_sentence(markdown: str) -> str:
    body = re.sub(r"^---.*?---\s*", "", markdown, flags=re.S)
    for block in re.split(r"\n\s*\n", body):
        text = block.strip()
        if not text or text.startswith(("#", "```", "|", "<", "!!!", "=", "-", ":")):
            continue
        text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
        text = re.sub(r"[*`>]", "", text).replace("\n", " ")
        return re.split(r"(?<=[.!?])\s", text, maxsplit=1)[0][:200]
    return ""


def on_post_build(config, **kwargs):
    site_url = (config.get("site_url") or "").rstrip("/")
    lines = [f"# {SITE_NAME}", "", f"> {SUMMARY}", "", "## Pages", ""]
    docs_dir = config["docs_dir"]
    for root, _, files in sorted(os.walk(docs_dir)):
        for name in sorted(files):
            if not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, docs_dir).replace(os.sep, "/")
            if rel.startswith(("proposals/", "studio/qa-level-editor")):
                continue
            text = open(path, encoding="utf-8").read()
            m = re.search(r"^#\s+(.+)$", text, flags=re.M)
            title = m.group(1).strip() if m else rel
            url_path = rel[:-3]
            url_path = "" if url_path in ("README", "index") else re.sub(r"/(README|index)$", "/", url_path) if url_path.endswith(("README", "index")) else url_path + "/"
            lines.append(f"- [{title}]({site_url}/{url_path}): {_first_sentence(text)}")
    out = os.path.join(config["site_dir"], "llms.txt")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
