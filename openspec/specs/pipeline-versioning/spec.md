# pipeline-versioning Specification

## Purpose
Versiona cada sincronización con mensajes de commit deterministas, tags de sync y un changelog acumulativo para poder revertir y auditar qué SHA originó cada cambio.

## Requirements

### Requirement: Mensaje de commit determinista y trazable

Todo commit de sync SHALL usar el formato `sync(codecommit): <short-sha-7> <timestamp-utc>` y SHALL incluir en el cuerpo extendido el SHA completo, `BUILD_TAG` y `BUILD_URL`. Queda prohibido usar `%DATE% %TIME%` locale-dependiente como único identificador.

#### Scenario: Commit con formato válido

- **WHEN** el script de push crea un commit para SHA `abc1234567890`
- **THEN** `git log -1 --pretty=%s` coincide con `^sync\(codecommit\): [0-9a-f]{7} [0-9T:\-Z]+$`

### Requirement: Tag de sync y changelog acumulativo

Cada sync con cambios SHALL crear un tag `sync-vYYYY.MM.DD-N` (incremental por día) apuntando al commit de sync y SHALL anteponer una entrada en `CHANGELOG.md` con fecha, SHA origen y URL del PR. Si no hay cambios, no SHALL crear tag ni entrada.

#### Scenario: Segundo sync del día incrementa sufijo

- **WHEN** ya existe `sync-v2026.09.25-1` y se sincroniza otro cambio el mismo día
- **THEN** se crea `sync-v2026.09.25-2` y `CHANGELOG.md` gana una entrada al inicio con ambos SHAs diferenciados
