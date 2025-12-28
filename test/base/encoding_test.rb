require_relative "../test_helper"

class EncodingTest < Test::Unit::TestCase
  def test_strings_are_utf8_encoded
    rss = SimpleRSS.parse(open(File.dirname(__FILE__) + "/../data/rss20.xml"))

    assert_equal Encoding::UTF_8, rss.title.encoding
    assert_equal Encoding::UTF_8, rss.link.encoding
    assert_equal Encoding::UTF_8, rss.description.encoding
  end

  def test_strings_without_percent_are_utf8_encoded
    # Issue #28: strings without '%' were returning ASCII-8BIT
    rss = SimpleRSS.parse(open(File.dirname(__FILE__) + "/../data/rss20.xml"))

    rss.items.each do |item|
      assert_equal Encoding::UTF_8, item.title.encoding, "Item title should be UTF-8"
      assert_equal Encoding::UTF_8, item.link.encoding, "Item link should be UTF-8"
    end
  end

  def test_utf8_content_preserved
    rss = SimpleRSS.parse(open(File.dirname(__FILE__) + "/../data/rss20_utf8.xml"))

    assert_equal Encoding::UTF_8, rss.title.encoding
    # Verify UTF-8 characters are preserved
    assert(rss.items.any? { |item| item.title && item.title.encoding == Encoding::UTF_8 })
  end

  def test_ascii_8bit_source_normalized_to_utf8
    # Issue #28: when source is ASCII-8BIT, output should still be UTF-8
    xml = <<~XML.b # .b forces ASCII-8BIT encoding
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>http://example.com</link>
          <description>A test feed</description>
          <item>
            <title>Test Item</title>
            <link>http://example.com/item</link>
          </item>
        </channel>
      </rss>
    XML

    assert_equal Encoding::ASCII_8BIT, xml.encoding, "Source should be ASCII-8BIT"

    rss = SimpleRSS.parse(xml)

    assert_equal Encoding::UTF_8, rss.title.encoding, "Title should be UTF-8"
    assert_equal Encoding::UTF_8, rss.link.encoding, "Link should be UTF-8"
    assert_equal Encoding::UTF_8, rss.items.first.title.encoding, "Item title should be UTF-8"
  end

  def test_consistent_encoding_with_and_without_percent
    # Issue #28: CGI.unescape returns UTF-8, but without '%' we got ASCII-8BIT
    xml_with_percent = <<~XML.b
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test%20Feed</title>
          <link>http://example.com</link>
          <description>Test</description>
        </channel>
      </rss>
    XML

    xml_without_percent = <<~XML.b
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>http://example.com</link>
          <description>Test</description>
        </channel>
      </rss>
    XML

    rss_with = SimpleRSS.parse(xml_with_percent)
    rss_without = SimpleRSS.parse(xml_without_percent)

    assert_equal rss_with.title.encoding, rss_without.title.encoding,
                 "Encoding should be consistent regardless of '%' in content"
    assert_equal Encoding::UTF_8, rss_without.title.encoding
  end
end
