# Tasks

## 1. Seguridad del pipeline y secretos

- [ ] 1.1 Mover `GITHUB_TOKEN` a `withCredentials(string)` + `maskPasswords` en el stage push y verificar que `grep -r GITHUB_TOKEN Jenkinsfile` no aparece en `environment`
- [ ] 1.2 Eliminar token de args CLI en `.bat`/`.sh` y helper Python, agregar rechazo de patrones `ghp_|github_pat_` y verificar con invocación que contiene token falso que falla exit != 0
- [ ] 1.3 Agregar validación estricta de URLs + extractor reescrito con regex y errores a `stderr`, verificar con `pytest -q` (≥6 casos) en verde
- [ ] 1.4 Reemplazar `push --force` por push normal + PR idempotente (`GET` abierto antes de `POST`, `--fail-with-body`, chequeo de `message/errors`) y verificar con mock de API 422/401 que el stage falla

## 2. Trazabilidad

- [ ] 2.1 Generar `sync-metadata.json` con 7 campos (sha, ramas, build_tag, build_url, timestamp UTC) y verificar que `python -m json.tool` lo parsea y ningún campo está vacío
- [ ] 2.2 Inyectar SHA/BUILD_TAG/BUILD_URL en PR title/body y verificar que el body renderizado contiene las 3 cadenas
- [ ] 2.3 Mover `pullrequest_response.json` al workspace + `archiveArtifacts` y verificar que `git status --porcelain` del clon no lo lista

## 3. Versionado

- [ ] 3.1 Cambiar mensaje a `sync(codecommit): <short7> <ts-utc>` + body con SHA completo/build y verificar con `git log -1 --pretty=%s` que cumple regex
- [ ] 3.2 Crear tags `sync-vYYYY.MM.DD-N` + entrada al inicio de `CHANGELOG.md` y verificar segundo sync del día genera `-N+1`

## 4. Portabilidad y buenas prácticas

- [ ] 4.1 Agregar `parameters` (7 params) + `options` (timestamps, timeout 30m, buildDiscarder 30, disableConcurrentBuilds, ansiColor) + `agent label` parametrizable y verificar con `yamllint`/parseo Groovy básico sin error
- [ ] 4.2 Crear espejos `sh/copy-content.sh` y `sh/push-and-pr.sh` (`set -euo pipefail`, quoting, `isUnix()` en Jenkinsfile) y verificar sync con ruta con espacios en Linux sale 0
- [ ] 4.3 Endurecer `.bat` (`setlocal`, `"%~1"`, mapeo robocopy `LEQ 7` → 0) y verificar `cmd /c` help o revisión lint sin regresión
- [ ] 4.4 `openspec validate` en verde y `git diff --stat` revisado antes de cada PR de requisito
