require "test_helper"

class FeedMergingAndDiffingTest < Test::Unit::TestCase
  def setup
    @feed_one = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Feed One</title>
          <item>
            <guid>shared-guid</guid>
            <title>Shared (older)</title>
            <pubDate>Mon, 01 Jan 2024 10:00:00 UTC</pubDate>
          </item>
          <item>
            <guid>one-guid</guid>
            <title>Only One</title>
            <pubDate>Mon, 01 Jan 2024 11:00:00 UTC</pubDate>
          </item>
          <item>
            <title>Unidentified One</title>
          </item>
        </channel>
      </rss>
    XML

    @feed_two = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Feed Two</title>
          <item>
            <guid>shared-guid</guid>
            <title>Shared (newer)</title>
            <pubDate>Mon, 01 Jan 2024 12:00:00 UTC</pubDate>
          </item>
          <item>
            <link>https://example.com/two-only</link>
            <title>Only Two</title>
            <pubDate>Mon, 01 Jan 2024 13:00:00 UTC</pubDate>
          </item>
          <item>
            <title>Unidentified Two</title>
          </item>
        </channel>
      </rss>
    XML
  end

  def test_merge_dedupes_and_sorts_newest_first
    merged = @feed_one.merge(@feed_two)
    titles = merged.map { |item| item[:title] }

    assert_equal [
      "Only Two",
      "Shared (newer)",
      "Only One",
      "Unidentified One",
      "Unidentified Two"
    ], titles
  end

  def test_class_merge_combines_multiple_feeds
    merged = SimpleRSS.merge(@feed_one, @feed_two)

    assert_equal 5, merged.size
    assert_equal "Only Two", merged.first[:title]
  end

  def test_diff_reports_added_and_removed_items
    old_feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Old Feed</title>
          <item>
            <guid>stay</guid>
            <title>Stay</title>
          </item>
          <item>
            <guid>remove</guid>
            <title>Remove</title>
          </item>
        </channel>
      </rss>
    XML

    new_feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>New Feed</title>
          <item>
            <guid>stay</guid>
            <title>Stay</title>
          </item>
          <item>
            <guid>add</guid>
            <title>Add</title>
          </item>
        </channel>
      </rss>
    XML

    diff = old_feed.diff(new_feed)

    assert_equal(["Add"], diff[:added].map { |item| item[:title] })
    assert_equal(["Remove"], diff[:removed].map { |item| item[:title] })
  end

  def test_dedupe_mutates_items_and_keeps_unidentified_entries
    feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Dedupe Feed</title>
          <item>
            <guid>duplicate</guid>
            <title>First duplicate</title>
          </item>
          <item>
            <guid>duplicate</guid>
            <title>Second duplicate</title>
          </item>
          <item>
            <title>Unidentified One</title>
          </item>
          <item>
            <title>Unidentified Two</title>
          </item>
        </channel>
      </rss>
    XML

    result = feed.dedupe

    assert_same feed, result
    assert_equal(["First duplicate", "Unidentified One", "Unidentified Two"], feed.items.map { |item| item[:title] })
  end
end
