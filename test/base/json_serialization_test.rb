require "test_helper"
require "json"

class JsonSerializationTest < Test::Unit::TestCase
  def setup
    @rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/rss20.xml")
    @atom = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/atom.xml")
  end

  def test_as_json_returns_hash
    result = @rss20.as_json
    assert_kind_of Hash, result
  end

  def test_as_json_includes_feed_title
    result = @rss20.as_json
    assert_equal "Technoblog", result[:title]
  end

  def test_as_json_includes_feed_link
    result = @rss20.as_json
    assert_equal "http://tech.rufy.com", result[:link]
  end

  def test_as_json_includes_items
    result = @rss20.as_json
    assert_kind_of Array, result[:items]
    assert_equal 10, result[:items].size
  end

  def test_as_json_items_have_title
    result = @rss20.as_json
    assert result[:items].first[:title].include?("some_string.starts_with?")
  end

  def test_as_json_converts_time_to_iso8601
    result = @rss20.as_json
    pub_date = result[:items].first[:pubDate]
    assert_kind_of String, pub_date
    assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, pub_date)
  end

  def test_as_json_works_with_atom
    result = @atom.as_json
    assert_equal "dive into mark", result[:title]
    assert_equal 1, result[:items].size
  end

  def test_to_json_returns_string
    result = @rss20.to_json
    assert_kind_of String, result
  end

  def test_to_json_is_valid_json
    result = @rss20.to_json
    parsed = JSON.parse(result)
    assert_kind_of Hash, parsed
  end

  def test_to_json_roundtrip
    json_string = @rss20.to_json
    parsed = JSON.parse(json_string, symbolize_names: true)

    assert_equal "Technoblog", parsed[:title]
    assert_equal 10, parsed[:items].size
    assert parsed[:items].first[:title].include?("some_string.starts_with?")
  end

  def test_as_json_excludes_nil_feed_tags
    result = @rss20.as_json
    # Feed tags that weren't in the source shouldn't appear
    refute result.key?(:subtitle)
    refute result.key?(:id)
  end

  def test_as_json_accepts_options_parameter
    # Should not raise, even if options aren't used yet
    result = @rss20.as_json(only: [:title])
    assert_kind_of Hash, result
  end
end
