# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - TBD

### Added

- **Durable execution workflows** - New `execute_workflow` method with `unique_by:` keyword argument for defining idempotent, resumable workflows
- **Workflow steps** - DSL for defining linear multi-step workflows with `step` method
- **Persisted context** - `ctx` object for storing state across steps and retries via `AcidicJob::Value` records
- **Step orchestration** - `repeat_step!` for iterating within a step, `halt_workflow!` for pausing workflows
- **Plugin system** - Extensible architecture for custom step behaviors via `around_step` hooks
- **Transactional steps** - Built-in `transactional: true` option wraps steps in database transactions
- **Step retry detection** - `step_retrying?` helper to check if current step is being retried
- **Custom serializers**:
  - `ExceptionSerializer` - YAML + Zlib compression for exception serialization
  - `JobSerializer` - Handles ActiveJob instances
  - `NewRecordSerializer` - Persists unsaved ActiveRecord models
  - `RangeSerializer` - For Range objects (Rails < 8.1 compatibility)
- **Instrumentation** - ActiveSupport notifications for workflow events (`define_workflow`, `initialize_workflow`, `process_workflow`, `process_step`, `perform_step`, `record_entry`)
- **Testing utilities** - `AcidicJob::Testing` module for test isolation with DatabaseCleaner
- **Execution management** - `Execution.clear_finished_in_batches` for cleaning up old records
- **Configuration options**:
  - `AcidicJob.plugins` - Global default plugins array
  - `AcidicJob.clear_finished_executions_after` - Duration before finished executions can be cleared (default: 1 week)
  - `AcidicJob.connects_to` - Database connection configuration
  - `AcidicJob.logger` - Custom logger configuration

### Changed

- **Complete rewrite** - Major refactor from v0.x architecture
- **New database schema** - Three tables: `acidic_job_executions`, `acidic_job_entries`, `acidic_job_values` (replaces `acidic_job_keys` and `staged_acidic_jobs`)
- **Minimum Ruby version** - Now requires Ruby 3.0+
- **Minimum Rails version** - Now requires Rails 7.1+
- **Minimum JSON version** - Now requires json gem 2.7.0+ for strict mode support
- **Idempotency key generation** - Now uses SHA256 hash of `[job_class, unique_by]` with strict JSON generation
- **Step definitions** - Moved from hash-based to block-based DSL

### Deprecated

- `halt_step!` - Use `halt_workflow!` instead
- Pre-1.0 workflow definition format (definitions without `"steps"` key) - Will be removed in v1.1

### Removed

- `AcidicJob::Key` model - Replaced by `AcidicJob::Execution`
- `AcidicJob::Staged` model - Staging functionality removed
- `idempotency_key` as a direct job method - Now generated internally from `unique_by`
- `job_id` override on jobs - Idempotency is now tracked via `Execution` records, resolving GoodJob compatibility issues
- Support for Ruby < 3.0
- Support for Rails < 7.1

### Fixed

- Exception serialization now properly handles complex exceptions like `ActionView::Template::Error`
- Nested transaction isolation errors resolved with proper transaction handling
- MySQL timestamp ordering issues fixed with `created_at` tiebreaker

## [1.0.0.rc7] - 2024-12-XX

### Added

- `RangeSerializer` for Rails versions prior to 8.1

### Fixed

- Custom serializer instances now properly registered

## [1.0.0.rc6] - 2024-11-XX

### Changed

- Converted from Combustion to proper Rails engine structure
- Updated CI matrix: Ruby 3.0-3.4, Rails 7.1-8.0+main
- Minimum Ruby version bumped to 3.0

### Fixed

- MySQL timestamp ordering with `created_at` tiebreaker in `Entry.ordered` scope
- Compatibility fixes for parallelized tests

## [1.0.0.rc5] - 2024-10-XX

### Changed

- Updated to use ChaoticJob for simulation testing
- Improved test resilience

## [1.0.0.rc4] - 2024-10-XX

### Added

- `Context#fetch` method for get-or-set operations
- Database adapter-specific handling for `upsert_all` in Context

### Changed

- Renamed `halt_step!` to `halt_workflow!` (old method deprecated)

### Fixed

- JSON generation uses `JSON.generate` instead of deprecated `JSON.fast_generate`

## [1.0.0.rc3] - 2024-09-XX

### Added

- `AcidicJob.plugins` global configuration for default plugins
- `AcidicJob.clear_finished_executions_after` configuration
- `Execution.clear_finished_in_batches` for batch cleanup
- `PluginContext` object passed to plugins with full context access
- Plugins can now work with callable methods that accept parameters

### Changed

- Distinctive instance variables (`@__acidic_job_*__`) to avoid collisions
- `Entry` and `Value` records now cascade delete with `Execution`
- Reduced transaction usage: direct updates/inserts where safe
- `Value#value` field changed from JSON to TEXT type

### Fixed

- Log subscriber now uses symbol keys consistently
- Backwards compatibility for `Execution#finished?` with old "FINISHED" value

## [1.0.0.rc2] - 2024-09-XX

### Added

- Strict JSON mode enforcement for idempotency key generation
- Minimum json gem version requirement (2.7.0)

### Fixed

- Error class initializers no longer incorrectly call super
- `UndefinedMethodError` only raised for actual missing step methods

## [1.0.0.rc1] - 2024-08-XX

### Added

- Initial release candidate with new architecture
- `execute_workflow` DSL with `unique_by:` parameter
- `step` method for workflow definition
- `ctx` object for persisted context
- `repeat_step!` and `halt_workflow!` orchestration methods
- `step_retrying?` helper method
- Plugin system with `TransactionalStep` built-in plugin
- New database schema with `executions`, `entries`, `values` tables
- Comprehensive instrumentation via ActiveSupport::Notifications
- `AcidicJob::Testing` module

### Changed

- Complete rewrite from v0.9.x
- Dropped support for Ruby < 3.0 and Rails < 7.1

---

## [0.9.0] - 2023-XX-XX

_See [v0.9.0 README](https://github.com/fractaledmind/acidic_job/tree/v0.9.0) for the previous stable release documentation._

[Unreleased]: https://github.com/fractaledmind/acidic_job/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/fractaledmind/acidic_job/compare/v0.9.0...v1.0.0
[1.0.0.rc7]: https://github.com/fractaledmind/acidic_job/compare/v1.0.0.rc6...v1.0.0.rc7
[1.0.0.rc6]: https://github.com/fractaledmind/acidic_job/compare/v1.0.0.rc5...v1.0.0.rc6
[1.0.0.rc5]: https://github.com/fractaledmind/acidic_job/compare/v1.0.0.rc4...v1.0.0.rc5
[1.0.0.rc4]: https://github.com/fractaledmind/acidic_job/compare/v1.0.0.rc3...v1.0.0.rc4
[1.0.0.rc3]: https://github.com/fractaledmind/acidic_job/compare/v1.0.0.rc2...v1.0.0.rc3
[1.0.0.rc2]: https://github.com/fractaledmind/acidic_job/compare/v1.0.0.rc1...v1.0.0.rc2
[1.0.0.rc1]: https://github.com/fractaledmind/acidic_job/compare/v0.9.0...v1.0.0.rc1
[0.9.0]: https://github.com/fractaledmind/acidic_job/releases/tag/v0.9.0
