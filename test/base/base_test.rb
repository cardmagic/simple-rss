#!/bin/env ruby
# encoding: utf-8

require 'test_helper'
require 'pry'

class BaseTest < Test::Unit::TestCase
  def setup
    @rss_bbc = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/bbc.xml')
    @rss09 = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/rss09.rdf')
    @rss20 = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/rss20.xml')
    @media_rss = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/media_rss.xml')
    @atom = SimpleRSS.parse open(File.dirname(__FILE__) + '/../data/atom.xml')
  end
  
  def test_channel
    assert_equal @rss_bbc, @rss_bbc.channel
    assert_equal @rss09, @rss09.channel
    assert_equal @rss20, @rss20.channel
    assert_equal @atom, @atom.feed
  end
  
  def test_items
    assert_kind_of Array, @rss_bbc.items
    assert_kind_of Array, @rss09.items
    assert_kind_of Array, @rss20.items
    assert_kind_of Array, @atom.entries
  end
  
  def test_rss_bbc
    assert_equal 9, @rss_bbc.items.size
    assert_equal "BBCBrasil.com | Vídeos e Fotos", @rss_bbc.title.force_encoding("UTF-8")
    assert_equal "http://www.bbc.com/portuguese/full_all.xml", @rss_bbc.channel.link
    assert_equal "http://www.bbc.com/portuguese/noticias/2015/11/151102_nadador_atlantico_desafio_lgb", @rss_bbc.items.first.link
    assert_equal "http://www.bbc.com/portuguese/noticias/2015/11/151102_nadador_atlantico_desafio_lgb", @rss_bbc.items.first[:link]
    assert_equal Time.parse("2015-11-03 08:21:50 -0200"), @rss_bbc.items.first.pubDate
    assert_equal Time.parse("2015-11-05 07:33:38 -0200"), @rss_bbc.channel.lastBuildDate
    assert_not_nil @rss_bbc.items.first.full_text
  end

  def test_rss09
    assert_equal 10, @rss09.items.size
    assert_equal "Slashdot", @rss09.title
    assert_equal "http://slashdot.org/", @rss09.channel.link
    assert_equal "http://books.slashdot.org/article.pl?sid=05/08/29/1319236&amp;from=rss", @rss09.items.first.link
    assert_equal "http://books.slashdot.org/article.pl?sid=05/08/29/1319236&amp;from=rss", @rss09.items.first[:link]
    assert_equal Time.parse("2005-09-09 06:52:31 -0300"), @rss09.items.first.dc_date
    assert_equal Time.parse("Fri Sep 09 02:52:31 PDT 2005"), @rss09.channel.dc_date
    assert_nil @rss09.items.first.full_text
  end

  def test_media_rss
    assert_equal 20, @media_rss.items.size
    assert_equal "Uploads from herval", @media_rss.title
    assert_equal "http://www.flickr.com/photos/herval/", @media_rss.channel.link
    assert_equal "http://www.flickr.com/photos/herval/4671960608/", @media_rss.items.first.link
    assert_equal "http://www.flickr.com/photos/herval/4671960608/", @media_rss.items.first[:link]
    assert_equal "http://farm5.static.flickr.com/4040/4671960608_10cb945d5c_o.jpg", @media_rss.items.first.media_content_url
    assert_equal "image/jpeg", @media_rss.items.first.media_content_type
    assert_equal "3168", @media_rss.items.first.media_content_height
    assert_equal "4752", @media_rss.items.first.media_content_width
    assert_equal "Woof?", @media_rss.items.first.media_title
    assert_equal "http://farm5.static.flickr.com/4040/4671960608_954d2297bc_s.jpg", @media_rss.items.first.media_thumbnail_url
    assert_equal "75", @media_rss.items.first.media_thumbnail_height
    assert_equal "75", @media_rss.items.first.media_thumbnail_width
    assert_equal "herval", @media_rss.items.first.media_credit
    assert_equal "photographer", @media_rss.items.first.media_credit_role
    assert_equal "pets frodo", @media_rss.items.first.media_category
    assert_equal "urn:flickr:tags", @media_rss.items.first.media_category_scheme
    assert_nil @media_rss.items.first.full_text
  end
  
  def test_rss20
    assert_equal 10, @rss20.items.size
    assert_equal "Technoblog", @rss20.title
    assert_equal "http://tech.rufy.com", @rss20.channel.link
    assert_equal "http://feeds.feedburner.com/rufytech?m=68", @rss20.items.first.link
    assert_equal "http://feeds.feedburner.com/rufytech?m=68", @rss20.items.first[:link]
    assert_equal "This is an XML content feed. It is intended to be viewed in a newsreader or syndicated to another site.", @rss20.channel.feedburner_browserFriendly
    assert_nil @rss20.items.first.full_text
  end
  
  def test_atom
    assert_equal 1, @atom.entries.size
    assert_equal "dive into mark", @atom.title
    assert_equal "http://example.org/", @atom.feed.link
    assert_equal "http://example.org/2005/04/02/atom", @atom.entries.first.link
    assert_equal "http://example.org/2005/04/02/atom", @atom.entries.first[:link]
    assert_nil @atom.entries.first.full_text
  end
  
  def test_bad_feed
    assert_raise(SimpleRSSError) { SimpleRSS.parse(open(File.dirname(__FILE__) + '/../data/not-rss.xml')) }
  end
end
