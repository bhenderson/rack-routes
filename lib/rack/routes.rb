module Rack
  module Routes
    VERSION    = '1.0.0'

    class Matcher
      NOTFOUND = proc{|env| [404, {'Content-Type' => 'text/plain',
                   'Content-Length' => '15'}, ['Route not found']] }

      def initialize app = nil
        Rack::Routes.compile!
        @app = app || NOTFOUND
      end

      def call env
        dup.call! env
      end

      def call! env
        @env  = env
        @path = URI.decode_www_form_component(@env['PATH_INFO']).
                  downcase

        match.call(@env)
      end

      def find_exact
        find_type(:exact){|pth| pth == @path}
      end

      def find_regex
        find_type(:regex){|pth| pth === @path and
          @env['rack.routes.matches'] = Regexp.last_match }
      end

      def find_string
        find_type(:string){|pth| @path.start_with? pth}
      end

      def find_string_break
        find_type(:string_break){|pth| @path.start_with? pth}
      end

      def find_type type
        app, _ = Rack::Routes.locations[type].find do |_, path, opts|
          next unless opts.all? do |k,v|
            v == @env[k] or v === @env[k]
          end
          yield path
        end

        app
      end

      def match
        find_exact          ||
          find_string_break ||
          find_regex        ||
          find_string       ||
          @app
      end

    end

    def self.new app = nil
      @app ||= Matcher.new app
    end

    def self.call env
      new.call env
    end

    def self.compile!
      # longest first
      locations.each_pair do |type, paths|
        break if type == :regex
        paths.sort_by!{|_, path| -path.length}
      end
    end

    def self.locations
      @locations ||= Hash.new {|h,k| h[k] = []}
    end

    def location path, opts = {}, &blk
      path = path.downcase if String === path
      type = case path
             when Regexp
               :regex
             when %r'^/'
               :string
             when %r'^\^~\s+(/.*)'
               path = $1
               :string_break
             when %r'^=\s+(/.*)'
               path = $1
               :exact
             end

      raise ArgumentError, "unknown type #{path.inspect}" unless type
      Rack::Routes.locations[type] << [blk, path, opts]
    end
    module_function :location

  end
end
