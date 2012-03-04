$:.unshift '../lib'
require 'rack/routes'

class Server
  class Request < Rack::Request
  end
  class Response < Rack::Response
  end

  Rack::Routes.try_files

  def self.route verb, path, opts = {}, &blk
    app = self
    opts.merge! :method => verb.upcase

    # change default behavior to use exact
    opts[:exact] = opts.fetch(:exact, true)
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

  get // do
    env.inspect
  end

  get '/' do
    foo
  end

  get '/asdf', :exact => false do
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

use Rack::Routes
run lambda{|env| [500, {'Content-Type' => 'text/plain'}, ['not found']]}
