# pipeline-security Specification

## Purpose
Garantiza que el pipeline sincronice CodeCommit a GitHub sin exponer secretos, sin sobrescribir historial y sin crear Pull Requests duplicados o silenciosamente fallidos.

## Requirements

### Requirement: Token nunca viaja como argumento ni aparece en logs

El pipeline SHALL inyectar `GITHUB_TOKEN` exclusivamente vía `withCredentials` (binding `string`) dentro del stage que lo usa, y SHALL activar enmascarado de secretos en logs. Ningún script SHALL aceptar el token como parámetro CLI.

#### Scenario: Token enmascarado en ejecución

- **WHEN** el stage "Push updated GitHub repository" se ejecuta con un token `ghp_FAKE123`
- **THEN** el log de Jenkins muestra `****` en lugar del valor y `ps`/línea de comandos no contiene el token

#### Scenario: Script rechaza token por argumento

- **WHEN** se invoca `PushAndPullRequestToGitHubRemoteRepository` (bat o sh) con un argumento que parece token
- **THEN** el script falla con exit code distinto de cero y mensaje "token MUST NOT be passed as argument"

### Requirement: Validación de URLs de entrada

El pipeline y el helper Python SHALL validar que `CodeCommitRepositoryURL` y `GitHubRepositoryURL` tengan formato HTTPS o SSH válido antes de cualquier `git`/`curl`, y SHALL abortar con mensaje claro si no lo tienen.

#### Scenario: URL inválida aborta temprano

- **WHEN** `GitHubRepositoryURL` es `not-a-url`
- **THEN** el pipeline falla en validación sin clonar ni llamar a la API

#### Scenario: Extractor rechaza error como nombre

- **WHEN** `ExtractGitHubRepositoryName.py` recibe una URL inválida o vacía
- **THEN** sale con exit code `1` en `stderr` y nunca imprime un `owner/repo` inventado en `stdout`

### Requirement: Push sin force y Pull Request idempotente

El pipeline SHALL publicar con `git push` normal (nunca `--force`) y SHALL reutilizar el PR abierto existente entre las mismas ramas en lugar de duplicarlo. La llamada a la API SHALL verificar el HTTP status y el campo `message`/`errors` de la respuesta y SHALL fallar el build si la creación/búsqueda del PR no tuvo éxito.

#### Scenario: Sync repetido no duplica PR

- **WHEN** ya existe un PR abierto de `sync-codecommit` hacia `main` y se re-ejecuta el sync sin cambios nuevos
- **THEN** no se crea un segundo PR y el build reporta la URL del PR existente

#### Scenario: Error API falla el build

- **WHEN** la API responde `422` o `401`
- **THEN** el stage falla con el mensaje de la API visible (sin el token) y `pullrequest_response.json` queda como artefacto, nunca commiteado
