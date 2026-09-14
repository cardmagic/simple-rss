# SimpleRSS

[![Gem Version](https://badge.fury.io/rb/simple-rss.svg)](https://badge.fury.io/rb/simple-rss)
[![CI](https://github.com/cardmagic/simple-rss/actions/workflows/ruby.yml/badge.svg)](https://github.com/cardmagic/simple-rss/actions/workflows/ruby.yml)
[![License: LGPL](https://img.shields.io/badge/License-LGPL-blue.svg)](https://opensource.org/licenses/LGPL-3.0)

A simple, flexible, extensible, and liberal RSS, Atom, and JSON Feed reader for Ruby. Designed to be backwards compatible with Ruby's standard RSS parser while handling malformed feeds gracefully.

## Features

- Parses RSS, Atom, and JSON Feed 1.0/1.1
- Tolerant of malformed XML (regex-based parsing)
- Built-in URL fetching with conditional GET support (ETags, Last-Modified)
- Explicit website feed discovery with request limits and destination policies
- JSON and XML serialization
- Extensible tag definitions
- No mandatory runtime gem dependencies; website discovery uses optional Nokogiri

## What's New in 2.3.0

- **Website discovery** - Find advertised RSS, Atom, and JSON feeds with
  `SimpleRSS.discover("example.com")`. Bare domains default to HTTPS, and
  requests have destination checks, timeouts, and size limits. Existing `fetch`
  callers can opt into these request controls with `network_policy`.
- **Normalized entries** - Use `normalized_entries` for consistent URLs, dates,
  content, authors, categories, and attachments while retaining raw feed data.
- **JSON Feed** - Parse JSON Feed 1.0 and 1.1 through the existing `parse` and
  `fetch` APIs, with the same normalized entry interface as RSS and Atom.
- **Parser fixes** - Correct Atom category terms and relation links, handle
  malformed dates during ordering, and accept self-closing empty feeds.

See the [2.3.0 release notes](CHANGELOG.md#230) for compatibility details.

## Earlier 2.x Features

See the [changelog](CHANGELOG.md) for release history and unreleased changes.

The 2.x releases add:

- **URL Fetching** - One-liner feed fetching with `SimpleRSS.fetch(url)`. Supports timeouts, custom headers, and automatic redirect following.

- **Conditional GET** - Bandwidth-efficient polling with ETag and Last-Modified support. Returns `nil` when feeds haven't changed (304 Not Modified).

- **JSON Serialization** - Export feeds with `to_json`, `to_hash`, and Rails-compatible `as_json`. Time objects serialize to ISO 8601.

- **XML Serialization** - Convert parsed XML feeds to clean RSS 2.0 or Atom XML with `to_xml(format: :rss2)` or `to_xml(format: :atom)`.

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

### Discovering Feeds from a Website

Add Nokogiri to applications that use discovery. Parsing and ordinary fetching
work without it:

```ruby
gem "simple-rss"
gem "nokogiri", ">= 1.16", "< 2"
```

`discover` uses Nokogiri's HTML5 parser, which requires CRuby. Missing HTML5
support raises `SimpleRSS::DiscoveryDependencyError` before making a request.

Bare domains and paths default to HTTPS: `SimpleRSS.discover("example.com/blog")`
requests `https://example.com/blog`. Protocol-relative inputs such as
`//example.com/blog` also use HTTPS. Explicit HTTP/HTTPS URLs are preserved;
other schemes remain unsupported. Include the scheme when specifying a port.
Discovery does not retry over HTTP if HTTPS fails.

```ruby
require "simple-rss"

candidates = SimpleRSS.discover("https://example.com/blog")
# => [{ url: "https://example.com/feed.xml", title: "News",
#       format: :rss, media_type: "application/rss+xml",
#       source: :html_link, verified: false }, ...]

candidate = candidates.first
if candidate
  feed = SimpleRSS.fetch(candidate.fetch(:url), network_policy: :public)
  feed.normalized_entries.each { |entry| puts entry.title || entry.identifier }
else
  puts "No advertised feeds found."
end
```

The application chooses among candidates. HTML results follow document order;
duplicate normalized URLs keep the first record. Fragments are removed, queries
are preserved, and relative/protocol-relative references use the final response
URL plus the first direct `head` base URL, when usable. Malformed, credentialed,
and non-HTTP link URLs are ignored. An invalid first base falls back to the
response URL; later base tags do not override it.

Only direct `head` links with an `alternate` relation token and a supported
media type are considered. Names, relation tokens, and media types are
case-insensitive; quoted/unquoted attributes and HTML entities follow HTML5
parsing. Supported types are `application/rss+xml`, `application/rdf+xml`,
`application/atom+xml`, `application/feed+json`, and `application/json`.
Scripts, comments, styles, templates, noscript content, and body links are
excluded. HTML parsing limits tree depth and attributes per element to 128.

| Candidate field | Meaning |
| --- | --- |
| `url` | Absolute HTTP/HTTPS URL, without a fragment |
| `title` | Advertised title or parsed feed title; may be nil |
| `format` | `:rss`, `:atom`, or `:json_feed` |
| `media_type` | Advertised supported type, or canonical type for a direct feed |
| `source` | `:html_link` for an advertisement, `:document` for a direct feed |
| `verified` | Whether this response was successfully parsed as a recognized feed |

An advertised type is a hint, and advertised destinations are not resolved or
fetched. They may be unreachable or prohibited by the application's policy.
Use the same network policy when fetching the chosen URL. A direct RSS, Atom,
or JSON Feed response returns one verified candidate at its final URL, even
when empty. Verification means SimpleRSS parsed it, not that it passed a full
standards validator. RSS/Atom root recognition and JSON structure take
precedence over server Content-Type. Empty self-closing RSS channels and Atom
feeds are also parseable.

Discovery makes one request plus permitted redirects. It never guesses paths,
executes scripts, fetches candidate feeds, follows pagination, or crawls links.
The [discovery example](examples/discover.rb) prints every candidate:

```bash
ruby -Ilib examples/discover.rb https://example.com/blog
```

#### Request limits and destination policy

Discovery defaults to a 10-second total HTTP/DNS budget, at most five redirects,
and a 2 MiB body budget. The byte budget covers both transferred and decompressed
body data, accumulated across the redirect chain. Streaming stops when either
budget is exceeded. Gzip and zlib-wrapped deflate are supported as single streams;
truncated streams, trailing compressed data, unsupported content encodings, and
partial responses fail explicitly. The time budget includes connection, TLS,
response reads, DNS resolution, and redirects; HTML/feed parsing follows the
bounded download.

```ruby
candidates = SimpleRSS.discover(
  "https://example.com/blog",
  timeout: 5,
  max_bytes: 1_048_576,
  max_redirects: 3,
  headers: { "User-Agent" => "Example Feed Reader", "Accept-Language" => "en" }
)
```

The default `network_policy: :public` checks every resolved address at every
hop and pins an approved address for the actual connection. Mixed public/private
DNS answers are rejected. TLS still verifies the original hostname; environment
proxies are disabled for policy-controlled requests. The conservative policy
excludes IPv4 private, loopback, link-local, shared, documentation, benchmark,
multicast, and reserved blocks. IPv6 permits global unicast `2000::/3`, excluding
special-purpose, documentation, and 6to4 ranges. Mapped/translated addresses and
other IPv6 ranges are excluded. See the
[IANA IPv4](https://www.iana.org/assignments/iana-ipv4-special-registry/) and
[IPv6 registries](https://www.iana.org/assignments/iana-ipv6-special-registry/).

For an application-controlled internal feed, provide a policy that returns true
for each permitted address:

```ruby
require "ipaddr"

internal_policy = lambda do |uri, address|
  uri.hostname == "feeds.internal.example" &&
    IPAddr.new("10.20.0.0/24").include?(address)
end
candidates = SimpleRSS.discover("https://feeds.internal.example/",
                                network_policy: internal_policy)
```

`network_policy: :unrestricted` deliberately allows any destination address while
retaining URL checks, pinning, time/byte limits, TLS verification, and redirect
rules. Keep this choice in application configuration. Policies receive a URI and
an IPAddr; invalid policy names raise `ArgumentError`.

On cross-origin redirects, custom headers are reduced to `Accept`,
`Accept-Language`, and `User-Agent`. Authorization, cookies, custom credential
headers, and conditional validators are removed and are not restored on a later
redirect back. Same-origin redirects retain them. A changed scheme or port is a
changed origin. URL credentials and unsupported destination schemes are rejected.
`Host`, proxy/connection/framing headers, `Range`, and `Accept-Encoding` are
transport-controlled and cannot be supplied in policy mode. `follow_redirects:
false` reports the initial redirect as an HTTP error during discovery.

Existing `fetch(url, options)` behavior is retained unless `network_policy` is
explicitly supplied. Opting in uses the same transport and defaults as discovery,
without requiring Nokogiri. `max_bytes` and `max_redirects` require a network
policy. Ordinary `fetch` still expects a feed and never performs discovery.
Parsing a supplied string or IO remains network-free.

| Outcome | Result |
| --- | --- |
| Successful HTML page with no supported advertisements | `[]` |
| Non-success HTTP status, including an unsolicited 304 | `SimpleRSS::HTTPError`, with `status_code` |
| Rejected URL or destination | `SimpleRSS::PolicyError` |
| Redirect loop or limit | `SimpleRSS::RedirectError` |
| Timeout | `SimpleRSS::RequestTimeout` |
| Body size limit | `SimpleRSS::ResponseTooLarge` |
| DNS, connection, TLS, compression, or HTTP transport failure | `SimpleRSS::RequestError` |
| Unrecognized or unparseable response, or HTML parser limit | `SimpleRSS::DiscoveryError` |
| Missing optional parser | `SimpleRSS::DiscoveryDependencyError` |

These errors inherit from `SimpleRSSError`. `fetch` retains its existing
`SimpleRSSError` for non-success HTTP statuses and returns nil on conditional
304 responses, including with an explicit network policy.

#### Feedbag alternative

Applications already using [Feedbag](https://github.com/damog/feedbag) can keep
it for discovery and pass its results to SimpleRSS:

```ruby
require "feedbag"
require "simple-rss"

Feedbag.find("https://example.com/blog", open_timeout: 10, read_timeout: 10).each do |url|
  feed = SimpleRSS.fetch(url, network_policy: :public)
  puts feed.title
end
```

Install the separate `feedbag` gem for this recipe; it is not a SimpleRSS runtime
dependency. The [Feedbag example](examples/feedbag.rb) and integration test cover
this workflow. Feedbag owns its discovery transport, URL heuristics, and error
handling; SimpleRSS's network policy applies only to the subsequent `fetch`.
The built-in API provides candidate metadata and explicit error/limit semantics
for applications that need them. Its acceptance corpus is in
[test/data/discovery.html](test/data/discovery.html), with discovery and transport
cases under `test/base/`.

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

Use `normalized_entries` when an importer or digest should handle RSS, Atom, and JSON Feed
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
against `source_url`. `fetch` always supplies the final response URL after
redirects, even if its options include a different or nil `source_url`;
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
reads all three formats without testing which one it received:

```bash
ruby -Ilib examples/digest.rb test/data/normalized_rss.xml
ruby -Ilib examples/digest.rb test/data/normalized_atom.xml
ruby -Ilib examples/digest.rb test/data/json_feed_1_1.json
```

The mapping follows the [Atom specification](https://www.rfc-editor.org/rfc/rfc4287.html),
[RSS specification](https://www.rssboard.org/rss-specification), and
[XML Base rules](https://www.w3.org/TR/xmlbase/). It is a tolerant extraction view,
not a standards validator. JSON Feed has the separate rules below.

### JSON Feed Parsing

JSON Feed 1.0 and 1.1 use the same `parse`, IO, and `fetch` entry points:

```ruby
require "simple-rss"
require "json"

source = JSON.generate(
  version: "https://jsonfeed.org/version/1.1",
  title: "Example",
  authors: [{ name: "Example Editor" }],
  items: [{
    id: "post:42",
    url: "https://example.com/posts/42",
    content_text: "Hello from JSON Feed",
    date_published: "2026-09-12T10:00:00Z",
    tags: ["ruby", "feeds"]
  }]
)
feed = SimpleRSS.parse(source)
entry = feed.normalized_entries.first

feed.feed_type        # => :json_feed
entry.identifier      # => "post:42"
entry.content_text    # => "Hello from JSON Feed"
entry.authors.first[:name] # => "Example Editor" (inherited)
entry.categories      # => ["ruby", "feeds"]
entry.published_at    # => a Time
entry.raw["id"]       # => "post:42"

feed = SimpleRSS.fetch("https://example.com/feed.json", timeout: 10)
feed.next_url         # Pagination metadata only; never fetched automatically
feed.raw_json         # Frozen original JSON document, including extensions
```

`fetch` detects the response body independently of Content-Type and sends an
Accept header covering all three formats. Custom headers can override Accept.
ETag, Last-Modified, redirects, and `nil` for HTTP 304 work as for XML feeds.

| Normalized field | JSON Feed mapping |
| --- | --- |
| `identifier` | `id`, preserved as an opaque string; numeric IDs become strings |
| `url`, `external_url` | Separate permalink and linkblog destination; no ID fallback |
| `published_at`, `updated_at` | `date_published`, `date_modified`, parsed separately as RFC 3339 |
| `content_html`, `content_text` | Corresponding fields, without decoding HTML entities or deriving one from the other |
| `summary`, `summary_type` | Plain text `summary`, with type `:text` |
| `image`, `banner_image` | Corresponding image URLs |
| `categories`, `category_details` | Nonblank `tags`, trimmed and deduplicated for categories; duplicate details retained |
| `authors` | Item authors, otherwise feed authors; includes `name`, `url`, `avatar`, and raw metadata |
| `language` | 1.1 item language, otherwise feed language |
| `attachments` | All attachments with URL, MIME type as `media_type`, title, size, duration, and raw metadata |

In 1.0, authors come from singular `author`. In 1.1, `authors` takes precedence
over deprecated `author` within the same object; an item's authors take
precedence over the feed's. An explicit empty `authors` array prevents
inheritance. The later `authors` and `language` fields are retained as raw data
but not normalized in a 1.0 document. Matching attachment titles preserve the
publisher's grouping of alternate formats. `external_url`, `image`,
`banner_image`, and `language` are additive normalized fields; XML entries
currently return `nil` for these fields.

Relative JSON URLs resolve against the supplied/fetched `source_url`, or the
JSON `feed_url` when no source URL is supplied. Per-call `source_url` overrides
still work. Missing bases and invalid URLs remain inspectable through `issues`
and raw data, using the same issue codes as XML. `content_base_url` is the item
URL when available, otherwise the source URL or feed URL. Content links are not
rewritten; no articles, attachments, hubs, or pagination URLs are fetched.

Parsing requires a supported version, string feed title, an items array, and
objects with nonblank string/numeric IDs and at least one string content field.
Titleless items and empty feeds are supported. Malformed JSON, missing required
fields, malformed author/tag/attachment structures, and wrong known field types
raise `SimpleRSSError` with a field path. When supplied, `expired` must be a
JSON boolean; strings such as `"false"` are rejected. Invalid required item data rejects the
whole feed; items are never assigned invented IDs or returned partially parsed.
Invalid optional dates and attachment numbers are preserved in raw data and
reported in `issues`, with `nil` normalized values. Dates are never substituted
with the current time. `effective_at`, `latest`, and `items_since` safely use a
valid modification date when publication is invalid or absent.

UTF-8 strings and readable IO accept ordinary leading JSON whitespace and one
UTF-8 BOM at the very start, before whitespace. Embedded or repeated BOMs are
rejected. `source` preserves the original input. This is a parser, not a complete
standards validator: it does not validate URL reachability, language tags, ID
uniqueness across updates, or publisher extension schemas.
`SimpleRSS.valid?(source)` reports parseability. A parsed JSON feed's instance
`valid?` is true, including an empty feed. XML retains its historical distinction:
the class method accepts parseable empty feeds, but instance `valid?` requires
items and a title or link.

For JSON feeds, `raw_json` is an immutable snapshot of the entire decoded
document with string keys. Each normalized entry's `raw` is its original JSON
item, also with string keys; `raw_xml` is `nil`. Original numeric IDs, date
strings, nested data, and unknown fields remain intact. Normalized entries are
immutable snapshots based on the original JSON, so edits to `items` do not
rewrite their normalized fields. Reordering or deduplication retains the source
association; inserting an unrelated item raises an error during normalization.

`items` remains an array of hashes with symbol keys and dot access. It retains
JSON fields and adds compatibility aliases: string `id`/`guid`, `link`,
`description`, `content`, category arrays, publication/update dates, and the first
attachment's enclosure metadata. Nested original JSON values are frozen.
XML-only tag configuration and `array_tags` do not affect JSON; passing XML
`mappings` to JSON normalization raises `ArgumentError`.

`as_json`, `to_hash`, and `to_json` export that Ruby object view: original feed
metadata plus compatibility fields and the current items, with times converted
to ISO 8601. These operations preserve extensions but are **not JSON Feed
exporters**. Use `raw_json` to inspect the original document. XML serialization
behavior is unchanged; calling `to_xml` on a JSON feed raises `SimpleRSSError`
until a separate conversion contract exists.

These mappings follow the [JSON Feed 1.0 specification](https://www.jsonfeed.org/version/1/)
and [JSON Feed 1.1 specification](https://www.jsonfeed.org/version/1.1/).

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

Convert parsed XML feeds to standard RSS 2.0 or Atom format:

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
