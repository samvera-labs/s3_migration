# s3_migration

Move a Hyrax application's original files from disk storage to S3, with every copy verified and every step reversible.

Original files often sit on a shared or network volume that costs far more per GB than object storage. This gem copies them to an S3 bucket through the [valkyrie-shrine](https://github.com/samvera-labs/valkyrie-shrine) adapter, checks each copy before the file's identifier is switched, and then helps you quarantine, roll back or purge the disk copies from a manifest, never by deleting a directory.

## Requirements

- Ruby 3.2 or newer, Rails 7.x and Hyrax 5.x, with Valkyrie as the metadata layer.
- Originals on a plain `Valkyrie::Storage::Disk` adapter (`disk://` ids). The versioned disk adapter that `rails generate hyrax:install` sets up is not supported; the tasks stop with a message explaining why.
- A `valkyrie-shrine` adapter registered as `:repository_s3`, for the bucket.

## Installation

```ruby
gem 's3_migration', github: 'samvera-labs/s3_migration'
```

The rake tasks load with the Rails app; there is nothing to generate.

## Usage

Every task that changes anything is a dry run unless you set `APPLY=true`, and the migration itself reports what it would do with `DRY_RUN=true`.

| Task | What it does |
| --- | --- |
| `s3_migration:report` | Read-only: files and gigabytes by use and storage scheme. |
| `s3_migration:migrate` | Copy originals to S3, verify them, then switch their identifiers. The disk copy is never touched. |
| `s3_migration:verify` | Read-only audit of what is already in S3. Get zero problems before deleting anything. |
| `s3_migration:quarantine` | Re-check each migrated file against the manifest, then move its disk copy into `.quarantine`. |
| `s3_migration:rollback` | Put a disk copy and its original identifier back, and remove the unused upload. |
| `s3_migration:purge` | Delete quarantined copies older than `MIN_AGE_DAYS` (default 14). |

Options: `DRY_RUN`, `INLINE` (run in the foreground instead of queueing jobs), `LIMIT=<n>` files, `APPLY`, `VERIFY_SHA=false`, `MIN_AGE_DAYS=<positive number>`, `S3_MIGRATION_QUEUE`, and `PROGRESS_EVERY=<n>` (`0` turns progress lines off).

The full walkthrough, including creating the bucket, registering the adapter and reclaiming disk space safely, is in [docs/migrating-files-to-s3.md](docs/migrating-files-to-s3.md).

### Multitenant applications

The tasks work on whichever repository the app is pointed at, so run them once per tenant. If one bucket serves several tenants, set `S3Migration.scope_provider` to a callable returning the current tenant's label; manifest entries, and therefore quarantine, rollback and purge, are then limited to that tenant.

## Development

The specs run in a small Rails app under `spec/internal` that boots Hyrax with the Postgres Valkyrie adapter. They need only Postgres, not Fedora, Solr, Redis or S3.

### Running the specs

1. Start Postgres. [docker-compose.yaml](docker-compose.yaml) runs one on `localhost:5432` with user and password `postgres`, matching the default connection:

   ```bash
   docker compose up -d --wait postgres
   ```

   If port 5432 is taken (for example by a local Postgres), pick another and point the specs at it:

   ```bash
   POSTGRES_PORT=5433 docker compose up -d --wait postgres
   export DATABASE_URL=postgres://postgres:postgres@localhost:5433/s3_migration_test
   ```

   Any other Postgres works too: set `DATABASE_URL` to it. Without `DATABASE_URL` the specs use `postgres://postgres:postgres@localhost:5432/s3_migration_test`.

2. Install the gems (Ruby 3.2 or newer):

   ```bash
   bundle install
   ```

3. Run the specs. The first run creates the `s3_migration_test` database and loads `spec/internal/db/schema.rb` into it.

   ```bash
   bundle exec rspec                                  # whole suite
   bundle exec rspec spec/s3_migration/file_migrator_spec.rb       # one file
   bundle exec rspec spec/s3_migration/file_migrator_spec.rb:42    # one example, by line
   bundle exec rspec --only-failures                  # re-run what failed last time
   ```

   A full run fails unless line coverage is 100%; the report is written to `coverage/index.html`. A run of a single file always reports low coverage, so ignore that failure when you filter.

4. Lint with `bundle exec rubocop`, then stop Postgres when you are done:

   ```bash
   docker compose down        # add -v to delete the database volume too
   ```

### Troubleshooting

- `PG::ConnectionBad` or `connection refused`: Postgres is not up yet, or `DATABASE_URL` points somewhere else. Check `docker compose ps`.
- Schema changes: after editing `spec/internal/db/schema.rb`, run `docker compose down -v` and start again so the specs reload it into a fresh database.

CI (GitHub Actions) runs rubocop and the specs on each push and pull request, and requires both to pass.

## License

MIT. See [LICENSE](LICENSE).
