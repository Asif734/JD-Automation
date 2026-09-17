from pathlib import Path

from scripts.audit_kb_conflicts import audit


ROOT = Path(__file__).resolve().parents[1]


def test_whole_database_audit_has_no_unresolved_conflicts() -> None:
    result = audit(ROOT)
    assert result["unresolved_conflict_count"] == 0, result["unresolved_conflicts"]
