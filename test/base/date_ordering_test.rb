require "test_helper"

class DateOrderingTest < Test::Unit::TestCase
  def setup
    @feed = SimpleRSS.parse(File.read(File.join(__dir__, "../data/mixed_dates.xml")))
  end

  def test_latest_uses_valid_fallbacks_and_preserves_equal_date_order
    assert_equal [
      "Updated first", "Updated second", "Fractional", "Published", "Publication",
      "Historical", "Missing first", "Blank", "Invalid"
    ], @feed.latest.map(&:title)
  end

  def test_latest_limits_results_without_changing_original_entries
    original = @feed.to_hash

    assert_equal ["Updated first", "Updated second", "Fractional"], @feed.latest(3).map(&:title)
    assert_equal [], @feed.latest(0)
    assert_same @feed.items[3], @feed.latest.first
    assert_equal original, @feed.to_hash
  end

  def test_latest_sorts_atom_entries_with_only_published_dates
    feed = SimpleRSS.parse <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Publication dates</title>
        <entry><title>Newer</title><published>2026-09-03T00:00:00Z</published></entry>
        <entry><title>Older</title><published>2026-09-01T00:00:00Z</published></entry>
      </feed>
    XML

    assert_equal %w[Newer Older], feed.latest.map(&:title)
  end

  def test_items_since_uses_valid_fallbacks_and_excludes_undated_entries
    assert_equal ["Fractional", "Updated first", "Published", "Updated second"],
                 @feed.items_since(Time.iso8601("2026-09-01T00:00:00Z")).map(&:title)
    assert_equal ["Fractional", "Updated first", "Updated second"],
                 @feed.items_since(Time.iso8601("2026-09-02T00:00:00Z")).map(&:title)
    assert_equal [], @feed.items_since(Time.iso8601("2026-09-04T00:00:00Z"))
  end

  def test_merge_sorts_dated_entries_before_undated_identified_entries
    assert_equal [
      "Updated first", "Updated second", "Fractional", "Published", "Publication",
      "Historical", "Blank", "Invalid", "Missing first"
    ], @feed.merge.map(&:title)
  end

  def test_merge_uses_fallback_dates_to_dedupe_and_keeps_unidentified_entries_last
    other_feed = SimpleRSS.parse <<~XML
      <rss version="2.0">
        <channel>
          <title>Other feed</title>
          <item>
            <guid>updated-first</guid>
            <title>Replacement</title>
            <pubDate>not-a-date</pubDate>
            <published>2026-09-04T00:00:00Z</published>
          </item>
          <item><title>Unidentified newest</title><pubDate>2030-01-01T00:00:00Z</pubDate></item>
        </channel>
      </rss>
    XML
    original = @feed.to_hash
    other_original = other_feed.to_hash

    assert_equal [
      "Replacement", "Updated second", "Fractional", "Published", "Publication",
      "Historical", "Blank", "Invalid", "Missing first", "Unidentified newest"
    ], SimpleRSS.merge(@feed, other_feed).map(&:title)
    assert_equal original, @feed.to_hash
    assert_equal other_original, other_feed.to_hash
  end

  def test_merge_keeps_the_first_duplicate_when_dates_are_equal
    other_feed = SimpleRSS.parse <<~XML
      <rss version="2.0">
        <channel>
          <title>Other feed</title>
          <item>
            <guid>updated-second</guid>
            <title>Later duplicate</title>
            <updated>2026-09-03T00:00:00.000000002Z</updated>
          </item>
        </channel>
      </rss>
    XML

    duplicates = @feed.merge(other_feed).select { |item| item[:guid] == "updated-second" }

    assert_equal ["Updated second"], duplicates.map(&:title)
  end
end
