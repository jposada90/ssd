# Requirements Analyst

Agente global de Pi para explorar propuestas de producto o diseños técnicos y convertirlos, tras discutirlos, en requisitos claros y verificables.

## Dependencias

| Dependencia | Tipo | Instalación |
|---|---|---|
| pi-subagents | Extensión Pi, necesaria para cargar agentes personalizados | `pi install npm:pi-subagents` |
| grilling | Skill pública de Matt Pocock, para la entrevista y el análisis de decisiones | `npx skills add mattpocock/skills --skill grilling --global --agent pi --yes` |
| cognitive-doc-design | Skill local para producir documentos fáciles de revisar | Copia la carpeta de skill a `~/.pi/agent/skills/cognitive-doc-design/`; instrucciones abajo |

## Instalación

Desde la raíz de este repositorio, ejecuta en la máquina destino:

```bash
pi install npm:pi-subagents
npx skills add mattpocock/skills --skill grilling --global --agent pi --yes
mkdir -p ~/.pi/agent/agents
cp requirements-analyst/requirements-analyst.md ~/.pi/agent/agents/
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

Pide a Pi que use `requirements-analyst` para aclarar una propuesta, revisar una especificación existente o preparar un PRD/especificación técnica. El agente separa requisitos confirmados, hipótesis y preguntas abiertas; no implementa código.

## Archivos

- `requirements-analyst.md`: definición Pi del subagente.