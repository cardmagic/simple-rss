require "test_helper"

class MediaAndEnclosureHelpersTest < Test::Unit::TestCase
  def setup
    @feed = SimpleRSS.parse <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>Podcast Feed</title>
          <item>
            <title>Episode 1</title>
            <enclosure url="https://example.com/audio-1.mp3" type="audio/mpeg" length="12345" />
            <media:content url="https://example.com/image-1.jpg" type="image/jpeg" />
            <media:description>Episode image</media:description>
            <media:thumbnail url="https://example.com/thumb-1.jpg" />
            <itunes:duration>00:42:00</itunes:duration>
            <itunes:image href="https://example.com/itunes-1.jpg" />
          </item>
          <item>
            <title>Episode 2</title>
            <media:thumbnail url="https://example.com/thumb-2.jpg" />
          </item>
          <item>
            <title>Episode 3</title>
            <enclosure url="https://example.com/audio-3.mp3" type="audio/mpeg" length="999" />
          </item>
          <item>
            <title>Episode 4</title>
            <enclosure url="" type="audio/mpeg" length="111" />
            <media:thumbnail url="" />
            <itunes:image href="" />
          </item>
        </channel>
      </rss>
    XML
  end

  def test_enclosures_extracts_podcast_enclosures
    enclosures = @feed.enclosures

    assert_equal 2, enclosures.size
    assert_equal "https://example.com/audio-1.mp3", enclosures.first[:url]
    assert_equal "audio/mpeg", enclosures.first[:type]
    assert_equal "12345", enclosures.first[:length]
    assert_equal "Episode 1", enclosures.first[:item][:title]
  end

  def test_images_collects_unique_media_urls
    images = @feed.images

    assert_equal [
      "https://example.com/thumb-1.jpg",
      "https://example.com/image-1.jpg",
      "https://example.com/itunes-1.jpg",
      "https://example.com/thumb-2.jpg"
    ], images
  end

  def test_item_media_helpers
    first_item = @feed.items.first
    second_item = @feed.items[1]
    third_item = @feed.items[2]
    fourth_item = @feed.items.last

    assert_equal true, first_item.has_media?
    assert_equal "https://example.com/image-1.jpg", first_item.media_url

    assert_equal true, second_item.has_media?
    assert_equal "https://example.com/thumb-2.jpg", second_item.media_url

    assert_equal true, third_item.has_media?
    assert_equal "https://example.com/audio-3.mp3", third_item.media_url

    assert_equal false, fourth_item.has_media?
    assert_nil fourth_item.media_url
  end

  def test_media_description_and_itunes_duration_are_parsed
    first_item = @feed.items.first

    assert_equal "Episode image", first_item[:media_description]
    assert_equal "00:42:00", first_item[:itunes_duration]
  end
end
