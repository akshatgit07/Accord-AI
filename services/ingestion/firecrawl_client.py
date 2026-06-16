from __future__ import annotations

import argparse
import json
from urllib.parse import urlparse

import requests

from shared.models import RawDocument
from shared.settings import settings
from shared.storage import RAW_DOCS_FILE, append_jsonl

FIRECRAWL_SCRAPE_URL = "https://api.firecrawl.dev/v2/scrape"
OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"


def scrape_markdown(url: str) -> dict:
    if not settings.firecrawl_api_key:
        raise RuntimeError("FIRECRAWL_API_KEY is not configured")

    response = requests.post(
        FIRECRAWL_SCRAPE_URL,
        headers={
            "Authorization": f"Bearer {settings.firecrawl_api_key}",
            "Content-Type": "application/json",
        },
        json={
            "url": url,
            "formats": ["markdown"],
            "onlyMainContent": True,
        },
        timeout=60,
    )
    response.raise_for_status()
    return response.json()


def parse_markdown(scrape_payload: dict) -> str:
    data = scrape_payload.get("data", scrape_payload)
    markdown = data.get("markdown") if isinstance(data, dict) else None
    if not markdown:
        raise ValueError("Firecrawl response did not include markdown")
    return markdown


def parse_title(scrape_payload: dict, url: str) -> str:
    data = scrape_payload.get("data", scrape_payload)
    metadata = data.get("metadata", {}) if isinstance(data, dict) else {}
    return metadata.get("title") or urlparse(url).netloc or url


def summarize_markdown(markdown: str, url: str) -> str:
    if not settings.openai_api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")

    response = requests.post(
        OPENAI_RESPONSES_URL,
        headers={
            "Authorization": f"Bearer {settings.openai_api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": settings.openai_summary_model,
            "input": [
                {
                    "role": "system",
                    "content": (
                        "You prepare scraped web content for geopolitical intelligence extraction. "
                        "Keep concrete facts, actors, locations, dates, claims, and source context. "
                        "Remove navigation, boilerplate, marketing copy, cookie text, and duplicated lines."
                    ),
                },
                {
                    "role": "user",
                    "content": f"URL: {url}\n\nSummarize this scraped markdown for event extraction:\n\n{markdown[:20000]}",
                },
            ],
        },
        timeout=60,
    )
    response.raise_for_status()
    payload = response.json()

    if isinstance(payload.get("output_text"), str):
        return payload["output_text"]

    for item in payload.get("output", []):
        for content in item.get("content", []):
            if isinstance(content.get("text"), str):
                return content["text"]

    raise ValueError("OpenAI response did not include summary text")


def scrape_url_to_document(url: str, summarize: bool = True) -> RawDocument:
    payload = scrape_markdown(url)
    markdown = parse_markdown(payload)
    title = parse_title(payload, url)
    raw_text = summarize_markdown(markdown, url) if summarize else markdown[:20000]

    return RawDocument(
        source_type="firecrawl",
        source_name=urlparse(url).netloc or "Firecrawl",
        title=title,
        url=url,
        raw_text=raw_text,
        metadata={
            "scrape_provider": "firecrawl",
            "scraped_markdown_length": len(markdown),
            "summarized_with_openai": summarize,
            "summary_model": settings.openai_summary_model if summarize else None,
        },
    )


def run(urls: list[str], summarize: bool = True) -> list[RawDocument]:
    documents = []
    for url in urls:
        document = scrape_url_to_document(url, summarize=summarize)
        append_jsonl(RAW_DOCS_FILE, document)
        documents.append(document)
        print(
            json.dumps(
                {
                    "url": url,
                    "title": document.title,
                    "raw_text_length": len(document.raw_text),
                    "document_id": document.document_id,
                }
            )
        )
    return documents


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scrape web pages with Firecrawl and add them to Accord AI raw documents.")
    parser.add_argument("urls", nargs="+", help="One or more URLs to scrape.")
    parser.add_argument(
        "--no-summary",
        action="store_true",
        help="Store trimmed markdown directly instead of summarizing with OpenAI first.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(args.urls, summarize=not args.no_summary)
