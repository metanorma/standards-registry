# frozen_string_literal: true

require_relative "lib/registry/version"

Gem::Specification.new do |spec|
  spec.name = "standards-registry"
  spec.version = Registry::VERSION
  spec.authors = ["Ribose"]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Registry engine for standards organizations using Metanorma"
  spec.description = "The documents-index catalog contract, enrichment engine, validator and " \
                     "frontend conformance suite for standards registries. Any conforming " \
                     "generator may produce the catalog; any conforming renderer may serve it."
  spec.homepage = "https://github.com/metanorma/standards-registry"
  spec.license = "BSD-2-Clause"

  spec.files = Dir["lib/**/*.rb"] + Dir["lib/standards-registry/{layouts,templates}/*"] +
               Dir["bin/*"] + Dir["schema/*.json"] +
               Dir["fixtures/**/*"] + Dir["docs/*.md"] + %w[README.md LICENSE]
  spec.bindir = "bin"
  spec.executables = %w[registry-validate registry-conformance]
  spec.require_paths = ["lib"]

  spec.add_dependency "json_schemer", "~> 2.0"
  spec.add_dependency "rexml", "~> 3.4"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
