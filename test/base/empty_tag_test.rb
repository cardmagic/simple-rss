require_relative "../test_helper"
require "timeout"

class EmptyTagTest < Test::Unit::TestCase
  def setup
    @rss20 = SimpleRSS.parse(open(File.dirname(__FILE__) + "/../data/rss20.xml"))
  end

  def test_empty_item_tag_does_not_hang
    # Reproduces issue #16: 100% cpu and hanging process on blank item tag
    # Adding an empty tag should not cause regex catastrophic backtracking
    original_tags = SimpleRSS.item_tags.dup

    begin
      SimpleRSS.item_tags << :""

      # This should complete quickly, not hang
      Timeout.timeout(5) do
        rss = SimpleRSS.parse(open(File.dirname(__FILE__) + "/../data/rss20.xml"))
        assert_not_nil rss.items
      end
    ensure
      SimpleRSS.item_tags.replace(original_tags)
    end
  end

  def test_blank_item_tag_does_not_hang
    original_tags = SimpleRSS.item_tags.dup

    begin
      SimpleRSS.item_tags << :"   "

      Timeout.timeout(5) do
        rss = SimpleRSS.parse(open(File.dirname(__FILE__) + "/../data/rss20.xml"))
        assert_not_nil rss.items
      end
    ensure
      SimpleRSS.item_tags.replace(original_tags)
    end
  end

  def test_empty_feed_tag_does_not_hang
    original_tags = SimpleRSS.feed_tags.dup

    begin
      SimpleRSS.feed_tags << :""

      Timeout.timeout(5) do
        rss = SimpleRSS.parse(open(File.dirname(__FILE__) + "/../data/rss20.xml"))
        assert_not_nil rss.channel
      end
    ensure
      SimpleRSS.feed_tags.replace(original_tags)
    end
  end
end
