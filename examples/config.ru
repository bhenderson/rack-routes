$:.unshift '../lib'
require 'rack/routes'
require 'json'

class Server
  class Request < Rack::Request
  end
  class Response < Rack::Response
  end

  def self.route verb, path, opts = {}, &blk
    app = self
    opts = {
      'REQUEST_METHOD' => verb,
    }.merge! opts

    Rack::Routes.location path, opts do |env|
      app.call(env, &blk)
    end
  end

  def self.get(*a, &b)  route 'GET', *a, &b end
  def self.post(*a, &b) route 'POST', *a, &b end

  def self.call env, &blk
    new.call! env, &blk
  end

  attr_reader :env, :request, :response
  def call! env, &blk
    @env = env
    @request  = Request.new @env
    @response = Response.new

    status 200
    content_type 'text/plain'

    response.write instance_exec(&blk)
    response.finish
  end

  def content_type type
    return headers['Content-Type'] unless type
    headers 'Content-Type' => type
  end

  def headers opts = {}
    response.headers.merge! opts
  end

  def status num = nil
    return response.status unless num
    response.status = num.to_i
  end

  get /images/i do
    content_type 'application/json'
    env.to_json
  end

  get '= /' do
    foo
  end

  get '/asdf' do
    'hi there'
  end

  post '/' do
    bar
  end

  def foo
    '3'
  end

  def bar
    '4'
  end
end

run Rack::Routes
