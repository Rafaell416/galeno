# Galeno

App nativa de Mac que, con un wizard, crea y configura un agente en Claude Code para
Product Managers: conecta sus herramientas y escribe la configuración con los guardrails
ya puestos.

**Estado:** estructura y documentación. Todavía no hay código.

## Estructura

| Carpeta | Qué es | Fase |
|---|---|---|
| `GalenoApp/` | App Mac en Swift/SwiftUI: el wizard | 4 |
| `GalenoCore/` | Swift Package: el motor que genera la config | 2 |
| `whatsapp-bridge/` | Binario Go: puente de WhatsApp + MCP de solo lectura | 3 |
| `skills/` | Skills del perfil PM y catálogo curado | 5 |
| `site/` | Sitio web | 9 |
| `docs/` | Plan de producto, perfil de PM, especificación y design system | — |
| `.github/workflows/` | CI | — |

## Por dónde empezar

- [HANDOFF.md](HANDOFF.md) — resumen ejecutivo: decisiones cerradas, arquitectura, reglas.
- [AGENTS.md](AGENTS.md) — guía de trabajo en este repo.
- [docs/03-especificacion-v0.0.1.md](docs/03-especificacion-v0.0.1.md) — la fuente de verdad del alcance.

## Reglas

1. Nunca se commitean tokens ni credenciales.
2. El bridge de WhatsApp es de solo lectura: no tiene herramientas de envío.
3. Todo cambio va por rama + PR.
