require 'helper'

class TestRack::TestRoutes < RoutesTestCase
  def setup
    @env = {'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/'}
    app.locations.clear
  end

  def test_location_exact
    app.location '/', :exact => true do
      "1"
    end

    assert_location_match '1', '/'
    refute_location_match '/asdf'
  end

  def test_location_string
    app.location '/' do
      "2"
    end

    assert_location_match '2', '/'
    assert_location_match '2', '/asdf'
  end

  def test_location_string_longest
    app.location '/' do
      "2"
    end
    app.location '/asd' do
      "3"
    end
    app.compile!

    assert_location_match '3', '/asdf'
  end

  def test_location_complex
    app.location '/', :exact => true do
      "1"
    end
    app.location '/' do
      "2"
    end
    app.location '/images/', :prefix => '^~' do
      "3"
    end
    app.location %r/\.(gif|jpg|jpeg)$/i do
      "4"
    end

    assert_location_match '1', '/'
    assert_location_match '2', '/docs/docs.html'
    assert_location_match '3', '/images/1.gif'
    assert_location_match '4', '/docs/1.jpg'
  end

  def test_decoded_uris
    app.location '/images/ /test' do
      '1'
    end

    assert_location_match '1', '/images/%20/test'
  end

  def test_captures
    app.location %r/^\/imag(.*)/ do
    end

    @env['PATH_INFO'] = '/images/foo'
    app.call @env

    m = @env['routes.location.matchdata']
    assert_equal 'es/foo', m[1]
  end

  def test_request_method
    app.location '/', :method => 'GET' do
      '1'
    end
    app.location '/', :method => 'POST' do
      '2'
    end

    assert_location_match '1', '/'
    assert_location_match '2', '/', 'REQUEST_METHOD' => 'POST'
  end

  def test_string_break_skips_regex
    app.location '/asd', :prefix => '^~' do
      '1'
    end

    app.location %r/\/asdf/ do
      '2'
    end

    assert_location_match '1', '/asdf'
  end

  def test_regex_first
    app.location '/asd' do
      '1'
    end

    assert_location_match '1', '/asdf'

    app.location %r/\/asdf/ do
      '2'
    end

    assert_location_match '2', '/asdf'
  end

  def test_call_twice
    app.location %r/\/asdf/ do
      '2'
    end

    assert_location_match '2', '/asdf'
    assert_location_match '2', '/asdf'
  end

  def test_invalid_types
    assert_raises app::LocDirectiveError do
      app.location '/', :prefix => nil do
      end
    end
    assert_raises app::LocDirectiveError do
      app.location '/', :prefix => 'unknown' do
      end
    end
  end

  def assert_location_match expected, path, opts = {}
    @env.merge! opts
    @env['PATH_INFO'] = path
    actual = app.call @env
    assert_equal expected, actual, path
  end

  def refute_location_match path
    assert_raises NoMethodError do
      app.call 'PATH_INFO' => path
    end
  end

end
