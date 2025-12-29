# SimpleRSS

[![Gem Version](https://badge.fury.io/rb/simple-rss.svg)](https://badge.fury.io/rb/simple-rss)
[![CI](https://github.com/cardmagic/simple-rss/actions/workflows/ci.yml/badge.svg)](https://github.com/cardmagic/simple-rss/actions/workflows/ci.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL-blue.svg)](https://opensource.org/licenses/LGPL-3.0)

A simple, flexible, extensible, and liberal RSS and Atom reader for Ruby. Designed to be backwards compatible with Ruby's standard RSS parser while handling malformed feeds gracefully.

## Features

- Parses both RSS and Atom feeds
- Tolerant of malformed XML (regex-based parsing)
- Built-in URL fetching with conditional GET support (ETags, Last-Modified)
- JSON and XML serialization
- Extensible tag definitions
- Zero runtime dependencies

## What's New in 2.0

Version 2.0 is a major update with powerful new capabilities:

- **URL Fetching** - One-liner feed fetching with `SimpleRSS.fetch(url)`. Supports timeouts, custom headers, and automatic redirect following.

- **Conditional GET** - Bandwidth-efficient polling with ETag and Last-Modified support. Returns `nil` when feeds haven't changed (304 Not Modified).

- **JSON Serialization** - Export feeds with `to_json`, `to_hash`, and Rails-compatible `as_json`. Time objects serialize to ISO 8601.

- **XML Serialization** - Convert any parsed feed to clean RSS 2.0 or Atom XML with `to_xml(format: :rss2)` or `to_xml(format: :atom)`.

- **Array Tags** - Collect all occurrences of a tag (like multiple categories) with the `array_tags:` option.

- **Attribute Parsing** - Extract attributes from feed, item, and media tags using the `tag#attr` syntax.

- **UTF-8 Normalization** - All parsed content is automatically normalized to UTF-8 encoding.

- **Modern Ruby** - Full compatibility with Ruby 3.1 through 4.0, with RBS type annotations and Steep type checking.

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

### Collecting Multiple Values

By default, SimpleRSS returns only the first occurrence of each tag. To collect all values:

```ruby
# Collect all categories for each item
feed = SimpleRSS.parse(xml, array_tags: [:category])

item.category  # => ["tech", "programming", "ruby"]
```

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
