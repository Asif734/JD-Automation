from __future__ import annotations

from .config import Settings
from .index import RagIndex
from .knowledge import load_corpus
from .openai_service import OpenAIService


def main() -> None:
    settings = Settings.from_env()
    if not settings.openai_api_key:
        raise SystemExit("OPENAI_API_KEY is required to build the vector index")
    corpus = load_corpus(settings.knowledge_dir)
    index = RagIndex(settings.data_dir, corpus)
    client = OpenAIService(
        settings.openai_api_key,
        settings.generation_model,
        settings.embedding_model,
    )
    records, dimensions = index.rebuild(client)
    print(f"Built {records} vectors ({dimensions} dimensions) in {settings.data_dir}")
    for warning in corpus.warnings:
        print(f"WARNING: {warning}")


if __name__ == "__main__":
    main()
