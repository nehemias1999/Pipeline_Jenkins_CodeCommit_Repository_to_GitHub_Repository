# pipeline-portability Specification

## Purpose
Convierte el pipeline en portable Windows/Linux con parámetros declarados, opciones de robustez y scripts espejo testeables localmente con pytest y yamllint.

## Requirements

### Requirement: Parámetros y opciones declarativas del pipeline

El `Jenkinsfile` SHALL declarar bloque `parameters` (7 parámetros actuales tipados) y bloque `options` con `timestamps()`, `timeout(time: 30, unit: 'MINUTES')`, `buildDiscarder(logRotator(numToKeepStr: '30'))`, `disableConcurrentBuilds()` y `ansiColor('xterm')`. El `agent label` SHALL ser parametrizable con default `SERVER_1`.

#### Scenario: Build con defaults y timeout activo

- **WHEN** se lanza el job sin parámetros y tarda más de 30 minutos
- **THEN** Jenkins lo aborta por timeout y conserva máximo 30 builds con timestamps en el log

### Requirement: Scripts espejo POSIX con manejo robusto de errores

Cada `.bat` SHALL tener un espejo `sh/*.sh` POSIX con el mismo contrato CLI (menos el token), `set -euo pipefail`, quoting de rutas con espacios y códigos de salida compatibles (robocopy `≤7` mapeado a `0` solo en el `.bat`). El `Jenkinsfile` SHALL elegir `bat` o `sh` según `isUnix()`.

#### Scenario: Mismo sync en Linux

- **WHEN** el pipeline corre en un agente Linux con rutas que contienen espacios
- **THEN** el sync completa con exit `0` y el contenido destino es idéntico al origen (excluyendo `.git`, `.github`, `.cursor`)

### Requirement: Verificación local con tests y lint

El repo SHALL incluir suite `pytest` para `ExtractGitHubRepositoryName.py` (HTTPS, SSH, `.git`, inválidas) y SHALL pasar `yamllint`/`groovy` básico del `Jenkinsfile` sin instalar Jenkins. `openspec validate` SHALL pasar.

#### Scenario: Dev valida sin Jenkins

- **WHEN** un dev ejecuta `pytest -q` y `yamllint`/`python -m py_compile`
- **THEN** ambos comandos salen `0` y cubren al menos 6 casos del extractor
