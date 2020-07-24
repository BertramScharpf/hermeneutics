#
#  hermeneutics/cgi.rb  -- CGI responses
#

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
      attrs[ :action] = @cgi.fullpath attrs[ :action]
      form **attrs, &block
    end

    def href dest, params = nil, anchor = nil
      @utx ||= URLText.new
      dest = @cgi.fullpath dest
      @utx.mkurl dest, params, anchor
    end

    def href! params = nil, anchor = nil
      href nil, params, anchor
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

    # Overwrite this.
    def run
      document Html
    end

    def parameters &block
      if block_given? then
        case request_method
          when "GET", "HEAD" then parse_query query_string, &block
          when "POST"        then parse_posted &block
          else                    parse_input &block
        end
      else
        p = {}
        parameters do |k,v|
          p[ k] = v
        end
        p
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

    private

    def parse_query data, &block
      URLText.decode_hash data, &block
    end

    def parse_posted &block
      data = $stdin.read.force_encoding Encoding::ASCII_8BIT
      data.bytesize == content_length.to_i or
        @warn = "Content length #{content_length} is wrong (#{data.bytesize})."
      ct = ContentType.parse content_type
      case ct.fulltype
        when "application/x-www-form-urlencoded" then
          parse_query data, &block
        when "multipart/form-data" then
          mp = Multipart.parse data, **ct.hash
          parse_multipart mp, &block
        when "text/plain" then
          # Suppose this is for testing purposes only.
          mk_params data.lines, &block
        else
          parse_query data, &block
      end
    end

    def parse_multipart mp
      mp.each { |part|
        cd = part.headers.content_disposition
        if cd.caption == "form-data" then
          yield cd.name, part.body_decoded, **cd.hash
        end
      }
    end

    def mk_params l
      l.each { |s|
        k, v = s.split %r/=/
        v ||= k
        [k, v].each { |x| x.strip! }
        yield k, v
      }
    end

    def parse_input &block
      if $*.any? then
        l = $*
      else
        if $stdin.tty? then
          $stderr.puts <<~EOT
            Offline mode: Enter name=value pairs on standard input.
          EOT
        end
        l = []
        while (a = $stdin.gets) and a !~ /^$/ do
          l.push a
        end
      end
      ENV[ "SCRIPT_NAME"] = $0
      mk_params l, &block
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
        dest = %Q'#{https? ? "https" : "http"}://#{http_host}#{fullpath dest}'
      end
      url = utx.mkurl dest, params, anchor
      done { |res| res.headers.add "Location", url }
    end

    def fullpath dest
      if dest then
        dest =~ %r{\A/} || dest =~ /\.\w+\z/ ? dest : dest + ".rb"
      else
        File.basename script_name
      end
    end


    if defined? MOD_RUBY then
      # This has not been tested.
      def query_string
        Apache::request.args
      end
    end

  end

end

