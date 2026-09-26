# Proposal

## Why

El pipeline actual sincroniza CodeCommit a GitHub pero expone el `GITHUB_TOKEN` como argumento plano, usa `push --force` sin idempotencia, no registra trazabilidad (SHA origen, build) ni versionado, y solo corre en Windows. Endurecerlo ahora evita fugas de secretos, PRs duplicados y syncs no auditables.

## What Changes

- **Seguridad**: `GITHUB_TOKEN` solo vía `withCredentials` + `maskPasswords`; ningún secreto en args/logs/`ps`; validación de URLs; `push` sin `--force`; manejo de errores API con fallo explícito; `pullrequest_response.json` fuera del repo (stash/archivo, no commit).
- **Trazabilidad**: cada sync registra CodeCommit SHA, Jenkins `BUILD_TAG`/`BUILD_URL`, timestamp UTC ISO-8601; PR body estructurado; artefactos archivados (`sync-metadata.json`, respuesta PR).
- **Versionado**: commits formato `sync(codecommit): <short-sha> <timestamp>` + tags `sync-vYYYY.MM.DD-N`; `CHANGELOG.md` acumulativo por sync.
- **Portabilidad y buenas prácticas**: bloque `parameters` + `options` (timestamps, timeout, buildDiscarder, disableConcurrentBuilds, ansiColor); espejo `sh/` POSIX de cada `.bat`; quoting `"%~1"`/`"$1"`; `setlocal`/`set -euo pipefail`; validación local con `pytest` + `yamllint`.
- **BREAKING**: se elimina `push --force`; se eliminan credenciales hardcodeadas (`github_username`, `github_email@gmail.com`) — pasan a parámetros/credenciales; el token deja de aceptarse como argumento CLI de los scripts.

## Capabilities

### New Capabilities

- `pipeline-security`: manejo seguro de secretos, validación de entradas, push sin force, PR idempotente con verificación de errores.
- `pipeline-traceability`: registro y archivo de SHA origen, metadatos de build y respuesta de PR en cada sincronización.
- `pipeline-versioning`: mensajes de commit trazables, tags de sync y changelog acumulativo.
- `pipeline-portability`: pipeline portable Win/Linux con parámetros, opciones y scripts espejo testeables localmente.

### Modified Capabilities

<!-- Sin specs previas que modificar. -->

## Impact

- Afectados: `Jenkinsfile`, `bat/*.bat`, `py/ExtractGitHubRepositoryName.py` (+ nuevos `sh/*.sh`, `tests/`, `CHANGELOG.md`).
- Sistemas: agentes Jenkins Windows y Linux (`SERVER_1` pasa a label parametrizable); credenciales `CODECOMMIT_CREDENTIALS`, `GITHUB_CREDENTIALS`, `GITHUB_TOKEN` (PAT con scope `repo`); API `api.github.com/repos/{owner}/{repo}/pulls`.
- Dependencias nuevas solo para verificación local: `pytest`, `pyyaml`, `yamllint`.
