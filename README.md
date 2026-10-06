# SDD Agents

Una suite de ocho agentes que implementa un ciclo **Spec-Driven Development** completo:
`proposal → specs → design → task → apply → verify → archive`.

Cada fase tiene un agente que la posee. El `conductor` enruta, verifica el estado del
repositorio y archiva. Funciona en **Claude Code**, **OpenCode V2** y **Pi**: el prompt se
escribe una vez y se emite para los tres, porque lo único que cambia entre harnesses es el
frontmatter.

- **Instalación** → [INSTALL.md](INSTALL.md), o `bash install.sh --claude`

```bash
bash install.sh --claude        # instalar (también: --opencode, --pi, --all)
bash install.sh --check         # ver qué hay instalado
node build.mjs --check          # ¿dist/ está al día con los prompt.md?
```

---

## El ciclo

| Fase | Agente | Qué produce | Modelo sugerido |
|---|---|---|---|
| `proposal` | `initiative-proposer` | `changes/<id>/proposal.md` | deep / high |
| `specs` | `requirements-analyst` | `changes/<id>/specs.md`, `tests.md`, `traceability.md` | deep / high |
| `design` | `design-analyst` | `changes/<id>/design.md` | deep / high |
| `task` | `task-decomposer` | JSON en `roadmap/`, más `TreeTask.md` | standard / medium |
| `apply` | `worker` | `changes/<id>/apply.md` y el código | standard / high |
| `verify` | `verifier` | `changes/<id>/verify.md` | deep / high |
| `archive` | `conductor` + `documentation-maintainer` | `doc/es/`, `doc/en/`, commit | light / low |

`documentation-maintainer` además trabaja de forma transversal: no solo en el archivo, sino
como agente de documentación del repositorio.

---

## Los agentes

### `conductor`

El director. Es el punto de entrada del ciclo y **no escribe** propuestas, diseños, código ni
informes de verificación: enruta al agente de cada fase y responde del ciclo entero.

En cada sesión, en este orden:

1. **Init**, si el proyecto no tiene `.sdd/`. Crea `AGENTS.md`, `changes/`, `doc/es`,
   `doc/en`, `doc/glossary.md`, `roadmap/` y `scripts/`. **Antes te pregunta para qué harnesses
   es el repo**, y solo crea los entry points de esos: un `CLAUDE.md` caducado de un harness que
   nadie abre es peor que no tener el fichero.
2. **Versión.** Compara la versión del SDD y su layout con lo que espera el agente. Detecta el
   cambio de versión y también el drift silencioso. Si hay migración registrada, te enseña el
   plan en `--dry-run` antes de preguntar.
3. **Modelos.** Recomienda modelo y esfuerzo por subagente, muestra lo guardado en `.sdd/sdd.json`
   contra lo recomendado, y pregunta siempre, incluso si hay elección guardada.
4. **Preflight.** Tres checks: build/test/lint, árbol de git, consistencia del roadmap.
5. **Enrutado.** Lee `TreeTask.md` y clasifica la petición: tarea existente, nueva, bug, o
   consulta.

Ante un fallo de compilación o de tests informa de la causa y ofrece abrir una issue, pero no
arregla nada ahí: un `verify` sobre una base ya rota no produce un informe fiable. Ante cambios
sin commitear pregunta al usuario, nunca limpia por su cuenta.

Nunca migra una versión de SDD sin permiso, nunca commitea sin que se lo pidan, y nunca marca
algo `completed` sin un informe de `verifier` detrás.

### `initiative-proposer` (proposal)

Convierte una idea u oportunidad en 2–3 conceptos materiales y una propuesta revisable.
Mantiene el problema separado de la solución que propone, nunca inventa evidencia, métricas ni
costes, y no baja a requisitos ni criterios de aceptación. Investiga antes de proponer: si la
idea ya está construida o ya descartada en el repositorio, ese es el hallazgo más útil que
puede devolver.

### `requirements-analyst` (specs)

Elicita y desafía requisitos hasta que el usuario confirma comprensión compartida. Produce
requisitos con ids estables (`REQ`, `NFR`, `CON`, `ASM`, `AC`), plan de pruebas y tabla de
trazabilidad requisito→prueba. Diseña el test que detectaría una implementación incorrecta de
cada requisito. Un umbral sin fuente se marca como abierto, nunca se inventa.

### `design-analyst` (design)

Convierte requisitos aprobados en un diseño que se puede implementar sin adivinar: estructura,
datos, interfaces, caminos de fallo explícitos y alternativas descartadas con su porqué. Traza
en ambas direcciones: cada requisito cubierto, cada elemento del diseño con un requisito o una
pregunta abierta detrás.

### `task-decomposer` (task)

