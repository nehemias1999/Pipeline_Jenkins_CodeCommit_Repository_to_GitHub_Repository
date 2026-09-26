# Pipeline Jenkins CodeCommit Repository to GitHub Repository

Sincronización automática y auditable de un repositorio AWS CodeCommit hacia GitHub, con secretos enmascarados, trazabilidad por SHA, versionado determinista y soporte Windows + Linux.

## Table of Contents

- [Background](#background)
- [Install](#install)
- [Usage](#usage)
- [API / Configuration](#api--configuration)
- [Contributing](#contributing)
- [License](#license)

## Background

### Contexto

El pipeline detecta cambios en la rama monitoreada de CodeCommit, los copia al clon de GitHub, los publica en una rama temporal y abre (o reutiliza) un Pull Request hacia la rama destino. Está endurecido tras el change `hardening-cicd` (ver `openspec/changes/archive/hardening-cicd/` como fuente de verdad de requirements): el token nunca viaja en argumentos ni logs, el push nunca usa `--force`, cada sync deja metadatos archivados y cada commit sigue un formato trazable.

### Tecnologías

- **Jenkins** (declarative pipeline, Groovy): orquestación.
- **Batch (.bat) + POSIX shell (sh/)**: operaciones Git y copia de archivos (`robocopy` en Windows, `rsync` en Linux).
- **Python 3.9+**: `ExtractGitHubRepositoryName.py`, `generate_sync_metadata.py`, `format_sync_message.py`, `next_sync_tag.py`.
- **Git + GitHub REST API** (`POST/GET /repos/{owner}/{repo}/pulls`): publicación y PR idempotente.
- **AWS CodeCommit** (origen) y **GitHub** (destino).

### Arquitectura / Flujo

```text
CodeCommit (origen) --> Checking Changes --> Clone CodeCommit --> Clone GitHub
      --> Copy content (robocopy/rsync, con exclusiones)
      --> Commit sync(codecommit): <sha> --> push (sin --force)
      --> PR idempotente --> artefactos archivados
```

1. **Checking Changes**: clona el repo CodeCommit si no existe, hace `fetch` y compara la rama local con la remota. Sin cambios y sin forzado, el build termina `NOT_BUILT`.
2. **Clone CodeCommit / Clone GitHub**: clones frescos en `<LocalFolder>/CodeCommit` y `<LocalFolder>/GitHub`.
3. **Copy content**: `bat/CopyContentToLocalRepository.bat` o `sh/copy-content.sh` según `isUnix()`. Excluye `.git/`, `.github/`, `.cursor/`, `docker-compose.yaml|.yml`, `.gitignore`, `.gitattributes`, `README.md`, `.cursorrules`.
4. **Push + PR**: calcula el SHA (`git rev-parse HEAD`), genera `sync-metadata.json`, commitea `sync(codecommit): <short7> <ts-UTC>`, crea el tag `sync-vYYYY.MM.DD-N`, antepone entrada en `CHANGELOG.md`, hace `push` normal y crea (o reutiliza) el PR con body trazable. Archiva `sync-metadata.json` y `pullrequest_response.json` fuera del clon.

## Install

### Prerrequisitos

- Agente Jenkins Windows (`powershell >= 5.0`, `robocopy`) o Linux (`bash`, `rsync`, `curl`, `python3 >= 3.9`).
- En el agente: `git`, `python3`, `curl` en `PATH`.
- Plugins Jenkins: **Git**, **Pipeline**, **Credentials Binding** (+ **Mask Passwords** y **AnsiColor** para `maskPasswords()`/`ansiColor`).
- Credenciales Jenkins:
  - `CODECOMMIT_CREDENTIALS` (usuario/contraseña o SSH).
  - `GITHUB_CREDENTIALS` (usuario/token para `git`).
  - `GITHUB_TOKEN` (Secret Text, PAT con scope `repo`).
- Verificación local (sin Jenkins): `python3 >= 3.9`, `pytest`, `bash`.

```bash
pip install -r requirements-dev.txt
python -m pytest tests/ -q
bash -n sh/copy-content.sh && bash -n sh/push-and-pr.sh
```

## Usage

Happy path en Jenkins: crear un job de pipeline apuntando a este repo, completar los parámetros y lanzar. Con cambios en CodeCommit (o `FORCE_PIPELINE_RUN`), el job deja un PR listo para revisión con el SHA origen y el link al build en su descripción.

```bash
# Validar el extractor
python py/ExtractGitHubRepositoryName.py "https://github.com/acme/demo.git"
# Generar metadatos de un sync (ejemplo)
python py/generate_sync_metadata.py --sha abc1234567890abcdef1234567890abcdef1234 \
  --branch main --base main --head sync-codecommit \
  --build-tag "sync-42" --build-url "https://jenkins/job/42/" \
  --timestamp "2026-09-25T12:34:56Z" --output sync-metadata.json
# Seco portable en Linux
sh/copy-content.sh "/tmp/CodeCommit" "/tmp/GitHub"
```

## API / Configuration

Parámetros del job (`parameters`, todos con defaults):

| Parámetro | Tipo | Default | Formato |
|---|---|---|---|
| `FORCE_PIPELINE_RUN` | boolean | `false` | `true` ejecuta aunque no haya cambios |
| `LOCAL_FOLDER_PATH` | string | `''` | Ruta base del agente (ej. `C:\sync` o `/var/sync`) |
| `CODECOMMIT_REPOSITORY_URL` | string | `''` | HTTPS o SSH de CodeCommit |
| `CODECOMMIT_REPOSITORY_BRANCH` | string | `main` | Rama origen monitoreada |
| `GITHUB_REPOSITORY_URL` | string | `''` | `https://github.com/{owner}/{repo}[.git]` o `git@github.com:{owner}/{repo}[.git]` |
| `GITHUB_REPOSITORY_DESTINY_BRANCH` | string | `main` | Rama base del PR |
| `GITHUB_REPOSITORY_TEMPORARY_BRANCH` | string | `update-from-codecommit` | Rama head del PR |
| `AGENT_LABEL` | string | `SERVER_1` | Label del agente |
| `GITHUB_USERNAME` / `GITHUB_EMAIL` | string | `sync-bot` / `sync-bot@local` | Identidad de los commits de sync |

Variables de entorno internas (no parametrizar): `GH_TOKEN` (inyectado vía `withCredentials`, nunca como argumento), `SYNC_SHA`, `SYNC_TIMESTAMP`, `BUILD_TAG`, `BUILD_URL`, `WORKSPACE`.

`options`: `timestamps()`, `timeout(30 min)`, `buildDiscarder(30 builds)`, `disableConcurrentBuilds()`, `ansiColor('xterm')`.

Scripts:

- `py/ExtractGitHubRepositoryName.py <url>` → imprime `owner/repo` en stdout; errores a stderr, exit `1`.
- `py/generate_sync_metadata.py --sha ... --output sync-metadata.json` → JSON de 7 campos; error exit `2`.
- `py/format_sync_message.py` / `py/next_sync_tag.py` → subject `sync(codecommit): <short7> <ts>` y tag `sync-vYYYY.MM.DD-N`.
- `bat/*.bat` / `sh/*.sh` → mismo contrato CLI (rutas); el token solo por env `GH_TOKEN`; rechazan argumentos con forma de token.

Limitación conocida: el stage `Checking Changes` aún usa `powershell(...)` incondicional, por lo que un agente Linux requiere PowerShell instalado (follow-up: dispatch `isUnix()`).

## Contributing

Entorno local:

```bash
pip install -r requirements-dev.txt
python -m pytest tests/ -q   # 29 tests: extractor, metadata, versionado, portabilidad
openspec validate hardening-cicd
```

Convención de commits: `sync(codecommit): <short7> <timestamp-UTC>` para commits de sincronización en runtime; para desarrollo usar Conventional Commits (`feat(...)`, `fix(...)`, `chore(...)`). Todo cambio de comportamiento pasa por `openspec new change` + `openspec validate` y se entrega vía PR a `main` (nunca push directo), con `CHANGELOG.md` actualizado cuando aplique.

## License

Sin archivo `LICENSE` en el repo: todos los derechos reservados a sus autores hasta declarar una licencia explícita.
