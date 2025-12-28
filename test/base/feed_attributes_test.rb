require "test_helper"

class FeedAttributesTest < Test::Unit::TestCase
  def setup
    # Add feed attribute tags before parsing
    SimpleRSS.feed_tags << :"channel#custom:version"
    SimpleRSS.feed_tags << :"feed#app:id"

    @rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/rss20_with_channel_attrs.xml")
    @atom = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/atom_with_feed_attrs.xml")
  end

  def teardown
    # Clean up added tags
    SimpleRSS.feed_tags.delete(:"channel#custom:version")
    SimpleRSS.feed_tags.delete(:"feed#app:id")
  end

  def test_rss20_channel_attribute
    assert_equal "2.0", @rss20.channel_custom_version
  end

  def test_atom_feed_attribute
    assert_equal "12345", @atom.feed_app_id
  end
end
