require 'minitest/autorun'
require 'rack/routes'
require 'rack/test'

class TestRack
end
class RoutesTestCase < MiniTest::Unit::TestCase
  include Rack::Test::Methods

  def app
    Rack::Lint.new Rack::Routes
  end

  def assert_response status, body = nil
    assert_equal status, last_response.status
    assert_equal body, last_response.body if body
  end
end
