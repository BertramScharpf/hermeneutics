#
#  hermeneutics/cgi.rb  -- CGI responses
#

require "supplement"
require "hermeneutics/escape"
require "hermeneutics/message"
require "hermeneutics/html"


module Hermeneutics

  class Html

    CONTENT_TYPE = "text/html"

    attr_reader :cgi

    def initialize cgi
      @cgi = cgi
    end

    def form! **attrs, &block
      attrs[ :action] = @cgi.fullname attrs[ :action]
      form **attrs, &block
    end

    def href dest, params = nil, anchor = nil
      @utx ||= URLText.new
      dest = @cgi.fullname dest
      @utx.mkurl dest, params, anchor
    end

    def href! dest, params = nil, anchor = nil
      dest = @cgi.fullpath dest
      href dest, params, anchor
    end

  end

  class Text
    CONTENT_TYPE = "text/plain"
    attr_reader :cgi
    def initialize cgi
      @cgi = cgi
    end
    def generate out = nil
      @out = out||$stdout
      yield
    ensure
      @out = nil
    end
    def document *args, **kwargs, &block
      build *args, **kwargs, &block
    end
    def build *args, **kwargs, &block
    end
    private
    def p *args
      args.each { |a| @out << a.to_s }
    end
    def l arg
      arg = arg.to_s
      @out << arg
      arg.ends_with? $/ or @out << $/
    end
    def nl
      @out << $/
    end
  end


  # Example:
  #
  # class MyCgi < Cgi
  #   def run
  #     p = parameters
  #     if p.empty? then
  #       location "/sorry.rb"
  #     else
  #       document MyHtml
  #     end
  #   rescue
  #     document MyErrorPage
  #   end
  # end
  # Cgi.execute
  #
  class Cgi

    class <<self
      attr_accessor :main
      def inherited cls
        Cgi.main = cls
      end
      def execute out = nil
        (@main||self).new.execute out
      end
    end

    CGIENV = %w(content document gateway http query
                          remote request script server unique)

    def method_missing sym, *args
      if args.empty? and CGIENV.include? sym[ /\A(\w+?)_\w+\z/, 1] then
        ENV[ sym.to_s.upcase]
      else
        super
      end
    end

    def https?
      ENV[ "HTTPS"].notempty?
    end

    # Overwrite this.
    #
    # If you're reacting to POST uploads, please consider limiting
    # the upload size.
    #   Apache:   LimitRequestBody
    #   Nginx:    client_max_body_size
    #   Lighttpd: server.max-request-size
    #
    def run
      document Html
    end

    def parameters &block
      if block_given? then
        data.parse &block
      else
        p = {}
        parameters do |k,v|
          p[ k] = v
        end
        p
      end
    end

    def data
      case request_method
        when "GET", "HEAD" then
          Data::UrlEnc.new query_string
        when "POST"        then
          data = $stdin.read
          data.bytesize == content_length.to_i or
            warn "Content length #{content_length} is wrong (#{data.bytesize})."
          ct = ContentType.parse content_type
          data.force_encoding ct[ :charset]||Encoding::ASCII_8BIT
          case ct.fulltype
            when "application/x-www-form-urlencoded" then
              Data::UrlEnc.new data
            when "multipart/form-data" then
              Data::Multipart.new data, ct.hash
            when "text/plain" then
              Data::Plain.new data
            when "application/json" then
              Data::Json.new data
            when "application/x-yaml", "application/yaml" then
              Data::Yaml.new data
            else
              Data::UrlEnc.new data
          end
        else
          Data::Lines.new read_interactive
      end
    end


    private

    module Data
      class Plain
        attr_reader :data
        def initialize data
          @data = data
        end
      end
      class UrlEnc < Plain
        def parse &block
          URLText.decode_hash @data, &block
        end
      end
      class Multipart < Plain
        def initialize data, params
          super data
          @params = params
        end
        def parse
          mp = Multipart.parse @data, **@params
          mp.each { |part|
            cd = part.headers.content_disposition
            if cd.caption == "form-data" then
              yield cd.name, part.body_decoded, **cd.hash
            end
          }
        end
      end
      class Lines < Plain
        def initialize lines
          @lines = lines
        end
        def data ; @lines.join $/ ; end
        def parse
          @lines.each { |s|
            k, v = s.split %r/=/
            v ||= k
            [k, v].each { |x| x.strip! }
            yield k, v
          }
        end
      end
      class Json < Plain
        def parse &block
          require "json"
          (JSON.load @data).each_pair &block
        end
      end
      class Yaml < Plain
        def parse &block
          require "yaml"
          (YAML.load @data).each_pair &block
        end
      end
    end


    def read_interactive
      ENV[ "SCRIPT_NAME"] ||= $0
      if $*.any? then
        $*
      else
        if $stdin.tty? then
          $stderr.puts "Offline mode: Enter name=value pairs on standard input."
          l = []
          while (a = $stdin.gets) and a !~ /^$/ do
            l.push a
          end
          l
        else
          $stdin.read.split $/
        end
      end
    end

    class Done < Exception
      attr_reader :result
      def initialize result
        super nil
        @result = result
      end
    end

    def done ct = nil
      res = Message.create
      yield res
      d = Done.new res
      raise d
    end

    public

    def execute out = nil
      @out ||= $stdout
      begin
        run
      rescue
        done { |res|
          res.body = "#$! (#{$!.class})#$/"
          $@.each { |a| res.body << "\t" << a << $/ }
          res.headers.add :content_type,
                            "text/plain", charset: res.body.encoding
        }
      end
    rescue Done
      @out << $!.result.to_s
    ensure
      @out = nil
    end

    def document cls = Html, *args, &block
      done { |res|
        doc = cls.new self
        res.body = ""
        doc.generate res.body do
          doc.document *args, &block
        end

        ct = if doc.respond_to?    :content_type then doc.content_type
        elsif   cls.const_defined? :CONTENT_TYPE then doc.class::CONTENT_TYPE
        end
        ct and res.headers.add :content_type, ct,
                    charset: res.body.encoding||Encoding.default_external
        if doc.respond_to? :cookies then
          doc.cookies do |c|
            res.headers.add :set_cookie, c
          end
        end
      }
    end

    def location dest = nil, params = nil, anchor = nil
      if Hash === dest then
        dest, params, anchor = anchor, dest, params
      end
      utx = URLText.new mask_space: true
      unless dest =~ %r{\A\w+://} then
        dest = %Q'#{https? ? "https" : "http"}://#{http_host||"localhost"}#{fullpath dest}'
      end
      url = utx.mkurl dest, params, anchor
      done { |res| res.headers.add "Location", url }
    end

    def fullname dest
      if dest then
        if dest =~ /\.\w+\z/ then
          dest
        else
          "#{dest}.rb"
        end
      else
        script_name
      end
    end

    def fullpath dest
      dest = fullname dest
      unless File.absolute_path? dest then
        dir = File.dirname script_name rescue ""
        dest = File.join dir, dest
      end
    end

    def warn msg
    end


    if defined? MOD_RUBY then
      # This has not been tested.
      def query_string
        Apache::request.args
      end
    end

  end

end

