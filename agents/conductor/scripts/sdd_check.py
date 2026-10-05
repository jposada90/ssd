"""Compare the project's recorded SDD version and layout against what this agent expects.

Detects a version mismatch, and also silent drift: someone moves a directory and the
version string still agrees with us. Read-only. Nothing is migrated here.

Usage: python3 sdd_check.py <agent_dir>

<agent_dir> is the conductor's own directory, which holds versions.json. It cannot be
guessed once this file is copied into a project.

Exit codes: 0 in sync, 1 out of sync, 2 cannot determine.
"""

import json
import os
import pathlib
import sys


def main():
    if len(sys.argv) < 2:
        print("usage: python3 sdd_check.py <agent_dir>", file=sys.stderr)
        print("SDD CHECK ERROR", file=sys.stderr)
        return 2

    agent_dir = pathlib.Path(sys.argv[1]).resolve()
    versions_path = agent_dir / "versions.json"
    if not versions_path.exists():
        print(f"no versions.json at {versions_path}", file=sys.stderr)
        return 2

    versions = json.loads(versions_path.read_text())
    agent_version = versions["current"]
    known = versions["versions"]

    print(f"agent:   {agent_version}")

    config_path = pathlib.Path("sdd.json")
    if not config_path.exists():
        print("project: no sdd.json; not initialized for SDD")
        print(f"AGENT EXPECTS: {agent_version}")
        print("SDD UNINITIALIZED")
        return 2

    project_version = json.loads(config_path.read_text()).get("sddVersion")
    print(f"project: {project_version}")
    print()

    problems = []

    if project_version != agent_version:
        if project_version in known:
            steps = known[project_version].get("migrations", [])
            detail = f"{len(steps)} registered migration step(s)" if steps else \
                     "no migration steps registered; do it by hand"
            problems.append(
                f"version mismatch: project {project_version}, agent {agent_version} ({detail})"
            )
        else:
            problems.append(
                f"version mismatch: project {project_version} is unknown to this agent "
                f"(agent knows {agent_version}). No migration path exists."
            )

        expected_layout = known.get(agent_version, {}).get("layout", {})
        recorded_layout = json.loads(config_path.read_text()).get("layout", {})
        for key, path in expected_layout.items():
            if key == "symlinks":
                continue
            was = recorded_layout.get(key)
            if was and was != path:
                problems.append(f"  {key}: project has {was}, this version expects {path}")
        problems.append(
            "  compare the two layouts by hand and tell the user what moves; "
            "do not rewrite the project unasked."
        )

    layout = known.get(agent_version, {}).get("layout")
    if layout is None:
        problems.append(f"agent does not declare a layout for its own version {agent_version}")
    else:
        recorded = json.loads(config_path.read_text()).get("layout", {})

        for key, path in layout.items():
            if key == "symlinks":
                continue
            if not os.path.exists(path):
                problems.append(f"missing {path} (declared as {key})")
            if key in recorded and recorded[key] != path:
                problems.append(
                    f"{key}: sdd.json records {recorded[key]}, this version expects {path}"
                )

        for link in layout.get("symlinks", []):
            if not os.path.lexists(link):
                problems.append(f"missing {link} (symlink to {layout['agentsFile']})")
            elif os.path.islink(link) and not os.path.exists(link):
                problems.append(f"{link} is a broken symlink")

    if problems:
        print("== out of sync")
        for p in problems:
            print(f"  {p}")
        print()
        print("Ask the user whether to migrate. Do not migrate unasked.")
        print("SDD VERSION MISMATCH")
        return 1

    print(f"project matches agent SDD {agent_version}")
    print("SDD VERSION OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())