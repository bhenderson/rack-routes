require 'helper'

class TestRack::TestRoutes < RoutesTestCase
  include Rack::Routes

  def setup
    Rack::Routes.locations.clear
  end

  def test_not_found
    get '/'
    assert_response 404, 'Route not found'
  end

  def test_regex
    location %r''

    assert_equal [:regex], Rack::Routes.locations.keys
  end

  def test_exact
    location '= /'

    assert_equal [:exact], Rack::Routes.locations.keys
  end

  def test_exact_space
    location '=  /'

    assert_equal [:exact], Rack::Routes.locations.keys
  end

  def test_exact_must_begin_with_slash
    util_argument_error '= '
  end

  def test_string_break
    location '^~ /'

    assert_equal [:string_break], Rack::Routes.locations.keys
  end

  def test_sting_break_must_begin_with_slash
    util_argument_error '^~'
  end

  def test_string_break_space
    location '^~  /'

    assert_equal [:string_break], Rack::Routes.locations.keys
  end

  def test_string
    location '/'

    assert_equal [:string], Rack::Routes.locations.keys
  end

  def test_string_must_begin_with_slash
    util_argument_error ''
  end

  def test_configuration_a
    setup_test_routes

    get '/'
    assert_response 200, 'A'
  end

  def test_configuration_b
    setup_test_routes

    get '/index.html'
    assert_response 200, 'B'
  end

  def test_configuration_c
    setup_test_routes

    get '/documents/document.html'
    assert_response 200, 'C'
  end

  def test_configuration_d
    setup_test_routes

    get '/images/1.gif'
    assert_response 200, 'D'
  end

  def test_configuration_e
    setup_test_routes

    get '/documents/1.gif'
    assert_response 200, 'E'
  end

  def test_decoded_uris
    loc '/images/ /test' do 'decoded' end

    get '/images/%20/test'
    assert_response 200, 'decoded'
  end

  def test_matchdata
    matches = nil
    loc %r'/images/(.*)' do |env|
      matches = env['rack.routes.matches']; ''
    end

    get '/images/2.gif'
    assert_response 200
    assert_equal ['/images/2.gif', '2.gif'], matches.to_a
  end

  def test_request_method_miss
    loc '/foo', 'REQUEST_METHOD' => 'POST' do 'post' end

    get '/foo'
    assert_response 404, 'Route not found'
  end

  def test_request_method_match
    loc '/foo', 'REQUEST_METHOD' => 'POST' do 'post' end

    post '/foo'
    assert_response 200, 'post'
  end

  def test_multiple_request_methods
    loc '/foo', 'REQUEST_METHOD' => 'GET' do 'foo post' end
    loc '/bar', 'REQUEST_METHOD' => 'POST' do 'bar post' end

    post '/bar'
    assert_response 200, 'bar post'
  end

  def test_env_match_fuzzy
    loc '/foo', 'ACCEPT' => %r'^app/json' do 'json' end

    get '/foo', {}, 'ACCEPT' => 'app/json; utf-8'
    assert_response 200, 'json'
  end

  def loc path, opts = {}
    location path, opts do |env|
      [200, {'Content-Type' => 'text/plain'}, [yield(env)]]
    end
  end

  def setup_test_routes
    loc '= /'                 do 'A' end
    loc '/'                   do 'B' end
    loc '/documents/'         do 'C' end
    loc '^~ /images/'         do 'D' end
    loc %r'\.(gif|jpg|jpeg)$' do 'E' end

    # this is taken care of by Matcher.new, but it only gets run once
    # for the whole file.
    Rack::Routes.compile!
  end

  def util_argument_error path
    e = assert_raises ArgumentError do
      location path
    end

    assert_equal "unknown type #{path.inspect}", e.message
  end
end
