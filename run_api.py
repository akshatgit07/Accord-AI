from __future__ import annotations

import argparse

import uvicorn

from shared.settings import settings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Accord AI FastAPI server.")
    parser.add_argument(
        "--reload",
        action="store_true",
        help="Enable auto-reload for local development.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    uvicorn.run("api.main:app", host=settings.api_host, port=settings.api_port, reload=args.reload)
