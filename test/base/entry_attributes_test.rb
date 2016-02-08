require File.dirname(__FILE__) + '/../test_helper'
class EntryAttributesTest < Test::Unit::TestCase
	def setup
	  SimpleRSS.item_tags << :'entry#gr:crawl-timestamp-msec'
	  
    @rss09 = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/rss09.rdf')
		@rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/rss20.xml')
		@media_rss = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/media_rss.xml')
		@atom = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/atom.xml')
	end
		
  def test_rss09
    assert_equal "1291841305234", @rss09.items.first[:'entry_gr_crawl-timestamp-msec']
  end
  
  def test_media_rss
    assert_equal "1291841305234", @media_rss.items.first[:'entry_gr_crawl-timestamp-msec']
  end
  
  def test_rss20
    assert_equal "1291841305234", @rss20.items.first[:'entry_gr_crawl-timestamp-msec']
  end
  
  def test_atom
    assert_equal "1291841305234", @atom.entries.first[:'entry_gr_crawl-timestamp-msec']
  end
end