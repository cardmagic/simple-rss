require "test_helper"
require "json"
require "stringio"

class JsonFeedTest < Test::Unit::TestCase
  def test_parses_json_feed_through_the_public_api
    source = JSON.generate(version: "https://jsonfeed.org/version/1.1", title: "Example",
                           items: [{ id: "opaque:%2F:001", url: "https://example.com/1", content_text: "Hello" }])
    feed = SimpleRSS.parse(source)
    entry = feed.normalized_entries.first

    assert_equal :json_feed, feed.feed_type
    assert_equal "Example", feed.title
    assert_equal "opaque:%2F:001", entry.identifier
    assert_equal "https://example.com/1", entry.url
    assert_equal "Hello", entry.content_text
  end

  def test_accepts_an_empty_json_feed
    source = JSON.generate(version: "https://jsonfeed.org/version/1", title: "Example", items: [])
    feed = SimpleRSS.parse(StringIO.new(source))

    assert_empty feed.items
    assert_empty feed.normalized_entries
    assert SimpleRSS.valid?(source)
    assert feed.valid?
  end

  def test_expired_accepts_only_booleans_when_present
    assert_nil parse_items([]).expired
    [true, false].each do |value|
      feed = parse_items([], expired: value)
      assert_equal value, feed.expired
      assert_equal value, feed.raw_json["expired"]
      assert_equal value, feed.to_hash[:expired]
    end
    ["false", "true", 0, 1, nil, [], {}].each do |value|
      error = assert_raise(SimpleRSSError) { parse_items([], expired: value) }
      assert_include error.message, "feed.expired must be a boolean"
    end
  end

  def test_spec_fixtures_preserve_feed_metadata_and_extensions
    %w[1 1_1].each do |version|
      feed = fixture(version)
      assert_equal "A feed of examples", feed.description
      assert_equal "https://example.com/", feed.link
      assert_equal "https://example.com/", feed.home_page_url
      assert_equal "https://example.com/feed.json", feed.feed_url
      assert_equal "https://example.com/older.json", feed.next_url
      assert_equal "https://example.com/icon.png", feed.icon
      assert_equal "https://example.com/favicon.png", feed.favicon
      assert_equal true, feed.expired
      assert_equal "WebSub", feed.hubs.first["type"]
      assert_equal "Subscribe with a feed reader.", feed.user_comment
      assert_equal [1, 2], feed.raw_json["_publisher"]["sequence"]
      assert_equal "original", feed.normalized_entries.first.raw["_extension"]["value"]
    end
  end

  def test_rss_atom_and_json_share_normalized_core_fields
    entries = %w[rss atom].map do |format|
      SimpleRSS.parse(File.read(File.join(__dir__, "../data/normalized_#{format}.xml"))).normalized_entries.first
    end
    entries << fixture("1_1").normalized_entries.first
    entries.each do |entry|
      assert_equal "opaque:%2F:001", entry.identifier
      assert_equal "Ruby & feeds", entry.title
      assert_equal "https://example.com/blog/article?one=1&two=2", entry.url
      assert_equal Time.utc(2026, 9, 12, 10), entry.published_at
      assert_equal Time.utc(2026, 9, 13, 11), entry.updated_at
      assert_equal "<p>Full &amp; complete.</p>", entry.content_html
      assert_equal %w[ruby feeds], entry.categories
      assert_equal(["https://example.com/audio/one.mp3", "https://example.com/images/two.png"], entry.attachments.map { |attachment| attachment[:url] })
      assert_equal([1234, 4321], entry.attachments.map { |attachment| attachment[:size_in_bytes] })
    end
  end

  def test_normalizes_json_specific_fields_without_losing_associations
    entry = fixture("1_1").normalized_entries.first
    assert_equal "Full & complete.", entry.content_text
    assert_equal "A summary.", entry.summary
    assert_equal :text, entry.summary_type
    assert_equal "https://example.org/original", entry.external_url
    assert_equal "https://example.com/image.png", entry.image
    assert_equal "https://example.com/banner.png", entry.banner_image
    assert_equal "en", entry.language
    assert_equal(%w[alternate related], entry.links.map { |link| link[:rel] })
    assert_equal ["ruby", "feeds", "ruby", " "], entry.raw["tags"]
    assert_equal 3, entry.category_details.size
    assert_equal(%w[Episode Cover], entry.attachments.map { |attachment| attachment[:title] })
    assert_equal(%w[audio/mpeg image/png], entry.attachments.map { |attachment| attachment[:media_type] })
    assert_equal 62.5, entry.attachments.first[:duration_in_seconds]
    assert_equal false, entry.attachments.first[:raw]["_codec"]["lossless"]
    assert_equal "date_published", entry.field_sources[:published_at]
    assert_empty entry.issues
    assert_nil entry.raw_xml
  end

  def test_authors_inherit_and_item_authors_take_precedence
    %w[1 1_1].each do |version|
      inherited = fixture(version).normalized_entries.first
      assert_equal(["Example Editor"], inherited.authors.map { |author| author[:name] })
      assert_equal "https://example.com/avatar.png", inherited.authors.first[:avatar]
      assert_equal "editor", inherited.authors.first[:raw]["_profile"]["role"]
    end
    feed = parse_items([{ id: "1", content_text: "Hello", authors: [{ name: "First" }, { url: "https://example.com/second" }],
                          author: { name: "Legacy" }, language: "fr" }], authors: [{ name: "Feed" }], language: "en")
    entry = feed.normalized_entries.first
    assert_equal(["First", nil], entry.authors.map { |author| author[:name] })
    assert_equal "https://example.com/second", entry.authors.last[:url]
    assert_equal "authors", entry.field_sources[:authors]
    assert_equal "fr", entry.language
    assert_equal "Legacy", entry.raw["author"]["name"]
  end

  def test_singular_author_and_empty_authors_have_deliberate_precedence
    entry = parse_items([{ id: "1", content_text: "Hello", author: { name: "Item" } }], authors: [{ name: "Feed" }]).normalized_entries.first
    assert_equal(["Item"], entry.authors.map { |author| author[:name] })
    entry = parse_items([{ id: "1", content_text: "Hello", authors: [], author: { name: "Legacy" } }], authors: [{ name: "Feed" }]).normalized_entries.first
    assert_empty entry.authors
    entry = parse_items([{ id: "1", content_text: "Hello" }], author: { name: "Legacy" }, authors: [{ name: "Current" }]).normalized_entries.first
    assert_equal(["Current"], entry.authors.map { |author| author[:name] })
  end

  def test_version_one_ignores_later_version_fields_but_retains_them
    feed = parse_items([{ id: "1", content_text: "Hello", authors: "unknown", language: 12 }],
                       version: "https://jsonfeed.org/version/1", author: { name: "Legacy" }, authors: "unknown", language: 12)
    entry = feed.normalized_entries.first
    assert_equal(["Legacy"], entry.authors.map { |author| author[:name] })
    assert_nil entry.language
    assert_equal "unknown", entry.raw["authors"]
    assert_equal 12, feed.raw_json["language"]
  end

  def test_titleless_content_is_not_decoded_or_synthesized
    entry = parse_items([{ id: " x:%2F&=1 ", content_text: "<b>&amp; 😀</b>" }]).normalized_entries.first
    assert_nil entry.title
    assert_nil entry.url
    assert_nil entry.content_html
    assert_nil entry.summary
    assert_equal " x:%2F&=1 ", entry.identifier
    assert_equal "<b>&amp; 😀</b>", entry.content_text
    assert_equal "", parse_items([{ id: "empty", content_text: "" }]).normalized_entries.first.content_text
  end

  def test_numeric_identifiers_are_coerced_only_in_the_item_view
    feed = parse_items([{ id: 42, content_text: "Hello" }, { id: 1.5, content_html: "<p>Hi</p>" }])
    assert_equal ["42", "1.5"], feed.map(&:id)
    assert_equal ["42", "1.5"], feed.normalized_entries.map(&:identifier)
    assert_equal 42, feed.raw_json["items"].first["id"]
    assert_equal 42, feed.normalized_entries.first.raw["id"]
  end

  def test_invalid_dates_are_inspectable_and_do_not_break_effective_date_helpers
    feed = parse_items([
                         { id: "invalid", content_text: "One", date_published: "not a date", date_modified: "2026-09-13T11:00:00Z" },
                         { id: "old", content_text: "Two", date_published: "1960-01-01T00:00:00Z" },
                         { id: "undated", content_text: "Three", date_published: { bad: true }, date_modified: "2026-02-30T00:00:00Z" }
                       ])
    first, old, undated = feed.normalized_entries
    assert_nil first.published_at
    assert_equal Time.utc(2026, 9, 13, 11), first.effective_at
    assert_equal "not a date", first.raw["date_published"]
    assert_equal :invalid_date, first.issues.first[:code]
    assert_equal :published_at, first.issues.first[:field]
    assert_equal "date_published", first.issues.first[:source]
    assert_nil old.updated_at
    assert_nil undated.effective_at
    assert_equal 2, undated.issues.size
    assert_equal %w[invalid old undated], feed.latest.map(&:id)
    assert_equal ["invalid"], feed.items_since(Time.utc(2020)).map(&:id)
    %w[2026-09-12 tomorrow 2026-09-12T10:00:00 2026-09-12T25:00:00Z].each do |value|
      entry = parse_items([{ id: "1", content_text: "Hi", date_published: value }]).normalized_entries.first
      assert_nil entry.published_at, value
      assert_equal :invalid_date, entry.issues.first[:code]
    end
  end

  def test_attachment_numeric_recovery_preserves_original_values
    feed = parse_items([{ id: "1", content_text: "Hello", attachments: [
                         { url: "https://example.com/one", mime_type: "audio/mpeg", title: "Episode", size_in_bytes: "big", duration_in_seconds: -1 },
                         { url: "https://example.com/two", mime_type: "audio/ogg", title: "Episode", size_in_bytes: 0, duration_in_seconds: 0 }
                       ] }])
    entry = feed.normalized_entries.first
    assert_nil entry.attachments.first[:size_in_bytes]
    assert_nil entry.attachments.first[:duration_in_seconds]
    assert_equal [0, 0], entry.attachments.last.values_at(:size_in_bytes, :duration_in_seconds)
    assert_equal "big", entry.attachments.first[:raw]["size_in_bytes"]
    assert_equal(%w[Episode Episode], entry.attachments.map { |attachment| attachment[:title] })
    assert_equal(["attachments[0].size_in_bytes", "attachments[0].duration_in_seconds"], entry.issues.map { |issue| issue[:source] })
  end

  def test_rfc3339_rejects_out_of_range_clock_and_offset_components
    invalid = %w[
      2026-09-01T24:00:00Z 2026-09-01T24:01:00Z 2026-09-01T12:60:00Z
      2026-09-01T00:00:00+25:00 2026-09-01T00:00:00-24:00
      2026-09-01T00:00:00+00:60 2026-09-01T00:00:00-00:99
    ]
    invalid.each do |value|
      feed = parse_items([{ id: "1", content_text: "Hi", date_published: value, date_modified: value }])
      entry = feed.normalized_entries.first
      assert_nil entry.published_at, value
      assert_nil entry.updated_at, value
      assert_equal(%w[date_published date_modified], entry.issues.map { |issue| issue[:source] })
      assert_equal value, entry.raw["date_published"]
      assert_empty feed.items_since(Time.utc(2026))
    end
  end

  def test_rfc3339_accepts_boundary_offsets_and_uses_gregorian_dates
    expected = {
      "2026-09-01T23:59:59.125+23:59" => Time.utc(2026, 9, 1, 0, 0, 59.125),
      "2026-09-01t00:00:00-23:59" => Time.utc(2026, 9, 1, 23, 59),
      "1582-10-10T00:00:00Z" => Time.utc(1582, 10, 10)
    }
    expected.each do |value, time|
      entry = parse_items([{ id: "1", content_text: "Hi", date_published: value }]).normalized_entries.first
      assert_equal time, entry.published_at
      assert_empty entry.issues
    end
    entry = parse_items([{ id: "1", content_text: "Hi", date_published: "1500-02-29T00:00:00Z" }]).normalized_entries.first
    assert_nil entry.published_at
    assert_equal :invalid_date, entry.issues.first[:code]
  end

  def test_raw_and_serialized_representations_are_explicit_and_immutable
    feed = fixture("1_1")
    before = feed.to_json
    entry = feed.normalized_entries.first
    assert_equal before, feed.to_json
    assert_equal JSON.parse(before), JSON.parse(JSON.generate(feed.as_json))
    assert_equal feed.as_json, feed.to_hash
    assert_equal "2026-09-12T10:00:00+00:00", feed.to_hash[:items].first[:pubDate]
    assert_equal "2026-09-12T10:00:00Z", feed.to_hash[:items].first[:date_published]
    assert_equal [1, 2], feed.to_hash[:_publisher]["sequence"]
    assert_equal "original", JSON.parse(before)["items"].first["_extension"]["value"]
    assert_raise(FrozenError) { feed.raw_json["_publisher"]["sequence"] << 3 }
    assert_raise(FrozenError) { entry.raw["_extension"]["value"].replace("changed") }
    assert_raise(FrozenError) { entry.authors.first[:raw]["name"].replace("changed") }
    assert_raise(SimpleRSSError) { feed.to_xml }
    assert_raise(SimpleRSSError) { feed.to_xml(format: :atom) }
    assert_raise(ArgumentError) { feed.normalized_entries(mappings: { content_text: "custom" }) }
  end

  def test_legacy_helpers_and_dedupe_retain_the_original_entry_context
    feed = fixture("1_1")
    assert_equal feed.first, feed.search("Full").first
    assert_equal feed.first, feed.items_by_category("RUBY").first
    assert feed.first.has_media?
    assert_equal "https://example.com/audio/one.mp3", feed.enclosures.first[:url]
    assert_include feed.images, "https://example.com/image.png"
    feed.items << feed.first
    assert_equal 1, feed.dedupe.items.size
    assert_equal "opaque:%2F:001", feed.normalized_entries.first.identifier
    feed.items << { id: "unrelated" }
    assert_raise(SimpleRSSError) { feed.normalized_entries }
  end

  def test_utf8_bom_whitespace_and_readable_binary_io
    source = JSON.generate(version: "https://jsonfeed.org/version/1.1", title: "😀", items: [])
    [source, " \r\n\t#{source}", "\uFEFF \n#{source}"].each do |body|
      feed = SimpleRSS.parse(StringIO.new(body.b))
      assert_equal "😀", feed.title
      assert_equal body.b, feed.source
    end
    assert_raise(SimpleRSSError) { SimpleRSS.parse(" \uFEFF#{source}") }
    assert_raise(SimpleRSSError) { SimpleRSS.parse("\uFEFF\uFEFF#{source}") }
  end

  def test_invalid_utf8_is_rejected_before_exposing_feed_data
    source = JSON.generate(version: "https://jsonfeed.org/version/1.1", title: "Example", items: [{ id: "1", content_text: "payload" }])
    ["\xFF".b, "\xC0\x80".b, "\xE2\x82".b].each do |invalid|
      body = source.b.sub("payload", invalid)
      [body, StringIO.new(body)].each do |input|
        error = assert_raise(SimpleRSSError) { SimpleRSS.parse(input) }
        assert_include error.message, "invalid UTF-8"
      end
      assert_false SimpleRSS.valid?(body)
    end
  end

  def test_overflowing_json_numbers_cannot_collapse_identifiers_or_break_serialization
    sources = [
      '{"version":"https://jsonfeed.org/version/1.1","title":"QA","items":[{"id":1e999,"content_text":"One"},{"id":2e999,"content_text":"Two"}]}',
      '{"version":"https://jsonfeed.org/version/1.1","title":"QA","items":[],"_extension":{"numbers":[-1e999]}}',
      '{"version":"https://jsonfeed.org/version/1.1","title":"QA","items":[{"id":"one","content_text":"One","attachments":[{"url":"https://example.com/audio","mime_type":"audio/mpeg","size_in_bytes":1e999}]}]}'
    ]
    sources.each do |source|
      error = assert_raise(SimpleRSSError) { SimpleRSS.parse(source) }
      assert_include error.message, "number exceeds the supported range"
      assert_false SimpleRSS.valid?(source)
    end
    identifier = 10**100
    feed = parse_items([{ id: identifier, content_text: "Large integer" }], _number: 1.5)
    assert_equal identifier.to_s, feed.normalized_entries.first.identifier
    assert_equal identifier, feed.raw_json["items"].first["id"]
    assert_equal 1.5, JSON.parse(feed.to_json)["_number"]
  end

  def test_invalid_json_and_structures_raise_library_errors
    ['{"version":', "[]", "null", "42", "true", '"hello"',
     '{"description":"<channel><item>not XML</item></channel>"}'].each do |source|
      assert_raise(SimpleRSSError, source) { SimpleRSS.parse(source) }
      assert_equal false, SimpleRSS.valid?(source)
    end
    [{ version: "https://jsonfeed.org/version/2" }, { version: nil }, { title: nil }, { items: nil },
     { items: {} }, { home_page_url: [] }, { authors: {} }, { authors: [{}] }, { author: false },
     { hubs: [nil] }, { hubs: [{ type: "WebSub" }] }].each do |override|
      assert_raise(SimpleRSSError, override.inspect) { parse_items([], **override) }
    end
    [nil, [], {}, { id: "1" }, { id: nil, content_text: "Hi" }, { id: [], content_text: "Hi" },
     { id: true, content_text: "Hi" }, { id: " ", content_text: "Hi" },
     { id: "1", content_text: 1 }, { id: "1", content_text: "Hi", tags: {} },
     { id: "1", content_text: "Hi", tags: [false] }, { id: "1", content_text: "Hi", authors: [nil] },
     { id: "1", content_text: "Hi", attachments: [nil] },
     { id: "1", content_text: "Hi", attachments: [{ url: "https://example.com/file" }] }].each do |item|
      error = assert_raise(SimpleRSSError, item.inspect) { parse_items([item]) }
      assert_include error.message, "items[0]"
    end
  end

  def test_format_dispatch_preserves_tolerant_xml_prefixes
    source = 'Unexpected prefix <rss version="2.0"><channel><title>Example</title><item><title>Post</title></item></channel></rss>'
    assert_equal "Post", SimpleRSS.parse(source).first.title
    source = JSON.generate("<channel><title>Not an XML feed</title><item>Wrong</item></channel>")
    assert_raise(SimpleRSSError) { SimpleRSS.parse(source) }
  end

  def test_blank_urls_never_become_feed_urls
    entry = parse_items([{ id: "1", url: " ", image: "", content_text: "Hi" }], feed_url: "https://example.com/feed.json").normalized_entries.first
    assert_nil entry.url
    assert_nil entry.image
  end

  def test_xml_behavior_and_configuration_remain_unchanged
    source = '<rss version="2.0"><channel><title>Empty</title></channel></rss>'
    tags = [SimpleRSS.feed_tags.dup, SimpleRSS.item_tags.dup]
    feed = SimpleRSS.parse(source)
    before = [feed.to_json, feed.to_hash, feed.to_xml]
    fixture("1_1").normalized_entries
    assert_equal before, [feed.to_json, feed.to_hash, feed.to_xml]
    assert_equal tags, [SimpleRSS.feed_tags, SimpleRSS.item_tags]
    assert_nil feed.raw_json
    assert_equal false, feed.valid?
    assert SimpleRSS.valid?(source)
  end

  def test_relative_and_invalid_urls_are_preserved_with_normalization_issues
    feed = parse_items([{ id: "relative", url: "article", external_url: "bad space", content_text: "Hi", image: "image.png" }])
    entry = feed.normalized_entries.first
    assert_equal "article", entry.url
    assert_equal(%i[relative_url_without_base invalid_url relative_url_without_base], entry.issues.map { |issue| issue[:code] })
    entry = feed.normalized_entries(source_url: "https://example.com/blog/feed.json").first
    assert_equal "https://example.com/blog/article", entry.url
    assert_equal "https://example.com/blog/image.png", entry.image
    assert_equal "bad space", entry.external_url
    assert_equal "article", entry.raw["url"]
    assert_equal "https://example.com/blog/article", entry.content_base_url
  end

  private

  def fixture(version)
    SimpleRSS.parse(File.read(File.join(__dir__, "../data/json_feed_#{version}.json")))
  end

  def parse_items(items, **fields)
    source = { version: "https://jsonfeed.org/version/1.1", title: "Example", items: items }.merge(fields)
    SimpleRSS.parse(JSON.generate(source))
  end
end
