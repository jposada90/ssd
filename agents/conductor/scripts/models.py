"""Print the recommended model and effort per subagent, merged with the project's saved choice.

The Conductor uses this to show the user what it proposes before launching anything.
Recommendations are advisory: the user picks, the project remembers.

Usage: python3 models.py <agent_dir> [phase]

<phase> applies a per-phase override, e.g. archive, which downgrades
documentation-maintainer to a lighter tier.
"""

import json
import os
import pathlib
import sys


def main():
    if len(sys.argv) < 2:
        print("usage: python3 models.py <agent_dir> [phase]", file=sys.stderr)
        return 2

    agent_dir = pathlib.Path(sys.argv[1]).resolve()
    phase = sys.argv[2] if len(sys.argv) > 2 else None

    models_path = agent_dir / "models.json"
    if not models_path.exists():
        print(f"no models.json at {models_path}", file=sys.stderr)
        return 2

    models = json.loads(models_path.read_text())
    tiers = models["tiers"]

    saved = {}
    config = pathlib.Path("sdd.json")
    if config.exists():
        saved = json.loads(config.read_text()).get("models", {})

    # Detect the harness so the concrete model id is the right vocabulary.
    harness = "opencode" if os.environ.get("OPENCODE") or pathlib.Path(".opencode").exists() else "claude"

    rows = []
    for agent, rec in models["recommendations"].items():
        override = rec.get("byPhase", {}).get(phase) if phase else None
        effective = {**rec, **(override or {})}
        tier_name = effective["tier"]
        tier = tiers.get(tier_name, {})
        saved_entry = saved.get(agent, {})
        chosen_tier = saved_entry.get("tier", tier_name)
        chosen_effort = saved_entry.get("effort", effective["effort"])
        rows.append({
            "agent": agent,
            "recommendedTier": tier_name,
            "recommendedEffort": effective["effort"],
            "chosenTier": chosen_tier,
            "chosenEffort": chosen_effort,
            "modelId": tier.get(harness, "?"),
            "reason": effective["reason"],
            "isSaved": bool(saved_entry),
        })

    print(f"harness: {harness}")
    print(f"phase:   {phase or 'default'}")
    print()
    for r in rows:
        tag = "saved" if r["isSaved"] else "proposed"
        flag = " *" if (r["isSaved"] and r["chosenTier"] != r["recommendedTier"]) else ""
        print(f"{r['agent']}  [{tag}{flag}]")
        print(f"  tier:      {r['chosenTier']} -> {r['modelId']}")
        print(f"  effort:    {r['chosenEffort']} (recommended {r['recommendedEffort']})")
        print(f"  why:       {r['reason']}")
    print()
    print("` *` means the project saved a choice that differs from the recommendation.")
    print("Ask the user before launching. Do not launch on the recommendation alone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())