require "test_helper"

class HashXmlSerializationTest < Test::Unit::TestCase
  def setup
    @rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/rss20.xml")
    @atom = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/atom.xml")
  end

  # to_hash tests

  def test_to_hash_returns_hash
    result = @rss20.to_hash
    assert_kind_of Hash, result
  end

  def test_to_hash_includes_feed_title
    result = @rss20.to_hash
    assert_equal "Technoblog", result[:title]
  end

  def test_to_hash_includes_items
    result = @rss20.to_hash
    assert_kind_of Array, result[:items]
    assert_equal 10, result[:items].size
  end

  def test_to_hash_is_alias_for_as_json
    assert_equal @rss20.as_json, @rss20.to_hash
  end

  # to_xml RSS 2.0 tests

  def test_to_xml_returns_string
    result = @rss20.to_xml
    assert_kind_of String, result
  end

  def test_to_xml_default_format_is_rss2
    result = @rss20.to_xml
    assert_match(/<rss version="2.0">/, result)
  end

  def test_to_xml_rss2_has_xml_declaration
    result = @rss20.to_xml(format: :rss2)
    assert_match(/^<\?xml version="1.0" encoding="UTF-8"\?>/, result)
  end

  def test_to_xml_rss2_has_channel
    result = @rss20.to_xml(format: :rss2)
    assert_match(/<channel>/, result)
    assert_match(%r{</channel>}, result)
  end

  def test_to_xml_rss2_has_title
    result = @rss20.to_xml(format: :rss2)
    assert_match(%r{<title>Technoblog</title>}, result)
  end

  def test_to_xml_rss2_has_link
    result = @rss20.to_xml(format: :rss2)
    assert_match(%r{<link>http://tech.rufy.com</link>}, result)
  end

  def test_to_xml_rss2_has_items
    result = @rss20.to_xml(format: :rss2)
    assert_match(/<item>/, result)
    assert_match(%r{</item>}, result)
  end

  def test_to_xml_rss2_item_has_title
    result = @rss20.to_xml(format: :rss2)
    assert_match(/<item>\n<title>/, result)
  end

  def test_to_xml_rss2_item_has_guid
    result = @rss20.to_xml(format: :rss2)
    assert_match(%r{<guid>http://tech.rufy.com/entry/\d+</guid>}, result)
  end

  def test_to_xml_rss2_escapes_special_characters
    rss = SimpleRSS.parse('<rss version="2.0"><channel><title>Test &amp; Title</title><item><title>Item &lt;1&gt;</title></item></channel></rss>')
    result = rss.to_xml(format: :rss2)
    assert_match(/&amp;/, result)
  end

  # to_xml Atom tests

  def test_to_xml_atom_format
    result = @atom.to_xml(format: :atom)
    assert_match(%r{<feed xmlns="http://www.w3.org/2005/Atom">}, result)
  end

  def test_to_xml_atom_has_title
    result = @atom.to_xml(format: :atom)
    assert_match(%r{<title>dive into mark</title>}, result)
  end

  def test_to_xml_atom_has_link
    result = @atom.to_xml(format: :atom)
    assert_match(%r{<link href="http://example.org/" rel="alternate"/>}, result)
  end

  def test_to_xml_atom_has_entries
    result = @atom.to_xml(format: :atom)
    assert_match(/<entry>/, result)
    assert_match(%r{</entry>}, result)
  end

  def test_to_xml_atom_entry_has_title
    result = @atom.to_xml(format: :atom)
    assert_match(%r{<entry>\n<title>Atom draft-07 snapshot</title>}, result)
  end

  # Error handling

  def test_to_xml_raises_on_unknown_format
    assert_raise(ArgumentError) { @rss20.to_xml(format: :unknown) }
  end

  def test_to_xml_error_message_includes_supported_formats
    error = assert_raise(ArgumentError) { @rss20.to_xml(format: :foo) }
    assert_match(/Supported: :rss2, :atom/, error.message)
  end

  # Round-trip tests

  def test_to_xml_rss2_can_be_reparsed
    xml = @rss20.to_xml(format: :rss2)
    reparsed = SimpleRSS.parse(xml)

    assert_equal "Technoblog", reparsed.title
    assert_equal 10, reparsed.items.size
  end

  def test_to_xml_atom_can_be_reparsed
    xml = @atom.to_xml(format: :atom)
    reparsed = SimpleRSS.parse(xml)

    assert_equal "dive into mark", reparsed.title
    assert_equal 1, reparsed.items.size
  end
end
