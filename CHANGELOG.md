# Changelog

Entries through 2.2.0 were backfilled from Git history. Their dates identify
release tags or version-changing commits; older package publication dates can
differ. Linked source boundaries identify the evidence for each entry. The
repository begins with a 1.1 import, so earlier releases are not reconstructed.

## Unreleased

- Use the first valid `pubDate`, `updated`, or `published` timestamp in
  `latest`, `items_since`, and merge ordering. Malformed dates no longer make
  `latest` raise or hide a valid fallback. Preserve the original field values,
  retain source order for equal dates, and place undated entries after dated
  entries, including those before 1970. Preserve merge identity rules and the
  placement of unidentified entries. ([#62](https://github.com/cardmagic/simple-rss/pull/62))
- Make documented relation accessors such as `item.link_alternate` and
  `item[:link_alternate]` return the link's `href`, including when attributes
  precede `rel` or the link contains nested media. Keep relation matching within
  direct child links of the current entry. Preserve legacy keys such as
  `item[:"link+alternate"]` and the existing `item.link` behavior; hash and JSON
  serialization now include both relation keys.
  ([#57](https://github.com/cardmagic/simple-rss/issues/57))

## 2.2.0 - 2026-03-29

- Add `feed_type`, feed validation through instance and class `valid?` methods,
  and filtering with `items_since`, `items_by_category`, and `search`.
- Add instance and class `merge` methods to combine feeds, deduplicate identified
  entries, and order them by date. Add `diff` to report added and removed entries
  between feed snapshots.
- Add item `has_media?` and `media_url` helpers, feed-level `enclosures` and
  `images` collections, and parsing for `media:description`, `itunes:duration`,
  and `itunes:image#href`. Treat blank media URLs as absent when choosing a
  usable URL. ([Source](https://github.com/cardmagic/simple-rss/compare/v2.1.0...v2.2.0))

## 2.1.0 - 2025-12-29

- Add `SimpleRSS.fetch` with timeouts, custom headers, redirects, and conditional
  GET support. Expose ETag and Last-Modified values and return `nil` for a
  `304 Not Modified` response.
- Add `as_json`, `to_json`, and `to_hash`, serializing time values as ISO 8601.
  Add `to_xml` to generate RSS 2.0 or Atom output from a parsed feed.
- Include `Enumerable` so feeds support iteration, mapping, and filtering.
  Add index access with `feed[index]` and date ordering with `latest(count)`.
  ([Source](https://github.com/cardmagic/simple-rss/compare/v2.0.0...v2.1.0))

## 2.0.0 - 2025-12-28

- Add the `array_tags` option to collect multiple values for selected item tags.
- Support extracting attributes from channel/feed and item/entry elements with
  the `tag#attribute` syntax.
- Normalize parsed strings to UTF-8 and skip empty or whitespace-only tag
  definitions that could make parsing hang.
- Add inline RBS type annotations, Steep validation, and GitHub Actions checks
  for modern Ruby versions.
  ([Source](https://github.com/cardmagic/simple-rss/compare/f5e879b...v2.0.0))

## 1.3.3 - 2018-04-23

- Parse `media:content#duration`, making video duration available through
  `media_content_duration`. Synchronize the gemspec and library version at
  1.3.3. ([Source](https://github.com/cardmagic/simple-rss/compare/51f0eb6...f5e879b))

## 1.3.2 - 2015-08-17

- Stop forcing parsed content to binary encoding during unescaping. Apply CDATA
  removal and whitespace trimming after either unescaping branch, and add UTF-8
  fixture coverage. This date follows the version change in source;
  [RubyGems](https://rubygems.org/gems/simple-rss/versions/1.3.2) records package
  publication in April 2018.
  ([Source](https://github.com/cardmagic/simple-rss/compare/f3768bd...76a56c6))

## 1.3.1 - 2013-12-16

- Restore Ruby 1.8 compatibility by checking for `force_encoding` before calling
  it while unescaping content.
  ([Source](https://github.com/cardmagic/simple-rss/commit/f3768bd))

## 1.3.0 - 2013-12-16

- Make dynamically generated feed accessors usable on Ruby 1.9 without changing
  the visibility of private parser methods.
- Adjust regular expressions and encoding handling for Ruby 1.9, including
  suppression of UTF-8 regexp warnings.
  ([Source](https://github.com/cardmagic/simple-rss/compare/aaf86ad...0e2ce64))

## 1.2.3 - 2010-07-06

- Add `tag#attribute` mapping for item child elements. Parse Media RSS content
  URLs, types, dimensions, thumbnails, titles, credits, and categories through
  the corresponding attribute and element accessors.
  ([Source](https://github.com/cardmagic/simple-rss/compare/0915f34...aaf86ad))

## 1.2.2 - 2009-06-22

- Replace evaluation of feed-field assignments with `instance_variable_set`
  and generate feed readers directly. Copy the options hash when constructing
  the parser. ([Source](https://github.com/cardmagic/simple-rss/commit/0915f34))

## 1.2.1 - 2009-06-22

- Introduce an options hash for `parse` and initialization, including a
  `marshalable` option that skips feed-reader generation. This intermediate
  version is recorded in Git; a package publication was not verified.
  ([Source](https://github.com/cardmagic/simple-rss/commit/c9757d2))

## 1.2 - 2009-02-25

- Add `tag+rel` matching and built-in Atom link relations for alternate, self,
  edit, and replies links. Add `feedburner:origLink` support.
- Remove CDATA delimiters and trim whitespace even when percent-unescaping is
  unnecessary. ([Source](https://github.com/cardmagic/simple-rss/compare/40f3ca5...fa54025))

## 1.1 - 2006-02-02

- Earliest repository import: parse RSS and Atom from strings or IO objects,
  expose feed and item fields through method access, provide RSS/Atom aliases,
  and allow callers to extend the recognized feed and item tags.
  ([Source](https://github.com/cardmagic/simple-rss/commit/437b6a6))
- Subsequent commits retaining version 1.1 make percent-unescaping conditional
  and add gem packaging metadata. These changes postdate the initial import.
  ([Unescaping](https://github.com/cardmagic/simple-rss/commit/ac95fb4),
  [packaging](https://github.com/cardmagic/simple-rss/commit/379f639))
