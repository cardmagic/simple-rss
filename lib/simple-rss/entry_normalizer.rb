# rbs_inline: enabled

require "uri"

class SimpleRSS::EntryNormalizer
  ATOM = SimpleRSS::ATOM_NAMESPACE
  CONTENT = "http://purl.org/rss/1.0/modules/content/".freeze
  DUBLIN_CORE = "http://purl.org/dc/elements/1.1/".freeze
  MEDIA = "http://search.yahoo.com/mrss/".freeze
  ITUNES = "http://www.itunes.com/dtds/podcast-1.0.dtd".freeze
  XHTML = "http://www.w3.org/1999/xhtml".freeze

  # @rbs (Hash[Symbol, untyped]) -> void
  def self.validate_mappings(mappings)
    allowed = %i[content_html content_text categories]
    raise ArgumentError, "mappings must be a Hash with keys #{allowed.join(", ")}" unless mappings.is_a?(Hash) && (mappings.keys - allowed).empty?

    %i[content_html content_text].each do |field|
      next unless mappings.key?(field)
      raise ArgumentError, "#{field} mapping must be a nonempty XML tag name" unless mappings[field].is_a?(String) && !mappings[field].strip.empty?
    end
    return unless mappings.key?(:categories)

    categories = mappings[:categories]
    raise ArgumentError, "categories mapping must be an array of tag/separator records" unless categories.is_a?(Array)

    categories.each do |mapping|
      valid = mapping.is_a?(Hash) && (mapping.keys - %i[tag separator]).empty? && mapping[:tag].is_a?(String) && !mapping[:tag].strip.empty?
      valid &&= !mapping.key?(:separator) || (mapping[:separator].is_a?(String) && !mapping[:separator].empty?)
      raise ArgumentError, "category mappings require a tag and an optional nonempty separator" unless valid
    end
  end

  # @rbs (SimpleRSS::XmlElement, Hash[Symbol, untyped], Hash[Symbol, untyped]) -> void
  def initialize(element, raw, options)
    @element = element
    @children = element.children
    @source_url = options[:source_url] #: String?
    @mappings = options.fetch(:mappings) #: Hash[Symbol, untyped]
    @feed_authors = options.fetch(:feed_authors) #: Array[SimpleRSS::XmlElement]
    @values = { raw: raw, raw_xml: options[:raw_xml], field_sources: {}, issues: [] } #: Hash[Symbol, untyped]
    @field_elements = {} #: Hash[Symbol, SimpleRSS::XmlElement]
  end

  # @rbs () -> SimpleRSS::NormalizedEntry
  def entry
    read_identity
    read_links
    read_dates
    read_content
    read_categories
    read_attachments
    read_authors
    SimpleRSS::NormalizedEntry.new(@values)
  end

  private

  # @rbs () -> bool
  def atom?
    @element.namespace == ATOM
  end

  # @rbs (String) -> Array[SimpleRSS::XmlElement]
  def core_elements(name)
    @children.select { |element| atom? ? element.matches?(name, ATOM) : element.rss?(name) }
  end

  # @rbs (String, String) -> Array[SimpleRSS::XmlElement]
  def extension_elements(name, namespace)
    @children.select { |element| element.matches?(name, namespace) }
  end

  # @rbs (Symbol, untyped, SimpleRSS::XmlElement) -> void
  def assign(field, value, element)
    return if value.nil? || value == ""

    @values[field] = value
    @values[:field_sources][field] = element.name
    @field_elements[field] = element
  end

  # @rbs (Symbol, Symbol, untyped, SimpleRSS::XmlElement) -> nil
  def issue(field, code, value, element)
    @values[:issues] << { field: field, code: code, value: value, source: element.name }
    nil
  end

  # @rbs () -> void
  def read_identity
    identifier = core_elements(atom? ? "id" : "guid").find { |element| !element.text.empty? }
    assign(:identifier, identifier.text, identifier) if identifier
    title = core_elements("title").first
    assign(:title, title.text, title) if title
  end

  # @rbs () -> void
  def read_links
    elements = @children.select { |element| element.matches?("link", ATOM) || (!atom? && element.rss?("link")) }
    links = elements.map do |element|
      href = element.namespace == ATOM ? element.attributes["href"] : element.text
      relation = element.namespace == ATOM ? element.attributes.fetch("rel", "alternate") : "alternate"
      relation = relation.delete_prefix("http://www.iana.org/assignments/relation/")
      { url: resolve_url(href, element, :url), rel: relation, media_type: element.attributes["type"], raw: element.raw }
    end
    @values[:links] = links
    candidates = links.each_index.select { |index| links[index][:rel] == "alternate" && links[index][:url] }
    selected = candidates.min_by do |index|
      link = links[index]
      media_type = link[:media_type].to_s.split(";").first.to_s.downcase.strip
      [!atom? && elements.fetch(index).rss?("link") ? 0 : 1, media_type_priority(media_type), index]
    end
    assign(:url, links[selected][:url], elements.fetch(selected)) if selected
  end

  # @rbs (String) -> Integer
  def media_type_priority(media_type)
    return 0 if %w[text/html application/xhtml+xml].include?(media_type)
    return 1 if media_type.empty?

    2
  end

  # @rbs (String?, SimpleRSS::XmlElement, Symbol) -> String?
  def resolve_url(value, element, field)
    return if value.nil? || value.strip.empty?

    reference = value.strip
    return reference if URI.parse(reference).absolute?

    base = base_url(element)
    unless base
      issue(field, :relative_url_without_base, value, element)
      return reference
    end
    URI.join(base, reference).to_s
  rescue URI::Error
    issue(field, :invalid_url, value, element)
    value
  end

  # @rbs (SimpleRSS::XmlElement) -> String?
  def base_url(element)
    candidates = [@source_url, *element.base_urls].compact
    start = candidates.rindex { |value| URI.parse(value).absolute? }
    return unless start

    base = candidates.fetch(start)
    candidates.drop(start + 1).each { |value| base = URI.join(base, value).to_s }
    base
  rescue URI::Error
    issue(:base_url, :invalid_url, candidates, element)
  end

  # @rbs () -> void
  def read_dates
    published = atom? ? core_elements("published") : core_elements("pubDate") + extension_elements("date", DUBLIN_CORE)
    updated = extension_elements("updated", ATOM)
    updated += core_elements("modified") unless atom?
    read_date(:published_at, published)
    read_date(:updated_at, updated)
  end

  # @rbs (Symbol, Array[SimpleRSS::XmlElement]) -> void
  def read_date(field, elements)
    elements.each do |element|
      next if element.text.empty?

      begin
        assign(field, Time.parse(element.text), element)
        break
      rescue ArgumentError, RangeError
        issue(field, :invalid_date, element.text, element)
      end
    end
  end

  # @rbs () -> void
  def read_content
    %i[content_html content_text].each do |field|
      selector = @mappings[field]
      element = selector && @children.find { |child| child.selected?(selector) && !child.text.empty? }
      assign(field, element.text, element) if element
    end
    encoded = extension_elements("encoded", CONTENT).find { |element| !element.text.empty? }
    assign(:content_html, encoded.text, encoded) if encoded && !@values[:content_html]
    content = extension_elements("content", ATOM).first
    if content
      if content.attributes["src"]
        assign(:content_url, resolve_url(content.attributes["src"], content, :content_url), content)
      else
        value, type = text_construct(content, :content)
        field = type == :html ? :content_html : :content_text
        assign(field, value, content) unless @values[field]
      end
    end
    full_content = @field_elements[:content_html] || @field_elements[:content_text]
    @values[:content_base_url] = base_url(content_container(full_content)) if full_content
    summary = core_elements(atom? ? "summary" : "description").first
    return unless summary

    value, type = atom? ? text_construct(summary, :summary) : [summary.text, :html]
    assign(:summary, value, summary)
    @values[:summary_type] = type if @values[:summary]
  end

  # @rbs (SimpleRSS::XmlElement) -> SimpleRSS::XmlElement
  def content_container(element)
    type = element.attributes["type"].to_s.split(";", 2).first.to_s.strip.downcase
    return element unless %w[xhtml application/xhtml+xml].include?(type)

    element.children.find { |child| child.matches?("div", XHTML) } || element
  end

  # @rbs (SimpleRSS::XmlElement, Symbol) -> [String?, Symbol?]
  def text_construct(element, field)
    type = element.attributes.fetch("type", "text").split(";", 2).first.to_s.strip.downcase
    case type
    when "text", "text/plain"
      return [element.text, :text] if element.children.empty?

      issue(field, :unexpected_markup, element.content, element)
    when "html", "text/html"
      return [element.text, :html]
    when "xhtml", "application/xhtml+xml"
      children = element.children
      return [children.first.xhtml_content, :html] if children.size == 1 && children.first.matches?("div", XHTML)

      issue(field, :invalid_xhtml, element.content, element)
    else
      issue(field, :unsupported_content_type, type, element)
    end
    [nil, nil]
  end

  # @rbs () -> void
  def read_categories
    details = @children.flat_map do |element|
      mappings = @mappings[:categories] || [] #: Array[Hash[Symbol, untyped]]
      mapping = mappings.find { |candidate| element.selected?(candidate[:tag]) }
      term = category_term(element)
      next [] unless mapping || term

      terms = [term]
      terms = mapping[:separator] ? element.text.split(mapping[:separator]) : [element.text] if mapping
      terms.filter_map do |value|
        next if value.nil? || value.strip.empty?

        {
          term: value.strip, label: element.attributes["label"], scheme: element.attributes["scheme"] || element.attributes["domain"],
          source: element.name, raw: element.raw
        }
      end
    end
    @values[:category_details] = details
    @values[:categories] = details.map { |category| category[:term] }.uniq
  end

  # @rbs (SimpleRSS::XmlElement) -> String?
  def category_term(element)
    return element.attributes["term"] if element.matches?("category", ATOM)
    return element.text if !atom? && element.rss?("category")
    return element.text if element.matches?("subject", DUBLIN_CORE)
    return element.text if element.matches?("keywords", MEDIA) || element.matches?("keywords", ITUNES)

    nil
  end

  # @rbs () -> void
  def read_attachments
    elements = @children.flat_map { |element| element.matches?("group", MEDIA) ? element.children : [element] }
    attachments = elements.filter_map do |element|
      attributes = element.attributes
      if element.matches?("content", MEDIA)
        attachment(element, attributes["url"], attributes["fileSize"], attributes["duration"])
      elsif !atom? && element.rss?("enclosure")
        attachment(element, attributes["url"], attributes["length"], nil)
      elsif element.matches?("link", ATOM) && attributes["rel"].to_s.delete_prefix("http://www.iana.org/assignments/relation/") == "enclosure"
        attachment(element, attributes["href"], attributes["length"], nil)
      end
    end
    duration = extension_elements("duration", ITUNES).first
    if attachments.size == 1 && duration && attachments.first[:duration_in_seconds].nil?
      attachments.first[:duration_in_seconds] = duration_seconds(duration.text, duration)
      attachments.first[:raw_duration] = duration.raw
    end
    @values[:attachments] = attachments
  end

  # @rbs (SimpleRSS::XmlElement, String?, String?, String?) -> Hash[Symbol, untyped]?
  def attachment(element, url, size, duration)
    resolved_url = resolve_url(url, element, :attachment_url)
    return unless resolved_url

    {
      url: resolved_url, media_type: element.attributes["type"], size_in_bytes: size_in_bytes(size, element),
      duration_in_seconds: duration_seconds(duration, element), source: element.name, raw: element.raw
    }
  end

  # @rbs (String?, SimpleRSS::XmlElement) -> Integer?
  def size_in_bytes(value, element)
    return if value.nil?
    return value.to_i if value.match?(/\A\d+\z/)

    issue(:size_in_bytes, :invalid_number, value, element)
  end

  # @rbs (String?, SimpleRSS::XmlElement) -> (Integer | Float)?
  def duration_seconds(value, element)
    return if value.nil?
    return value.to_f if value.match?(/\A\d+(?:\.\d+)?\z/) && value.to_f.finite?

    if element.matches?("duration", ITUNES) && value.match?(/\A\d+:\d{2}(?::\d{2})?\z/)
      parts = value.split(":").map(&:to_i)
      return parts.reduce(0) { |total, part| (total * 60) + part } if parts.drop(1).all? { |part| part < 60 }
    end
    issue(:duration_in_seconds, :invalid_number, value, element)
  end

  # @rbs () -> void
  def read_authors
    elements = core_elements("author")
    elements += extension_elements("creator", DUBLIN_CORE) unless atom?
    if atom? && elements.empty?
      source = core_elements("source").first
      elements = source.children.select { |element| element.matches?("author", ATOM) } if source
      elements = @feed_authors if elements.empty?
    end
    @values[:authors] = elements.map do |element|
      if element.matches?("creator", DUBLIN_CORE)
        next { name: element.text, email: nil, url: nil, raw: element.raw }
      end
      next { name: nil, email: element.text, url: nil, raw: element.raw } unless element.namespace == ATOM

      children = element.children
      name = children.find { |child| child.matches?("name", ATOM) }
      email = children.find { |child| child.matches?("email", ATOM) }
      uri = children.find { |child| child.matches?("uri", ATOM) }
      { name: name&.text, email: email&.text, url: uri && resolve_url(uri.text, uri, :author_url), raw: element.raw }
    end
  end
end
