require "test_helper"
require "feedbag"
require_relative "../support/http_server"

class FeedbagIntegrationTest < Test::Unit::TestCase
  include HTTPServer

  def test_feedbag_candidates_can_be_consumed_by_simple_rss
    html = '<html><head><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head></html>'
    xml = '<rss version="2.0"><channel><title>Example</title><item><title>Post</title></item></channel></rss>'
    responses = [[200, { "Content-Type" => "text/html" }, html], [200, { "Content-Type" => "application/rss+xml" }, xml]]
    with_server(responses) do |url, requests|
      candidates = Feedbag.find(url, open_timeout: 1, read_timeout: 1)
      assert_equal ["#{url}/feed.xml"], candidates
      assert_equal 1, requests.size
      feed = SimpleRSS.fetch(candidates.first, timeout: 1)
      assert_equal "Post", feed.normalized_entries.first.title
      assert_equal ["GET / HTTP/1.1", "GET /feed.xml HTTP/1.1"], requests.map(&:first)
    end
  end
end
