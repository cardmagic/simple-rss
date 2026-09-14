# Repository Guidelines

This file is the shared source of project instructions. Keep `CLAUDE.md` as an
`@AGENTS.md` import so both tools use the same guidance.

## Commands

```bash
bundle exec rake test                    # Run all tests
bundle exec ruby -Ilib:test test/base/base_test.rb  # Run single test file
bundle exec rubocop                      # Lint
bundle exec rubocop -A                   # Auto-fix lint issues
bundle exec rbs-inline --output sig lib/ # Generate RBS from annotations
bundle exec rbs -I sig validate          # Validate generated types
bundle exec steep check                  # Type check
bundle exec rake console                 # Interactive console
```

## Architecture

The core library (`lib/simple-rss.rb`) uses regex-based XML parsing for flexibility
with malformed feeds. `lib/simple-rss/xml_element.rb` holds shared XML tokenization
and scoped element metadata. The optional normalized view lives in
`entry_normalizer.rb` and the format-independent `normalized_entry.rb` value object
under `lib/simple-rss/`. Preserve the existing raw parser and serialization
contracts when extending normalization. `json_feed.rb` validates JSON Feed
structure and preserves the original document; `json_entry_normalizer.rb` maps
JSON fields into the same immutable entry type. Keep format-specific extraction
separate and use the existing JSON standard library dependency.

`http_client.rb` is shared by ordinary fetching and website discovery. Explicit
network policies enable bounded requests; preserve legacy fetch defaults.
`request_policy.rb` checks resolved addresses and pins the connection target.
`discovery.rb` uses optional Nokogiri HTML5 parsing for head metadata. Keep core
parsing usable without Nokogiri, and verify new transport behavior with local
servers and controlled DNS/connection fixtures.

**Tag Syntax** (extend via `SimpleRSS.item_tags <<`):
- `tag` - simple element extraction
- `tag#attr` - attribute value (e.g., `media:content#url` → `media_content_url`)
- `tag+rel` - rel attribute matching (e.g., `link+alternate` → `link_alternate`)

**Dynamic Accessors**: Feed tags become `attr_reader` methods at parse time. Item tags are hash keys with `method_missing` for dot notation.

## Type Annotations

Uses RBS inline syntax:
```ruby
# @rbs (String, Integer) -> Bool   # method signature
attr_reader :name #: String         # attribute type
@items = [] #: Array[untyped]       # inline variable
```

## Changelog

Update `CHANGELOG.md` in the same pull request as any user-visible feature,
behavior change, or bug fix. Record unreleased work under `## Unreleased` at the
top. Keep released versions newest first with headings formatted as
`## X.Y.Z - YYYY-MM-DD`.

Write concise bullets that explain what changed for callers and why it matters.
Mention affected APIs, compatibility changes, and migration steps when relevant.
For bug fixes, describe the failing behavior and the corrected result. Link the
issue or pull request when useful. Include performance numbers only when they
were measured, and distinguish evidence from intended behavior.

Do not copy commit logs into the changelog, claim planned work is implemented,
or add a release date before publishing. Correct inaccurate history when found;
do not silently move a change into a version that did not contain it. Routine
test, tooling, and prose-only edits do not need their own release-note bullet.

When backfilling history, verify tag and commit boundaries, cite the source, and
distinguish source-history dates from package publication dates. Identify
intermediate source versions and the earliest repository import explicitly.

## Release

Before tagging a release, bump the version in both files:
- `simple-rss.gemspec` (`s.version`)
- `lib/simple-rss.rb` (`VERSION`)

Both values must match. If they do not, CI may build and attempt to push the wrong gem version.

Move the completed `Unreleased` notes into a section for that exact version and
the release date, then leave an empty `Unreleased` section for future work.
Check that the changelog, both version declarations, and the tag agree. Run the
test suite, RuboCop, RBS generation and validation, and Steep before publishing.
`Gemfile.lock` is ignored in this library; do not add it as part of a release.

Then tag with `v*` to trigger automated RubyGems release:
```bash
git tag -a vX.Y.Z -m "Version X.Y.Z"
git push origin vX.Y.Z
```

Quick preflight checks:
```bash
rg -n "s.version" simple-rss.gemspec
rg -n "VERSION" lib/simple-rss.rb
rg '^## ' CHANGELOG.md
gem build simple-rss.gemspec
```
