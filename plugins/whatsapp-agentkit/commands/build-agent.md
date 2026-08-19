---
description: Build a WhatsApp AI agent for the user's business, step by step (interview → code → local test → deploy)
---

Usa el skill `whatsapp-agentkit` (lee `SKILL.md` y, cuando corresponda, `reference.md`
para el detalle completo de cada fase) y ejecuta el flujo de onboarding de AgentKit
siguiendo las 5 fases EN ORDEN, sin saltarte ninguna:

1. **Bienvenida y verificación del entorno** — Python 3.11+, carpetas, dependencias, `.env`.
2. **Entrevista del negocio** — 10 preguntas, una por una, esperando respuesta antes de
   seguir. La pregunta 9 es el proveedor de WhatsApp (Zernio o Meta Cloud API) y la 10
   pide las credenciales específicas de ese proveedor.
3. **Generación del agente** — genera `agent/`, `config/`, `tests/`, `Dockerfile`,
   `docker-compose.yml` y `.env` con las respuestas de la entrevista. Genera SOLO el
   adaptador del proveedor elegido.
4. **Testing local** — corre `tests/test_local.py` y no avances sin la aprobación del usuario.
5. **Deploy a Railway** — solo si el usuario lo confirma.

Reglas: habla siempre en español, una pregunta a la vez, nunca hardcodees API keys, no
avances de fase sin confirmación del usuario, y no cambies el modelo de Claude por tu
cuenta para ahorrar costo.
