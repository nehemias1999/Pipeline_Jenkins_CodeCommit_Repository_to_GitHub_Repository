# Design

## Context

Estado actual: `Jenkinsfile` declarativo sin `parameters`/`options`, token vía `credentials()` en `environment` y pasado como arg al `.bat` (fuga en `ps`/logs); `push --force` + `curl` sin chequeo de status; commit con `%DATE% %TIME%`; `pullrequest_response.json` dentro del clon; solo `.bat` Windows. Restricción: agente `SERVER_1` Windows hoy, pero el usuario aprobó espejo POSIX y `isUnix()`. Ver `proposal.md` para motivación.

## Goals / Non-Goals

**Goals:**

- Token solo como env enmascarada del stage; scripts sin parámetro token.
- Push normal + PR idempotente con fallo explícito ante `4xx/5xx`.
- Trazabilidad archivada (`sync-metadata.json`, respuesta PR) y PR body con SHA/BUILD_URL.
- Versionado determinista (commit `sync(codecommit): …`, tag `sync-v…`, `CHANGELOG.md`).
- Paridad `bat`/`sh` con verificación local (`pytest`, `yamllint`).

**Non-Goals:**

- No migrar a GitHub Actions ni a Jenkins Shared Library; no provisionar Jenkins (JCasC) en este cambio.
- No rotar secretos existentes ni implementar GitHub App/OIDC (ruta futura documentada).
- No reescribir `robocopy` a `rsync` byte-a-byte; el espejo `sh` usa `rsync` con mismas exclusiones.

## Decisions

1. **`withCredentials([string(credentialsId: 'GITHUB_TOKEN', variable: 'GH_TOKEN')])` dentro del stage + `maskPasswords`** sobre guardar en `environment`.
   - Alternativa descartada: `environment { GH = credentials() }` — expone en todos los stages y facilita interpolación accidental en `echo`.
2. **Token vía `stdin`/env al `curl`, nunca CLI**: el `.bat`/`sh` lee `GH_TOKEN` del entorno; si detecta arg con prefijo `ghp_|github_pat_` falla.
   - Alternativa: fichero temporal — más I/O y limpieza; env enmascarada es idiomático Jenkins.
3. **PR idempotente con `GET /pulls?head=…&base=…&state=open` previo al `POST`** usando `curl --fail-with-body` + `jq`/PowerShell `ConvertFrom-Json`.
   - Alternativa: siempre `POST` y tolerar `422` — genera ruido y carreras.
4. **SHA origen como fuente de verdad**: `git rev-parse HEAD` del clon CodeCommit post-fetch; timestamp UTC via `powershell (Get-Date -Format o)` / `date -u +%FT%TZ`; commit `sync(codecommit): <short7> <ts>`.
   - Alternativa: `%DATE%` — locale-dependiente, no ordenable.
5. **Espejo `sh/` + `isUnix()`** en vez de un solo script Python políglota.
   - Alternativa: reescribir todo en Python — mayor diff, pierde `robocopy` nativo en Windows que el equipo ya opera.
6. **Extractor estricto**: regex `^(https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(\.git)?/?$`, error a `stderr`, exit `1`, sin prefijo `;` mágico (se mantiene compat de `;` solo como fallback parseado en Jenkins, no en el script).
   - Alternativa: mantener prefijo `;` — acopla Jenkins al formato de debug.

## Risks / Trade-offs

- [Risk] `maskPasswords` no cubre `ps` si el token va en CLI → Mitigación: prohibición contractual + chequeo en script.
- [Risk] `GET pulls` con paginación/rate-limit → Mitigación: `--fail-with-body`, retry 3x con backoff solo en `5xx`/red.
- [Risk] `rsync` vs `robocopy /MIR` difieren en ACLs/extended attrs → Mitigación: documentado; exclusiones idénticas, contenido versionado idéntico.
- [Risk] Tags concurrentes mismo día (`-N` race) → Mitigación: `disableConcurrentBuilds()` + cálculo `git tag -l` justo antes de crear.
- [Risk] Agentes sin `jq`/PowerShell 5 → Mitigación: fallback a `python -c json` que ya es prerrequisito.

## Migration Plan

1. Merge por requisito con PRs pequeños (security → traceability → versioning → portability).
2. En Jenkins: cambiar `GITHUB_TOKEN` a tipo Secret Text si es username/password; agregar parámetros (con defaults = valores actuales); probar con `Force Pipeline Run`.
3. Rollback: revert del PR del requisito; el formato viejo de commit/PR sigue siendo legible por GitHub.

## Open Questions

- Ninguna que cambie specs o tareas; pendiente futuro: GitHub App vs PAT de larga vida.
