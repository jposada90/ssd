#!/usr/bin/env node
// Renders each agent's canonical prompt.md into per-harness agent files.
//
//   node build.mjs            # build every agent
//   node build.mjs --check    # fail if generated files are stale
//
// Input:  agents/<agent>/{prompt.md,agent.json}
// Output: agents/<agent>/dist/{pi,claude,opencode}/<name>.md
// The body is identical across harnesses; only frontmatter differs.

import { readFile, writeFile, mkdir, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)));
const AGENTS_DIR = join(ROOT, "agents");
const HARNESSES = ["pi", "claude", "opencode"];
const check = process.argv.includes("--check");

function yamlString(value) {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function yamlValue(value) {
  if (Array.isArray(value)) return `[${value.map(yamlString).join(", ")}]`;
  if (typeof value === "boolean" || typeof value === "number") return String(value);
  return yamlString(value);
}

function frontmatter(fields) {
  const lines = Object.entries(fields)
    .filter(([, v]) => v !== undefined && v !== null)
    .filter(([, v]) => !(Array.isArray(v) && v.length === 0))
    .map(([k, v]) => `${k}: ${yamlValue(v)}`);
  return `---\n${lines.join("\n")}\n---\n`;
}

function piFrontmatter(agent) {
  return frontmatter({
    name: agent.name,
    description: agent.description,
    advertise: true,
    systemPromptMode: "append",
    inheritProjectContext: true,
    inheritSkills: false,
    tools: agent.pi.tools,
    skills: agent.skills,
    allowNestedSubagents: agent.pi.allowNestedSubagents,
    allowedAgents: agent.pi.allowedAgents,
    maxSubagentDepth: agent.pi.maxSubagentDepth,
  });
}

function claudeFrontmatter(agent) {
  return frontmatter({
    name: agent.name,
    description: agent.description,
    tools: agent.claude.tools,
    model: agent.claude.model,
  });
}

function opencodeFrontmatter(agent) {
  const permissions = agent.opencode.permissions
    .map((r) => `  - action: ${r.action}\n    resource: ${yamlString(r.resource)}\n    effect: ${r.effect}`)
    .join("\n");
  return [
    "---",
    `description: ${yamlString(agent.description)}`,
    `mode: ${agent.mode}`,
    "permissions:",
    permissions,
    "---",
    "",
  ].join("\n");
}

const RENDERERS = {
  pi: piFrontmatter,
  claude: claudeFrontmatter,
  opencode: opencodeFrontmatter,
};

async function buildAgent(dir) {
  const name = dir;
  const agentDir = join(AGENTS_DIR, name);
  const manifest = JSON.parse(await readFile(join(agentDir, "agent.json"), "utf8"));
  const body = (await readFile(join(agentDir, "prompt.md"), "utf8")).trimEnd();
  const files = [];

  for (const harness of HARNESSES) {
    const target = join(agentDir, "dist", harness, `${manifest.name}.md`);
    const content = `${RENDERERS[harness](manifest)}\n${body}\n`;
    files.push([target, content]);
  }

  for (const [target, content] of files) {
    const current = existsSync(target) ? await readFile(target, "utf8") : null;
    if (current === content) continue;
    if (check) {
      console.error(`stale: ${target.replace(`${ROOT}/`, "")}`);
      process.exitCode = 1;
      continue;
    }
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, content);
    console.log(`wrote ${target.replace(`${ROOT}/`, "")}`);
  }
}

if (!existsSync(AGENTS_DIR)) {
  console.error(`no agents/ directory at ${AGENTS_DIR}`);
  process.exit(2);
}

const dirs = (await readdir(AGENTS_DIR, { withFileTypes: true }))
  .filter((e) => e.isDirectory())
  .map((e) => e.name)
  .filter((n) => existsSync(join(AGENTS_DIR, n, "agent.json")))
  .sort();

for (const dir of dirs) await buildAgent(dir);
if (!check) console.log(`${dirs.length} agents: ${dirs.join(", ")}`);