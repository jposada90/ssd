# Instalación

Ejecuta todo esto **desde la raíz del repo**, donde están `install.sh`, `build.mjs` y `agents/`.

## Lo mínimo

```bash
bash install.sh --claude
```

Instala los ocho agentes para **Claude Code** a nivel de usuario, más el suite de scripts, y
avisa si falta la skill opcional. Reinicia Claude Code y ya está.

## Elegir harness y ámbito

| Flag | Efecto |
|---|---|
| `--claude` / `--opencode` / `--pi` | Para qué harness(es). Repetible. |
| `--all` | Los tres. |
| `--global` | A nivel de usuario (por defecto). Los agentes sirven en cualquier proyecto. |
| `--project` | Solo en el proyecto actual, y se versiona con el repo. |
| `--skills` / `--no-skills` | Enlazar las skills opcionales (por defecto: sí). |
| `--force` | Sobrescribir ficheros que ya existen. |
| `--check` | Informe del estado. No cambia nada. |
| `--uninstall` | Quita lo que instaló este script. |
| `--source <dir>` | Dónde está el repo, si no es el directorio del propio script. |

## Dónde acaba cada cosa

Con `--global`:

```
~/.claude/agents/*.md              # 8 agentes, planos
~/.config/opencode/agents/*.md     # 8 agentes, planos
~/.pi/agent/agents/*.md            # 8 agentes, planos

~/.config/sdd-agents/suite/        # el suite: una copia, compartida por los tres
  conductor/{prompt.md,versions.json,models.json,scripts/}
  task-decomposer/schema/
~/.config/sdd-agents/root          # puntero al suite, para que el Conductor lo encuentre
```

El instalador no toca nada dentro de un proyecto. Eso lo hace el Conductor en su primer uso en
cada repo, y crea allí:

```
<proyecto>/
├── AGENTS.md
├── .sdd.json                 # versión del SDD, layout, harnesses elegidos, modelos
├── changes/  doc/es  doc/en  doc/glossary.md  roadmap/  scripts/
└── CLAUDE.md, GEMINI.md...   # solo los entry points de los harnesses que elijas
```

`.sdd.json` es oculto a propósito: es configuración de la suite, no documentación del proyecto,
y así no se confunde con `AGENTS.md` ni aparece en un `ls` de un vistazo. Va versionado con el
repo, porque registra decisiones que el equipo debe compartir.

Los ficheros de agente van **planos** a propósito: en OpenCode, un anidamiento se convierte en
parte del id (`agents/team/x.md` → `team/x`), y eso rompería las referencias entre agentes.

El suite va **una sola vez por ámbito**, no uno por harness: es neutral respecto al harness
salvo las variantes generadas.

Con `--project`, todo baja un nivel:

```
.claude/agents/*.md
.sdd/agents/                        # el suite
```

## Instalación desde código remoto

El script espera el repo en su propio directorio, así que basta con clonar y ejecutar:

```bash
git clone <url-del-repo> sdd-agents
bash sdd-agents/install.sh --claude
```

O sin dejar el repo en sitio permanente:

```bash
git clone --depth 1 <url> /tmp/sdd && bash /tmp/sdd/install.sh --all
```

El instalador **no** hace clone de nada: espera que el repo ya esté en disco. Así se puede
instalar desde un checkout, un tarball o una copia local, y no hay red en el camino crítico.

## Requisitos

- **node**, para renderizar las variantes. Sin él el instalador se detiene: los ficheros de
  `dist/` ya vienen generados y versionados, pero `--check` los regenera.
- **python3** con `jsonschema`, para el roadmap: `pip install jsonschema`.
- **git**, para `git-check.sh` y para que el Conductor ubique la raíz del proyecto.

## Skills

Solo `documentation-maintainer` usa una skill: `writing-for-agents`, para documentos que leen
agentes (`AGENTS.md`, `CLAUDE.md`, skills). Si está en `~/.agents/skills/`, el instalador la
enlaza al directorio de skills de cada harness, de forma que una actualización llega a los tres.

Si no está, el resto de las reglas del agente ya están en su prompt y degrada sin ella. Para
instalarla:

```bash
npx skills add mattpocock/skills --skill writing-for-agents --global --yes
```

