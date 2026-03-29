require "test_helper"

class FilteringAndValidationTest < Test::Unit::TestCase
  def setup
    @rss09 = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/rss09.rdf")
    @rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/rss20.xml")
    @atom = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/atom.xml")
  end

  def test_feed_type_for_known_formats
    assert_equal :rss1, @rss09.feed_type
    assert_equal :rss2, @rss20.feed_type
    assert_equal :atom, @atom.feed_type
  end

  def test_feed_type_unknown_for_non_standard_feed
    feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed>
        <title>Unknown Feed</title>
        <entry>
          <title>Post</title>
        </entry>
      </feed>
    XML

    assert_equal :unknown, feed.feed_type
  end

  def test_class_valid_returns_true_for_well_formed_feed
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Valid Feed</title>
          <link>http://example.com</link>
          <item>
            <title>Post</title>
          </item>
        </channel>
      </rss>
    XML

    assert_equal true, SimpleRSS.valid?(xml)
  end

  def test_class_valid_returns_false_for_invalid_feed
    invalid_xml = open(File.dirname(__FILE__) + "/../data/not-rss.xml").read

    assert_equal false, SimpleRSS.valid?(invalid_xml)
  end

  def test_instance_valid_requires_metadata_and_items
    valid_feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Valid Feed</title>
          <item>
            <title>Post</title>
          </item>
        </channel>
      </rss>
    XML

    invalid_feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <description>No title and no link</description>
          <item>
            <description>Body only</description>
          </item>
        </channel>
      </rss>
    XML

    empty_feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>No Items</title>
        </channel>
      </rss>
    XML

    assert_equal true, valid_feed.valid?
    assert_equal false, invalid_feed.valid?
    assert_equal false, empty_feed.valid?
  end

  def test_items_since_filters_by_date
    threshold = Time.parse("Wed Aug 24 13:30:00 UTC 2005")

    filtered = @rss20.items_since(threshold)

    assert_equal 1, filtered.size
    assert_operator filtered.first[:pubDate], :>, threshold
  end

  def test_items_by_category_matches_strings_and_arrays
    feed_with_string_category = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>String Category Feed</title>
          <item>
            <title>Ruby News</title>
            <category>Technology</category>
          </item>
          <item>
            <title>Sports News</title>
            <category>Sports</category>
          </item>
        </channel>
      </rss>
    XML

    feed_with_array_category = SimpleRSS.parse(
      <<~XML,
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Array Category Feed</title>
            <item>
              <title>Dev Update</title>
              <category>Technology</category>
              <category>Ruby</category>
            </item>
          </channel>
        </rss>
      XML
      array_tags: [:category]
    )

    string_results = feed_with_string_category.items_by_category("tech")
    array_results = feed_with_array_category.items_by_category("ruby")

    assert_equal 1, string_results.size
    assert_equal "Ruby News", string_results.first[:title]
    assert_equal 1, array_results.size
    assert_equal "Dev Update", array_results.first[:title]
  end

  def test_search_matches_title_description_summary_and_content
    feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Search Feed</title>
          <item>
            <title>Ruby Patterns</title>
            <description>Language design</description>
          </item>
          <item>
            <title>Other Topic</title>
            <description>Talks about BREAKING updates</description>
          </item>
          <item>
            <title>Third Topic</title>
            <summary>A quick ruby summary</summary>
          </item>
          <item>
            <title>Fourth Topic</title>
            <content>Deep dive into Ruby internals</content>
          </item>
        </channel>
      </rss>
    XML

    ruby_results = feed.search("ruby")
    breaking_results = feed.search("breaking")

    assert_equal 3, ruby_results.size
    assert_equal 1, breaking_results.size
    assert_equal "Other Topic", breaking_results.first[:title]
  end
end
