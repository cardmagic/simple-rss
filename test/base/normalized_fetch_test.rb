require "test_helper"
require "socket"
require "stringio"
require "json"

class NormalizedFetchTest < Test::Unit::TestCase
  def test_fetch_uses_the_final_response_url_after_relative_redirects
    body = '<feed xmlns="http://www.w3.org/2005/Atom"><title>Example</title><entry><link href="article"/>' \
           '<content type="text/plain" src="full.txt"/></entry></feed>'
    responses = [[302, { "Location" => "../feeds/final.xml" }, ""], [200, { "Content-Type" => "application/atom+xml" }, body]]
    with_server(responses) do |base_url, requests|
      feed = SimpleRSS.fetch("#{base_url}/start/feed.xml", timeout: 1)
      entry = feed.normalized_entries.first

      assert_equal "#{base_url}/feeds/final.xml", feed.source_url
      assert_equal "#{base_url}/feeds/article", entry.url
      assert_equal "#{base_url}/feeds/full.txt", entry.content_url
      assert_nil entry.content_text
      assert_equal ["GET /start/feed.xml HTTP/1.1", "GET /feeds/final.xml HTTP/1.1"], requests.map(&:first)
    end
  end

  def test_fetch_retains_conditional_get_and_parse_options
    body = '<rss version="2.0"><channel><title>Example</title><item><link>article</link><category>ruby</category>' \
           "<category>feeds</category></item></channel></rss>"
    headers = { "ETag" => '"version-1"', "Last-Modified" => "Sat, 12 Sep 2026 10:00:00 GMT" }
    with_server([[200, headers, body], [304, headers, ""]]) do |base_url, requests|
      feed = SimpleRSS.fetch("#{base_url}/feed.xml", timeout: 1, array_tags: [:category])

      assert_equal '"version-1"', feed.etag
      assert_equal headers["Last-Modified"], feed.last_modified
      assert_equal %w[ruby feeds], feed.first.category
      assert_equal "#{base_url}/article", feed.normalized_entries.first.url
      assert_nil SimpleRSS.fetch("#{base_url}/feed.xml", timeout: 1, etag: feed.etag, last_modified: feed.last_modified)
      assert_include requests.last, 'If-None-Match: "version-1"'
      assert_include requests.last, "If-Modified-Since: #{feed.last_modified}"
    end
  end

  def test_readable_io_and_explicit_source_url_work_without_fetching
    source = StringIO.new('<rss version="2.0"><channel><title>Example</title><item><link>article</link></item></channel></rss>')
    feed = SimpleRSS.parse(source, source_url: "https://example.com/feed.xml")

    assert_equal "https://example.com/article", feed.normalized_entries.first.url
    assert_nil feed.etag
  end

  def test_fetched_source_url_wins_over_shared_parse_options_without_mutating_them
    body = '<rss version="2.0"><channel><title>Example</title><item><link>article</link></item></channel></rss>'
    responses = [[302, { "Location" => "/feeds/final.xml" }, ""], [200, {}, body]] * 2
    with_server(responses) do |base_url, requests|
      [nil, "https://wrong.example.com/old.xml"].each do |source_url|
        options = { source_url: source_url, timeout: 1 }
        feed = SimpleRSS.fetch("#{base_url}/initial.xml", options)

        assert_equal "#{base_url}/feeds/final.xml", feed.source_url
        assert_equal "#{base_url}/feeds/article", feed.normalized_entries.first.url
        assert_equal source_url, options[:source_url]
        assert_equal "https://override.example.com/article", feed.normalized_entries(source_url: "https://override.example.com/feed.xml").first.url
      end
      assert_equal 4, requests.size
    end
  end

  def test_json_fetch_detects_the_body_across_content_types_and_preserves_conditional_get
    %w[application/feed+json application/json text/plain application/rss+xml].each do |content_type|
      body = JSON.generate(version: "https://jsonfeed.org/version/1.1", title: "Example",
                           next_url: "/older.json", items: [{ id: "1", url: "article", content_text: "Hello" }])
      headers = { "Content-Type" => content_type, "ETag" => '"json-1"', "Last-Modified" => "Sat, 12 Sep 2026 10:00:00 GMT" }
      with_server([[200, headers, body], [304, headers, ""]]) do |base_url, requests|
        feed = SimpleRSS.fetch("#{base_url}/feed.json", timeout: 1)
        assert_equal :json_feed, feed.feed_type
        assert_equal "#{base_url}/article", feed.normalized_entries.first.url
        assert_equal "/older.json", feed.next_url
        assert_equal '"json-1"', feed.etag
        assert_equal headers["Last-Modified"], feed.last_modified
        assert_equal 1, requests.size
        assert_include requests.first.find { |header| header.start_with?("Accept:") }, "application/feed+json"
        assert_nil SimpleRSS.fetch("#{base_url}/feed.json", timeout: 1, etag: feed.etag, last_modified: feed.last_modified)
        assert_include requests.last, 'If-None-Match: "json-1"'
        assert_include requests.last, "If-Modified-Since: #{headers["Last-Modified"]}"
        assert_equal 2, requests.size
      end
    end
  end

  def test_json_fetch_handles_redirects_and_custom_accept_without_fetching_linked_resources
    body = JSON.generate(version: "https://jsonfeed.org/version/1", title: "Example", next_url: "/older.json",
                         items: [{ id: "1", url: "article", content_text: "Hello",
                                   attachments: [{ url: "episode.mp3", mime_type: "audio/mpeg" }] }])
    responses = [[302, { "Location" => "../feeds/final.json" }, ""], [200, {}, body]]
    with_server(responses) do |base_url, requests|
      feed = SimpleRSS.fetch("#{base_url}/start/feed", timeout: 1, headers: { "Accept" => "application/json" })
      entry = feed.normalized_entries.first
      assert_equal "#{base_url}/feeds/final.json", feed.source_url
      assert_equal "#{base_url}/feeds/article", entry.url
      assert_equal "#{base_url}/feeds/episode.mp3", entry.attachments.first[:url]
      assert_equal "/older.json", feed.next_url
      assert_equal ["GET /start/feed HTTP/1.1", "GET /feeds/final.json HTTP/1.1"], requests.map(&:first)
      requests.each { |request| assert_include request, "Accept: application/json" }
    end
  end

  private

  def with_server(responses)
    server = TCPServer.new("127.0.0.1", 0)
    base_url = "http://127.0.0.1:#{server.addr[1]}"
    requests = []
    worker = Thread.new do
      responses.each do |status, headers, body|
        client = server.accept
        request = []
        while (line = client.gets)
          break if line == "\r\n"

          request << line.strip
        end
        requests << request
        response_headers = headers.merge("Content-Length" => body.bytesize.to_s, "Connection" => "close")
        client.write("HTTP/1.1 #{status} Test\r\n" + response_headers.map { |name, value| "#{name}: #{value}\r\n" }.join + "\r\n" + body)
        client.close
      end
    end
    yield base_url, requests
    worker.value
  ensure
    worker&.kill
    worker&.join
    server&.close
  end
end
