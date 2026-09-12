require "test_helper"
require "json"

class RelationLinksTest < Test::Unit::TestCase
  def test_documented_accessor_and_legacy_key_return_the_same_link
    feed = parse_entry(<<~XML)
      <link rel="self" href="https://example.com/api/1"/>
      <link rel="alternate" href="https://example.com/posts/1"/>
    XML
    item = feed.first

    assert_equal "https://example.com/posts/1", item.link_alternate
    assert_equal item.link_alternate, item[:link_alternate]
    assert_equal item.link_alternate, item[:"link+alternate"]
    assert_equal "https://example.com/api/1", item.link
  end

  def test_relations_accept_attribute_order_quotes_whitespace_and_paired_tags
    item = parse_entry(<<~XML).first
      <link href = '/posts/1?view=full' title="Article > summary" rel = 'alternate'/>
      <atom:link xmlns:atom="http://www.w3.org/2005/Atom"
        rel = "self"
        href = "https://example.com/api/1"></atom:link>
      <link href='https://example.com/edit/1' rel='edit'>Edit entry</link>
      <link rel="replies" type="application/atom+xml" href="/posts/1/replies" />
    XML

    assert_equal "/posts/1?view=full", item.link_alternate
    assert_equal "https://example.com/api/1", item.link_self
    assert_equal "https://example.com/edit/1", item.link_edit
    assert_equal "/posts/1/replies", item.link_replies
    %w[alternate self edit replies].each do |relation|
      assert_equal item[:"link_#{relation}"], item[:"link+#{relation}"]
    end
  end

  def test_nested_media_does_not_replace_the_link_href
    source = File.read(File.join(__dir__, "../data/atom_nested_link.xml"))
    feed = SimpleRSS.parse(source)

    assert_equal "https://example.com/story", feed.first.link_alternate
    assert_equal "https://example.com/story", feed.first[:"link+alternate"]
    assert_equal source, feed.source
  end

  def test_relations_do_not_borrow_neighboring_attributes_or_content
    item = parse_entry(<<~XML).first
      <link href="/unrelated"/>
      <link rel="self" href="/self"/>
      <link rel="alternate"><media:thumbnail href="/thumbnail"/></link>
      <link rel="replies" href="/replies"></link>
    XML

    assert_equal "/self", item.link_self
    assert_equal "/replies", item.link_replies
    assert_nil item.link_alternate
    assert_nil item[:"link+alternate"]
    assert_nil item.link_edit
  end

  def test_relations_ignore_nested_source_content_comments_and_cdata
    item = parse_entry(<<~XML).first
      <source><link rel="alternate" href="/source"/></source>
      <content type="xhtml"><div><link rel="edit" href="/content"/></div></content>
      <!-- <link rel="self" href="/comment"/> -->
      <![CDATA[<link rel="replies" href="/cdata"/>]]>
      <?example <link rel="self" href="/instruction"/> ?>
      <extension><link rel="replies" href="/extension"/></extension>
      <link rel="alternate" href="/entry"/>
    XML

    assert_equal "/entry", item.link_alternate
    assert_nil item.link_self
    assert_nil item.link_edit
    assert_nil item.link_replies
  end

  def test_relations_match_exact_element_and_attribute_names
    item = parse_entry(<<~XML).first
      <linkage rel="alternate" href="/wrong-element"/>
      <other:link rel="alternate" href="/wrong-namespace"/>
      <link data-rel="alternate" href="/wrong-attribute"/>
      <link title="rel='alternate' href='/quoted'" href="/wrong-value"/>
      <link rel="self" data-href="/wrong-href"/>
      <link rel="alternate" href="/correct"/>
    XML

    assert_equal "/correct", item.link_alternate
    assert_nil item.link_self
  end

  def test_relations_stay_within_their_entry
    feed = SimpleRSS.parse <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Separate entries</title>
        <link rel="edit" href="/feed-edit"/>
        <entry><title>First</title><link rel="self" href="/first"/></entry>
        <entry><title>Second</title><link rel="edit" href="/second"/></entry>
      </feed>
    XML

    assert_equal "/first", feed.first.link_self
    assert_nil feed.first.link_edit
    assert_equal "/second", feed[1].link_edit
    assert_nil feed[1].link_self
  end

  def test_first_matching_relation_wins
    item = parse_entry(<<~XML).first
      <link rel="alternate" href="/first"/>
      <link rel="alternate" href="/second"></link>
    XML

    assert_equal "/first", item.link_alternate
  end

  def test_relations_preserve_case_insensitive_matching
    item = parse_entry('<LINK REL="ALTERNATE" HREF="/article"/>').first

    assert_equal "/article", item.link_alternate
    assert_equal "/article", item[:"link+alternate"]
  end

  def test_hash_and_json_serialization_include_both_relation_keys
    feed = parse_entry('<link rel="alternate" href="/article"/>')
    expected = { title: "Entry", link: "/article", "link+alternate": "/article", link_alternate: "/article" }

    assert_equal expected, feed.first
    assert_equal expected, feed.to_hash[:items].first
    assert_equal expected, feed.as_json[:items].first
    assert_equal expected, JSON.parse(feed.to_json, symbolize_names: true)[:items].first
  end

  def test_custom_relations_preserve_legacy_keys_and_unrelated_tag_names
    original_tags = SimpleRSS.item_tags.dup
    SimpleRSS.item_tags.push(:"link+enclosure", :"custom:label+featured", :"custom:value")
    item = parse_entry(<<~XML).first
      <link href="/episode.mp3" rel="enclosure"/>
      <custom:label rel="featured">Featured</custom:label>
      <custom:value>Unchanged</custom:value>
    XML

    assert_equal "/episode.mp3", item.link_enclosure
    assert_equal "/episode.mp3", item[:"link+enclosure"]
    assert_equal "Featured", item.custom_label_featured
    assert_equal "Featured", item[:"custom_label+featured"]
    assert_equal "Unchanged", item.custom_value
  ensure
    SimpleRSS.item_tags.replace(original_tags)
  end

  private

  def parse_entry(content)
    SimpleRSS.parse <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Relation links</title>
        <entry><title>Entry</title>#{content}</entry>
      </feed>
    XML
  end
end
