
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge DeepSeek entries into a Codex model catalog.")
    parser.add_argument("--codex-catalog", type=Path, required=True)
    parser.add_argument("--deepseek-catalog", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    codex = json.loads(args.codex_catalog.read_text(encoding="utf-8"))
    deepseek = json.loads(args.deepseek_catalog.read_text(encoding="utf-8"))
    upstream = codex.get("models", [])
    custom = deepseek.get("models", [])
    custom_slugs = {item.get("slug") for item in custom}
    merged = custom + [item for item in upstream if item.get("slug") not in custom_slugs]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"models": merged}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(merged)} models to {args.output}")


if __name__ == "__main__":
    main()


