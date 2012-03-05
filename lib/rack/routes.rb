require 'uri'
require 'rack/file'

module Rack
  class Routes
    VERSION = '0.2.0'
    TYPES = [:file, :exact, :string_break, :regex, :string]
    SORT_TYPES = [:exact, :string, :string_brea]

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
        SORT_TYPES.each do |type|
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
      # +app+:: Optional object which responds to :call
      # +block+:: required if +app+ is missing
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
      # raises ArgumentError if app or block is missing or if type is invalid
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

      def location path, *args, &blk
        app = args.last.respond_to?(:call) ? args.pop : blk
        raise ArgumentError, 'must provide either an app or a block' unless app

        opts = Hash === args.last ? args.pop : {}

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

        raise ArgumentError, "unknown type `#{type}'" unless TYPES.include? type

        locations[type] << [path, app, opts]
      end

      # accessor for @locations hash
      def locations
        @locations ||= Hash.new{|h,k| h[k] = []}
      end

      # try_files [path1...], :dir => Dir.pwd
      # Some issues with this method:
      # * how to handle caching? RFC 2616
      # * how to handle compression?
      # it seems like there are other tools much better designed for simply
      # displaying files.
      def try_files *files
        opts = Hash === files.last ? files.pop : {}
        dir = opts.fetch :dir, Dir.pwd
        opts[:files] = files

        app = lambda{|path, env|
          env['PATH_INFO'] = path # override with string matched path
          # TODO Some how pass caching to this
          Rack::File.new(dir).call(env)
        }

        locations[:file] << [dir, app, opts]
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
        yield path, opts
      end
      app
    end

    def find_exact
      find_type(:exact){|pth| pth == @path}
    end

    # Rack::File will server a file or return 404 etc. I want to just test if the file is there.
    def find_files
      path = nil

      app = find_type(:file){ |dir, opts|
        files = opts[:files]
        files << ':uri' if files.empty? # set default pattern
        Dir.chdir(dir) do
          files.any? do |file|
            path = file.gsub ':uri', @path[1..-1] # remove /
            path = './' + path # fix issues for requesting /index.html
            test ?f, path and
              test ?R, path and
              ::File.expand_path(path).start_with?(Dir.pwd) # safe file? ie. no '../'
          end
        end
      }

      return unless app
      app.curry[path]
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
      find_files          ||
        find_exact        ||
        find_string_break ||
        find_regex        ||
        find_string
    end
  end
end