Descompone el diseño en slices verticales, cada una un camino completo y verificable por sí
misma. La excepción es el refactor ancho, que se secuencia *expand–migrate–contract* porque
ninguna rebanada puede quedar verde sola. Escribe los documentos JSON del roadmap y valida
contra el schema. Sus dos piezas verificables:

- `schema/roadmap.schema.json` — fuente de verdad del formato (42 tests)
- `schema/check_roadmap.py` — valida el árbol entero y escribe `TreeTask.md`

### `worker` (apply)

Implementa **una** tarea dentro de su alcance. La regla que más caro sale si no se escribe: si
al implementar descubres que otra tarea debe cambiar, es un hallazgo, no permiso para
cambiarla. No commitea, no hace push, no marca nada `completed` (eso lo confirma el verify), y si
la build falla por un bug preexistente lo reporta en vez de arreglarlo de paso.

### `verifier` (verify)

Comprueba el cambio en cinco capas (tests, criterios de aceptación, build y checks estáticos,
comportamiento manual, consistencia con el contrato) y clasifica cada fallo: regresión,
pre-existente, criterio no cumplido, o problema de calidad del test. **No arregla nada**: en
cuanto empieza a arreglar deja de ser el control de esa corrección.

### `documentation-maintainer` (archive)

Documentación del repositorio y, en la fase de archivo, el archivado y la traducción. Verifica
cada afirmación contra el código, propone estructura antes de redactar, y distingue cuatro tipos
de documento (tutorial, how-to, referencia, explicación). Traduce `doc/es` a `doc/en` dejando
código, identificadores y comandos sin traducir.

---

## Cómo se usa

### El Conductor es el agente por defecto

Está pensado como **la puerta de entrada**: se pide a `conductor` y él decide si la petición es
una tarea existente, una feature nueva, un bug, o una consulta que no necesita roadmap.

En **Claude Code** es un subagente: invócalo por su nombre.

```
Usa el agente conductor para añadir filtrado por precio al catálogo
```

En **OpenCode** está definido con `mode: all`, así que aparece tanto como agente seleccionable
de sesión como subagente. Elige `conductor` en la lista de agentes, o dile al agente principal
que lo use.

En **Pi** se instala con `pi-subagents` y se invoca por nombre.

### Los demás agentes también son invocables

No hace falta pasar por el Conductor. Son útiles por separado:

| Quiero… | Invoco |
|---|---|
| Solo desdoblar un diseño en tareas | `task-decomposer` |
| Revisar un README sin tocar nada más | `documentation-maintainer` |
| Revisar una especificación existente | `requirements-analyst` |
| Verificar un cambio ya hecho | `verifier` |
| Investigar una pregunta sobre el proyecto | el subagente explorador del harness |

Lo que pierdes al saltarte el Conductor es la verificación de estado: nadie comprueba que la base
esté verde, que el árbol de git esté limpio, ni que el registro del roadmap sea consistente.

### Qué pasa la primera vez

El Conductor detecta que el proyecto no está inicializado y crea el andamiaje. Se detiene en un
punto: los comandos de verificación. Tienes que rellenar el bloque `Verification` de `AGENTS.md`
con los comandos reales de compilación y test del proyecto, porque `preflight.sh` los ejecuta
literalmente y un comando inventado es peor que uno vacío.

Después, cada sesión corre el check de versión, propone modelos, pasa el preflight, y entra.

---

## Estructura del repositorio

```
.
├── install.sh                # instalador: --claude / --opencode / --pi / --all
├── build.mjs                 # emite las variantes por harness (--check para CI)
├── README.md                 # este fichero
├── INSTALL.md                # instalación detallada
└── agents/
    └── <agent>/
        ├── prompt.md         # prompt canónico, sin frontmatter
        ├── agent.json        # nombre, descripción y config por harness
        ├── schema/  example/ # solo task-decomposer
        ├── scripts/          # solo conductor
        └── dist/
            ├── pi/<name>.md
            ├── claude/<name>.md
            └── opencode/<name>.md
```

`prompt.md` no lleva frontmatter a propósito: es la única fuente del body, y `build.mjs` genera
las tres variantes a partir de ahí. Edita siempre `prompt.md` y `agent.json`, nunca `dist/`.

`build.mjs` y `install.sh` viven en la raíz y esperan `agents/` al lado. Un subdirectorio
`agents/<nombre>/` cuenta como agente si tiene `agent.json`, así que añadir uno es crear su
carpeta y rodar `node build.mjs`; no hay lista que actualizar en ningún sitio.

---

## Decisiones que conviene conocer antes de tocar nada

**`status` y `phase` son ejes ortogonales.** `status` es el estado administrativo (`draft`,
`ready`, `blocked`, `inProgress`, `paused`, `completed`, `canceled`); `phase` es el punto del
ciclo. Se solapan en un nodo concreto pero responden a preguntas distintas. `phase` es opcional
a propósito: un nodo que abarca varias fases no tiene una sola, y adivinar es peor que omitir.

