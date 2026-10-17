"""MkDocs hook: make repo-relative links in docs/ work on the published site.

The docs link to source files and package READMEs with paths like
``../../packages/engine_core/README.md`` so they work when browsing on
GitHub. Those targets are outside ``docs/`` and so don't exist on the built
site; this rewrites them to absolute GitHub URLs at build time. Links that
stay inside ``docs/`` are untouched.
"""

import posixpath
import re

REPO = "https://github.com/arashrasoulzadeh/agentic-game-engine"
BRANCH = "main"

# [text](target) -- skips images' leading "!" being special; they're handled
# the same way. Targets with a scheme or a bare #anchor are left alone.
_LINK = re.compile(r"(\]\()([^)\s]+)(\))")


def _rewrite(page_src_uri: str, target: str) -> str:
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#"):
        return target
    path, _, anchor = target.partition("#")
    if not path:
        return target
    page_dir = posixpath.dirname(page_src_uri)
    resolved = posixpath.normpath(posixpath.join(page_dir, path))
    if not resolved.startswith(".."):
        return target  # stays inside docs/
    repo_path = posixpath.normpath(posixpath.join("docs", page_dir, path))
    if repo_path.startswith(".."):
        return target
    last = posixpath.basename(repo_path)
    kind = "blob" if "." in last else "tree"
    url = f"{REPO}/{kind}/{BRANCH}/{repo_path}"
    return f"{url}#{anchor}" if anchor else url


def on_page_markdown(markdown, page, config, files):
    def sub(match):
        return match.group(1) + _rewrite(page.file.src_uri, match.group(2)) + match.group(3)

    return _LINK.sub(sub, markdown)
