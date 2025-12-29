require "test_helper"

class EnumerableTest < Test::Unit::TestCase
  def setup
    @rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/rss20.xml")
    @atom = SimpleRSS.parse open(File.dirname(__FILE__) + "/../data/atom.xml")
  end

  def test_includes_enumerable
    assert_includes SimpleRSS.included_modules, Enumerable
  end

  def test_each_iterates_over_items
    titles = @rss20.map { |item| item[:title] }
    assert_equal @rss20.items.map { |i| i[:title] }, titles
  end

  def test_each_returns_enumerator_without_block
    enumerator = @rss20.each
    assert_kind_of Enumerator, enumerator
    assert_equal @rss20.items.size, enumerator.count
  end

  def test_each_returns_self_with_block
    count = 0
    result = @rss20.each { |_item| count += 1 }
    assert_equal @rss20, result
    assert_equal @rss20.items.size, count
  end

  def test_enumerable_map
    titles = @rss20.map { |item| item[:title] }
    assert_equal @rss20.items.map { |i| i[:title] }, titles
  end

  def test_enumerable_select
    items_with_link = @rss20.select { |item| item[:link] }
    assert_equal @rss20.items.select { |i| i[:link] }, items_with_link
  end

  def test_enumerable_first
    assert_equal @rss20.items.first, @rss20.first
    assert_equal @rss20.items.first(3), @rss20.first(3)
  end

  def test_enumerable_count
    assert_equal @rss20.items.size, @rss20.count
  end

  def test_index_accessor
    assert_equal @rss20.items[0], @rss20[0]
    assert_equal @rss20.items[5], @rss20[5]
    assert_equal @rss20.items[-1], @rss20[-1]
  end

  def test_index_accessor_out_of_bounds
    assert_nil @rss20[100]
  end

  def test_latest_returns_sorted_items
    latest = @rss20.latest(3)
    assert_equal 3, latest.size

    dates = latest.map { |item| item[:pubDate] }
    assert_equal dates, dates.sort.reverse
  end

  def test_latest_default_count
    latest = @rss20.latest
    assert latest.size <= 10
  end

  def test_latest_with_atom_uses_updated
    latest = @atom.latest(1)
    assert_equal 1, latest.size
  end

  def test_latest_handles_missing_dates
    rss_with_missing_dates = SimpleRSS.parse <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <link>http://example.com</link>
          <item>
            <title>No Date</title>
          </item>
          <item>
            <title>Has Date</title>
            <pubDate>Wed, 24 Aug 2005 13:33:34 GMT</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    latest = rss_with_missing_dates.latest(2)
    assert_equal 2, latest.size
    assert_equal "Has Date", latest.first[:title]
    assert_equal "No Date", latest.last[:title]
  end
end
