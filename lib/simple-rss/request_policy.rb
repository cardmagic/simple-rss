# rbs_inline: enabled

require "ipaddr"
require "resolv"
require "uri"

class SimpleRSS::RequestPolicy
  BLOCKED_IPV4 = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
    192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.18.0.0/15
    198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
  ].map { |range| IPAddr.new(range).freeze }.freeze
  GLOBAL_IPV6 = IPAddr.new("2000::/3").freeze
  BLOCKED_IPV6 = %w[2001::/23 2001:db8::/32 2002::/16 3fff::/20].map { |range| IPAddr.new(range).freeze }.freeze

  # @rbs @policy: untyped

  # @rbs (untyped) -> void
  def initialize(policy)
    unless %i[public unrestricted].include?(policy) || policy.respond_to?(:call)
      raise ArgumentError, "network_policy must be :public, :unrestricted, or a callable"
    end

    @policy = policy
  end

  # @rbs (String) -> untyped
  def self.parse_url(value)
    uri = URI.parse(value)
    raise SimpleRSS::PolicyError, "Expected an absolute HTTP or HTTPS URL" unless uri.is_a?(URI::HTTP)

    unless uri.hostname && !uri.hostname.to_s.empty? && uri.port&.between?(1, 65_535)
      raise SimpleRSS::PolicyError, "Expected a valid host and port"
    end
    raise SimpleRSS::PolicyError, "Credentials in URLs are not supported" if uri.userinfo

    uri.fragment = nil
    uri.path = "/" if uri.path.to_s.empty?
    uri.normalize
  rescue URI::Error, TypeError
    raise SimpleRSS::PolicyError, "Malformed HTTP or HTTPS URL"
  end

  # @rbs (untyped) -> String
  def address(uri)
    addresses = resolve(uri.hostname.to_s)
    raise SimpleRSS::RequestError, "No destination addresses were resolved" if addresses.empty?
    unless addresses.all? { |address| allowed?(uri, address) }
      raise SimpleRSS::PolicyError, "Destination address is prohibited by network_policy"
    end

    (addresses.find(&:ipv4?) || addresses.fetch(0)).to_s
  end

  private

  # @rbs (String) -> Array[untyped]
  def resolve(hostname)
    [IPAddr.new(hostname)]
  rescue IPAddr::InvalidAddressError
    Resolv.getaddresses(hostname).uniq.map { |address| IPAddr.new(address) }
  end

  # @rbs (untyped, untyped) -> bool
  def allowed?(uri, address)
    return true if @policy == :unrestricted
    return @policy.call(uri.dup.freeze, address.dup.freeze) == true if @policy.respond_to?(:call)
    return BLOCKED_IPV4.none? { |range| range.include?(address) } if address.ipv4?

    GLOBAL_IPV6.include?(address) && BLOCKED_IPV6.none? { |range| range.include?(address) }
  end
end
