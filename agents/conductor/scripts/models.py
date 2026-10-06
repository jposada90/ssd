"""Show, and optionally save, the model and effort per subagent.

The Conductor shows the user what it proposes before launching anything, then records
what the user chose. Recommendations are advisory; the saved choice is only a default
to review, never a decision to reuse silently.

Usage:
  python3 models.py <agent_dir>                     # show, default phase
  python3 models.py <agent_dir> <phase>             # show, with that phase's override
  python3 models.py <agent_dir> --save <spec>...    # record the user's answers
  python3 models.py <agent_dir> --clear <agent>...  # drop a saved default

A spec is  agent=tier[:effort][@phase]
  design-analyst=deep:high
  documentation-maintainer=light:low@archive

Saving is validated against models.json: an unknown tier or effort is rejected, because
a typo stored in .sdd.json would silently pin an agent to a wrong model forever.

--save replaces the default for an agent but keeps its per-phase answers, since those
were separate decisions. --clear is how you drop them.
"""

import json
import os
import pathlib
import sys


def load_saved():
    for name in (".sdd.json", "sdd.json"):
        config = pathlib.Path(name)
        if config.exists():
            return json.loads(config.read_text()).get("models", {}) or {}
    return {}


def detect_harness():
    if os.environ.get("OPENCODE") or pathlib.Path(".opencode").exists():
        return "opencode"
    return "claude"


def resolve(agent, saved_entry, recommendation, phase):
    """Saved choice wins, then a saved per-phase override, then the recommendation."""
    rec = recommendation
    if phase and phase in rec.get("byPhase", {}):
        rec = {**rec, **rec["byPhase"][phase]}

    entry = saved_entry or {}
    phase_entry = entry.get("byPhase", {}).get(phase, {}) if phase else {}

    tier = phase_entry.get("tier") or entry.get("tier") or rec["tier"]
    effort = phase_entry.get("effort") or entry.get("effort") or rec["effort"]
    return tier, effort


def show(agent_dir, models, phase):
    tiers = models["tiers"]
    saved = load_saved()
    harness = detect_harness()

    print(f"harness: {harness}")
    print(f"phase:   {phase or 'default'}")
    print()

    unknown = [a for a in saved if a not in models["recommendations"]]
    for a in unknown:
        print(f"warning: .sdd.json saves settings for '{a}', which no agent recommendation matches")

    for agent, rec in models["recommendations"].items():
        entry = saved.get(agent)
        tier_name, effort = resolve(agent, entry, rec, phase)

        rec_tier = rec["tier"]
        rec_effort = rec["effort"]
        if phase and phase in rec.get("byPhase", {}):
            rec_tier = rec["byPhase"][phase]["tier"]
            rec_effort = rec["byPhase"][phase]["effort"]

        diff = "" if (tier_name == rec_tier and effort == rec_effort) else " *"
        tag = "saved" if entry else "proposed"
        model_id = tiers.get(tier_name, {}).get(harness, "?")

        print(f"{agent}  [{tag}{diff}]")
        print(f"  tier:    {tier_name} -> {model_id}")
        print(f"  effort:  {effort}" + ("" if effort == rec_effort else f" (recommended {rec_effort})"))
        if entry:
            phases = ", ".join(sorted((entry.get("byPhase") or {}).keys())) or "-"
            print(f"  saved for phases: {phases}")
        print(f"  why:     {rec['reason']}")

    print()
    print("` *` = the saved default differs from the recommendation.")
    print("Ask the user every session. A saved default is not a decision to reuse silently.")
    return 0


def save(models, specs, clear=False):
    if clear:
        return clear_saved(models, specs)

    config_path = pathlib.Path(".sdd.json")
    config_path = pathlib.Path(".sdd.json")
    if not config_path.exists():
        print(f"no .sdd.json here; run the Conductor's boot step first", file=sys.stderr)
        return 1

    config = json.loads(config_path.read_text())
    saved = config.get("models") or {}
    tiers = models["tiers"]
    efforts = models["effortLevels"]
    known_agents = models["recommendations"]

    errors = []
    for spec in specs:
        if "=" not in spec:
            errors.append(f"'{spec}' is not agent=tier[:effort][@phase]")
            continue
        agent, rest = spec.split("=", 1)
        phase = None
        if "@" in rest:
            rest, phase = rest.rsplit("@", 1)
        tier = rest
        effort = None
        if ":" in rest:
            tier, effort = rest.split(":", 1)

        if agent not in known_agents:
            errors.append(f"unknown agent '{agent}'; known: {', '.join(sorted(known_agents))}")
            continue
        if tier not in tiers:
            errors.append(f"unknown tier '{tier}'; known: {', '.join(tiers)}")
            continue
        if effort and effort not in efforts:
            errors.append(f"unknown effort '{effort}'; known: {', '.join(efforts)}")
            continue

        entry = saved.setdefault(agent, {})
        if phase:
            entry.setdefault("byPhase", {})[phase] = {"tier": tier}
            if effort:
                entry["byPhase"][phase]["effort"] = effort
            print(f"saved {agent}: {tier}:{effort} for phase {phase}")
        else:
            entry["tier"] = tier
            if effort:
                entry["effort"] = effort
            # Phase-specific answers are separate decisions. Setting a new default
            # must not silently retire them, or archive goes back to standard the
            # moment someone re-tunes the general case. Use --clear to drop them.
            note = ""
            if entry.get("byPhase"):
                note = f" (kept phase overrides: {', '.join(sorted(entry['byPhase']))})"
            print(f"saved {agent}: {tier}:{effort or '(default effort)'}{note}")

    if errors:
        print()
        print("nothing was saved; fix these first:")
        for e in errors:
            print(f"  {e}")
        return 1

    config["models"] = saved
    config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
    print(f"\nwrote {len(saved)} agent(s) into {config_path} .models")
    return 0


def clear_saved(models, agents):
    """Drop a saved default so the recommendation applies again. Explicit, because
    saving a new default deliberately keeps phase overrides and would otherwise
    leave no way to undo them."""
    config_path = pathlib.Path(".sdd.json")
    if not config_path.exists():
        print("no .sdd.json here; run the Conductor's boot step first", file=sys.stderr)
        return 1

    config = json.loads(config_path.read_text())
    saved = config.get("models") or {}

    unknown = [a for a in agents if a not in models["recommendations"]]
    if unknown:
        print(f"unknown agent(s): {', '.join(unknown)}")
        print(f"known: {', '.join(sorted(models['recommendations']))}")
        return 1

    removed = []
    for agent in agents:
        if saved.pop(agent, None) is not None:
            removed.append(agent)
        else:
            print(f"nothing saved for {agent}, nothing to clear")

    config["models"] = saved
    config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
    print(f"cleared: {', '.join(removed) or 'nothing'}")
    print("those agents fall back to the recommendation again")
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    agent_dir = pathlib.Path(sys.argv[1]).resolve()
    models_path = agent_dir / "models.json"
    if not models_path.exists():
        print(f"no models.json at {models_path}", file=sys.stderr)
        return 2
    models = json.loads(models_path.read_text())

    args = sys.argv[2:]
    if args and args[0] == "--save":
        return save(models, args[1:])
    if args and args[0] == "--clear":
        return clear_saved(models, args[1:])

    phase = args[0] if args and not args[0].startswith("-") else None
    return show(agent_dir, models, phase)


if __name__ == "__main__":
    raise SystemExit(main())