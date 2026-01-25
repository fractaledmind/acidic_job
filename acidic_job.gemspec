# frozen_string_literal: true

require_relative "lib/acidic_job/version"

Gem::Specification.new do |spec|
  spec.name        = "acidic_job"
  spec.version     = AcidicJob::VERSION
  spec.authors     = [ "Stephen Margheim" ]
  spec.email       = [ "stephen.margheim@gmail.com" ]
  spec.homepage    = "https://github.com/fractaledmind/acidic_job"
  spec.summary     = "🧪 Durable execution workflows for Active Job"
  spec.description = "Write reliable and repeatable multi-step distributed operations that are Atomic ⚛️, Consistent 🤖, Isolated 🕴🏼, and Durable ⛰️."
  spec.license     = "MIT"

  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/fractaledmind/acidic_job"
  spec.metadata["changelog_uri"] = "https://github.com/fractaledmind/acidic_job/CHANGELOG.md"

  spec.files = Dir["README.md", "LICENSE", "lib/**/*", "app/**/*"]

  rails_version = ">= 7.1"

  spec.add_dependency "json", ">= 2.7.0" # see: https://github.com/ruby/json/pull/519
  spec.add_dependency "activejob", rails_version
  spec.add_dependency "activerecord", rails_version
  spec.add_dependency "activesupport", rails_version
  spec.add_dependency "railties", rails_version

  spec.add_development_dependency "chaotic_job", ">= 0.11.2"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "minitest", "< 6" # minitest 6.0 removed minitest/mock
  spec.add_development_dependency "mysql2"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "actionmailer"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.metadata["rubygems_mfa_required"] = "true"
end
