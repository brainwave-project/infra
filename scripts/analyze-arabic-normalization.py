"""Print the primary paired BM25 comparison and its largest query deltas."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} REPORT.json", file=sys.stderr)
        return 2

    report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    conditions = report["conditions"]
    raw = next(
        row for row in conditions if row["retriever"] == "bm25" and row["preset"] == "raw"
    )
    candidate = next(
        row
        for row in conditions
        if row["retriever"] == "bm25" and row["preset"] == "conservative"
    )

    comparison = candidate["comparison_to_raw"]["ndcg@10"]
    print("BM25 conservative versus raw, nDCG@10")
    print(json.dumps(comparison, ensure_ascii=False, indent=2))

    raw_scores = {row["qid"]: row["metrics"]["ndcg@10"] for row in raw["per_query"]}
    deltas = [
        {
            "qid": row["qid"],
            "query": row["query"],
            "delta": row["metrics"]["ndcg@10"] - raw_scores[row["qid"]],
        }
        for row in candidate["per_query"]
    ]
    print("\nFive largest wins")
    wins = sorted(
        (row for row in deltas if row["delta"] > 0),
        key=lambda row: row["delta"],
        reverse=True,
    )[:5]
    print(json.dumps(wins, ensure_ascii=False, indent=2))
    print("\nFive largest losses")
    losses = sorted(
        (row for row in deltas if row["delta"] < 0),
        key=lambda row: row["delta"],
    )[:5]
    print(json.dumps(losses, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
