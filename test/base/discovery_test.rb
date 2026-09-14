require "test_helper"
require_relative "../support/http_server"

class DiscoveryTest < Test::Unit::TestCase
  include HTTPServer

  def test_discovers_advertised_feeds_without_fetching_them
    html = '<html><head><link rel="alternate" type="application/rss+xml" title="News" href="/feed.xml"></head></html>'
    with_server([[200, { "Content-Type" => "text/html" }, html]]) do |url, requests|
      candidates = SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1)
      assert_equal [{ url: "#{url}/feed.xml", title: "News", format: :rss, media_type: "application/rss+xml", source: :html_link, verified: false }], candidates
      assert_equal 1, requests.size
    end
  end

  def test_acceptance_corpus_preserves_formats_order_titles_and_distinct_queries
    html = File.read(File.join(__dir__, "../data/discovery.html"))
    with_server([[200, { "Content-Type" => "text/html; charset=utf-8" }, html]]) do |url, requests|
      candidates = SimpleRSS.discover("#{url}/blog/index.html", network_policy: :unrestricted, timeout: 1)
      assert_equal(["news.xml?edition=1&lang=en", "atom.xml", "feed.json", "legacy.json", "feed.rdf", "news.xml?edition=2&lang=en"], candidates.map { |candidate| candidate[:url].delete_prefix("#{url}/syndication/") })
      assert_equal(%i[rss atom json_feed json_feed rss rss], candidates.map { |candidate| candidate[:format] })
      assert_equal "News & updates", candidates.first[:title]
      assert_equal "application/rss+xml", candidates.first[:media_type]
      assert_equal [false], candidates.map { |candidate| candidate[:verified] }.uniq
      assert_equal [:html_link], candidates.map { |candidate| candidate[:source] }.uniq
      assert_equal 1, requests.size
    end
  end

  def test_direct_empty_feeds_are_verified_without_instance_valid
    sources = {
      rss: '<rss version="2.0"><channel><title>RSS</title></channel></rss>',
      atom: '<feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title></feed>',
      json_feed: '{"version":"https://jsonfeed.org/version/1.1","title":"JSON Feed","items":[]}'
    }
    sources.each do |format, body|
      with_server([[200, { "Content-Type" => "text/plain" }, body]]) do |url, requests|
        candidate = SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1).first
        assert_equal "#{url}/", candidate[:url]
        assert_equal format, candidate[:format]
        assert_equal :document, candidate[:source]
        assert_equal true, candidate[:verified]
        assert_equal 1, requests.size
      end
    end
  end

  def test_empty_self_closing_feed_containers_are_recognized
    ['<rss version="2.0"><channel/></rss>', '<feed xmlns="http://www.w3.org/2005/Atom"/>'].each do |body|
      with_server([[200, {}, body]]) do |url, _requests|
        candidates = SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1)
        assert_equal true, candidates.first[:verified]
        assert_empty SimpleRSS.parse(body).normalized_entries
      end
    end
  end

  def test_rdf_feed_and_xhtml_metadata_are_supported
    rdf = '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/"><channel><title>RDF</title></channel></rdf:RDF>'
    with_server([[200, {}, rdf]]) do |url, _requests|
      candidate = SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1).first
      assert_equal :rss, candidate[:format]
      assert_equal "RDF", candidate[:title]
    end
    xhtml = '<html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="alternate" type="application/atom+xml" href="feed.xml" /></head><body /></html>'
    with_server([[200, { "Content-Type" => "application/xhtml+xml" }, xhtml]]) do |url, _requests|
      assert_equal(["#{url}/feed.xml"], SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1).map { |candidate| candidate[:url] })
    end
  end

  def test_redirects_base_urls_and_protocol_relative_links_preserve_queries
    html = '<html><head><base href="../feeds/"><link rel=alternate type=application/rss+xml href="news.xml?edition=1#items"><link rel=alternate type=application/atom+xml href="//example.com/atom?q=1#entry"></head></html>'
    responses = [[302, { "Location" => "../pages/index?view=1#head" }, ""], [200, { "Content-Type" => "text/html" }, html]]
    with_server(responses) do |url, requests|
      candidates = SimpleRSS.discover("#{url}/start/page", network_policy: :unrestricted, timeout: 1)
      assert_equal(["#{url}/feeds/news.xml?edition=1", "http://example.com/atom?q=1"], candidates.map { |candidate| candidate[:url] })
      assert_equal ["GET /start/page HTTP/1.1", "GET /pages/index?view=1 HTTP/1.1"], requests.map(&:first)
    end
  end

  def test_invalid_links_are_ignored_and_invalid_first_base_uses_document_url
    html = '<html><head><base href="javascript:wrong"><base href="https://wrong.example.com/">' \
           '<link rel=alternate type=application/rss+xml href="valid.xml">' \
           '<link rel=alternate type=application/rss+xml href="javascript:wrong">' \
           '<link rel=alternate type=application/rss+xml href="file:///tmp/feed.xml">' \
           '<link rel=alternate type=application/rss+xml href="http://user:password@example.com/feed">' \
           '<link rel=alternate type=application/rss+xml href="http://[broken">' \
           '<link rel=alternate type=application/rss+xml href=" "></head></html>'
    with_server([[200, { "Content-Type" => "text/html" }, html]]) do |url, requests|
      assert_equal(["#{url}/valid.xml"], SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1).map { |candidate| candidate[:url] })
      assert_equal 1, requests.size
    end
  end

  def test_omitted_head_tags_and_html_entities_are_parsed_as_html
    html = '<!doctype html><title>Example</title><link rel=alternate type=application/rss+xml href="/feed?q=1&amp;b=2" title="Café &amp; ☀"><p>Post</p>'
    with_server([[200, { "Content-Type" => "text/html; charset=utf-8" }, html]]) do |url, _requests|
      candidate = SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1).first
      assert_equal "#{url}/feed?q=1&b=2", candidate[:url]
      assert_equal "Café & ☀", candidate[:title]
    end
  end

  def test_no_feeds_is_distinct_from_http_and_parse_failures
    with_server([[200, { "Content-Type" => "text/html" }, "<p>No feeds here</p>"]]) do |url, _requests|
      assert_empty SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1)
    end
    with_server([[404, { "Content-Type" => "text/html" }, "<p>Not found</p>"]]) do |url, _requests|
      error = assert_raise(SimpleRSS::HTTPError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
      assert_equal 404, error.status_code
    end
    ['{"version":', '{"hello":"world"}', '<rss version="2.0">broken</rss>', "not a feed", ""].each do |body|
      with_server([[200, { "Content-Type" => "application/octet-stream" }, body]]) do |url, _requests|
        assert_raise(SimpleRSS::DiscoveryError, body) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
      end
    end
  end

  def test_feed_markup_in_html_scripts_does_not_become_a_direct_feed
    html = '<html><head><script type="text/plain"><rss version="2.0"><channel><title>Wrong</title></channel></rss></script></head><body></body></html>'
    with_server([[200, { "Content-Type" => "application/rss+xml" }, html]]) do |url, _requests|
      assert_empty SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1)
    end
  end

  def test_foreign_namespaces_do_not_fabricate_verified_feeds
    ['<feed xmlns="urn:component"/>', '<rss xmlns="urn:component"><channel/></rss>'].each do |body|
      with_server([[200, { "Content-Type" => "text/html" }, body]]) do |url, _requests|
        assert_empty SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1)
      end
    end
  end

  def test_parser_limits_fail_clearly
    html = "<html><head></head><body>" + ("<div>" * 140)
    with_server([[200, { "Content-Type" => "text/html" }, html]]) do |url, _requests|
      assert_raise(SimpleRSS::DiscoveryError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
    end
  end

  def test_advertised_private_urls_are_only_unverified_metadata
    html = '<html><head><link rel=alternate type=application/rss+xml href="http://127.0.0.1:9/feed"></head></html>'
    with_server([[200, { "Content-Type" => "text/html" }, html]]) do |url, requests|
      candidate = SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1).first
      assert_equal false, candidate[:verified]
      assert_equal "http://127.0.0.1:9/feed", candidate[:url]
      assert_raise(SimpleRSS::PolicyError) { SimpleRSS.fetch(candidate[:url], network_policy: :public) }
      assert_equal 1, requests.size
    end
  end
end
