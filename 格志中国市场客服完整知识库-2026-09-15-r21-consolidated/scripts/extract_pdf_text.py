import sys
from pathlib import Path

from pypdf import PdfReader


def main():
    pdf_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    reader = PdfReader(str(pdf_path))
    parts = []
    for idx, page in enumerate(reader.pages, start=1):
        try:
            text = page.extract_text() or ""
        except Exception as exc:
            text = f"[extract_error: {exc}]"
        parts.append(f"\n\n--- page {idx} ---\n{text}")
    out_path.write_text("".join(parts), encoding="utf-8")
    print(f"{pdf_path.name}: pages={len(reader.pages)} chars={sum(len(p) for p in parts)} -> {out_path}")


if __name__ == "__main__":
    main()
