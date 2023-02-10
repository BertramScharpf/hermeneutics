#
#  hermeneutics/message.rb  --  a message as in mails or in HTTP communication
#

require "hermeneutics/types"
require "hermeneutics/contents"
require "hermeneutics/addrs"


module Hermeneutics

  class Multipart < Mime

    MIME = /^multipart\//

    class IllegalBoundary < StandardError ; end
    class ParseError      < StandardError ; end

    public

    class <<self

      def parse input, **parameters
        b = parameters[ :boundary]
        b or raise ParseError, "Missing boundary parameter."
        list = input.split /^--#{Regexp.quote b}/
        prolog = list.shift
        epilog = list.pop
        epilog and epilog.slice! /\A--\n/ or raise "Missing last separator."
        list.each { |p|
          p.slice! /\A\n/ or raise "Malformed separator: #{b + p[/.*/]}."
        }
        list.map! { |t| Message.parse t }
        new b, prolog, list, epilog
      end

    end

    BOUNDARY_CHARS_STD = [ [*"0".."9"], [*"A".."Z"], [*"a".."z"]].join
    BOUNDARY_CHARS = BOUNDARY_CHARS_STD + "+_./:=-" # "'()+_,-./:=?"

    attr_reader :boundary, :prolog, :list, :epilog

    def initialize boundary, prolog, list, epilog
      @boundary = boundary.notempty?
      @prolog, @list, @epilog = prolog, list, epilog
    end

    def boundary!
      b = BOUNDARY_CHARS_STD.length
      r = Time.now.strftime "%Y%m%d%H%M%S."
      16.times { r << BOUNDARY_CHARS_STD[ (rand b)].chr }
      @boundary = r
    end

    def inspect
      r = ""
      r << "#<#{self.class}:"
      r << "0x%x" % (object_id<<1)
      r << " n=#{@list.length}"
      r << ">"
    end

    def to_s
      @boundary or raise IllegalBoundary
      r = ""
      splitter = "--#@boundary"
      re = /#{Regexp.quote @boundary}/
      @prolog =~ re and raise IllegalBoundary
      r << @prolog
      @list.each { |p|
        s = p.to_s
        s =~ re rescue nil
        $& and raise IllegalBoundary
        r << splitter << "\n" << s
      }
      @epilog =~ re and raise IllegalBoundary
      r << splitter << "--\n" << @epilog
    rescue IllegalBoundary
      boundary!
      retry
    end

    def [] num
      @list[ num]
    end

    def each &block
      @list.each &block
    end

    def length ; @list.length ; end

  end


  class Message < Mime

    MIME = "message/rfc822"

    class ParseError < StandardError ; end

    class Header

      @line_max = 78
      @indent   = 4

      class <<self

        attr_accessor :line_max, :indent

        private :new

        def parse str
          str =~ /:\s*/ or
            raise ParseError, "Header line without a colon: #{str}"
          new $`, $'
        end

        def create name, *contents
          name = build_name name
          i = new name.to_s, nil
          i.set *contents
        end

        def build_name name
          n = name.to_s
          unless n.equal? name then
            n.gsub! /_/, "-"
            n.gsub! /\b[a-z]/ do |c| c.upcase end
          end
          n
        end

      end

      attr_reader :name, :data

      def initialize name, data
        @name, @data, @contents = name, data
      end

      def to_s
        "#@name: #@data"
      end

      def contents type = nil
        if type then
          if @contents then
            if not @contents.is_a? type then
              @contents = type.parse @data
            end
          else
            @contents = type.parse @data
          end
        else
          unless @contents then
            @contents = @data
            @contents.strip!
            @contents.gsub! /\s\+/m, " "
          end
        end
        @contents
      end

      def name_is? name
        (@name.casecmp name).zero?
      end

      def set *contents
        type, *args = *contents
        d = case type
          when Class then
            @contents = type.new *args
            case (e = @contents.encode)
              when Array then e
              when nil   then []
              else            [ e]
            end
          when nil then
            @contents = nil
            split_args args
          else
            @contents = nil
            split_args contents
        end
        @data = mk_lines d
        self
      end

      def reset type
        d = if type then
          (contents type).encode
        else
          @contents
        end
        @data = mk_lines d
        self
      end

      private

      def mk_lines strs
        m = self.class.line_max - @name.length - 2  # 2 == ": ".size
        data = ""
        strs.each { |e|
          unless data.empty? then
            if 1 + e.length <= m then
              data << " "
              m -= 1
            else
              data << "\n" << (" "*self.class.indent)
              m = self.class.line_max - self.class.indent
            end
          end
          data << e
          m -= e.length
        }
        data
      end

      def split_args ary
        r = []
        ary.each { |a|
          r.concat case a
            when Array then split_args a
            else            a.to_s.split
          end
        }
        r
      end

    end

    class Headers

      @types = {
        "Content-Type"        => ContentType,
        "To"                  => AddrList,
        "Cc"                  => AddrList,
        "Bcc"                 => AddrList,
        "From"                => AddrList,
        "Subject"             => PlainText,
        "Content-Disposition" => Contents,
        "Sender"              => AddrList,
        "Content-Transfer-Encoding" => Contents,
        "User-Agent"          => PlainText,
        "Date"                => Timestamp,
        "Delivery-Date"       => Timestamp,
        "Message-ID"          => Id,
        "List-ID"             => Id,
        "References"          => IdList,
        "In-Reply-To"         => Id,
        "Reply-To"            => AddrList,
        "Content-Length"      => Count,
        "Lines"               => Count,
        "Return-Path"         => AddrList,
        "Envelope-To"         => AddrList,
        "DKIM-Signature"      => Dictionary,
        "DomainKey-Signature" => Dictionary,

        "Set-Cookie"          => Dictionary,
        "Cookie"              => Dictionary,
      }

      class <<self
        def set_field_type name, type
          e = Header.create name
          if type then
            @types[ e.name] = type
          else
            @types.delete e.name
          end
        end
        def find_type entry
          @types.each { |k,v|
            return v if entry.name_is? k
          }
          nil
        end
      end

      class <<self
        private :new
        def parse *list
          list.flatten!
          list.map! { |h| Header.parse h }
          new list
        end
        def create
          new []
        end
      end

      def initialize list
        @list = list
      end

      def length
        @list.length
      end
      alias size length

      def to_s
        @list.map { |e| "#{e}\n" }.join
      end

      private

      def header_contents entry, type = nil
        type ||= Headers.find_type entry
        entry.contents type
      end

      public

      def each
        @list.each { |e| yield e.name, (header_contents e) }
        self
      end
      include Enumerable

      def has? name
        e = find_entry name
        not e.nil?
      end

      def raw name
        e = find_entry name
        e.data if e
      end

      def field name, type = nil
        e = find_entry name
        header_contents e, type if e
      end
      def [] name, type = nil
        case name
          when Integer then raise "Not a field name: #{name}"
          else              field name, type
        end
      end

      private

      def method_missing sym, type = nil, *args
        if args.empty? and not sym =~ /[!?=]\z/ then
          field sym, type
        else
          super
        end
      end

      public

      def insert name, *contents
        e = build_entry name, *contents
        @list.unshift e
        self
      end

      def add name, *contents
        e = build_entry name, *contents
        @list.push e
        self
      end

      def remove name, type = nil
        block_given? or return remove name, type do |_| true end
        pat = Header.create name
        @list.reject! { |e|
          e.name_is? pat.name and yield (header_contents e, type)
        }
        self
      end
      alias delete remove

      def compact name, type = nil
        remove name, type do |c| c.empty? end
      end
      alias remove_empty compact

      def replace name, *contents
        block_given? or return replace name, *contents do true end
        entry = build_entry name, *contents
        @list.map! { |e|
          if e.name_is? entry.name and yield (header_contents e) then
            entry
          else
            e
          end
        }
        self
      end

      def replace_all name, type = nil
        pat = Header.create name
        type ||= Headers.find_type pat
        @list.map! { |e|
          if e.name_is? pat.name then
            c = e.contents type
            y = yield c
            if y.equal? c then
              e.reset type
            else
              y = [ type, *y] if type
              next build_entry name, *y
            end
          end
          e
        }
        self
      end

      def replace_add name, *contents
        entry = build_entry name, *contents
        replace_all name do |c|
          if entry then
            c.push entry.contents
            entry = nil
          end
          c
        end
        @list.push entry if entry
        self
      end

      def recode name, type = nil
        n = Header.build_name name
        @list.each { |e|
          next unless e.name_is? n
          type ||= Headers.find_type e
          e.reset type
        }
        self
      end

      def inspect
        r = ""
        r << "#<#{self.class}:"
        r << "0x%x" % (object_id<<1)
        r << " (#{length})"
        r << ">"
      end

      private

      def find_entry name
        e = Header.build_name name
        @list.find { |x| x.name_is? e }
      end

      def build_entry name, *contents
        e = Header.create name
        type, = *contents
        case type
          when Class then
            e.set *contents
          else
            type = Headers.find_type e
            e.set type, *contents
        end
        e
      end

    end

    class <<self

      private :new

      def parse input
        parse_hb input do |h,b|
          new h, b
        end
      end

      def create
        new nil, nil
      end

      private

      def parse_hb input
        hinput, input = input.split /^\n/, 2
        h = parse_headers hinput
        c = h.content_type
        b = c.parse_mime input if c
        unless b then
          b = ""
          input.each_line { |l| b << l }
          b
        end
        yield h, b
      end

      def parse_headers input
        h = []
        input.each_line { |l|
          l.chomp!
          case l
            when /^$/ then
              break
            when /^\s+/ then
              h.last or
                raise ParseError, "First line may not be a continuation."
              h.last << "\n" << l
            else
              h.push l
          end
        }
        Headers.parse h
      end

    end

    attr_reader :headers, :body

    def initialize headers, body
      @headers, @body = headers, body
      @headers ||= Headers.create
    end

    def header sym, type = nil
      @headers.field sym, type
    end

    private

    def method_missing sym, *args, &block
      case sym
        when /\Ah_(.*)/, /\Aheader_(.*)/ then
          header $1.to_sym, *args
        else
          super
      end
    end

    public

    def has? name
      @headers.has? name
    end
    alias has_header? has?

    def [] name, type = nil
      @headers[ name, type]
    end

    def is_multipart?
      Multipart === @body
    end
    alias mp? is_multipart?

    def inspect
      r = ""
      r << "#<#{self.class}:"
      r << "0x%x" % (object_id<<1)
      r << " headers:#{@headers.length}"
      r << " multipart" if is_multipart?
      r << ">"
    end

    def to_s
      r = ""
      if is_multipart? then
        c = @headers.field :content_type
        u = @body.boundary
        if c[ :boundary] != u then
          @headers.replace :content_type, c.fulltype, boundary: u
        end
      end
      r << @headers.to_s << "\n" << @body.to_s
      r.ends_with? "\n" or r << "\n"
      r
    end

    def transfer_encoding
      c = @headers[ :content_transfer_encoding]
      c.caption if c
    end

    def body_decoded
      r = case transfer_encoding
        when "quoted-printable" then
          (@body.unpack "M").join
        when "base64" then
          (@body.unpack "m").join
        else
          @body
      end
      c = @headers.content_type
      r.force_encoding c&&c[ :charset] || Encoding::ASCII_8BIT
      r
    end

    def body_text= body
      body = body.to_s
      @headers.replace :content_type, "text/plain", charset: body.encoding
      @headers.replace :content_transfer_encoding, "quoted-printable"
      @body = [ body].pack "M*"
    end

    def body_binary= body
      @headers.replace :content_transfer_encoding, "base64"
      @body = [ body].pack "m*"
    end

    def body= body
      @body = body
    end

  end

end