**`decisions` existe para que una autorización quede registrada.** El schema rechaza un nodo
`ready` o en `apply` con preguntas abiertas y sin decisión detrás. Solo el usuario autoriza; el
agente lo registra.

**El versionado del SDD y el del schema son independientes.** `sddVersion` es el layout y el
ciclo; `schemaVersion` dentro de cada documento del roadmap es el schema JSON de ese documento.

**La traducción es un paso del archivo, no un agente.** Lo que falla al traducir no es la
traducción: es la deriva de términos y que `doc/en` se quede atrás. De ahí el glosario como
fuente única y el `i18n-check.sh`, que compara estructura entre los dos idiomas.

---

## Los scripts

Todos en `agents/conductor/scripts/`, y copiados al proyecto en `.sdd/scripts/` al inicializar, para
que el ciclo sea verificable sin este repo presente.

| Script | Para qué |
|---|---|
| `init-sdd.sh` | Crea el andamiaje y `.sdd/`. Pregunta para qué harnesses es el repo y solo enlaza esos entry points. `--for <nombres>` lo hace no interactivo. Idempotente. |
| `preflight.sh` | Lee el bloque `Verification` de `AGENTS.md` y ejecuta build, test, lint, typecheck y format. Distingue fallo de omitido. |
| `git-check.sh` | Estado del árbol de trabajo: staged, modificados y sin seguimiento. |
| `sdd_check.py` | Compara la versión y el layout con lo que espera el agente. Detecta el cambio de versión y el drift silencioso, y verifica solo los entry points elegidos. |
| `migrate_sdd.py` | Aplica la migración registrada, en declarativo desde `versions.json`. `--dry-run` enseña el plan sin tocar nada. |
| `i18n-check.sh` | Comprueba que `doc/es` y `doc/en` están sincronizados y que existe glosario. No juzga calidad de traducción, atrapa deriva de estructura y terminología. |
| `models.py` | Propone modelo y esfuerzo por subagente, mezclando lo guardado en `.sdd/sdd.json` con lo recomendado, con override por fase. `--save` registra la respuesta del usuario validando tier y esfuerzo; `--clear` borra un default guardado. |

Cada uno está probado en ambos sentidos: fallan con el detalle del problema y pasan cuando todo
está en orden.

### Modelos guardados por proyecto

La elección del usuario vive en `.sdd/sdd.json`, en `models`:

```json
"models": {
  "verifier": { "tier": "light", "effort": "low" },
  "documentation-maintainer": {
    "tier": "standard", "effort": "medium",
    "byPhase": { "archive": { "tier": "light", "effort": "low" } }
  }
}
```

Se guarda **tier y esfuerzo, nunca el id concreto del modelo**: el tier es neutral respecto al
harness y `models.json` lo traduce. Cambiar de modelo no toca ningún proyecto.

`--save` valida contra `models.json` y no guarda nada si el tier o el esfuerzo no existen, porque
un error de tipeo escrito en el JSON dejaría un agente clavado en el modelo equivocado para
siempre. Un default nuevo no borra las respuestas por fase, que son decisiones aparte; para
quitarlas está `--clear`.

### Versionado del SDD

`.sdd/sdd.json` registra qué versión del SDD tocó el proyecto, qué layout declaró y qué harnesses
eligió. Va bajo `.sdd/`, que el init añade al `.gitignore`. `versions.json` en el agente dice cuál entiende él.

Lo útil de que cada versión declare su layout es que `sdd_check.py` detecta el caso que un
número solo no ve: alguien renombra `changes/` a `work/` sin subir la versión, las claves siguen
diciendo `changes`, y el drift aparece igual.

Cuando hay desajuste, el check dice si existe una migración registrada. El Conductor te enseña el
plan en `--dry-run` y no aplica nada hasta que lo apruebas.

Dos versiones que no hay que confundir: `sddVersion` es el layout y el ciclo;
`schemaVersion` dentro de cada documento del roadmap es el schema JSON de ese documento y avanza
por separado.

---

## Desarrollo de la propia suite

```bash
node build.mjs             # regenera dist/
node build.mjs --check     # falla si dist/ está desactualizado

# schema y checker del roadmap
python3 agents/task-decomposer/schema/test_schema.py
python3 agents/task-decomposer/schema/check_roadmap.py \
  agents/task-decomposer/example/roadmap \
  agents/task-decomposer/schema/roadmap.schema.json
```

`build.mjs --check` está pensado para CI: sale con 1 si algún `dist/` no coincide con su
`prompt.md`, así que un `prompt.md` editado sin regenerar no llega a commitearse.