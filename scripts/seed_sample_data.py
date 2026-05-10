from __future__ import annotations

import sys
from pathlib import Path
from typing import List

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from shared.models import RawDocument
from shared.storage import RAW_DOCS_FILE, overwrite_jsonl


def build_seed_documents() -> List[RawDocument]:
    return [
        RawDocument(
            source_type="seed",
            source_name="Reuters",
            title="Iran and Israel exchange warnings after regional strike",
            url="https://example.com/reuters-1",
            published_at="2026-04-21T09:10:00Z",
            raw_text="Iran and Israel traded warnings after a regional strike near Tehran. Officials in both countries signaled possible escalation.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="BBC",
            title="Regional tensions rise as sanctions pressure grows",
            url="https://example.com/bbc-1",
            published_at="2026-04-21T09:30:00Z",
            raw_text="Sanctions pressure increased while regional officials in Jerusalem discussed escalation risks involving Iran and Israel.",
            metadata={"language": "en"},
        ),
    ]


if __name__ == "__main__":
    overwrite_jsonl(RAW_DOCS_FILE, build_seed_documents())
    print("Seeded sample raw documents.")
