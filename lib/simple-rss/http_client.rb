# rbs_inline: enabled

require "net/http"
require "timeout"
require "openssl"
require_relative "request_errors"
require_relative "request_policy"

class SimpleRSS::HTTPClient
  ACCEPT = "application/feed+json, application/rss+xml, application/atom+xml, application/json, application/xml, text/xml, */*".freeze
  REDIRECT_CODES = %w[301 302 303 307 308].freeze
  CROSS_ORIGIN_HEADERS = %w[accept accept-language user-agent].freeze
  PROTECTED_HEADERS = %w[host connection proxy-authorization proxy-connection accept-encoding range transfer-encoding content-length te trailer upgrade
                         expect].freeze

  # @rbs @options: Hash[Symbol, untyped]
  # @rbs @headers: Hash[untyped, untyped]
  # @rbs @policy: SimpleRSS::RequestPolicy?
  # @rbs @remaining_bytes: Integer
  # @rbs @remaining_wire_bytes: Integer
  # @rbs @redirect_limit: Integer
  # @rbs @timeout: untyped

  # @rbs (Hash[Symbol, untyped]) -> void
  def initialize(options)
    @options = options.dup
    @headers = (@options[:headers] || {}).dup
    @policy = @options.key?(:network_policy) ? SimpleRSS::RequestPolicy.new(@options[:network_policy]) : nil
    @remaining_bytes = @options.fetch(:max_bytes, 2 * 1024 * 1024)
    @remaining_wire_bytes = @remaining_bytes
    @redirect_limit = @options.fetch(:max_redirects, 5)
    @timeout = @options.fetch(:timeout, @policy ? 10 : nil)
    validate_options
  end

  # @rbs (String) -> [untyped, untyped]
  def get(url)
    return perform(URI.parse(url)) unless @policy

    Timeout.timeout(@timeout, SimpleRSS::RequestTimeout, "HTTP operation exceeded its timeout") do
      perform(SimpleRSS::RequestPolicy.parse_url(url))
    end
  rescue Timeout::Error
    raise unless @policy

    raise SimpleRSS::RequestTimeout, "HTTP operation exceeded its timeout"
  rescue IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Resolv::ResolvError, Zlib::Error => e
    raise unless @policy

    raise SimpleRSS::RequestError, "HTTP transport failed: #{e.message}"
  end

  private

  # @rbs () -> void
  def validate_options
    if !@policy && (@options.key?(:max_bytes) || @options.key?(:max_redirects))
      raise ArgumentError, "max_bytes and max_redirects require network_policy"
    end
    return unless @policy

    unless @timeout.is_a?(Numeric) && @timeout.real? && @timeout.finite? && @timeout.positive?
      raise ArgumentError, "timeout must be a positive finite number"
    end
    unless @remaining_bytes.is_a?(Integer) && @remaining_bytes.positive?
      raise ArgumentError, "max_bytes must be a positive integer"
    end
    unless @redirect_limit.is_a?(Integer) && @redirect_limit >= 0
      raise ArgumentError, "max_redirects must be a nonnegative integer"
    end
    raise ArgumentError, "headers must be a hash" unless @headers.is_a?(Hash)

    @headers.each do |name, value|
      if PROTECTED_HEADERS.include?(name.to_s.downcase)
        raise ArgumentError, "The transport controls the #{name} header"
      end
      unless name.to_s.match?(/\A[!#$%&'*+.^_`|~0-9A-Za-z-]+\z/) && value.is_a?(String) && !value.match?(/[\r\n\x00]/)
        raise ArgumentError, "Invalid request header"
      end
    end
  end

  # @rbs (untyped) -> [untyped, untyped]
  def perform(uri)
    visited = {} #: Hash[String, bool]
    redirects = @policy ? 0 : (@options[:_redirects] || 0)
    redirect_error = @policy ? SimpleRSS::RedirectError : SimpleRSSError
    loop do
      raise SimpleRSS::RedirectError, "Redirect loop detected" if @policy && visited[uri.to_s]

      visited[uri.to_s] = true
      response = request(uri)
      return [response, uri] unless redirect?(response)

      location = response["Location"]
      return [response, uri] unless location

      redirects += 1
      raise redirect_error, "Too many redirects" if redirects > @redirect_limit

      next_uri = URI.join(uri.to_s, location)
      next_uri = SimpleRSS::RequestPolicy.parse_url(next_uri.to_s) if @policy
      strip_credentials if @policy && origin(uri) != origin(next_uri)
      uri = next_uri
    end
  rescue URI::Error
    raise unless @policy

    raise SimpleRSS::PolicyError, "Malformed redirect URL"
  end

  # @rbs (untyped) -> bool
  def redirect?(response)
    return false if @options[:follow_redirects] == false
    return REDIRECT_CODES.include?(response.code) if @policy

    response.is_a?(Net::HTTPRedirection)
  end

  # @rbs (untyped) -> untyped
  def request(uri)
    http = build_http(uri)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = ACCEPT
    request["User-Agent"] = "SimpleRSS/#{SimpleRSS::VERSION}"
    request["If-None-Match"] = @options[:etag] if @options[:etag]
    request["If-Modified-Since"] = @options[:last_modified] if @options[:last_modified]
    @headers.each { |name, value| request[name] = value }
    return http.request(request) unless @policy

    request["Accept-Encoding"] = "gzip, deflate, identity"
    http.request(request) { |response| read_response(response) }
  end

  # @rbs (untyped) -> untyped
  def build_http(uri)
    host = uri.hostname || raise(SimpleRSSError, "Invalid URL: missing host")
    policy = @policy
    http = policy ? Net::HTTP.new(host, uri.port, nil) : Net::HTTP.new(host, uri.port)
    http.use_ssl = uri.scheme == "https"
    if @timeout
      http.open_timeout = @timeout
      http.read_timeout = @timeout
    end
    return http unless policy

    http.ipaddr = policy.address(uri)
    http.write_timeout = @timeout
    http.max_retries = 0
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_hostname = true
    http
  end

  # @rbs (untyped) -> void
  def read_response(response)
    return unless response.class.body_permitted?

    encoding = response["Content-Encoding"].to_s.downcase
    unless ["", "identity", "none", "gzip", "x-gzip", "deflate"].include?(encoding)
      raise SimpleRSS::RequestError, "Unsupported Content-Encoding"
    end
    raise SimpleRSS::RequestError, "Partial HTTP responses are not supported" if response["Content-Range"] || response.code == "206"

    body = +"".b
    wire_bytes = 0
    inflater = Zlib::Inflate.new(32 + Zlib::MAX_WBITS) if %w[gzip x-gzip deflate].include?(encoding)
    response.read_body do |chunk|
      if chunk.bytesize > @remaining_wire_bytes
        raise SimpleRSS::ResponseTooLarge, "HTTP response bodies exceeded max_bytes"
      end

      @remaining_wire_bytes -= chunk.bytesize
      wire_bytes += chunk.bytesize
      unless inflater
        append_body(body, chunk)
        next
      end
      inflater.inflate(chunk) { |decoded| append_body(body, decoded) }
      raise SimpleRSS::RequestError, "Trailing data in compressed HTTP response" if inflater.total_in != wire_bytes
    end
    raise SimpleRSS::RequestError, "Incomplete compressed HTTP response" if inflater && !inflater.finished?

    declared_length = response.content_length
    if declared_length && !response.chunked? && wire_bytes != declared_length
      raise SimpleRSS::RequestError, "Incomplete HTTP response body"
    end

    response.delete("Content-Encoding")
    response["Content-Length"] = body.bytesize.to_s if declared_length
    response.body = body
  ensure
    inflater&.close
  end

  # @rbs (String, String) -> nil
  def append_body(body, chunk)
    raise SimpleRSS::ResponseTooLarge, "HTTP response bodies exceeded max_bytes" if chunk.bytesize > @remaining_bytes

    @remaining_bytes -= chunk.bytesize
    body << chunk
    nil
  end

  # @rbs (untyped) -> Array[untyped]
  def origin(uri)
    [uri.scheme.downcase, uri.hostname.downcase, uri.port]
  end

  # @rbs () -> void
  def strip_credentials
    @headers = @headers.select { |name, _value| CROSS_ORIGIN_HEADERS.include?(name.to_s.downcase) }
    @options.delete(:etag)
    @options.delete(:last_modified)
  end
end
