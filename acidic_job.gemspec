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
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 4.0.0"
  spec.add_dependency "activesupport"
  spec.add_development_dependency "railties", ">= 4.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
