import json
import pathlib
import sys

import jsonschema

SCHEMA = pathlib.Path(__file__).resolve().parents[1] / "schema" / "roadmap.schema.json"
schema = json.loads(SCHEMA.read_text())
validator = jsonschema.Draft202012Validator(schema)


def check(label, doc, should_pass):
    errors = sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path))
    ok = not errors
    verdict = "PASS" if ok == should_pass else "UNEXPECTED"
    print(f"[{verdict}] {label}: expected {'valid' if should_pass else 'invalid'}, got "
          f"{'valid' if ok else 'invalid'}")
    for e in errors[:3]:
        path = "/".join(str(p) for p in e.absolute_path) or "<root>"
        print(f"         {path}: {e.message[:110]}")


def node(**kw):
    base = {
        "schemaVersion": "1.0",
        "id": "F-01",
        "version": "1.0",
        "name": "Orden de compra",
        "description": "Permite crear y seguir una orden de compra.",
        "level": "feature",
        "status": "ready",
        "openQuestions": [],
        "tasks": [],
    }
    base.update(kw)
    return base


# --- root document
check("root main", node(id="MAIN-00", level="main", name="main",
                        status="draft",
                        openQuestions=["¿Mercado inicial?"], tasks=[]), True)

# --- leaf inlined in the parent
check("leaf entry", node(tasks=[{
    "id": "T-001",
    "name": "Crear orden",
    "status": "ready",
    "whatToBuild": "El comprador crea una orden y la ve listada.",
    "acceptanceCriteria": ["Dada una orden, aparece en el listado del comprador."],
    "blockedBy": [],
}]), True)

# --- child with its own document, referenced
check("file reference", node(tasks=[{
    "id": "F-02", "name": "Pagos", "status": "draft", "file": "F-01-pagos/F-02.json"
}]), True)

# --- ready must not carry open questions
check("ready with openQuestions", node(status="ready", openQuestions=["¿Cuándo?"]), False)

# --- draft may carry open questions
check("draft with openQuestions", node(status="draft", openQuestions=["¿Cuándo?"]), True)

# --- main must be MAIN-00 / name main
check("main with wrong id", node(id="MAIN-01", level="main"), False)
check("main with wrong name", node(id="MAIN-00", level="main", name="Roadmap"), False)

# --- bad enums and bad versions
check("unknown status", node(status="block"), False)
check("bad version format", node(version="1"), False)
check("bad id format", node(id="feature-1"), False)

# --- main cannot appear as a child
check("main as child", node(tasks=[{"id": "MAIN-01", "name": "x", "status": "draft"}]), False)

# --- unknown fields rejected, both at root and in a child
check("unknown root field", node(phase="sdd-req"), False)
check("unknown child field", node(tasks=[{"id": "T-001", "name": "x", "status": "draft",
                                         "priority": "high"}]), False)

# --- child must not restate the parent's gitInfo / level bookkeeping
check("child repeats gitInfo", node(tasks=[{"id": "T-001", "name": "x", "status": "draft",
                                           "gitInfo": {"mainBranch": "main"}}]), False)

# --- blockedBy edges
check("blockedBy edges", node(tasks=[
    {"id": "T-001", "name": "a", "status": "ready", "blockedBy": []},
    {"id": "T-002", "name": "b", "status": "blocked", "blockedBy": ["T-001"]},
]), True)

# --- acceptanceCriteria may not be an empty array
check("empty acceptanceCriteria", node(tasks=[{
    "id": "T-001", "name": "a", "status": "ready", "acceptanceCriteria": []
}]), False)

# --- gitInfo present
check("gitInfo", node(gitInfo={"mainBranch": "main", "parentBranch": "main",
                               "featureBranch": "feat/orden",
                               "statusBranch": "development"}), True)

# --- phase: optional, and every stage is a legal value
check("phase on document", node(phase="apply"), True)
for stage in ["proposal", "spec", "design", "task", "apply", "verify", "archive"]:
    check(f"phase {stage}", node(phase=stage), True)

check("phase omitted", node(), True)
check("phase unknown value", node(phase="sdd-req"), False)
check("phase empty string", node(phase=""), False)

# --- decisions: a user authorization releases a blocking question
DEC = {"date": "2026-10-05", "question": "¿Se admite cancelación parcial?",
       "resolution": "No, fuera de alcance", "authorizedBy": "usuario"}

check("ready with a recorded decision", node(status="ready", openQuestions=["¿Cuál?"],
                                             decisions=[DEC]), True)
check("ready with an unresolved question", node(status="ready", openQuestions=["¿Cuál?"]), False)
check("apply with a recorded decision", node(status="inProgress", phase="apply",
                                             openQuestions=["¿Cuál?"],
                                             decisions=[DEC]), True)
check("apply with an unresolved question", node(status="inProgress", phase="apply",
                                                openQuestions=["¿Cuál?"]), False)
check("draft needs no decision", node(status="draft", openQuestions=["¿Cuál?"]), True)
check("decision missing fields", node(status="ready", openQuestions=["¿Cuál?"],
                                      decisions=[{"date": "2026-10-05"}]), False)
check("decision with unknown field", node(status="ready", openQuestions=["¿Cuál?"],
                                          decisions=[{**DEC, "by": "agente"}]), False)
check("decision on a leaf", node(tasks=[{
    "id": "T-001", "name": "a", "status": "ready", "decisions": [DEC],
}]), True)

# --- a phase value never implies approval by itself
check("proposal with open questions", node(status="draft", phase="proposal",
                                           openQuestions=["¿Cuál?"]), True)

# --- phase on a leaf entry
check("phase on leaf", node(tasks=[{
    "id": "T-001", "name": "a", "status": "inProgress", "phase": "verify",
    "whatToBuild": "a", "acceptanceCriteria": ["done"], "blockedBy": [],
}]), True)
check("phase on leaf invalid", node(tasks=[{
    "id": "T-001", "name": "a", "status": "ready", "phase": "deployed",
}]), False)
check("leaf phase omitted", node(tasks=[{
    "id": "T-001", "name": "a", "status": "draft",
}]), True)

# --- byte-identical duplicate children rejected; same id with different content is
# not caught by the schema (uniqueItems compares objects, not members) and is the
# agent's job to prevent.
check("identical duplicate child", node(tasks=[
    {"id": "T-001", "name": "a", "status": "ready"},
    {"id": "T-001", "name": "a", "status": "ready"},
]), False)
check("same id different content", node(tasks=[
    {"id": "T-001", "name": "a", "status": "ready"},
    {"id": "T-001", "name": "b", "status": "ready"},
]), True)

print("\ndone")
sys.exit(0)