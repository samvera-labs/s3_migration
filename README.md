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

The specs run in a small Rails app under `spec/internal` that boots Hyrax with the Postgres Valkyrie adapter. It needs only a Postgres database, not Fedora, Solr or Redis.

```bash
bundle install               # the specs create the database if it is missing; set DATABASE_URL to use another Postgres
bundle exec rspec            # fails below 100% line coverage
bundle exec rubocop
```

CI (GitHub Actions) runs rubocop and the specs on each push and pull request, and requires both to pass.

## License

MIT. See [LICENSE](LICENSE).
