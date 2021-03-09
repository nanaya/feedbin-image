require_relative "../test_helper"
class FindImageTest < Minitest::Test
  def setup
    flush
  end

  def test_should_process_an_image
    image_url = "http://example.com/image.jpg"
    page_url = "http://example.com/article"
    urls = [image_url]

    stub_request_file("html.html", page_url)
    stub_request_file("image.jpeg", image_url, headers: {content_type: "image/jpeg"})

    stub_request(:get, "http://example.com/image/og_image.jpg").to_return(status: 404)
    stub_request(:get, "http://example.com/image/twitter_image.jpg").to_return(status: 404)

    stub_request(:put, /.*\.s3\.amazonaws\.com/).to_return(status: 200, body: aws_copy_body)

    Sidekiq::Testing.inline! do
      FindImage.perform_async(SecureRandom.hex, urls, page_url)
    end

    assert_requested :get, "http://example.com/image/og_image.jpg"
    assert_requested :get, "http://example.com/image/twitter_image.jpg"

    assert_equal 0, EntryImage.jobs.size
    FindImage.new.perform(SecureRandom.hex, urls, nil)
    assert_equal 1, EntryImage.jobs.size
  end

  def test_should_enqueue_recognized_image
    url = "https://i.ytimg.com/vi/id/maxresdefault.jpg"
    image_url = "http://example.com/image.jpg"

    stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: ("lorem " * 3_500))

    assert_equal 0, ProcessImage.jobs.size
    FindImage.new.perform(SecureRandom.hex, [image_url], "https://www.youtube.com/watch?v=id")
    assert_equal 1, ProcessImage.jobs.size

    assert_requested :get, url
    refute_requested :get, image_url
  end

  def test_should_try_all_urls
    urls = [
      "http://example.com/image_1.jpg",
      "http://example.com/image_2.jpg",
      "http://example.com/image_3.jpg",
    ]

    urls.each do |url|
      stub_request(:get, url).to_return(headers: {content_type: "image/jpg"}, body: ("lorem " * 3_500))
    end

    Sidekiq::Testing.inline! do
      FindImage.perform_async(SecureRandom.hex, urls, nil)
    end

    assert_requested :get, urls[0]
    assert_requested :get, urls[1]
    assert_requested :get, urls[2]
  end
end
