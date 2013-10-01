#
#  hermes/cgi.rb  -- CGI responses
#

require "hermes/escape"
require "hermes/message"
require "hermes/html"


module Hermes

  class PostedFile < String
    attr_reader :filename, :content_type
    def initialize data, filename, content_type
      @filename, @content_type = filename, content_type
      super data
    end
  end


  class Html

    CONTENT_TYPE = "text/html"

    attr_reader :cgi

    def initialize cgi, *args
      @cgi = cgi
    end

    def form! name, attrs = nil, &block
      attrs ||= {}
      attrs[ :name] = name
      attrs[ :action] = scriptpath attrs[ :action]
      form attrs, &block
    end

    def href dest, params = nil, anchor = nil
      @utx ||= URLText.new
      dest = scriptpath dest
      @utx.mkurl dest, params, anchor
    end

    def href! params = nil, anchor = nil
      href nil, params, anchor
    end

    private

    def scriptpath dest
      unless dest =~ %r{\A/} then
        if dest then
          dest =~ /\.\w+\z/ or dest += ".rb"
        else
          dest = File.basename @cgi.script_name
        end
      end
      dest
    end

  end


  # Example:
  #
  # class MyCgi < Cgi
  #   def run
  #     if params.empty? then
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
        @main.new.execute out
      end
    end

    # Overwrite this.
    def run
      document Html
    end

    def initialize inp = nil
      $env ||= ENV
      @inp ||= $stdin
      @params = case request_method
        when "GET", "HEAD" then parse_query query_string
        when "POST"        then parse_posted
        else                    parse_input
      end
    ensure
      @inp = nil
    end

    attr_reader :params
    alias param params
    alias parameters params
    alias parameter params
    def [] key ; @params[ key] ; end

    CGIENV = %w(content document gateway http query
                          remote request script server unique)

    def method_missing sym, *args
      if args.empty? and CGIENV.include? sym[ /\A(\w+?)_\w+\z/, 1] then
        $env[ sym.to_s.upcase]
      else
        super
      end
    end

    def https?
      $env[ "HTTPS"].notempty?
    end

    private

    def parse_query data
      URLText.decode_hash data
    end

    def parse_posted
      data = @inp.read
      data.bytesize == content_length.to_i or
        @warn = "Content length #{content_length} is wrong (#{data.bytesize})."
      ct = ContentType.parse content_type
      case ct.fulltype
        when "application/x-www-form-urlencoded" then
          parse_query data
        when "multipart/form-data" then
          mp = Multipart.parse data, ct.hash
          parse_multipart mp
        when "text/plain" then
          # Suppose this is for testing purposes only.
          l = []
          data.each_line { |a| l.push a }
          mk_params l
        else
          parse_query data
      end
    end

    def parse_multipart mp
      URLText::Dict.create do |p|
        mp.each { |part|
          cd = part.headers.content_disposition
          if cd.caption == "form-data" then
            val = if (fn = cd.filename) then
              PostedFile.new part.body, fn, part.headers.content_type
            else
              part.body
            end
            p.parse cd.name, val
          end
        }
      end
    end

    def mk_params l
      URLText::Dict.create do |p|
        l.each { |s|
          s.chomp! unless s.frozen?
          k, v = s.split %r/=/
          p.parse k, v||true if k
        }
      end
    end

    def parse_input
      if $*.any? then
        l = $*
      else
        if $stdin.tty? then
          $stderr.puts <<-EOT
Offline mode: Enter name=value pairs on standard input.
          EOT
        end
        l = []
        $stdin.readlines.each { |a| l.push a }
      end
      mk_params l
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

    def document cls = Html, *args
      doc = cls.new self, *args
      ct = if doc.respond_to? :content_type then
        doc.content_type
      elsif cls.const_defined? :CONTENT_TYPE then
        doc.class::CONTENT_TYPE
      end
      done { |res|
        res.body = ""
        f = res.body.encoding
        doc.document res.body
        if ct then
          e = res.body.encoding.nil_if f
          res.headers.add :content_type, ct, charset: e
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
        unless dest =~ %r{\A/} then
          dest = if dest then
            d = File.dirname script_name
            dest =~ /\.\w+\z/ or dest += ".rb"
            File.join d, dest
          else
            script_name
          end
        end
        dest = %Q'#{https? ? "https" : "http"}://#{http_host}#{dest}'
      end
      url = utx.mkurl dest, params, anchor
      done { |res| res.headers.add "Location", url }
    end


    if defined? MOD_RUBY then
      # This has not been tested yet.
      def query_string
        Apache::request.args
      end
    end

  end

end

