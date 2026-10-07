# frozen_string_literal: true

require "digest"
require "json"

module Registry
  # Build-gate verification over the emitted catalog
  # (TODO.improvements/02,03,04,10). Three layers:
  #
  #   catalog rules — Registry::CatalogRules (projection recompute, file
  #                   shape, URL/edition invariants; shared with
  #                   bin/registry-validate)
  #   disk          — every files[] entry verified against the artifact
  #                   on disk (bytes + sha256)
  #   pipeline      — registry/catalog.json equals a fresh in-memory
  #                   enrichment of the producer outputs
  class Consistency
    MAX_REPORTED = 20

    attr_reader :problems

    def initialize(config)
      @config = config
      @problems = []
    end

    def run
      return self unless File.exist?(@config.catalog_path)

      catalog = Catalog.from_file(@config.catalog_path)
      run_catalog_rules(catalog)
      check_pipeline(catalog)
      check_files(catalog)
      check_search_index(catalog)
      self
    end

    def ok?
      problems.empty?
    end

    private

    def run_catalog_rules(catalog)
      rules = CatalogRules.new(urn_namespace: @config.urn_namespace,
                               docs_prefix: @config.docs_prefix,
                               license_default: @config.license_default,
                               display_categories: @config.display_categories)
      rules.check("items" => catalog.items)
      rules.problems.each { |problem| add_problem(problem) }
    end

    def check_pipeline(catalog)
      return unless File.exist?(@config.relaton_index_path)

      fresh = Enricher.new(config: @config).build.catalog
      diff(fresh.to_h, catalog.to_h, "catalog")
    end

    def check_files(catalog)
      catalog.items.each do |item|
        item["files"].each do |file|
          check_file(item, file)
        end
      end
    end

    def check_file(item, file)
      slug = item["slug"]
      rel = file["url"].delete_prefix("#{@config.docs_prefix}/")
      abs = File.join(@config.output_dir, rel)
      unless File.file?(abs)
        add_problem("items[#{slug}].files: #{file['url']} missing on disk")
        return
      end

      add("items[#{slug}].files[#{file['format']}].bytes", file["bytes"], File.size(abs))
      add("items[#{slug}].files[#{file['format']}].sha256", file["sha256"],
          Digest::SHA256.file(abs).hexdigest)
    end

    def check_search_index(catalog)
      return unless File.exist?(@config.search_index_path)

      fresh = SearchIndex.build(catalog.items,
                                generated_at: catalog.meta[:generated_at],
                                org: catalog.meta[:org])
      stored = JSON.parse(File.read(@config.search_index_path))
      diff(fresh.to_h, stored, "search-index")
    end

    def add(label, actual, expected)
      return if actual == expected

      add_problem("#{label}: #{actual.inspect} != recomputed #{expected.inspect}")
    end

    def add_problem(message)
      @problems << message
    end

    def diff(expected, actual, label)
      out = []
      deep_diff(expected, actual, label, out)
      out.first(MAX_REPORTED).each { |line| add_problem(line) }
      add_problem("#{label}: #{out.length - MAX_REPORTED} more differences") if out.length > MAX_REPORTED
    end

    def deep_diff(expected, actual, path, out)
      return out << "#{path}: #{expected.inspect} != #{actual.inspect}" unless comparable?(expected, actual)

      if expected.is_a?(Hash)
        (expected.keys | actual.keys).each do |key|
          deep_diff(expected[key], actual[key], "#{path}.#{key}", out)
        end
      elsif expected.is_a?(Array)
        if expected.length != actual.length
          out << "#{path}: length #{expected.length} != #{actual.length}"
        else
          expected.each_with_index { |value, i| deep_diff(value, actual[i], "#{path}[#{i}]", out) }
        end
      elsif expected != actual
        out << "#{path}: #{expected.inspect} != #{actual.inspect}"
      end
    end

    def comparable?(expected, actual)
      expected.class == actual.class ||
        (expected.is_a?(Hash) && actual.is_a?(Hash)) ||
        (expected.is_a?(Array) && actual.is_a?(Array))
    end
  end
end
