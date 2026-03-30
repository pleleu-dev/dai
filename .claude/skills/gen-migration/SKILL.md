---
name: gen-migration
description: Use when creating a new database migration, adding or altering tables, adding indexes, or changing the schema
---

# Generate Migration

Create an Ecto migration following project conventions.

## Steps

1. Generate the migration file: `mix ecto.gen.migration <descriptive_snake_case_name>`
2. Write the migration body following conventions below
3. Run `mix ecto.migrate` to verify it applies cleanly
4. Run `mix ecto.rollback` then `mix ecto.migrate` to verify reversibility

## Project Conventions

| Convention | Example |
|-----------|---------|
| UUID primary keys | `create table(:things, primary_key: false)` then `add :id, :binary_id, primary_key: true` |
| UUID foreign keys | `references(:other, type: :binary_id, on_delete: :restrict)` |
| UTC timestamps | `timestamps(type: :utc_datetime)` |
| JSONB for complex data | `add :metadata, :map, default: %{}` |
| Use `change/0` | Prefer reversible `change` over `up/down` unless irreversible |
| Index naming | Let Ecto auto-name, or use `name:` for partial/unique indexes |
| Partial unique indexes | `create unique_index(:t, [:col], where: "condition", name: :descriptive_name)` |

## Naming Patterns

Follow existing naming: `create_<table>`, `add_<column>_to_<table>`, `add_<feature>_to_<table>`.
