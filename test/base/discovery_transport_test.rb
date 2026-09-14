require "test_helper"
require "simple-rss/http_client"
require "zlib"
require "stringio"
require_relative "../support/http_server"
require_relative "../support/replace_method"

class DiscoveryTransportTest < Test::Unit::TestCase
  include HTTPServer
  include ReplaceMethod

  PAGE = [200, { "Content-Type" => "text/html" }, "<html><head></head><body>Example</body></html>"].freeze
  FEED = '<rss version="2.0"><channel><title>Example</title></channel></rss>'.freeze

  def test_public_policy_rejects_prohibited_ipv4_and_ipv6_before_connecting
    prohibited = %w[
      0.0.0.0 10.0.0.1 100.64.0.1 127.0.0.1 169.254.169.254 172.16.0.1 192.0.0.1 192.0.2.1
      192.88.99.1 192.168.1.1 198.18.0.1 198.51.100.1 203.0.113.1 224.0.0.1 255.255.255.255
      [::] [::1] [::ffff:127.0.0.1] [64:ff9b::7f00:1] [100::1] [2001::1] [2001:db8::1]
      [2002:7f00:1::] [3fff::1] [fc00::1] [fe80::1] [ff02::1]
    ]
    with_replaced_method(TCPSocket, :open, ->(*) { flunk "Prohibited address reached the socket" }) do
      prohibited.each do |host|
        assert_raise(SimpleRSS::PolicyError, host) { SimpleRSS.discover("http://#{host}/", timeout: 1) }
      end
    end
  end

  def test_malformed_urls_and_schemes_fail_before_connecting
    with_replaced_method(TCPSocket, :open, ->(*) { flunk "Invalid URL reached the socket" }) do
      ["example.com", "/relative", "ftp://example.com/feed", "file:///tmp/feed", "http://", "http://[broken", "http://example.com:0", "http://example.com:65536", "https://user:password@example.com/"].each do |url|
        assert_raise(SimpleRSS::PolicyError, url) { SimpleRSS.discover(url) }
      end
    end
  end

  def test_mixed_public_and_private_dns_answers_are_rejected
    with_replaced_method(Resolv, :getaddresses, ->(_host) { ["8.8.8.8", "127.0.0.1"] }) do
      with_replaced_method(TCPSocket, :open, ->(*) { flunk "Mixed DNS answers reached the socket" }) do
        assert_raise(SimpleRSS::PolicyError) { SimpleRSS.discover("http://site.example/") }
      end
    end
  end

  def test_checked_dns_address_is_pinned_and_host_header_is_preserved
    resolutions = 0
    resolver = lambda do |host|
      assert_equal "site.example", host
      resolutions += 1
      resolutions == 1 ? ["8.8.8.8"] : ["127.0.0.1"]
    end
    with_server([PAGE]) do |local_url, requests|
      with_pinned_connection(local_url, resolver) do |connections|
        assert_empty SimpleRSS.discover("http://site.example/", timeout: 1)
        assert_equal [["8.8.8.8", 80]], connections
        assert_equal 1, resolutions
        assert_include requests.first, "Host: site.example"
      end
    end
  end

  def test_dns_policy_is_rechecked_on_each_redirect
    resolutions = 0
    resolver = lambda do |_host|
      resolutions += 1
      resolutions == 1 ? ["8.8.8.8"] : ["127.0.0.1"]
    end
    with_server([[302, { "Location" => "/next" }, ""]]) do |local_url, requests|
      with_pinned_connection(local_url, resolver) do |connections|
        assert_raise(SimpleRSS::PolicyError) { SimpleRSS.discover("http://site.example/", timeout: 1) }
        assert_equal 2, resolutions
        assert_equal 1, connections.size
        assert_equal 1, requests.size
      end
    end
  end

  def test_redirect_to_a_private_literal_is_blocked
    with_server([[302, { "Location" => "http://127.0.0.1:9/feed" }, ""]]) do |local_url, requests|
      with_pinned_connection(local_url, ->(_host) { ["8.8.8.8"] }) do |connections|
        assert_raise(SimpleRSS::PolicyError) { SimpleRSS.discover("http://site.example/", timeout: 1) }
        assert_equal 1, connections.size
        assert_equal 1, requests.size
      end
    end
  end

  def test_public_ipv6_addresses_are_checked_and_pinned
    with_server([PAGE]) do |local_url, _requests|
      with_pinned_connection(local_url, ->(_host) { ["2606:4700:4700::1111"] }) do |connections|
        assert_empty SimpleRSS.discover("http://site.example/", timeout: 1)
        assert_equal [["2606:4700:4700::1111", 80]], connections
      end
    end
  end

  def test_an_application_policy_can_allow_one_internal_destination
    with_server([PAGE]) do |url, requests|
      policy = ->(uri, address) { uri.hostname == "127.0.0.1" && IPAddr.new("127.0.0.1/32").include?(address) }
      assert_empty SimpleRSS.discover(url, network_policy: policy, timeout: 1)
      assert_equal 1, requests.size
    end
  end

  def test_cross_origin_redirects_strip_credentials_and_keep_safe_headers
    headers = { "Authorization" => "Bearer fixture", "Cookie" => "session=fixture", "X-Api-Key" => "fixture", "User-Agent" => "Feed tests", "Accept" => "text/html", "Accept-Language" => "en" }
    options = { network_policy: :unrestricted, timeout: 1, headers: headers, etag: '"fixture"', last_modified: "Sat, 12 Sep 2026 10:00:00 GMT" }
    with_server([PAGE]) do |destination, destination_requests|
      with_server([[302, { "Location" => destination }, ""]]) do |source, source_requests|
        assert_empty SimpleRSS.discover(source, options)
        assert_include source_requests.first, "Authorization: Bearer fixture"
        assert_include source_requests.first, "Cookie: session=fixture"
        assert_include source_requests.first, 'If-None-Match: "fixture"'
        assert_empty destination_requests.first.grep(/Authorization:|Cookie:|Api-Key:|If-None-Match:|If-Modified-Since:/i)
        assert_include destination_requests.first, "User-Agent: Feed tests"
        assert_include destination_requests.first, "Accept: text/html"
        assert_include destination_requests.first, "Accept-Language: en"
        assert_equal "Bearer fixture", options[:headers]["Authorization"]
        assert_equal '"fixture"', options[:etag]
      end
    end
  end

  def test_same_origin_redirects_keep_authorization
    with_server([[302, { "Location" => "/next" }, ""], PAGE]) do |url, requests|
      SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1, headers: { "Authorization" => "Bearer fixture" })
      requests.each { |request| assert_include request, "Authorization: Bearer fixture" }
    end
  end

  def test_redirect_loops_and_limits_are_bounded
    with_server([[302, { "Location" => "/" }, ""]]) do |url, requests|
      assert_raise(SimpleRSS::RedirectError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
      assert_equal 1, requests.size
    end
    with_server([[302, { "Location" => "/next" }, ""]]) do |url, requests|
      assert_raise(SimpleRSS::RedirectError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1, max_redirects: 0) }
      assert_equal 1, requests.size
    end
    ["file:///tmp/feed", "ftp://example.com/feed", "http://[invalid", "https://user:password@example.com/"].each do |location|
      with_server([[302, { "Location" => location }, ""]]) do |url, requests|
        assert_raise(SimpleRSS::PolicyError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
        assert_equal 1, requests.size
      end
    end
  end

  def test_bodyless_conditional_responses_ignore_representation_encoding
    response = [304, { "Content-Encoding" => "gzip", "ETag" => '"fixture"' }, ""]
    with_server([response, response]) do |url, _requests|
      assert_nil SimpleRSS.fetch(url, network_policy: :unrestricted, timeout: 1, max_bytes: 1, etag: '"fixture"')
      error = assert_raise(SimpleRSS::HTTPError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
      assert_equal 304, error.status_code
    end
  end

  def test_truncated_content_length_is_a_transport_failure
    response = lambda do |client, _request|
      client.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: #{PAGE.last.bytesize + 20}\r\nConnection: close\r\n\r\n#{PAGE.last}")
    end
    with_server([response]) do |url, _requests|
      assert_raise(SimpleRSS::RequestError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
    end
  end

  def test_no_follow_option_reports_the_redirect_status
    with_server([[302, { "Location" => "/next" }, ""]]) do |url, requests|
      error = assert_raise(SimpleRSS::HTTPError) { SimpleRSS.discover(url, network_policy: :unrestricted, follow_redirects: false, timeout: 1) }
      assert_equal 302, error.status_code
      assert_equal 1, requests.size
    end
  end

  def test_response_byte_limit_accepts_the_boundary_and_rejects_overflow
    with_server([PAGE, PAGE]) do |url, requests|
      assert_empty SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1, max_bytes: PAGE.last.bytesize)
      assert_raise(SimpleRSS::ResponseTooLarge) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1, max_bytes: PAGE.last.bytesize - 1) }
      assert_equal 2, requests.size
    end
  end

  def test_chunked_body_is_stopped_before_its_end
    response = lambda do |client, _request|
      client.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\n\r\n100\r\n" + ("x" * 256) + "\r\n")
      wait_for_disconnect(client)
    end
    with_server([response]) do |url, requests|
      assert_raise(SimpleRSS::ResponseTooLarge) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1, max_bytes: 128) }
      assert_equal 1, requests.size
    end
  end

  def test_gzip_and_deflate_are_decoded_with_a_decompressed_size_limit
    { "gzip" => gzip(PAGE.last), "deflate" => Zlib::Deflate.deflate(PAGE.last) }.each do |encoding, compressed|
      with_server([[200, PAGE[1].merge("Content-Encoding" => encoding), compressed]]) do |url, _requests|
        assert_empty SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1)
      end
    end
    compressed = gzip("<html><body>" + ("x" * 200_000) + "</body></html>")
    assert_operator compressed.bytesize, :<, 1024
    with_server([[200, PAGE[1].merge("Content-Encoding" => "gzip"), compressed]]) do |url, _requests|
      assert_raise(SimpleRSS::ResponseTooLarge) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1, max_bytes: 1024) }
    end
  end

  def test_body_budget_is_shared_across_redirects
    responses = [[302, { "Location" => "/next" }, "x" * 100], PAGE]
    with_server(responses) do |url, requests|
      assert_raise(SimpleRSS::ResponseTooLarge) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1, max_bytes: 100 + PAGE.last.bytesize - 1) }
      assert_equal 2, requests.size
    end
  end

  def test_invalid_compression_and_partial_responses_fail_clearly
    responses = [
      [200, PAGE[1].merge("Content-Encoding" => "br"), "wrong"],
      [200, PAGE[1].merge("Content-Encoding" => "gzip"), "wrong"],
      [200, PAGE[1].merge("Content-Encoding" => "gzip"), gzip(PAGE.last).byteslice(0, 15)],
      [200, PAGE[1].merge("Content-Encoding" => "gzip"), gzip(PAGE.last) + gzip("ignored")],
      [206, PAGE[1].merge("Content-Range" => "bytes 0-9/100"), "0123456789"]
    ]
    responses.each do |response|
      with_server([response]) do |url, _requests|
        assert_raise(SimpleRSS::RequestError) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 1) }
      end
    end
  end

  def test_read_timeout_is_visible_and_does_not_retry
    with_server([->(client, _request) { wait_for_disconnect(client) }]) do |url, requests|
      assert_raise(SimpleRSS::RequestTimeout) { SimpleRSS.discover(url, network_policy: :unrestricted, timeout: 0.1) }
      assert_equal 1, requests.size
    end
  end

  def test_dns_resolution_is_inside_the_total_timeout
    with_replaced_method(Resolv, :getaddresses, ->(_host) { Queue.new.pop }) do
      assert_raise(SimpleRSS::RequestTimeout) { SimpleRSS.discover("http://site.example/", timeout: 0.1) }
    end
  end

  def test_missing_dns_results_and_connection_failures_are_not_empty_candidates
    with_replaced_method(Resolv, :getaddresses, ->(_host) { [] }) do
      assert_raise(SimpleRSS::RequestError) { SimpleRSS.discover("http://site.example/") }
    end
    with_replaced_method(Resolv, :getaddresses, ->(_host) { ["8.8.8.8"] }) do
      with_replaced_method(TCPSocket, :open, ->(*) { raise Errno::ECONNREFUSED }) do
        assert_raise(SimpleRSS::RequestError) { SimpleRSS.discover("http://site.example/") }
      end
    end
  end

  def test_policy_disables_environment_proxies_and_keeps_tls_verification
    constructor = Net::HTTP.method(:new)
    sessions = []
    replacement = lambda do |*arguments|
      assert_equal ["site.example", 443, nil], arguments
      session = constructor.call(*arguments)
      sessions << session
      session
    end
    with_replaced_method(Resolv, :getaddresses, ->(_host) { ["8.8.8.8"] }) do
      with_replaced_method(Net::HTTP, :new, replacement) do
        with_replaced_method(TCPSocket, :open, ->(*) { raise Errno::ECONNREFUSED }) do
          assert_raise(SimpleRSS::RequestError) { SimpleRSS.discover("https://site.example/", timeout: 1) }
        end
      end
    end
    assert_equal false, sessions.first.proxy?
    assert_equal "site.example", sessions.first.address
    assert_equal "8.8.8.8", sessions.first.ipaddr
    assert_equal OpenSSL::SSL::VERIFY_PEER, sessions.first.verify_mode
    assert_equal true, sessions.first.verify_hostname
  end

  def test_pinned_https_preserves_certificate_hostname_verification
    certificate, private_key = test_certificate
    store = OpenSSL::X509::Store.new
    store.add_cert(certificate)
    context = OpenSSL::SSL::SSLContext.new
    context.cert = certificate
    context.key = private_key
    server = TCPServer.new("127.0.0.1", 0)
    ssl_server = OpenSSL::SSL::SSLServer.new(server, context)
    requests = []
    worker = Thread.new do
      2.times do
        client = nil
        begin
          client = ssl_server.accept
          request = []
          while (line = client.gets)
            break if line == "\r\n"

            request << line.strip
          end
          requests << request
          client.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: #{PAGE.last.bytesize}\r\nConnection: close\r\n\r\n#{PAGE.last}")
        rescue OpenSSL::SSL::SSLError
          next
        ensure
          client&.close
        end
      end
    end
    constructor = Net::HTTP.method(:new)
    replacement = lambda do |*arguments|
      session = constructor.call(*arguments)
      session.cert_store = store
      session
    end
    with_replaced_method(Net::HTTP, :new, replacement) do
      with_pinned_connection("http://127.0.0.1:#{server.addr[1]}", ->(_host) { ["8.8.8.8"] }) do |connections|
        assert_empty SimpleRSS.discover("https://site.example/", timeout: 1)
        error = assert_raise(SimpleRSS::RequestError) { SimpleRSS.discover("https://wrong.example/", timeout: 1) }
        assert_kind_of OpenSSL::SSL::SSLError, error.cause
        assert_equal [["8.8.8.8", 443], ["8.8.8.8", 443]], connections
      end
    end
    worker.value
    assert_equal 1, requests.size
    assert_include requests.first, "Host: site.example"
  ensure
    worker&.kill
    worker&.join
    server&.close
  end

  def test_bounded_fetch_reuses_the_policy_and_conditional_get
    headers = { "ETag" => '"fixture"', "Last-Modified" => "Sat, 12 Sep 2026 10:00:00 GMT" }
    with_server([[200, headers, FEED], [304, headers, ""]]) do |url, requests|
      feed = SimpleRSS.fetch(url, network_policy: :unrestricted, timeout: 1)
      assert_equal "Example", feed.title
      assert_equal "#{url}/", feed.source_url
      assert_nil SimpleRSS.fetch(url, network_policy: :unrestricted, timeout: 1, etag: feed.etag, last_modified: feed.last_modified)
      assert_include requests.last, 'If-None-Match: "fixture"'
      assert_include requests.last, "If-Modified-Since: #{headers["Last-Modified"]}"
    end
  end

  def test_invalid_options_and_controlled_headers_fail_before_connecting
    options = [
      { network_policy: nil }, { network_policy: :unknown }, { timeout: 0 }, { timeout: nil }, { timeout: Float::INFINITY },
      { max_bytes: 0 }, { max_bytes: 1.5 }, { max_redirects: -1 }, { max_redirects: 1.5 }, { headers: [] },
      { headers: { "X-Value" => "bad\r\nInjected: header" } }, { headers: { "Bad Header" => "value" } }
    ]
    options += %w[Host Proxy-Authorization Accept-Encoding Range Connection Transfer-Encoding].map { |name| { headers: { name => "value" } } }
    with_replaced_method(TCPSocket, :open, ->(*) { flunk "Invalid options reached the socket" }) do
      options.each do |override|
        assert_raise(ArgumentError, override.inspect) { SimpleRSS.discover("https://site.example/", override) }
      end
    end
  end

  private

  def test_certificate
    private_key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = OpenSSL::X509::Name.parse("/CN=site.example")
    certificate.issuer = certificate.subject
    certificate.public_key = private_key.public_key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = certificate
    factory.issuer_certificate = certificate
    certificate.add_extension(factory.create_extension("basicConstraints", "CA:TRUE", true))
    certificate.add_extension(factory.create_extension("subjectAltName", "DNS:site.example"))
    certificate.sign(private_key, OpenSSL::Digest.new("SHA256"))
    [certificate, private_key]
  end

  def gzip(body)
    output = StringIO.new
    writer = Zlib::GzipWriter.new(output)
    writer.write(body)
    writer.close
    output.string
  end

  def with_pinned_connection(local_url, resolver)
    socket_open = TCPSocket.method(:open)
    connections = []
    local_port = URI.parse(local_url).port
    with_replaced_method(Resolv, :getaddresses, resolver) do
      replacement = lambda do |address, port, *_arguments|
        connections << [address, port]
        socket_open.call("127.0.0.1", local_port)
      end
      with_replaced_method(TCPSocket, :open, replacement) { yield connections }
    end
  end
end
