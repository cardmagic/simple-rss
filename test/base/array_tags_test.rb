require "test_helper"

class ArrayTagsTest < Test::Unit::TestCase
  def setup
    @rss20 = SimpleRSS.parse(
      open(File.dirname(__FILE__) + "/../data/rss20.xml"),
      array_tags: [:category]
    )
    @rss20_no_array = SimpleRSS.parse(
      open(File.dirname(__FILE__) + "/../data/rss20.xml")
    )
  end

  def test_array_tag_returns_array
    assert_kind_of Array, @rss20.items.first.category
  end

  def test_array_tag_contains_all_values
    categories = @rss20.items.first.category
    assert_equal 2, categories.size
    assert_includes categories, "Programming"
    assert_includes categories, "Ruby"
  end

  def test_single_value_still_returns_array
    # Item with only one category should still return an array
    categories = @rss20.items[2].category
    assert_kind_of Array, categories
    assert_equal 1, categories.size
    assert_equal ["General"], categories
  end

  def test_without_array_tags_returns_string
    # Default behavior should return just the first/last match as a string
    assert_kind_of String, @rss20_no_array.items.first.category
  end
end
