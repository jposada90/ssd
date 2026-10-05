# Initiative Proposer

Agente global de Pi para generar y comparar conceptos de features o proyectos y desarrollar una propuesta breve. La propuesta queda separada de los requisitos y de la implementación.

## Dependencias

| Dependencia | Tipo | Instalación |
|---|---|---|
| pi-subagents | Extensión Pi, necesaria para cargar agentes personalizados y permitir el traspaso limitado | `pi install npm:pi-subagents` |
| grilling | Skill pública de Matt Pocock, para explorar y cuestionar decisiones | `npx skills add mattpocock/skills --skill grilling --global --agent pi --yes` |
| cognitive-doc-design | Skill local para presentar propuestas con claridad | Copia la carpeta de skill a `~/.pi/agent/skills/cognitive-doc-design/`; instrucciones abajo |
| requirements-analyst | Agente incluido en `../requirements-analyst/`; opcional, necesario solo si quieres pedirle el traspaso a requisitos | Instálalo siguiendo `../requirements-analyst/README.md` |

## Instalación

Desde la raíz de este repositorio, ejecuta en la máquina destino:

```bash
pi install npm:pi-subagents
npx skills add mattpocock/skills --skill grilling --global --agent pi --yes
mkdir -p ~/.pi/agent/agents
cp initiative-proposer/initiative-proposer.md ~/.pi/agent/agents/
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

Pide a Pi que use `initiative-proposer` para generar 2–3 conceptos desde un tema o desarrollar una idea existente. El traspaso a `requirements-analyst` no es automático: solicítalo explícitamente y asegúrate de que ese agente también esté instalado.

## Archivos

- `initiative-proposer.md`: definición Pi del subagente.