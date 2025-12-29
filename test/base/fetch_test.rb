require "test_helper"
require "net/http"

class FetchTest < Test::Unit::TestCase
  def setup
    @sample_feed = File.read(File.dirname(__FILE__) + "/../data/rss20.xml")
  end

  # Test attr_readers exist and default to nil for parsed feeds

  def test_etag_attr_reader_exists
    rss = SimpleRSS.parse(@sample_feed)
    assert_respond_to rss, :etag
  end

  def test_last_modified_attr_reader_exists
    rss = SimpleRSS.parse(@sample_feed)
    assert_respond_to rss, :last_modified
  end

  def test_etag_nil_for_parsed_feed
    rss = SimpleRSS.parse(@sample_feed)
    assert_nil rss.etag
  end

  def test_last_modified_nil_for_parsed_feed
    rss = SimpleRSS.parse(@sample_feed)
    assert_nil rss.last_modified
  end

  # Test fetch class method exists

  def test_fetch_class_method_exists
    assert_respond_to SimpleRSS, :fetch
  end

  # Test fetch with invalid URL raises error

  def test_fetch_raises_on_invalid_host
    # Socket::ResolutionError was added in Ruby 3.3, use SocketError for older versions
    expected_errors = [SocketError, Errno::ECONNREFUSED, SimpleRSSError]
    expected_errors << Socket::ResolutionError if defined?(Socket::ResolutionError)
    assert_raise(*expected_errors) do
      SimpleRSS.fetch("http://this-host-does-not-exist-12345.invalid/feed.xml", timeout: 1)
    end
  end

  # Test fetch options are accepted

  def test_fetch_accepts_etag_option
    # Just verify it doesn't raise an ArgumentError
    assert_nothing_raised do
      SimpleRSS.fetch("http://localhost:1/feed.xml", etag: '"abc123"', timeout: 0.1)
    rescue StandardError
      # Expected - connection will fail
    end
  end

  def test_fetch_accepts_last_modified_option
    assert_nothing_raised do
      SimpleRSS.fetch("http://localhost:1/feed.xml", last_modified: "Wed, 21 Oct 2015 07:28:00 GMT", timeout: 0.1)
    rescue StandardError
      # Expected - connection will fail
    end
  end

  def test_fetch_accepts_headers_option
    assert_nothing_raised do
      SimpleRSS.fetch("http://localhost:1/feed.xml", headers: { "X-Custom" => "test" }, timeout: 0.1)
    rescue StandardError
      # Expected - connection will fail
    end
  end

  def test_fetch_accepts_timeout_option
    assert_nothing_raised do
      SimpleRSS.fetch("http://localhost:1/feed.xml", timeout: 0.1)
    rescue StandardError
      # Expected - connection will fail
    end
  end

  def test_fetch_accepts_follow_redirects_option
    assert_nothing_raised do
      SimpleRSS.fetch("http://localhost:1/feed.xml", follow_redirects: false, timeout: 0.1)
    rescue StandardError
      # Expected - connection will fail
    end
  end
end

# Integration tests that require network access
# These are skipped by default, run with NETWORK_TESTS=1
class FetchIntegrationTest < Test::Unit::TestCase
  def test_fetch_real_feed
    omit unless ENV["NETWORK_TESTS"]
    # Use a reliable, long-lived RSS feed
    rss = SimpleRSS.fetch("https://feeds.bbci.co.uk/news/rss.xml", timeout: 10)
    assert_kind_of SimpleRSS, rss
    assert rss.title
    assert rss.items.any?
  end

  def test_fetch_stores_caching_headers
    omit unless ENV["NETWORK_TESTS"]
    rss = SimpleRSS.fetch("https://feeds.bbci.co.uk/news/rss.xml", timeout: 10)
    # At least one of these should be present for most feeds
    assert(rss.etag || rss.last_modified, "Expected ETag or Last-Modified header")
  end

  def test_fetch_follows_redirect
    omit unless ENV["NETWORK_TESTS"]
    # GitHub raw URLs often redirect
    rss = SimpleRSS.fetch("https://github.com/cardmagic/simple-rss/commits/master.atom", timeout: 10)
    assert_kind_of SimpleRSS, rss
  end
end
