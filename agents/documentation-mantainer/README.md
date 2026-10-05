# Documentation Maintainer

Agente global de Pi para crear, actualizar y revisar `README.md`, `AGENTS.md` y otros documentos del repositorio.

## Dependencias

| Dependencia | Tipo | Instalación |
|---|---|---|
| pi-subagents | Extensión Pi, necesaria para cargar agentes personalizados | `pi install npm:pi-subagents` |
| writing-for-agents | Skill pública de Matt Pocock para `AGENTS.md` y documentos consumidos por agentes | `npx skills add mattpocock/skills --skill writing-for-agents --global --agent pi --yes` |
| documentation-writer | Skill de GitHub Awesome Copilot para documentación técnica | `npx skills add github/awesome-copilot --skill documentation-writer --global --agent pi --yes` |
| cognitive-doc-design | Skill local para legibilidad y revisión | Copia la carpeta de skill a `~/.pi/agent/skills/cognitive-doc-design/`; instrucciones abajo |

## Instalación

Desde la raíz de este repositorio, ejecuta en la máquina destino:

```bash
pi install npm:pi-subagents
npx skills add mattpocock/skills --skill writing-for-agents --global --agent pi --yes
npx skills add github/awesome-copilot --skill documentation-writer --global --agent pi --yes
mkdir -p ~/.pi/agent/agents
cp documentation-maintainer/documentation-maintainer.md ~/.pi/agent/agents/
```

Instala `cognitive-doc-design` para que el subagente pueda precargarla. Si ya está en `~/.agents/skills/cognitive-doc-design`, crea el enlace para Pi:

```bash
mkdir -p "$HOME/.pi/agent/skills"
if [ ! -e "$HOME/.pi/agent/skills/cognitive-doc-design" ] && [ ! -L "$HOME/.pi/agent/skills/cognitive-doc-design" ]; then
  ln -s "$HOME/.agents/skills/cognitive-doc-design" "$HOME/.pi/agent/skills/cognitive-doc-design"
fi
```

Si la skill no existe en esa máquina, copia la carpeta completa `cognitive-doc-design` desde una fuente de confianza a `~/.pi/agent/skills/cognitive-doc-design/`. Esta skill local no se incluye en este paquete ni tiene aquí una fuente pública verificada.

Si Pi ya tiene alguna dependencia, omite su comando de instalación. Después de instalar, ejecuta `/reload` o reinicia Pi.

## Uso

Pide a Pi que use `documentation-maintainer` para actualizar la documentación solicitada. Antes de redactar documentación sustancial, propone audiencia, alcance y estructura; verifica los comandos y afirmaciones contra el repositorio.

## Archivos

- `documentation-maintainer.md`: definición Pi del subagente.