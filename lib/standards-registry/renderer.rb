# frozen_string_literal: true

# The Jekyll reference renderer, shipped in the gem and loaded when the
# instance lists standards-registry in its :jekyll_plugins group
# (TODO.improvements/11.3, 11.5). Reads the neutral registry/ handoff and
# generates the routes the conformance profile requires. A non-Jekyll
# frontend implements the same behaviour and passes the same suite; this
# renderer holds no private advantages.

require "json"

module StandardsRegistry
  GEM_ROOT = File.expand_path("../..", __dir__)
end

module Jekyll
  # A Layout whose file lives in the gem (Jekyll::Layout forces paths
  # under site.source, which cannot see gem files).
  class GemLayout < Layout
    def initialize(site, path)
      @site = site
      @base = File.dirname(path)
      @dir = ""
      @name = File.basename(path)
      @path = path
      process(@name)
      raw = File.read(path)
      if raw =~ Jekyll::Document::YAML_FRONT_MATTER_REGEXP
        @content = Regexp.last_match.post_match
        @data = SafeYAML.load(Regexp.last_match(1)) || {}
      else
        @content = raw
        @data = {}
      end
    end
  end

  class RegistryAssetFile < StaticFile
    def initialize(site, registry_dir, file_name, dest_name: nil)
      @registry_file_name = file_name
      @dest_name = dest_name || file_name
      super(site, site.source, registry_dir, file_name)
    end

    def destination(dest)
      Jekyll.sanitized_path(dest, @dest_name)
    end

    def copy_file(dest_path)
      FileUtils.cp(path, dest_path)
    end
  end

  class GeneratedPage < PageWithoutAFile
    def initialize(site, dir, layout, name = "index.html", data = {})
      @site = site
      @base = site.source
      @dir = dir
      @name = name
      process(name)
      self.data = { "layout" => layout }.merge(data)
      self.content = ""
    end
  end

  # A page emitted verbatim (no layout, no conversion): citation files,
  # checksum sidecars.
  class RawPage < PageWithoutAFile
    def initialize(site, dir, name, content)
      @site = site
      @base = site.source
      @dir = dir
      @name = name
      process(name)
      self.data = {}
      self.content = content
    end
  end

  class RegistryCatalogGenerator < Generator
    priority :high
    GEM_ROOT = ::StandardsRegistry::GEM_ROOT

    def generate(site)
      catalog = load_catalog(site)
      return if catalog.nil?

      inject_layouts(site)
      generate_templated_pages(site)
      site.data["registry_catalog"] = catalog
      site.data["registry_search_index"] = load_json(site, registry_dir(site), "search-index.json")

      serve_endpoints(site)
      serve_citation_exports(site)
      generate_catalog_checksum(site)
      if html_enabled?(site)
        generate_document_pages(site, catalog)
        generate_latest_aliases(site, catalog)
        generate_legacy_redirects(site, catalog)
      end
    end

    private

    # Instance layouts win; the gem's reference layouts (document,
    # redirect, doc-type) fill any gaps so an instance needs no layout
    # code of its own.
    def inject_layouts(site)
      dir = File.join(GEM_ROOT, "lib", "standards-registry", "layouts")
      %w[document redirect doc-type].each do |name|
        next if site.layouts.key?(name)

        path = File.join(dir, "#{name}.html")
        site.layouts[name] = GemLayout.new(site, path) if File.exist?(path)
      end
    end

    # feed.xml, opensearch.xml, sitemap.xml rendered from gem templates;
    # an instance page at the same URL takes precedence.
    def generate_templated_pages(site)
      templates = File.join(GEM_ROOT, "lib", "standards-registry", "templates")
      { "feed.xml" => "feed.xml", "opensearch.xml" => "opensearch.xml", "sitemap.xml" => "sitemap.xml" }.each do |url_name, template_name|
        next if site.pages.any? { |p| p.url == "/#{url_name}" }

        content = File.read(File.join(templates, template_name))
        site.pages << RawPage.new(site, "/", url_name, content)
      end
    end

    # Headless instances (registry.features.html: false) serve the data
    # endpoints only — HTML routes are optional in the conformance profile
    # (TODO.improvements/12).
    def html_enabled?(site)
      site.config.dig("registry", "features", "html") != false
    end

    def registry_dir(site)
      site.config.dig("registry", "dir") || "registry"
    end

    def load_catalog(site)
      load_json(site, registry_dir(site), "catalog.json")
    end

    def load_json(site, dir, name)
      path = site.in_source_dir(dir, name)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    end

    def serve_endpoints(site)
      site.static_files << RegistryAssetFile.new(site, registry_dir(site), "catalog.json")
      site.static_files << RegistryAssetFile.new(site, registry_dir(site), "search-index.json")
    end

    # Citation exports (ISO 690, BibTeX, RIS, CSL — generated from the
    # contract by scripts/generate-citations.mjs via relaton-ts) served
    # at /docs/{slug}.{ext}, alongside the artifacts.
    def serve_citation_exports(site)
      dir = File.join(registry_dir(site), "citations")
      return unless File.directory?(site.in_source_dir(dir))

      Dir.glob(site.in_source_dir(dir, "*")).sort.each do |path|
        name = File.basename(path)
        site.static_files << RegistryAssetFile.new(
          site, File.join(registry_dir(site), "citations"), name,
          dest_name: File.join("docs", name)
        )
      end
    end

    def generate_catalog_checksum(site)
      require "digest"
      source = File.join(registry_dir(site), "catalog.json")
      digest = Digest::SHA256.file(source).hexdigest
      site.pages << RawPage.new(site, "/", "catalog.json.sha256", "#{digest}  catalog.json\n")
    end

    def generate_document_pages(site, catalog)
      catalog["items"].each do |item|
        dir = item["url"].delete_suffix("/")
        site.pages << GeneratedPage.new(site, dir, "document", "index.html",
                                        { "doc" => item, "title" => item["id"],
                                          "iso690" => iso690_for(site, item) })
      end
    end

    def iso690_for(site, item)
      path = site.in_source_dir(registry_dir(site), "citations", "#{item['slug']}.iso690.txt")
      File.exist?(path) ? File.read(path).strip : nil
    end

    def generate_latest_aliases(site, catalog)
      catalog["items"]
        .group_by { |item| item["document_id"] }
        .each_value do |group|
          current = group.map { |item| item["editions"].detect { |e| e["current"] } }.compact.first
          next if current.nil?

          latest = group.find { |item| item["url"] == current["url"] }
          dir = latest["latest_url"].delete_suffix("/")
          site.pages << GeneratedPage.new(site, dir, "redirect", "index.html",
                                          { "destination" => latest["url"], "canonical" => latest["url"] })
        end
    end

    def generate_legacy_redirects(site, catalog)
      legacy_prefixes(site).each do |prefix|
        catalog["items"].each do |item|
          item["files"].each do |file|
            next unless file["format"] == "html"

            name = File.basename(file["url"])
            site.pages << GeneratedPage.new(site, "/#{prefix}", "redirect", name,
                                            { "destination" => file["url"], "canonical" => file["url"] })          end
        end
      end
    end

    def legacy_prefixes(site)
      Array(site.config.dig("registry", "legacy_prefixes"))
    end
  end
end
