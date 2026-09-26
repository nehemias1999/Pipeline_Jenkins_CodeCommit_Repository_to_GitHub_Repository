# pipeline-traceability Specification

## Purpose
Hace cada sincronización auditable de extremo a extremo registrando el SHA origen de CodeCommit, los metadatos del build Jenkins y la respuesta del PR en artefactos archivados.

## Requirements

### Requirement: Metadatos de sync registrados y archivados

Cada ejecución que sincroniza SHALL generar `sync-metadata.json` con `codecommit_sha`, `codecommit_branch`, `github_base`, `github_head`, `jenkins_build_tag`, `jenkins_build_url` y `timestamp_utc` (ISO-8601), y SHALL archivarlo con `archiveArtifacts`.

#### Scenario: Metadata completa tras sync

- **WHEN** el sync copia contenido y hace push con CodeCommit SHA `abc1234`
- **THEN** `sync-metadata.json` existe con los 7 campos no vacíos y queda archivado en el build

### Requirement: Cuerpo del PR con trazabilidad

El PR creado o reutilizado SHALL incluir en su body el SHA de CodeCommit, el `BUILD_TAG`, el `BUILD_URL` y el timestamp UTC, de modo que cualquier revisor pueda rastrear el origen sin entrar a Jenkins.

#### Scenario: Revisor rastrea origen desde el PR

- **WHEN** un revisor abre el PR generado por el sync
- **THEN** el body contiene `CodeCommit SHA`, `Jenkins Build` (URL clicable) y `Timestamp UTC`

### Requirement: Respuesta de la API nunca contamina el repo

El archivo `pullrequest_response.json` SHALL escribirse en el workspace (no dentro del clon Git) y SHALL archivarse; nunca SHALL ser commiteado ni pusheado al destino.

#### Scenario: Workspace limpio tras push

- **WHEN** el stage de push termina con éxito
- **THEN** `git status --porcelain` del clon GitHub no lista `pullrequest_response.json` ni `sync-metadata.json` como cambios a commitear
