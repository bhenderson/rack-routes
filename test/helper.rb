require 'minitest/autorun'
require 'rack/routes'

class TestRack
end
class RoutesTestCase < MiniTest::Unit::TestCase
  def app
    Rack::Routes
  end
end
