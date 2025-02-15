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

    attr_accessor :cgi

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
    attr_accessor :cgi
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
      arg.ends_with? "\n" or @out << "\n"
    end
    def nl
      @out << "\n"
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

    private

    def method_missing sym, *args
      if args.empty? and CGIENV.include? sym[ /\A(\w+?)_\w+\z/, 1] then
        ENV[ sym.to_s.upcase]
      else
        super
      end
    end

    public

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

    def parameters! nl: false, sym: false, strip: false
      @parameters ||= parameters nl: nl, sym: sym, strip: strip
      nil
    end

    def parameters nl: false, sym: false, strip: false
      if block_given? then
        parameter_data.parse do |k,v,**kw|
          k = k.to_sym if sym
          if v then
            v.strip! if strip
            v.gsub! "\r\n", "\n" if nl
          end
          yield k, v.notempty?, **kw
        end
      else
        p = {}
        parameters nl: nl, sym: sym, strip: strip do |k,v|
          p[ k] = v
        end
        p
      end
    end

    def parameter_data
      case request_method
        when "GET", "HEAD" then
          dc, d = Data::UrlEnc, query_string
        when "POST"        then
          d = $stdin.binmode.read
          d.bytesize == content_length.to_i or
            warn "Content length #{content_length} is wrong (#{d.bytesize})."
          ct = ContentType.parse content_type
          d.force_encoding ct[ :charset]||Encoding::ASCII_8BIT
          dc = case ct.fulltype
            when "application/x-www-form-urlencoded"      then Data::UrlEnc
            when "multipart/form-data"                    then a = [ ct.hash] ; Data::Multiparted
            when "text/plain"                             then Data::Plain
            when "application/json"                       then Data::Json
            when "application/x-yaml", "application/yaml" then Data::Yaml
            else                                               Data::UrlEnc
          end
        else
          dc, d = Data::Lines, read_interactive
      end
      dc.new d, *a
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
      class Multiparted < Plain
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
          super nil
        end
        def data ; @data ||= @lines.join "\n" ; end
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
          $stderr.puts "A blank line finishes."
          l = []
          while (a = $stdin.gets) do
            a.chomp!
            break unless a.notempty?
            l.push a
          end
          l
        else
          l = []
          $stdin.read.each_line { |a|
            a.chomp!
            next unless a.notempty?
            next if a =~ /^#/
            l.push a
          }
          l
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
          res.body = if $!.class.const_defined? :HTTP_STATUS then
            res.headers.add :status, "%03d" % $!.class::HTTP_STATUS
            $!.message + "\n"
          else
            # Why doesn't Ruby provide the encoding of #message?
            ($!.full_message highlight: false, order: :top).force_encoding $!.message.encoding
          end
          res.headers.add :content_type, "text/plain", charset: res.body.encoding
        }
      end
    rescue Done
      @out << $!.result.to_s
    ensure
      @out = nil
    end

    def document cls = Html, *args, &block
      done { |res|
        doc = cls.new
        doc.cgi = self
        res.body = ""
        doc.generate res.body do
          doc.document *args, &block
        end

        ct = if doc.respond_to?    :content_type then doc.content_type
        elsif   cls.const_defined? :CONTENT_TYPE then doc.class::CONTENT_TYPE
        end
        if ct then
          cs = if doc.respond_to?    :charset then doc.charset
          elsif   cls.const_defined? :CHARSET then doc.class::CHARSET
          else
            res.body.encoding||Encoding.default_external
          end
          res.headers.add :content_type, ct, charset: cs
        end
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
      dest
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

