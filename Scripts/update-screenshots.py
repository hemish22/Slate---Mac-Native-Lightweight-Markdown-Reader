"""Embed screenshots only after all three real app exports exist."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
images = [
    ("Split view", "slate-split.png", "Markdown source and live preview side by side"),
    ("Editor", "slate-editor.png", "Native Markdown editor with line numbers and syntax colors"),
    ("Preview", "slate-preview.png", "Rendered Markdown in Slate's dark reading view"),
]
for _, filename, _ in images:
    if not (root / "docs/images" / filename).is_file():
        raise SystemExit(f"Missing app screenshot: {filename}; run make screenshots first.")

readme = root / "README.md"
content = readme.read_text()
start, end = "<!-- SCREENSHOTS:START -->", "<!-- SCREENSHOTS:END -->"
before, remainder = content.split(start, 1)
_, after = remainder.split(end, 1)
gallery = "\n\n".join(f"### {title}\n\n![{alt}](docs/images/{filename})" for title, filename, alt in images)
readme.write_text(before + start + "\n\n" + gallery + "\n\n" + end + after)
print("README updated with all three app screenshots.")
