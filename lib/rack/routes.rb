require 'uri'
require 'rack/file'

module Rack
  class Routes
    VERSION = '0.2.0'
    TYPES = [:file, :exact, :string_break, :regex, :string]
    SORT_TYPES = [:exact, :string, :string_brea]

    class << self

      # Private: Add new +path+ of type +type+.
      #
      # type - A Symbol and must be one of +TYPES+.
      # path - A String/Regexp to match PATH_INFO.
      # app  - An object that responds to call. yields +env+.
      # opts - A Hash of various options.
      #
      # Raises TypeError if +type+ is not one of +TYPES+.
      #
      # Returns nothing.
      def add_location type, path, app, opts
        raise TypeError, "unknown type `#{type}'" unless
          TYPES.include? type
        raise TypeError, "#{app.inspect} must respond to :call" unless
          app.respond_to? :call
        raise TypeError, "#{opts.inspect} must be a Hashy" unless
          opts.respond_to?(:[]) and opts.respond_to?(:[]=)

        @locations ||= Hash.new{|h,k| h[k] = []}
        @locations[type] << [path, app, opts]
      end

      # convience rack interface
      # Enables the use of either:
      # use Rack::Routes
      # or
      # run Rack::Routes

      def call env
        @app ||= new
        @app.call env
      end

      # Public: Clear currently known locations. This is global for everything
      # that uses this.
      def clear_locations
        @locations.clear if @locations
      end

      # location directives should be run in a certain order. This is needed to
      # establish that order.

      def compile!
        # longest first
        SORT_TYPES.each do |type|
          @locations[type].sort_by!{|path, _| -path.length}
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

        add_location type, path, app, opts
      end

      # Public: Nginx like directive "try_files"
      #   if the request matches an existing file, that file will be served.
      #   requests for files outside of this directory are silently ignored
      #   (include '..'). Files can contain the string ':uri' in which case
      #   that string will be replaced with the PATH_INFO string minus the
      #   leading slash (/) Nginx requires a default uri. The default uri in
      #   this case is just the next best matching path
      #
      # files - one or more file pattern. Defaults to ':uri'
      # opts  - hash of options
      #         :dir           - base directory in which to serve files.
      #         :cache_control - not sure actually. probably something like
      #                          rack/cache
      #
      # Examples
      #
      #   try_files /system/maintenance.html $uri $uri/index.html $uri.html
      #
      #   a request for /foobar will try the following:
      #   $PROJECT_ROOT/system/maintenance.html or
      #   $PROJECT_ROOT/foobar or
      #   $PROJECT_ROOT/foobar/index.html or
      #   $PROJECT_ROOT/foobar.html
      #
      # Some issues I have with this method:
      # * how to handle compression?
      def try_files *files
        opts = Hash === files.last ? files.pop : {}
        dir = opts.fetch :dir, Dir.pwd
        files << ':uri' if files.empty?
        opts[:files] = files

        app = Rack::File.new(dir, opts[:cache_control])

        add_location :file, dir, app, opts
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

    # Private: Wrapper method for finding +type+
    def find_type type
      _, app = locations[type].find do |path, _, opts|
        next if opts[:method] and opts[:method] != @env['REQUEST_METHOD']
        yield path, opts
      end
      app
    end

    # Private: Match exact type.
    def find_exact
      find_type(:exact){|pth| pth == @path}
    end

    # Private: Match file type.
    def find_files
      find_type(:file){ |dir, opts|
        # Rack::File will serve a file or return 404 etc. I want to just
        # test if the file is there.
        Dir.chdir(dir){
          opts[:files].any?{ |file| valid_path_from file }}
      }
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

    # Private: Accessor method for @locations Hash. The class doesn't have an
    # accessor method to keep people from adding arbitrary types, etc.
    def locations
      self.class.instance_variable_get :@locations
    end

    # search files
    # then search exact matches
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

    # Private: Convert file name to valid path from Dir.pwd
    #   file is invalid if not there; not readable; not "within" current
    #   directory.
    def valid_path_from file
      path = file.gsub ':uri', @path[1..-1]               # remove /
      path = './' + path                                  # make all paths relative to current dir. (fix issues for requesting /index.html)
      test ?f, path and test ?r, path and                 # file exists? and file readable by effective uid/gid?
        ::File.expand_path(path).start_with?(Dir.pwd) and # safe file? ie. no '../'
        @env['PATH_INFO'] = path                          # reset path to expanded form for reading file
    end

  end
end
