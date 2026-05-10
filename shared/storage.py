from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable, TypeVar

from pydantic import BaseModel

BASE_DIR = Path(__file__).resolve().parents[1]
DATA_DIR = BASE_DIR / "data"
RAW_DOCS_FILE = DATA_DIR / "raw_documents.jsonl"
EVENTS_FILE = DATA_DIR / "events.jsonl"

T = TypeVar("T", bound=BaseModel)


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def append_jsonl(path: Path, item: BaseModel) -> None:
    ensure_data_dir()
    with path.open("a", encoding="utf-8") as handle:
        handle.write(item.model_dump_json())
        handle.write("\n")


def read_jsonl(path: Path, model_cls: type[T]) -> list[T]:
    if not path.exists():
        return []

    records: list[T] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            records.append(model_cls.model_validate(json.loads(line)))
    return records


def overwrite_jsonl(path: Path, items: Iterable[BaseModel]) -> None:
    ensure_data_dir()
    with path.open("w", encoding="utf-8") as handle:
        for item in items:
            handle.write(item.model_dump_json())
            handle.write("\n")
