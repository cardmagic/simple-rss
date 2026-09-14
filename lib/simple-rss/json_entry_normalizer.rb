# rbs_inline: enabled

require "uri"
require "date"

class SimpleRSS::JsonEntryNormalizer
  RFC3339_TIMESTAMP = /\A\d{4}-\d{2}-\d{2}[tT]
                      (?:[01]\d|2[0-3]):[0-5]\d:(?:[0-5]\d|60)(?:\.\d+)?
                      (?:[zZ]|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z/x
  FIELDS = {
    title: "title", content_html: "content_html", content_text: "content_text", summary: "summary"
  }.freeze
  URL_FIELDS = %i[url external_url image banner_image].freeze

  # @rbs @item: Hash[String, untyped]
  # @rbs @feed: Hash[String, untyped]
  # @rbs @source_url: String?
  # @rbs @values: Hash[Symbol, untyped]
  # @rbs @issues: Array[Hash[Symbol, untyped]]
  # @rbs @sources: Hash[Symbol, untyped]

  # @rbs (Hash[String, untyped], Hash[String, untyped], ?source_url: String?) -> void
  def initialize(item, feed, source_url: nil)
    @item = item
    @feed = feed
    @source_url = source_url || feed["feed_url"]
    @issues = [] #: Array[Hash[Symbol, untyped]]
    @sources = {} #: Hash[Symbol, untyped]
    @values = { raw: item, issues: @issues, field_sources: @sources } #: Hash[Symbol, untyped]
  end

  # @rbs () -> SimpleRSS::NormalizedEntry
  def entry
    assign(:identifier, @item["id"].to_s, "id")
    FIELDS.each { |field, source| assign(field, @item[source], source) }
    URL_FIELDS.each { |field| assign(field, resolve_url(@item[field.to_s], field, field.to_s), field.to_s) }
    assign(:published_at, read_date("date_published", :published_at), "date_published")
    assign(:updated_at, read_date("date_modified", :updated_at), "date_modified")
    @values[:summary_type] = :text if @item["summary"]
    @values[:content_base_url] = @values[:url] || @source_url
    read_language
    read_categories
    read_authors
    @values[:attachments] = (@item["attachments"] || []).each_with_index.map { |attachment, index| read_attachment(attachment, index) }
    @values[:links] = %i[url external_url].filter_map do |field|
      next unless @values[field]

      { url: @values[field], rel: field == :url ? "alternate" : "related", media_type: nil, source: field.to_s, raw: @item[field.to_s] }
    end
    SimpleRSS::NormalizedEntry.new(@values)
  end

  private

  # @rbs (Symbol, untyped, String) -> void
  def assign(field, value, source)
    return if value.nil?

    @values[field] = value
    @sources[field] = source
  end

  # @rbs (Symbol, Symbol, untyped, String) -> void
  def issue(field, code, value, source)
    @issues << { field: field, code: code, value: value, source: source }
  end

  # @rbs (String, Symbol) -> Time?
  def read_date(source, field)
    value = @item[source]
    return if value.nil?
    return DateTime.rfc3339(value, Date::GREGORIAN).to_time if value.is_a?(String) && value.match?(RFC3339_TIMESTAMP)

    issue(field, :invalid_date, value, source)
    nil
  rescue ArgumentError, RangeError
    issue(field, :invalid_date, value, source)
    nil
  end

  # @rbs (String?, Symbol, String) -> String?
  def resolve_url(value, field, source)
    return if value.nil? || value.strip.empty?

    value = value.strip
    return value if URI.parse(value).absolute?

    source_url = @source_url
    return URI.join(source_url, value).to_s if source_url && URI.parse(source_url).absolute?

    issue(field, :relative_url_without_base, value, source)
    value
  rescue URI::Error
    issue(field, :invalid_url, value, source)
    value
  end

  # @rbs () -> void
  def read_language
    return unless @feed["version"] == SimpleRSS::JsonFeed::VERSIONS.last

    object = @item.key?("language") ? @item : @feed
    source = object.equal?(@item) ? "language" : "feed.language"
    assign(:language, object["language"], source)
  end

  # @rbs () -> void
  def read_categories
    tags = @item["tags"] || []
    categories = tags.map(&:strip).reject(&:empty?).uniq
    assign(:categories, categories, "tags") if @item.key?("tags")
    @values[:category_details] = tags.reject { |tag| tag.strip.empty? }.map { |tag| { term: tag.strip, label: nil, scheme: nil, source: "tags", raw: tag } }
  end

  # @rbs () -> void
  def read_authors
    object = @item
    plural = @feed["version"] == SimpleRSS::JsonFeed::VERSIONS.last
    object = @feed unless (plural && object.key?("authors")) || object.key?("author")
    source = plural && object.key?("authors") ? "authors" : "author"
    authors = source == "authors" ? object[source] : [object[source]].compact
    source = "feed.#{source}" if object.equal?(@feed)
    records = (authors || []).map do |author|
      { name: author["name"], email: nil, url: resolve_url(author["url"], :authors, source),
        avatar: resolve_url(author["avatar"], :authors, source), raw: author }
    end
    assign(:authors, records, source) unless records.empty?
  end

  # @rbs (Hash[String, untyped], Integer) -> Hash[Symbol, untyped]
  def read_attachment(attachment, index)
    source = "attachments[#{index}]"
    { url: resolve_url(attachment["url"], :attachments, "#{source}.url"), media_type: attachment["mime_type"],
      title: attachment["title"], size_in_bytes: read_number(attachment, "size_in_bytes", source),
      duration_in_seconds: read_number(attachment, "duration_in_seconds", source), source: source, raw: attachment }
  end

  # @rbs (Hash[String, untyped], String, String) -> Numeric?
  def read_number(attachment, field, source)
    value = attachment[field]
    return if value.nil?
    return value if value.is_a?(Numeric) && value >= 0 && value.finite?

    issue(:attachments, :invalid_number, value, "#{source}.#{field}")
    nil
  end
end
