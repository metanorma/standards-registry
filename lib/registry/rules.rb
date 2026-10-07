# frozen_string_literal: true

module Registry
  # Catalog-internal rules: everything verifiable from the catalog hash
  # alone — no disk, no producer output. Shared by Registry::Consistency
  # (rake validate_consistency) and bin/registry-validate, so the CLI and
  # the build gate can never drift apart.
  class CatalogRules
    attr_reader :problems

    # display_categories: the instance's doctype→category mapping; nil
    # (the default, e.g. from bin/registry-validate) skips the category
    # projection check, [] disables category assignment.
    def initialize(urn_namespace: nil, docs_prefix: "/docs", license_default: nil,
                   display_categories: nil)
      @urn_namespace = urn_namespace
      @docs_prefix = docs_prefix
      @license_default = license_default
      @display_categories = display_categories
      @problems = []
    end

    def check(catalog)
      items = catalog["items"] || []
      check_projection(items)
      check_files(items)
      check_urls(items)
      check_editions(items)
      self
    end

    def ok?
      @problems.empty?
    end

    private

    def check_projection(items)
      items.each do |item|
        bib = item["bibliographic"] || {}
        compare_item(item, bib) unless bib.empty?
      end
    end

    def compare_item(item, bib)
      slug = item["slug"]
      add("items[#{slug}].id", item["id"], Projection.identifier(bib, {})) if bib["docidentifier"]
      add("items[#{slug}].title", item["title"], Projection.title(bib, {})) if bib["title"]
      add("items[#{slug}].abstract", item["abstract"], Projection.abstract(bib))
      add("items[#{slug}].doctype", item["doctype"], Projection.doctype(bib, {})) if bib.dig("ext", "doctype")
      add("items[#{slug}].stage", item["stage"], Projection.stage(bib, {})) if bib.dig("status", "stage")
      add("items[#{slug}].date", item["date"], Projection.date(bib, {})) if bib["date"]
      add("items[#{slug}].language", item["language"], Projection.language(bib))
      add("items[#{slug}].license", item["license"], Projection.license(bib, @license_default))
      add("items[#{slug}].copyright", item["copyright"], Projection.copyright(bib))
      add("items[#{slug}].authors", item["authors"], Projection.authors(bib))
      add("items[#{slug}].committee", item["committee"], Projection.committee(bib))
      add("items[#{slug}].relaton_schema_version", item["relaton_schema_version"],
          Projection.relaton_schema_version(bib))
      if @display_categories
        add("items[#{slug}].display_category_slug", item["display_category_slug"],
            display_category_for(item["doctype"])&.fetch("slug", nil))
      end
      add("items[#{slug}].doctype_class", item["doctype_class"],
          item["doctype"] && "type-#{item['doctype'].downcase}")
      add("items[#{slug}].stage_css", item["stage_css"], item["stage"].gsub(/\s+/, "-"))
    end

    def check_files(items)
      items.each do |item|
        path = "items[#{item['slug']}].files"
        formats = item["files"].map { |f| f["format"] }
        if formats.length != formats.uniq.length
          add_problem("#{path}: duplicate format entries #{formats.tally.select { |_, n| n > 1 }.keys}")
        end
        ranked = item["files"].sort_by { |f| [Enricher::FORMAT_ORDER.index(f["format"]) || Enricher::FORMAT_ORDER.length, f["format"]] }
        add_problem("#{path}: not in canonical order") if item["files"] != ranked

        item["files"].each do |file|
          slug = item["slug"]
          add("items[#{slug}].files[#{file['format']}].media_type", file["media_type"],
              MediaTypes.for(file["format"]))
          add_problem("items[#{slug}].files: url not under #{@docs_prefix}: #{file['url']}") unless
            file["url"].to_s.start_with?("#{@docs_prefix}/")
          add_problem("items[#{slug}].files[#{file['format']}]: invalid sha256 #{file['sha256']}") unless
            file["sha256"].to_s.match?(/\A[a-f0-9]{64}\z/)
        end
      end
    end

    def check_urls(items)
      seen = Hash.new(0)
      items.each do |item|
        seen[item["url"]] += 1
        add("items[#{item['slug']}].latest_url", item["latest_url"], Urls.latest_path(item))
        if item["urn"] && @urn_namespace && !item["urn"].start_with?("urn:#{@urn_namespace}:")
          add_problem("items[#{item['slug']}].urn not in the instance namespace: #{item['urn']}")
        end
      end
      seen.each do |url, count|
        next unless count > 1

        add_problem("items: #{count} items share landing URL #{url} — source repos must use distinct slugs")
      end
    end

    def check_editions(items)
      items.group_by { |item| item["document_id"] }.each_value do |group|
        latest = Urls.latest(group)
        group.each do |item|
          current = item["editions"].select { |e| e["current"] }
          if current.length != 1
            add_problem("items[#{item['slug']}].editions: expected exactly 1 current, got #{current.length}")
            next
          end
          add("items[#{item['slug']}].editions[current].url", current.first["url"], latest["url"])
        end
      end
    end

    def add(label, actual, expected)
      return if actual == expected

      add_problem("#{label}: #{actual.inspect} != recomputed #{expected.inspect}")
    end

    def display_category_for(doctype)
      return nil if doctype.nil? || doctype.to_s.empty?

      category = @display_categories.find do |cat|
        (cat["doctypes"] || []).include?(doctype)
      end
      return nil unless category

      { "name" => category["name"], "slug" => category["slug"] }
    end

    def add_problem(message)
      @problems << message
    end
  end
end
