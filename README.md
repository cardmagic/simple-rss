# SimpleRSS

[![Gem Version](https://badge.fury.io/rb/simple-rss.svg)](https://badge.fury.io/rb/simple-rss)
[![CI](https://github.com/cardmagic/simple-rss/actions/workflows/ruby.yml/badge.svg)](https://github.com/cardmagic/simple-rss/actions/workflows/ruby.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL-blue.svg)](https://opensource.org/licenses/LGPL-3.0)

A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. Designed to be backwards compatible with Ruby's standard RSS parser while handling malformed feeds gracefully.

## Features

- Parses both RSS and Atom feeds
- Tolerant of malformed XML (regex-based parsing)
- Built-in URL fetching with conditional GET support (ETags, Last-Modified)
- JSON and XML serialization
- Extensible tag definitions
- Zero runtime dependencies

## What's New in 2.x

See the [changelog](CHANGELOG.md) for release history and unreleased changes.

The 2.x releases add:

- **URL Fetching** - One-liner feed fetching with `SimpleRSS.fetch(url)`. Supports timeouts, custom headers, and automatic redirect following.

- **Conditional GET** - Bandwidth-efficient polling with ETag and Last-Modified support. Returns `nil` when feeds haven't changed (304 Not Modified).

- **JSON Serialization** - Export feeds with `to_json`, `to_hash`, and Rails-compatible `as_json`. Time objects serialize to ISO 8601.

- **XML Serialization** - Convert any parsed feed to clean RSS 2.0 or Atom XML with `to_xml(format: :rss2)` or `to_xml(format: :atom)`.

- **Array Tags** - Collect all occurrences of a tag (like multiple categories) with the `array_tags:` option.

- **Attribute Parsing** - Extract attributes from feed, item, and media tags using the `tag#attr` syntax.

- **UTF-8 Normalization** - All parsed content is automatically normalized to UTF-8 encoding.

- **Modern Ruby** - Full compatibility with Ruby 3.1 through 4.0, with RBS type annotations and Steep type checking.

- **Enumerable Support** - Iterate feeds naturally with `each`, `map`, `select`, and all Enumerable methods. Access items by index with `rss[0]` and get the latest items sorted by date with `latest(n)`.

## Installation

Add to your Gemfile:

```ruby
gem "simple-rss"
```

Or install directly:

```bash
gem install simple-rss
```

## Quick Start

```ruby
require "simple-rss"
require "uri"
require "net/http"

# Parse from a string or IO object
xml = Net::HTTP.get(URI("https://example.com/feed.xml"))
rss = SimpleRSS.parse(xml)

rss.channel.title        # => "Example Feed"
rss.items.first.title    # => "First Post"
rss.items.first.pubDate  # => 2024-01-15 12:00:00 -0500 (Time object)
```

## Usage

### Fetching Feeds

SimpleRSS includes a built-in fetcher with conditional GET support for efficient polling:

```ruby
# Simple fetch
feed = SimpleRSS.fetch("https://example.com/feed.xml")

# With timeout
feed = SimpleRSS.fetch("https://example.com/feed.xml", timeout: 10)

# Conditional GET - only download if modified
feed = SimpleRSS.fetch("https://example.com/feed.xml")
# Store these for next request
etag = feed.etag
last_modified = feed.last_modified

# On subsequent requests, pass the stored values
feed = SimpleRSS.fetch(
  "https://example.com/feed.xml",
  etag:,
  last_modified:
)
# Returns nil if feed hasn't changed (304 Not Modified)
```

### Accessing Feed Data

SimpleRSS provides both RSS and Atom style accessors:

```ruby
feed = SimpleRSS.parse(xml)

# RSS style
feed.channel.title
feed.channel.link
feed.channel.description
feed.items

# Atom style (aliases)
feed.feed.title
feed.entries
```

### Item Attributes

Items support both hash and method access:

```ruby
item = feed.items.first

# Hash access
item[:title]
item[:link]
item[:pubDate]

# Method access
item.title
item.link
item.pubDate
```

Date fields are automatically parsed into `Time` objects:

```ruby
item.pubDate.class  # => Time
item.pubDate.year   # => 2024
```

### Iterating with Enumerable

SimpleRSS includes `Enumerable`, so you can iterate feeds naturally:

```ruby
feed = SimpleRSS.parse(xml)

# Iterate over items
feed.each { |item| puts item.title }

# Use any Enumerable method
titles = feed.map { |item| item.title }
tech_posts = feed.select { |item| item.category == "tech" }
first_five = feed.first(5)
total = feed.count

# Access items by index
feed[0].title   # first item
feed[-1].title  # last item

# Get the n most recent items
feed.latest(10)
```

`latest`, `items_since`, and merge ordering use the first successfully parsed date
from `pubDate`, `updated`, and `published`, in that order. Invalid date strings
remain available in the original fields. `latest` places entries without a usable
date after dated entries, including dates before 1970. Equal dates and undated
entries retain their source order, and `latest` does not modify the feed.

`items_since(time)` returns entries strictly newer than the given time in source
order, excluding entries without a usable date. Merging sorts identified entries
by the same date rules and keeps the newest entry for each identity. Equal dates
keep the first occurrence. Entries without an identity remain at the end in input
order, regardless of their dates.

### Normalized Entries

Use `normalized_entries` when an importer or digest should handle RSS and Atom
through the same fields:

```ruby
feed = SimpleRSS.parse(xml, source_url: "https://example.com/feed.xml")
entry = feed.normalized_entries.first

entry.identifier       # Publisher's opaque ID/GUID, or nil
entry.url              # Article URL, preferring an Atom HTML alternate
entry.published_at     # Time or nil; never filled from an update timestamp
entry.updated_at       # Time or nil
entry.content_html     # Full HTML content, when supplied
entry.content_text     # Full plain text, when supplied
entry.summary          # Separate synopsis; see summary_type (:html or :text)
entry.categories       # Nonempty terms, unique in first-seen order
entry.attachments      # Associated URL, media_type, size_in_bytes, duration_in_seconds
entry.authors          # Name, email, URL, and source metadata
entry.issues           # Inspect missing bases, invalid dates/numbers, unsupported content
entry.raw              # Frozen copy of the original item hash
entry.raw_xml          # Original entry XML, including unconfigured extensions
entry.field_sources    # Which XML tag supplied each normalized scalar field
```

This is an optional, immutable view of the original XML. `items`, `entries`,
iteration, custom tags, `latest`, `merge`, `diff`, and all existing serialization
methods keep their current behavior. Normalization neither changes global tag
configuration nor mutates or freezes raw items. Each call returns fresh snapshots;
raw item edits are preserved in `raw` but do not rewrite the XML-derived fields.
Reordering or deduplicating `items` preserves the association with each item's
original XML. Inserting an unrelated hash into `items` cannot provide that source
and raises `SimpleRSSError` when normalized.

| Normalized field | RSS mapping | Atom 1.0 mapping |
| --- | --- | --- |
| `identifier` | `guid`, without URL decoding or a generated fallback | `id`, without URL decoding or a generated fallback |
| `url` | Item `link`, then an Atom alternate extension | Alternate `link` (`rel` defaults to alternate); HTML/XHTML first, untyped second, other alternatives last; never a self/API fallback |
| `published_at` | First parseable `pubDate`, then Dublin Core `date` | `published` |
| `updated_at` | Atom `updated` extension, then `modified` | `updated` |
| `content_html` | Explicit mapping, then `content:encoded`, then an HTML/XHTML Atom content extension | Explicit mapping, then `content:encoded` if supplied, then HTML/XHTML `content` |
| `content_text` | Explicit mapping or a plain-text Atom content extension | Explicit mapping, then plain-text `content` |
| `summary` | `description`, treated as HTML-capable synopsis | `summary`, honoring text/HTML/XHTML type |
| `categories` | Repeated category text plus Dublin Core subjects and unsplit Media RSS/iTunes keywords | Category terms plus the same recognized extensions |
| `attachments` | Each `enclosure` and Media RSS `content` (direct or in a direct Media RSS group) | Each enclosure `link` and the same Media RSS elements |
| `authors` | Each `author` as its unparsed email value; Dublin Core `creator` as a name | Entry authors, otherwise source authors, otherwise feed authors |

Namespaces are resolved by their declared URI; standard extension prefixes may
vary. Ordinary metadata must be a direct child of its entry. Nested article
markup, comments, and unrelated source metadata cannot replace entry fields.
Missing scalars are `nil`; missing collections are empty arrays. Dates use Ruby's
permissive `Time.parse`: invalid values produce `nil` and an issue, with the source
retained. `effective_at` returns `published_at || updated_at` for a normalized
entry; existing raw-item date ordering is unchanged.

URLs use the applicable ancestor and element `xml:base` declarations, resolved
against `source_url`. `fetch` supplies the final response URL after redirects;
`normalized_entries(source_url: "https://example.com/feed.xml")` can override it
for one call. Relative redirects are resolved against the current request URL.
Without a usable base, relative values are preserved and reported in `issues`.
Invalid URI syntax is likewise preserved with an issue. Identifiers are never
resolved as URLs. Normalization performs no HTTP requests or article scraping.

Content is not sanitized, and HTML is never implicitly stripped into plain text.
XML entities are decoded once outside CDATA; CDATA content is retained literally.
Atom XHTML drops its enclosing XHTML `div` and removes XHTML namespace prefixes
from element names, preserving the original in `raw_xml`. `content_base_url`
provides the effective base for the selected HTML content (or plain text when
HTML is absent); links inside content are not rewritten. External Atom content
is exposed as `content_url` without fetching it. Unsupported content types remain
in raw data with an issue. Render HTML only through your application's usual
sanitization policy.

`category_details` preserves duplicate category records, labels, schemes/domains,
and their raw attributes/content even when `categories` removes repeated terms.
`links` preserves all entry link records with resolved `url`, `rel`, `media_type`,
and raw metadata. Each attachment includes `source` and `raw`; invalid numeric
values stay there and produce a `nil` normalized number plus an issue, rather
than becoming zero. An item-level iTunes duration applies only when there is one
attachment; its original element is then available as `raw_duration`.

Custom content and keyword rules belong to an individual normalization call:

```ruby
entries = feed.normalized_entries(mappings: {
  content_html: "full-text",
  content_text: "{urn:example:content}plain",
  categories: [
    { tag: "dc:subject", separator: ";" },
    { tag: "media:keywords", separator: "," }
  ]
})
```

Content mappings select the first nonempty direct element and take precedence
over the defaults for that representation. A selector is an exact XML qualified
name or `{namespace-uri}local-name`, not XPath. Hyphenated names such as
`full-text` need no generated accessor or global tag registration. Category
mappings override the selected element's default term extraction; a separator
is literal and optional. Unmapped subject/keyword strings are never guessed to
be comma- or semicolon-delimited. Unknown mapping keys and malformed mapping
options raise `ArgumentError`.

For migration, replace format-specific expressions such as
`item[:link_alternate] || item[:link]` with `entry.url`, while retaining
`entry.raw` for existing custom fields. The runnable [digest example](examples/digest.rb)
reads either format without testing which one it received:

```bash
ruby -Ilib examples/digest.rb test/data/normalized_rss.xml
ruby -Ilib examples/digest.rb test/data/normalized_atom.xml
```

The mapping follows the [Atom specification](https://www.rfc-editor.org/rfc/rfc4287.html),
[RSS specification](https://www.rssboard.org/rss-specification), and
[XML Base rules](https://www.w3.org/TR/xmlbase/). It is a tolerant extraction view,
not a standards validator. JSON Feed parsing is tracked separately in
[#60](https://github.com/cardmagic/simple-rss/issues/60).

### JSON Serialization

```ruby
feed = SimpleRSS.parse(xml)

# Get as hash
feed.to_hash
# => { title: "Feed Title", link: "...", items: [...] }

# Get as JSON string
feed.to_json
# => '{"title":"Feed Title","link":"...","items":[...]}'

# Works with Rails/ActiveSupport
feed.as_json
```

### XML Serialization

Convert parsed feeds to standard RSS 2.0 or Atom format:

```ruby
feed = SimpleRSS.parse(xml)

# Convert to RSS 2.0
feed.to_xml(format: :rss2)

# Convert to Atom
feed.to_xml(format: :atom)
```

### Extending Tag Support

Add support for custom or non-standard tags:

```ruby
# Add a new feed-level tag
SimpleRSS.feed_tags << :custom_tag

# Add item-level tags
SimpleRSS.item_tags << :custom_item_tag

# Parse tags with specific rel attributes (common in Atom)
SimpleRSS.item_tags << :"link+enclosure"
# Accessible as: item.link_enclosure

# Parse tag attributes
SimpleRSS.item_tags << :"media:content#url"
# Accessible as: item.media_content_url

# Parse item/entry attributes
SimpleRSS.item_tags << :"entry#xml:lang"
# Accessible as: item.entry_xml_lang
```

#### Tag Syntax Reference

| Syntax | Example | Accessor | Description |
|--------|---------|----------|-------------|
| `tag` | `:title` | `.title` | Simple element content |
| `tag#attr` | `:"media:content#url"` | `.media_content_url` | Attribute value |
| `tag+rel` | `:"link+alternate"` | `.link_alternate` | Element with specific `rel` attribute |

Relation tags provide both underscore and legacy `+` hash keys. For example,
`item.link_alternate`, `item[:link_alternate]`, and `item[:"link+alternate"]`
return the same parsed value. Both keys appear in `to_hash`, `as_json`, and
`to_json`; they are ordinary hash entries, so reassigning one does not update the
other. The built-in link relations are `alternate`, `self`, `edit`, and `replies`.

Link relation accessors read `href` from the first direct child link with the
requested explicit `rel` attribute. Attribute order and child markup do not
affect the URL. Links inside source metadata, content, or other nested elements
are excluded. A missing relation or `href` returns `nil`. Relative href values
remain relative. `item.link` retains its existing extraction behavior; it does
not select a canonical article URL across relations or feed formats.

### Collecting Multiple Values

By default, SimpleRSS returns only the first occurrence of each tag. To collect all values:

```ruby
# Collect all categories for each item
feed = SimpleRSS.parse(xml, array_tags: [:category])

item.category  # => ["tech", "programming", "ruby"]
```

RSS categories use element text, including CDATA: `<category>ruby</category>`.
Atom 1.0 categories use the `term` attribute:

```xml
<category term="ruby" label="Ruby Language" scheme="https://example.com/topics"/>
<category term="rails"/>
```

With `array_tags: [:category]`, those Atom categories become `["ruby", "rails"]`
in source order, preserving duplicates. Scalar mode returns the first usable
term. Both modes work with `feed.items_by_category("ruby")`. Missing or blank
Atom terms are skipped; labels and element content do not supply a fallback.
The original `label` and `scheme` attributes remain in `feed.source` for callers
that need the source metadata.

Category extraction uses direct children of each entry or item and resolves
default and prefixed namespace declarations on the feed, entry, and category.
Categories inside content or source metadata are excluded. RSS categories keep
their existing scalar/array and CDATA behavior.

## API Reference

### `SimpleRSS.parse(source, options = {})`

Parse RSS/Atom content from a string or IO object.

**Parameters:**
- `source` - String or IO object containing feed XML
- `options` - Hash of options
  - `:array_tags` - Array of tag symbols to collect as arrays

**Returns:** `SimpleRSS` instance

### `SimpleRSS.fetch(url, options = {})`

Fetch and parse a feed from a URL.

**Parameters:**
- `url` - Feed URL string
- `options` - Hash of options
  - `:timeout` - Request timeout in seconds
  - `:etag` - ETag from previous request (for conditional GET)
  - `:last_modified` - Last-Modified header from previous request
  - `:follow_redirects` - Follow redirects (default: true)
  - `:headers` - Hash of additional HTTP headers

**Returns:** `SimpleRSS` instance, or `nil` if 304 Not Modified

### Instance Methods

| Method | Description |
|--------|-------------|
| `#channel` / `#feed` | Returns self (for RSS/Atom style access) |
| `#items` / `#entries` | Array of parsed items |
| `#each` | Iterate over items (includes `Enumerable`) |
| `#[](index)` | Access item by index |
| `#latest(n = 10)` | Get n most recent items by date |
| `#to_json` | JSON string representation |
| `#to_hash` / `#as_json` | Hash representation |
| `#to_xml(format:)` | XML string (`:rss2` or `:atom`) |
| `#etag` | ETag header from fetch (if applicable) |
| `#last_modified` | Last-Modified header from fetch (if applicable) |
| `#source` | Original source XML string |

## Compatibility

- Ruby 3.1+
- No runtime dependencies

## Development

```bash
# Run tests
bundle exec rake test

# Run linter
bundle exec rubocop

# Type checking
bundle exec steep check

# Interactive console
bundle exec rake console
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes with tests
4. Ensure tests pass (`bundle exec rake test`)
5. Submit a pull request

## Authors

- [Lucas Carlson](mailto:lucas@rufy.com)
- [Herval Freire](mailto:hervalfreire@gmail.com)

Inspired by [Blagg](http://www.raelity.org/lang/perl/blagg) by Rael Dornfest.

## License

This library is released under the terms of the [GNU LGPL](LICENSE).
