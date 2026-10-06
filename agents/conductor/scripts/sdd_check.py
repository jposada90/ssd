"""Compare the project's recorded SDD version and layout against what this agent expects.

Detects a version mismatch, and also silent drift: someone moves a directory and the
version string still agrees with us. Entry points are checked only when the project
declared them, since which harnesses a project uses is a choice made at init.

Also checks that .sdd/ is actually gitignored and that its scripts match the installed
suite: a subagent editing the Conductor's own scripts is not something we can prevent
on every harness, but it is something we can notice.

Read-only. Nothing is migrated here.

Usage: python3 sdd_check.py <agent_dir>

<agent_dir> is the conductor's own directory, which holds versions.json. It cannot be
guessed once this file is copied into a project.

Exit codes: 0 in sync, 1 out of sync, 2 cannot determine.
"""

import hashlib
import json
import os
import pathlib
import subprocess
import sys

# Names the suite used before they moved under .sdd/ (SDD 1.2).
LEGACY_CONFIG = ["sdd.json", ".sdd.json"]
LEGACY_SCRIPTS_DIR = "scripts"


def gitignore_ok(path="."):
    """Is `path` ignored by git? A .sdd/ that is not ignored gets committed, and with
    it absolute paths and one person's model choices."""
    try:
        out = subprocess.run(
            ["git", "check-ignore", "-q", path],
            capture_output=True, timeout=10,
        )
        return out.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return None  # not a git repo, or git is unavailable


def suite_scripts(agent_dir):
    """Every script .sdd/scripts should hold, with its source. check_roadmap.py is the
    schema's companion and ships from task-decomposer/schema, not from conductor/scripts."""
    found = {}
    conductor = agent_dir / "scripts"
    if conductor.is_dir():
        for src in sorted(conductor.iterdir()):
            if src.is_file() and not src.name.endswith(".pyc"):
                found[src.name] = src
    companion = agent_dir.parent / "task-decomposer" / "schema" / "check_roadmap.py"
    if companion.is_file():
        found.setdefault("check_roadmap.py", companion)
    return found


def scripts_drift(agent_dir, sdd_dir):
    """Compare .sdd/scripts against the installed suite. The project copy is a copy, so
    any difference means someone edited it in place."""
    local = pathlib.Path(sdd_dir) / "scripts"
    if not local.is_dir():
        return []

    expected = suite_scripts(agent_dir)
    if not expected:
        return []

    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    drifted = []
    for name, src in sorted(expected.items()):
        copy = local / name
        if not copy.exists():
            drifted.append(f"{copy}: missing, the suite has it")
        elif digest(src) != digest(copy):
            drifted.append(f"{copy}: differs from the installed suite")

    for extra in sorted(local.iterdir()):
        if extra.is_file() and not extra.name.endswith(".pyc") and extra.name not in expected:
            drifted.append(f"{extra}: not part of the installed suite")
    return drifted


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

    problems = []

    if not pathlib.Path(".sdd/sdd.json").exists():
        for legacy in LEGACY_CONFIG:
            if pathlib.Path(legacy).exists():
                print(f"project: {legacy} (pre-{agent_version} name)")
                print()
                print("== out of sync")
                print(f"  this project predates the current SDD: it has {legacy}, "
                      f"this agent expects .sdd/sdd.json")
                print(f"  run: python3 {LEGACY_SCRIPTS_DIR}/migrate_sdd.py {agent_dir}"
                      if pathlib.Path(LEGACY_SCRIPTS_DIR).is_dir() else
                      f"  run: python3 migrate_sdd.py {agent_dir}")
                print()
                print("Ask the user whether to migrate. Do not migrate unasked.")
                print("SDD VERSION MISMATCH")
                return 1
        print("project: no .sdd/sdd.json; not initialized for SDD")
        print(f"AGENT EXPECTS: {agent_version}")
        print("SDD UNINITIALIZED")
        return 2

    project = json.loads(pathlib.Path(".sdd/sdd.json").read_text())
    project_version = project.get("sddVersion")
    print(f"project: {project_version}")
    print()

    if project_version != agent_version:
        if project_version in known:
            steps = known[project_version].get("migrations", [])
            if steps:
                problems.append(
                    f"version mismatch: project {project_version}, agent {agent_version}. "
                    f"A migration is registered; run migrate_sdd.py and report it to the user."
                )
            else:
                problems.append(
                    f"version mismatch: project {project_version}, agent {agent_version}. "
                    f"No migration steps registered; do it by hand."
                )
        else:
            problems.append(
                f"version mismatch: project {project_version} is unknown to this agent "
                f"(agent knows {agent_version}). No migration path exists."
            )

        expected_layout = known.get(agent_version, {}).get("layout", {})
        recorded_layout = project.get("layout", {})
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

    spec = known.get(agent_version, {})
    layout = spec.get("layout")
    if layout is None:
        problems.append(f"agent does not declare a layout for its own version {agent_version}")
    else:
        recorded = project.get("layout", {})

        for key, path in layout.items():
            if key == "symlinks":
                continue
            if not os.path.exists(path):
                problems.append(f"missing {path} (declared as {key})")
            if key in recorded and recorded[key] != path:
                problems.append(
                    f"{key}: .sdd/sdd.json records {recorded[key]}, this version expects {path}"
                )

        # .sdd/ must not be committable. An ignored directory is the only thing that
        # actually keeps this rule; a prompt asking nicely is not.
        sdd_dir = layout.get("sddDir", ".sdd")
        ignored = gitignore_ok(sdd_dir)
        if ignored is False:
            problems.append(
                f"{sdd_dir}/ is NOT in .gitignore: it would be committed, with absolute "
                f"paths and one person's model choices. Add {sdd_dir}/ to .gitignore."
            )

        for drifted in scripts_drift(agent_dir, sdd_dir):
            problems.append(
                f"{drifted}: .sdd/ belongs to the Conductor and must match the suite. "
                f"Re-run init-sdd.sh --force to restore it."
            )

        # Only the entry points the project asked for. A project that never wanted
        # a CLAUDE.md should not fail the check for not having one.
        agents_file = layout["agentsFile"]
        links = project.get("links", "missing")
        if links == "missing" or links is None:
            problems.append(
                "which harnesses this project uses is undecided (.sdd/sdd.json links is null). "
                "Ask the user, then run init-sdd.sh --for <names>, or --for none."
            )
        else:
            options = spec.get("linkOptions", {})
            for link in links:
                if link not in options.values():
                    problems.append(f"{link} is not a known entry point in this version")
                    continue
                if not os.path.lexists(link):
                    problems.append(f"missing {link} (entry point the project chose, for {agents_file})")
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
    if project.get("links"):
        print("entry points: " + ", ".join(project["links"]))
    elif project.get("links") == []:
        print("entry points: none by choice, AGENTS.md only")
    if ignored is True:
        print(".sdd/: ignored by git, as it should be")
    print("SDD VERSION OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())