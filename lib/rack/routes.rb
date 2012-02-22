require 'uri'

module Rack
  class Routes
    VERSION = '0.1.1'

    class LocDirectiveError < RuntimeError; end

    class << self

      # convience rack interface
      # Enables the use of either:
      # use Rack::Routes
      # or
      # run Rack::Routes

      def call env
        @app ||= new
        @app.call env
      end

      # location directives should be run in a certain order. This is needed to
      # establish that order.

      def compile!
        # longest first
        [:exact, :string, :string_break].each do |type|
          locations[type].sort_by!{|path, _| -path.length}
        end
      end

      ##
      # === Description
      #
      # Main interface method.
      # Reimplementation of nginx location directive.
      #
      # === Args
      # +path+:: The path to match on. Can be String or Regexp.
      # +opts+:: Hash of options. see below.
      #
      # +opts+ keys:
      # +:exact+:: Type of string matching. default false
      #            Also can be +:prefix+ (for making '^~' make sense)
      # +:method+:: HTTP Request Method matching. defaults nil (all)
      # +:type+:: Explicetly set the type of match.
      #
      # +exact+ values can be:
      # +false+:: prefix match
      # +true+:: literal match
      # +=+:: literal match
      # +^~+:: skip regex matching
      #
      # yields +env+
      #
      # === Examples
      #
      # # config.ru
      #
      # # matches everything
      # # but longer matches will get applied first
      # Rack::Routes.location '/' do
      #   [200, {}, ['hi']]
      # end
      #
      # # matches everything beginning with /asdf
      # Rack::Routes.location '/asdf' do
      #   [200, {}, ['hi asdf']]
      # end
      #
      # # matches /foo and not /foobar nor /foo/baz etc.
      # Rack::Routes.location '/foo', :exact => true do
      #   [200, {}, ['hi foo']]
      # end
      #
      # # matches anything beginning with /bar
      # # +path+ can be any ruby regex
      # # matchdata is stored in env['routes.location.matchdata']
      # Rack::Routes.location /\/bar(.*)/ do |env|
      #   m = env['routes.location.matchdata']
      #   [200, {}, ["hi #{m[1]}"]]
      # end
      #
      # # matches beginning of path but stops if match is found. Does not
      # evaluate regexen
      # Rack::Routes.location '/baz', :prefix => '^~' do
      #   [200, {}, ['hi baz']]
      # end
      #
      # run Rack::Routes

      def location path, opts = {}, &blk
        type = opts.fetch(:type, nil)
        type = :regex if Regexp === path
        type ||= case opts.fetch(:exact, opts.fetch(:prefix, false))
                 when FalseClass
                   :string
                 when TrueClass, '='
                   :exact
                 when '^~'
                   :string_break
                 end

        raise LocDirectiveError, "unknown type `#{type}'" unless
          [:regex, :string, :exact, :string_break].include? type

        app = blk

        locations[type] << [path, app, opts]
      end

      # accessor for @locations hash
      def locations
        @locations ||= Hash.new{|h,k| h[k] = []}
      end
    end


    # rack app
    def initialize app = nil
      self.class.compile!
      @app = app
    end

    # rack interface
    def call env
      dup.call! env
    end

    def call! env
      @env  = env
      @path = URI.decode_www_form_component @env['PATH_INFO']

      (matching_app || @app).call(env)
    end

    def find_type type
      _, app = locations[type].find do |path, _, opts|
        next if opts[:method] and opts[:method] != @env['REQUEST_METHOD']
        yield path
      end
      app
    end

    def find_exact
      find_type(:exact){|pth| pth == @path}
    end

    def find_string
      find_type(:string){|pth| @path[0, pth.length] == pth}
    end

    def find_string_break
      find_type(:string_break){|pth| @path[0, pth.length] == pth}
    end

    def find_regex
      find_type(:regex){|pth| pth === @path and
        @env['routes.location.matchdata'] = Regexp.last_match }
    end

    def locations
      self.class.locations
    end

    # search exact matches first
    # then ^~ strings (not sure what else to call them)
    # then regex
    # then all the other strings
    #
    # NOTE the docs say to run strings before regex but I don't see why it
    # matters as the return logic is the same.

    def matching_app
      find_exact          ||
        find_string_break ||
        find_regex        ||
        find_string
    end
  end
end