## Verificar

```bash
bash install.sh --check              # los tres harness
bash install.sh --check --claude     # solo Claude Code
```

Informa de los agentes por harness, si el suite está presente y si el puntero apunta a él.
Salida `CHECK OK` significa que las tres piezas están. Sin flag de harness comprueba los tres, así
que si solo instalaste uno verás `CHECK INCOMPLETE`: pásale `--claude` (o el que sea) para
comprobar solo ese.

Comprobaciones adicionales del propio suite:

```bash
node build.mjs --check
python3 agents/task-decomposer/schema/test_schema.py
python3 agents/task-decomposer/schema/check_roadmap.py \
  agents/task-decomposer/example/roadmap agents/task-decomposer/schema/roadmap.schema.json
```

## Desinstalar

```bash
bash install.sh --claude --uninstall
```

Quita los ocho ficheros de agente de ese harness. El suite es compartido por los tres harnesses
del ámbito, así que **sobrevive mientras quede alguno instalado**: si borras solo Claude Code,
OpenCode y Pi siguen teniendo sus agentes con el suite intacto. El suite y el puntero se van
cuando se desinstala el último.

Los ficheros que no instaló este script se respetan.

Con `--project`, borra lo del proyecto. **No toca** una instalación global: los ámbitos son
independientes.

## Después de instalar, en el proyecto

El Conductor no crea el andamiaje en la instalación, sino en el primer uso de un proyecto,
porque el layout depende de la versión del SDD. Arráncalo diciendo:

```
Usa el agente conductor
```

Te va a preguntar dos cosas que no puede adivinar: **para qué harnesses es el repo** (y con esa
respuesta crea solo los entry points que correspondan) y los **comandos de verificación** del
proyecto, que van en el bloque `Verification` de `AGENTS.md`.

Si prefieres hacerlo a mano:

```bash
bash scripts/init-sdd.sh                    # pregunta los harnesses, si hay terminal
bash scripts/init-sdd.sh --for claude      # o decides tú
bash scripts/init-sdd.sh --for none        # solo AGENTS.md, sin links
```

## Problemas frecuentes

**Los agentes no aparecen.** El harness descubre ficheros de agente al arrancar. Reinicia. Si
la carpeta de agentes no existía antes de la sesión, hace falta reinicio sí o sí.

**Un agente no arranca en Claude Code.** Suele ser un fichero con frontmatter de Pi o con
nombres de herramienta en minúsculas: `tools: read, grep` no resuelve a ninguna herramienta y
Claude Code se niega a lanzarlo. Los ficheros de `dist/claude/` llevan los nombres correctos.

**OpenCode no encuentra el Conductor.** Comprueba que el fichero está plano en
`~/.config/opencode/agents/`, no en un subdirectorio, y recarga OpenCode.

**`SDD VERSION MISMATCH` en la primera sesión.** El proyecto ya existe y su `.sdd.json` no lo
tocó esta versión del agente. El script dice si hay migración registrada y qué claves esperan
otros valores. Para ver el plan sin tocar nada:

```bash
python3 scripts/migrate_sdd.py <ruta al agente conductor> --dry-run
```

Y para aplicarla, solo cuando el usuario lo diga. El Conductor nunca migra por su cuenta.

**Falta `CLAUDE.md` u otro entry point y el check falla.** `.sdd.json` los registra como
elegidos, así que o faltan en disco o son symlinks rotos. Si el proyecto ya no usa ese harness,
bórralo de la lista `links` en `.sdd.json` en vez de crear el fichero. Para añadirlos después:

```bash
bash scripts/init-sdd.sh --for claude,copilot
```

**El check dice que los harnesses "no están decididos".** `.sdd.json` tiene `links` a `null`,
que es distinto de una lista vacía: la lista vacía es "no quiero ninguno", y `null` es "nadie lo
ha decidido". Pásale `--for` con los nombres.

**`PREFLIGHT FAILED` con todo en verde.** El bloque `Verification` de `AGENTS.md` tiene un
comando que devuelve distinto de cero, normalmente por estar vacío o por apuntar a algo que no
existe en ese proyecto. El script distingue omitido de fallido en su resumen.