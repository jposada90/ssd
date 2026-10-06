"""Apply a registered SDD migration, one step at a time, reporting what each did.

Migrations are declarative ops in versions.json, so this script has no per-version
branches to forget to update. It is deliberately not automatic: the Conductor asks
the user first, and the output of --dry-run is what they are shown.

Usage:
  python3 migrate_sdd.py <agent_dir>            # migrate
  python3 migrate_sdd.py <agent_dir> --dry-run  # show the plan, change nothing
  python3 migrate_sdd.py <agent_dir> --to 1.2   # target a specific version

Exit codes: 0 migrated or already current, 1 no path or a step failed.
"""

import json
import os
import pathlib
import sys

DRY = False


def apply_op(op, log):
    kind = op.get("op")

    if kind == "rename":
        src, dst = pathlib.Path(op["from"]), pathlib.Path(op["to"])
        if not src.exists():
            log(f"skip: {src} does not exist")
            return True
        if dst.exists():
            log(f"fail: {dst} already exists, {src} left alone")
            return False
        if DRY:
            log(f"would rename {src} -> {dst}")
            return True
        src.rename(dst)
        log(f"renamed {src} -> {dst}")
        return True

    if kind == "setLayout":
        # The recorded layout is a copy of the version's, so it moves with it.
        path = pathlib.Path(".sdd.json")
        if DRY:
            log(f"would refresh the layout block in {path}")
            return True
        if not path.exists():
            log(f"fail: {path} missing, nothing to migrate")
            return False
        doc = json.loads(path.read_text())
        doc["layout"] = {k: v for k, v in op["layout"].items() if k != "symlinks"}
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        log(f"refreshed layout in {path}")
        return True

    if kind == "initLinks":
        # Fill links from what is actually on disk: a project that predates the
        # per-harness choice already has its entry points, and recording an empty
        # list would make the check report "none by choice" while they exist.
        path = pathlib.Path(".sdd.json")
        if DRY:
            log(f"would record in {path} the entry points found on disk")
            return True
        if not path.exists():
            log(f"fail: {path} missing, nothing to migrate")
            return False
        found = [p for p in op["options"].values()
                 if os.path.lexists(p) and not (os.path.islink(p) and not os.path.exists(p))]
        doc = json.loads(path.read_text())
        if doc.get("links") is not None:
            log(f"skip: {path} already decided links={doc['links']}")
            return True
        doc["links"] = found
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        log(f"recorded links={found or 'none present'} in {path}")
        return True

    if kind == "requireKey":
        path = pathlib.Path(".sdd.json")
        if DRY:
            # A previous rename may not have run yet, so the filesystem is not
            # evidence here. Report the intent rather than failing the dry run.
            log(f"would ensure '{op['key']}' exists in {path}")
            log("  note: re-run init-sdd.sh --for <harnesses> to record the real ones")
            return True
        if not path.exists():
            log(f"fail: {path} missing, nothing to migrate")
            return False
        doc = json.loads(path.read_text())
        if op["key"] in doc:
            log(f"skip: {path} already has '{op['key']}'")
            return True
        doc[op["key"]] = []
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
        log(f"added empty '{op['key']}' to {path}")
        log("  note: re-run init-sdd.sh --for <harnesses> to record the real ones")
        return True

    log(f"fail: unknown op '{kind}'")
    return False


def main():
    global DRY
    args = sys.argv[1:]
    DRY = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]

    if len(args) < 1:
        print("usage: python3 migrate_sdd.py <agent_dir> [--dry-run] [--to <version>]",
              file=sys.stderr)
        return 2

    agent_dir = pathlib.Path(args[0]).resolve()
    versions_path = agent_dir / "versions.json"
    if not versions_path.exists():
        print(f"no versions.json at {versions_path}", file=sys.stderr)
        return 2

    versions = json.loads(versions_path.read_text())
    known = versions["versions"]
    target = None
    if "--to" in args:
        target = args[args.index("--to") + 1]
    target = target or versions["current"]

    config_path = pathlib.Path(".sdd.json")
    if not config_path.exists():
        if pathlib.Path("sdd.json").exists():
            print("this project still uses the pre-1.1 sdd.json; the first migration renames it")
            from_version = "1.0"
        else:
            print("no .sdd.json and no sdd.json: project not initialized for SDD")
            print("run the Conductor's boot step instead")
            return 1
    else:
        from_version = json.loads(config_path.read_text()).get("sddVersion")

    print(f"agent:   {versions['current']}")
    print(f"project: {from_version}")
    print(f"target:  {target}")
    print()

    if from_version == target:
        print(f"already on {target}; nothing to migrate")
        return 0

    if from_version not in known:
        print(f"project version {from_version} is unknown to this agent: no migration path")
        print("compare the layouts by hand")
        return 1

    # Walk forward one version at a time, following registered migrations.
    pending = []
    order = sorted(known, key=lambda v: [int(p) for p in v.split(".")])
    try:
        start = order.index(from_version)
        end = order.index(target)
    except ValueError:
        print(f"cannot path {from_version} -> {target} with versions {order}")
        return 1

    for version in order[start + 1: end + 1]:
        spec = known[version]
        steps = next((m["steps"] for m in spec.get("migrations", [])
                      if m.get("from") == from_version or m.get("from") == version), None)
        if steps is None:
            print(f"no migration registered into {version}; stopping before it")
            return 1 if not pending else 0
        pending.append((version, spec, steps))

    if not pending:
        print(f"no migration path {from_version} -> {target}")
        return 1

    log_lines = []
    for version, spec, steps in pending:
        print(f"== {from_version} -> {version}: {spec['summary']}")
        for op in steps:
            op = dict(op)
            op.setdefault("options", spec.get("linkOptions", {}))
            op.setdefault("layout", spec.get("layout", {}))
            apply_op(op, lambda m: log_lines.append(m) or print(f"  {m}"))
        print()

    if not config_path.exists() and not DRY:
        pass

    # Bump the recorded version to what we actually applied.
    if config_path.exists():
        if DRY:
            print(f"would set .sdd.json sddVersion to {target}")
        else:
            doc = json.loads(config_path.read_text())
            doc["sddVersion"] = target
            config_path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
            print(f"set .sdd.json sddVersion to {target}")

    print()
    if DRY:
        print("DRY RUN: nothing was changed")
        return 0
    print("MIGRATED")
    print("run sdd_check.py to confirm the project is in sync")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())