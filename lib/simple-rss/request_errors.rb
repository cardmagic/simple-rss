# rbs_inline: enabled

class SimpleRSS
  class RequestError < SimpleRSSError; end
  class PolicyError < RequestError; end
  class RequestTimeout < RequestError; end
  class ResponseTooLarge < RequestError; end
  class RedirectError < RequestError; end
  class DiscoveryError < SimpleRSSError; end
  class DiscoveryDependencyError < DiscoveryError; end

  class HTTPError < RequestError
    attr_reader :status_code #: Integer

    # @rbs (Integer) -> void
    def initialize(status_code)
      @status_code = status_code
      super("HTTP #{status_code} during feed discovery")
    end
  end
end
