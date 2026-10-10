# Instance Guide — adopt the registry as an SDO

Everything an organization needs to run a Metanorma standards registry
is configuration + content + branding. Zero engine code. The engine
(catalog contract, enrichment, validation, conformance) is this gem;
the reference instance —
[CalConnect/standards.calconnect.org](https://github.com/CalConnect/standards.calconnect.org),
live at <https://standards.calconnect.org> — is an Astro site that
consumes it. An instance contributes configuration, branding and
content, never engine code.

## 1. Prerequisites

- Ruby 3.4 + Node 24 — see the reference instance's `Gemfile` / `package.json`
- `GITHUB_TOKEN` with read access to your document repositories

## 2. Start from the reference instance

Clone or fork the reference instance, then change exactly three things:

1. **`_config.yml`** — site identity, the `registry:` map (org,
   urn_namespace, url_scheme, features, license_default) and the
   `branding:` block (logos, copyright line, footer link columns).
2. **`_data/navigation.yml`** — your categories and draft stages.
3. **Assets** — your logos, favicons, and `metanorma.aggregate.yml`
   pointed at your organization (`github.organizations` + topic).

The Gemfile pins this engine to a tagged release
(`gem "standards-registry", github: "metanorma/standards-registry", tag: "vX.Y.Z"`);
bump through tagged releases only.

## 3. Content pipeline (producer side)

Publish each document as a Metanorma repo whose releases carry the
`mn-release-metadata` block and a ZIP artifact, tagged with the
`metanorma-release` topic. Declare discovery in `metanorma.aggregate.yml`:

```yaml
source: github
output_dir: .artifacts/docs     # artifacts land here, finalized into dist/
file_routing: flat
cache_dir: .cache/aggregate
channels: [public]
include_drafts: true
display_categories:            # doctype → site category mapping
  - name: Standards
    slug: standards
    doctypes: [standard]
github:
  organizations: [YOUR_ORG]
  topic: metanorma-release
```

Small registries without release machinery can produce the same inputs
differently — the contract does not care. `fixtures/seed/` is a complete
hand-written producer (relaton records + artifact files); any tool that
emits `.artifacts/docs/relaton/index.json` + `.artifacts/docs/index.json`
is a valid producer.

## 4. Instance configuration (`_config.yml`)

```yaml
url: https://standards.YOUR_ORG.org
branding:                      # rendered by the Astro frontend
  logo_light: /assets/images/logo-light.svg
  logo_dark: /assets/images/logo-dark.svg
  copyright_name: Your Organization
  copyright_url: https://your-org.example.org/
  footer:
    community: [{text: Your Org, url: https://...}]
    resources: [{text: Policies, url: https://...}]
registry:
  org: yourorg                       # identity
  publisher_name: Your Organization  # citation_*, listing subtitles
  urn_namespace: yourorg             # urn:yourorg:doc:year
  url_scheme: "/docs/:document_id/:year/"
  docs_prefix: "/docs"
  legacy_prefixes: []                # old prefixes → redirect stubs
  features:
    search: true
    atom_feed: true
    jsonld: true
    opensearch: true
    html: true                       # false → headless (data endpoints only)
  license_default: null              # NEVER invent licenses; nulls are
                                     # tracked in registry/backfill.json
```

## 5. Build, validate, certify

```sh
bundle install && npm ci
bundle exec rake build              # fetch + enrich + citations + Astro + finalize + guard
bundle exec rake validate_schema    # catalog + search index vs published schemas
bundle exec rake validate_consistency  # Relaton projections, checksums, URLs, editions
bundle exec rspec                   # contract, projections, built-site suites
bundle exec rake conformance        # your built site AND the golden-fixture
                                    # build through your own pipeline
```

`rake conformance` certifies your instance's own built `dist/` **and**
re-renders the engine's golden fixture catalog through your frontend
(via `REGISTRY_DIR`), so your renderer proves it reads only the
contract — not your data.

## 6. What you get

- `/catalog.json` (+ `.sha256`, Sigstore signature sidecar in CI),
  `/search-index.json`, `/feed.xml`, `/opensearch.xml`, `/sitemap.xml`
- Per-document citations via relaton-ts: ISO 690 text, BibTeX, RIS, CSL-JSON
- Versioned document pages `/docs/{document_id}/{year}/` with JSON-LD,
  Google-Scholar `citation_*` meta, editions history and format buttons
  derived from `files[]`
- `latest` aliases, legacy redirects, category pages, client-side search
  plus full-text search (Pagefind)
- A data-quality backfill report (`registry/backfill.json`) — gaps are
  tracked, never fabricated

## 7. Swap or embed

- **Custom frontend**: implement the conformance profile
  (`docs/conformance-profile.md`) against `registry/catalog.json` and
  certify with `bin/registry-conformance` — `fixtures/second-renderer/`
  is a minimal Python example that passes.
- **Headless**: set `features.html: false` and embed the JSON endpoints
  elsewhere; certify with `--no-html`.

## 8. Data honesty rules

- Relaton (`bibliographic`) is canonical; projections are recomputed and
  verified on every build.
- Missing language/license/abstract stay `null` and are listed in
  `registry/backfill.json` — backfill in the source repos or via
  `license_default`, never by hand-editing the catalog.
- The catalog is rebuildable at any time: `rake enrich` is offline and
  deterministic.
