# rbs_inline: enabled

class SimpleRSS::XmlElement
  attr_reader :name #: String
  attr_reader :attributes #: Hash[String, String]
  attr_reader :content #: String
  attr_reader :namespaces #: Hash[String, String]
  attr_reader :base_urls #: Array[String]

  # @rbs (String, String, String?, Hash[Symbol, untyped]) -> void
  def initialize(name, attributes, content, parent)
    @name = name
    @attributes = self.class.attributes(attributes).transform_values { |value| CGI.unescapeHTML(value) }
    @content = content.to_s
    @namespaces = parent.fetch(:namespaces).merge(@attributes.select { |key, _value| key == "xmlns" || key.start_with?("xmlns:") })
    base_url = @attributes["xml:base"]
    @base_urls = parent.fetch(:base_urls).dup
    @base_urls << base_url if base_url
  end

  # @rbs () -> Array[SimpleRSS::XmlElement]
  def children
    self.class.child_elements(content).map do |name, attributes, body|
      self.class.new(name, attributes, body, { namespaces: namespaces, base_urls: base_urls })
    end
  end

  # @rbs () -> String?
  def namespace
    namespaces[name.include?(":") ? "xmlns:#{name.split(":").first}" : "xmlns"]
  end

  # @rbs (String, String?) -> bool
  def matches?(local_name, namespace)
    name.split(":").last == local_name && self.namespace == namespace
  end

  # @rbs (String) -> bool
  def rss?(local_name)
    return false if name.include?(":") && namespace.nil?

    name.split(":").last == local_name && SimpleRSS::RSS_NAMESPACES.include?(namespace)
  end

  # @rbs (String) -> bool
  def selected?(selector)
    if selector.start_with?("{")
      namespace, local_name = selector.delete_prefix("{").split("}", 2)
      return local_name ? matches?(local_name, namespace) : false
    end

    name == selector
  end

  # @rbs () -> String
  def text
    content.split(/(<!\[CDATA\[.*?\]\]>)/m).map do |part|
      part.start_with?("<![CDATA[") ? part[9...-3].to_s : CGI.unescapeHTML(part.gsub(/<!--.*?-->|<\?.*?\?>/m, ""))
    end.join.strip
  end

  # @rbs () -> Hash[Symbol, untyped]
  def raw
    { name: name, namespace: namespace, attributes: attributes, content: content }
  end

  # @rbs () -> String
  def xhtml_content
    scopes = [namespaces]
    content.gsub(SimpleRSS::XML_TAG_PATTERN) do |token|
      name = Regexp.last_match(2).to_s
      attributes = Regexp.last_match(3)
      closing = Regexp.last_match(1) == "/"
      next token unless attributes

      if closing
        context = scopes.last || namespaces
        scopes.pop if scopes.size > 1
      else
        declarations = self.class.attributes(attributes).select { |key, _value| key == "xmlns" || key.start_with?("xmlns:") }
        context = (scopes.last || namespaces).merge(declarations.transform_values { |value| CGI.unescapeHTML(value) })
        scopes << context unless attributes.rstrip.end_with?("/")
      end
      namespace = context[name.include?(":") ? "xmlns:#{name.split(":").first}" : "xmlns"]
      next token unless namespace == "http://www.w3.org/1999/xhtml"

      token.sub(name, name.split(":").last.to_s)
    end.strip
  end

  # @rbs (String) -> Hash[String, String]
  def self.attributes(attributes)
    values = {} #: Hash[String, String]
    attributes.scan(/([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/m) do
      name = Regexp.last_match(1)
      value = Regexp.last_match(2) || Regexp.last_match(3)
      values[name] = value if name && value
    end
    values
  end

  # @rbs (String) -> Array[[String, String, String?]]
  def self.child_elements(content)
    elements = [] #: Array[[String, String, String?]]
    current_element = nil #: [String, String, String?]?
    depth = 0
    body_start = 0
    position = 0

    while (token = SimpleRSS::XML_TAG_PATTERN.match(content, position))
      position = token.end(0)
      attributes = token[3]
      next unless attributes

      if token[1] == "/"
        depth = [depth - 1, 0].max
        if depth.zero? && current_element
          current_element[2] = content[body_start...token.begin(0)]
          current_element = nil
        end
        next
      end

      self_closing = attributes.rstrip.end_with?("/")
      if depth.zero?
        element = [token[2].to_s, attributes, nil] #: [String, String, String?]
        elements << element
        current_element = element unless self_closing
        body_start = token.end(0)
      end
      depth += 1 unless self_closing
    end

    elements
  end
end
