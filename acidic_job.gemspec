# frozen_string_literal: true

require_relative "lib/acidic_job/version"

Gem::Specification.new do |spec|
  spec.name = "acidic_job"
  spec.version = AcidicJob::VERSION
  spec.authors = ["fractaledmind"]
  spec.email = ["stephen.margheim@gmail.com"]

  spec.summary = "Idempotent operations for Rails apps, built on top of ActiveJob."
  spec.description = "Idempotent operations for Rails apps, built on top of ActiveJob."
  spec.homepage = "https://github.com/fractaledmind/acidic_job"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/fractaledmind/acidic_job"
  spec.metadata["changelog_uri"] = "https://github.com/fractaledmind/acidic_job/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir["README.md", "LICENSE", "lib/**/*", "app/**/*"]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "json", ">= 2.7.0" # see: https://github.com/ruby/json/pull/519
  ">= 7.1".tap do |rails_version|
    spec.add_dependency "activejob", rails_version
    spec.add_dependency "activerecord", rails_version
    spec.add_dependency "activesupport", rails_version
    spec.add_dependency "railties", rails_version
    spec.add_development_dependency "actionmailer", rails_version
  end

  spec.add_development_dependency "chaotic_job", "0.3.0"
  spec.add_development_dependency "combustion"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "sqlite3"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end
