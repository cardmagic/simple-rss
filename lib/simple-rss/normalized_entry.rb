# rbs_inline: enabled

class SimpleRSS::NormalizedEntry
  attr_reader :identifier, :url, :title #: String?
  attr_reader :published_at, :updated_at #: Time?
  attr_reader :content_html, :content_text, :content_url, :content_base_url, :summary #: String?
  attr_reader :summary_type #: Symbol?
  attr_reader :categories #: Array[String]
  attr_reader :category_details, :attachments, :links, :authors, :issues #: Array[Hash[Symbol, untyped]]
  attr_reader :raw, :field_sources #: Hash[Symbol, untyped]
  attr_reader :raw_xml #: String?

  # @rbs (Hash[Symbol, untyped]) -> void
  def initialize(attributes)
    values = immutable_copy(attributes)
    empty_categories = [] #: Array[String]
    empty_records = [] #: Array[Hash[Symbol, untyped]]
    empty_data = {} #: Hash[Symbol, untyped]
    empty_categories.freeze
    empty_records.freeze
    empty_data.freeze
    @identifier = values[:identifier]
    @url = values[:url]
    @title = values[:title]
    @published_at = values[:published_at]
    @updated_at = values[:updated_at]
    @content_html = values[:content_html]
    @content_text = values[:content_text]
    @content_url = values[:content_url]
    @content_base_url = values[:content_base_url]
    @summary = values[:summary]
    @summary_type = values[:summary_type]
    @categories = values.fetch(:categories, empty_categories)
    @category_details = values.fetch(:category_details, empty_records)
    @attachments = values.fetch(:attachments, empty_records)
    @links = values.fetch(:links, empty_records)
    @authors = values.fetch(:authors, empty_records)
    @issues = values.fetch(:issues, empty_records)
    @raw = values.fetch(:raw, empty_data)
    @raw_xml = values[:raw_xml]
    @field_sources = values.fetch(:field_sources, empty_data)
    freeze
  end

  # @rbs () -> Time?
  def effective_at
    published_at || updated_at
  end

  # @rbs () -> Hash[Symbol, untyped]
  def to_h
    {
      identifier: identifier, url: url, title: title, published_at: published_at, updated_at: updated_at,
      content_html: content_html, content_text: content_text, content_url: content_url, content_base_url: content_base_url,
      summary: summary, summary_type: summary_type, categories: categories, category_details: category_details,
      attachments: attachments, links: links, authors: authors, issues: issues, field_sources: field_sources,
      raw: raw, raw_xml: raw_xml
    }
  end

  private

  # @rbs (untyped) -> untyped
  def immutable_copy(value)
    case value
    when Hash then value.to_h { |key, child| [immutable_copy(key), immutable_copy(child)] }.freeze
    when Array then value.map { |child| immutable_copy(child) }.freeze
    when String, Time then value.dup.freeze
    else value
    end
  end
end
