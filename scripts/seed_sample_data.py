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
        RawDocument(
            source_type="seed",
            source_name="AP",
            title="Observers report ceasefire violation after overnight shelling",
            url="https://example.com/ap-1",
            published_at="2026-04-21T10:00:00Z",
            raw_text="Monitors said a ceasefire was violated after overnight shelling near Jerusalem, raising fears of a wider breach.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Al Jazeera",
            title="State media propaganda campaign amplifies false battlefield claims",
            url="https://example.com/aj-1",
            published_at="2026-04-21T10:20:00Z",
            raw_text="Analysts warned that a state media propaganda and disinformation campaign was amplifying false battlefield claims across the region.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Guardian",
            title="Ceasefire monitors document drone strike near northern border",
            url="https://example.com/guardian-1",
            published_at="2026-04-21T10:45:00Z",
            raw_text="Ceasefire monitors documented a drone strike near the northern Israel border and said the incident may breach the latest truce terms.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="France24",
            title="Diplomats push emergency talks after Tehran warning",
            url="https://example.com/france24-1",
            published_at="2026-04-21T11:05:00Z",
            raw_text="European diplomats called for emergency talks after officials in Tehran warned of retaliation if Israeli operations continue.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="DW",
            title="New sanctions package targets missile suppliers",
            url="https://example.com/dw-1",
            published_at="2026-04-21T11:30:00Z",
            raw_text="A new sanctions package targets firms accused of supplying missile components to Iranian-backed groups.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="NPR",
            title="Disinformation accounts recycle old explosion footage",
            url="https://example.com/npr-1",
            published_at="2026-04-21T11:55:00Z",
            raw_text="Researchers said disinformation accounts were recycling old explosion footage and labeling it as current battlefield video.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Times of Israel",
            title="Jerusalem cabinet weighs response after border attack",
            url="https://example.com/toi-1",
            published_at="2026-04-21T12:15:00Z",
            raw_text="The cabinet in Jerusalem weighed a response after a border attack raised fears of a wider regional escalation.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Haaretz",
            title="Aid convoy delayed after reported ceasefire breach",
            url="https://example.com/haaretz-1",
            published_at="2026-04-21T12:40:00Z",
            raw_text="An aid convoy was delayed after a reported ceasefire breach and shelling incident near a crossing point.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Politico",
            title="Washington prepares sanctions vote after escalation",
            url="https://example.com/politico-1",
            published_at="2026-04-21T13:00:00Z",
            raw_text="Officials in Washington prepared a sanctions vote after regional escalation involving Iran and Israel.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Sky News",
            title="State media claims disputed victory after overnight strike",
            url="https://example.com/sky-1",
            published_at="2026-04-21T13:25:00Z",
            raw_text="State media claimed a disputed military victory after an overnight strike, while independent analysts called the claim misleading propaganda.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="CNN",
            title="Ceasefire hotline activated after artillery exchange",
            url="https://example.com/cnn-1",
            published_at="2026-04-21T13:50:00Z",
            raw_text="A ceasefire hotline was activated after an artillery exchange near contested territory triggered warnings from monitors.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="The National",
            title="Regional leaders call for restraint after missile alert",
            url="https://example.com/national-1",
            published_at="2026-04-21T14:10:00Z",
            raw_text="Regional leaders called for restraint after a missile alert escalated tensions between Iran, Israel, and allied forces.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Axios",
            title="US officials brief allies on sanctions enforcement",
            url="https://example.com/axios-1",
            published_at="2026-04-21T14:35:00Z",
            raw_text="United States officials briefed allies on sanctions enforcement linked to weapons transfers and regional destabilization.",
            metadata={"language": "en"},
        ),
        RawDocument(
            source_type="seed",
            source_name="Bellingcat",
            title="Open-source analysts flag coordinated influence campaign",
            url="https://example.com/bellingcat-1",
            published_at="2026-04-21T15:00:00Z",
            raw_text="Open-source analysts flagged a coordinated influence campaign using bot accounts to spread misleading claims about ceasefire compliance.",
            metadata={"language": "en"},
        ),
    ]


if __name__ == "__main__":
    overwrite_jsonl(RAW_DOCS_FILE, build_seed_documents())
    print("Seeded sample raw documents.")
