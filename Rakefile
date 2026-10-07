# frozen_string_literal: true

require "fileutils"
require "rspec/core/rake_task"

GEM_ROOT = File.expand_path(__dir__)

desc "Enrich the golden fixtures into a workspace catalog"
task :fixture_enrich do
  $LOAD_PATH.unshift(File.join(GEM_ROOT, "lib"))
  require "registry"

  workspace = File.join(".tmp", "workspace")
  FileUtils.rm_rf(workspace)
  config = Registry::Config.new(
    site_config_path: File.join(GEM_ROOT, "fixtures", "seed", "instance.yml"),
    aggregate_config_path: File.join(GEM_ROOT, "fixtures", "seed", "aggregate.yml"),
    registry_dir: File.join(workspace, "registry"),
    generator_label: "fixture-producer v1"
  )
  result = Registry::Enricher.new(config: config).run
  puts "OK: fixture catalog #{result.catalog.items.length} items"
end

desc "Certify the second (non-Jekyll) renderer against the golden fixtures"
task conformance: :fixture_enrich do
  $LOAD_PATH.unshift(File.join(GEM_ROOT, "lib"))
  require "registry"

  workspace = File.join(".tmp", "workspace")
  out = File.join(workspace, "second-site")
  sh "python3 #{File.join(GEM_ROOT, 'fixtures', 'second-renderer', 'render.py')} " \
     "--registry #{File.join(workspace, 'registry')} --files #{File.join(GEM_ROOT, 'fixtures', 'seed', 'producer')} --out #{out}"
  sh "#{File.join(GEM_ROOT, 'bin', 'registry-conformance')} check #{out} " \
     "--expect #{File.join(workspace, 'registry', 'catalog.json')} " \
     "--schema #{File.join(GEM_ROOT, 'schema', 'documents-index.schema.json')}"
  puts "OK: non-Jekyll renderer certified against the golden fixtures"
end

desc "Validate the enriched fixture catalog with the shipped CLI"
task validate: :fixture_enrich do
  sh "#{File.join(GEM_ROOT, 'bin', 'registry-validate')} #{File.join('.tmp', 'workspace', 'registry', 'catalog.json')} " \
     "--files #{File.join(GEM_ROOT, 'fixtures', 'seed', 'producer')} --urn-namespace fixture"
end

RSpec::Core::RakeTask.new(:spec)

task default: %i[spec conformance validate]
