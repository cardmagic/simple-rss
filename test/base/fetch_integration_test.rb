require "test_helper"

# Integration tests that require network access
# These are skipped by default, run with NETWORK_TESTS=1
class FetchIntegrationTest < Test::Unit::TestCase
  def test_fetch_real_feed
    omit unless ENV["NETWORK_TESTS"]
    rss = SimpleRSS.fetch("https://feeds.bbci.co.uk/news/rss.xml", timeout: 10)
    assert_kind_of SimpleRSS, rss
    assert rss.title
    assert rss.items.any?
  end

  def test_fetch_stores_caching_headers
    omit unless ENV["NETWORK_TESTS"]
    rss = SimpleRSS.fetch("https://feeds.bbci.co.uk/news/rss.xml", timeout: 10)
    assert(rss.etag || rss.last_modified, "Expected ETag or Last-Modified header")
  end

  def test_fetch_follows_redirect
    omit unless ENV["NETWORK_TESTS"]
    rss = SimpleRSS.fetch("https://github.com/cardmagic/simple-rss/commits/master.atom", timeout: 10)
    assert_kind_of SimpleRSS, rss
  end
end
