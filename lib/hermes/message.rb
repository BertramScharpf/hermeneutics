#
#  hermes/message.rb  --  a message as in mails or in HTTP communication
#

require "hermes/types"
require "hermes/contents"
require "hermes/addrs"


class NilClass
  def eat_lines
  end
  def rewind
  end
end
class String
  def eat_lines
    @pos ||= 0
    while @pos < length do
      p = index /.*\n?/, @pos
      l = $&.length
      begin
        yield self[ @pos, l]
      ensure
        @pos += l
      end
    end
  end
  def rewind
    @pos = 0
  end
end
class Array
  def eat_lines &block
    @pos ||= 0
    while @pos < length do
      begin
        self[ @pos].eat_lines &block
      ensure
        @pos += 1
      end
    end
  end
  def rewind
    each { |e| e.rewind }
    @pos = 0
  end
end
class IO
  def eat_lines &block
    each_line &block
    nil
  end
  def to_s
    rewind
    read
  end
end


module Hermes

  class Multipart < Mime

    MIME = /^multipart\//

    class IllegalBoundary < StandardError ; end
    class ParseError < StandardError ; end

    # :stopdoc:
    class PartFile
      class <<self
        def open file, sep
          i = new file, sep
          yield i
        end
        private :new
      end
      public
      attr_reader :prolog, :epilog
      def initialize file, sep
        @file = file
        @sep = /^--#{Regexp.quote sep}(--)?/
        read_part
        @prolog = norm_nl @a
      end
      def next_part
        return if @epilog
        read_part
        @a.first.chomp!
        true
      end
      def eat_lines
        yield @a.pop while @a.any?
      end
      private
      def read_part
        @a = []
        e = nil
        @file.eat_lines { |l|
          l =~ @sep rescue nil
          if $& then
            e = [ $'] if $1
            @a.reverse!
            return
          end
          @a.push l
        }
        raise ParseError, "Missing separator #@sep"
      ensure
        if e then
          @file.eat_lines { |l| e.push l }
          e.reverse!
          @epilog = norm_nl e
        end
      end
      def norm_nl a
        r = ""
        while a.any? do
          l = a.pop
          l.chomp! and l << $/
          r << l
        end
        r
      end
    end
    # :startdoc:

    public

    class <<self

      def parse input, parameters
        b = parameters[ :boundary]
        b or raise ParseError, "Missing boundary parameter."
        PartFile.open input, b do |partfile|
          list = []
          while partfile.next_part do
            m = Message.parse partfile
            list.push m
          end
          new b, partfile.prolog, list, partfile.epilog
        end
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
      r << "#<#{cls}:"
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
        r << splitter << $/ << s << $/
      }
      @epilog =~ re and raise IllegalBoundary
      r << splitter << "--" << @epilog
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

    class Headers

      class Entry
        LINE_LENGTH = 78
        INDENT = "    "
        class <<self
          private :new
          def parse str
            str =~ /:\s*/ or
              raise ParseError, "Header line without a colon: #{str}"
            data = $'
            new $`, $&, data
          end
          def create name, *contents
            name = build_name name
            i = new name.to_s, ": ", nil
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
        attr_reader :name, :sep, :data
        def initialize name, sep, data
          @name, @sep, @data, @contents = name, sep, data
        end
        def to_s
          "#@name#@sep#@data"
        end
        def contents type
          if type then
            unless @contents and @contents.is_a? type then
              @contents = type.parse @data
            end
            @contents
          else
            @data
          end
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
          if type then
            c = contents type
            @data = mk_lines c.encode if c
          end
          self
        end
        private
        def mk_lines strs
          m = LINE_LENGTH - @name.length - @sep.length
          data = ""
          strs.each { |e|
            unless data.empty? then
              if 1 + e.length <= m then
                data << " "
                m -= 1
              else
                data << $/ << INDENT
                m = LINE_LENGTH - INDENT.length
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
          e = Entry.create name
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
          list.map! { |h| Entry.parse h }
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
        @list.map { |e| "#{e}#$/" }.join
      end

      def each
        @list.each { |e|
          type = Headers.find_type e
          c = e.contents type
          yield e.name, c
        }
        self
      end

      def raw name
        e = find_entry name
        e.data if e
      end

      def field name, type = nil
        e = find_entry name
        if e then
          type ||= Headers.find_type e
          e.contents type
        end
      end
      def [] name, type = nil
        case name
          when Integer then raise "Not a field name: #{name}"
          else              field name, type
        end
      end

      def method_missing sym, *args
        if args.empty? and not sym =~ /[!?=]\z/ then
          field sym, *args
        else
          super
        end
      end

      def add name, *contents
        e = build_entry name, *contents
        add_entry e
        self
      end

      def replace name, *contents
        e = build_entry name, *contents
        remove_entries e
        add_entry e
        self
      end

      def remove name
        e = Entry.create name
        remove_entries e
        self
      end
      alias delete remove

      def recode name, type = nil
        n = Entry.build_name name
        @list.each { |e|
          next unless e.name_is? n
          type ||= Headers.find_type e
          e.reset type
        }
        self
      end

      def inspect
        r = ""
        r << "#<#{cls}:"
        r << "0x%x" % (object_id<<1)
        r << " (#{length})"
        r << ">"
      end

      private

      def find_entry name
        e = Entry.build_name name
        @list.find { |x| x.name_is? e }
      end

      def build_entry name, *contents
        e = Entry.create name
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

      def add_entry entry
        @list.unshift entry
      end

      def remove_entries entry
        @list.reject! { |e| e.name_is? entry.name }
      end

    end

    class <<self

      private :new

      def parse input, parameters = nil
        parse_hb input do |h,b|
          new h, b
        end
      end

      def create
        new nil, nil
      end

      private

      def parse_hb input
        h = parse_headers input
        c = h.content_type
        b = c.parse_mime input if c
        unless b then
          b = ""
          input.eat_lines { |l| b << l }
          b
        end
        yield h, b
      end

      def parse_headers input
        h = []
        input.eat_lines { |l|
          l.chomp!
          case l
            when /^$/ then
              break
            when /^\s+/ then
              h.last or
                raise ParseError, "First line may not be a continuation."
              h.last << $/ << l
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

    def method_missing sym, *args, &block
      case sym
        when /h_(.*)/, /header_(.*)/ then
          @headers.field $1.to_sym, *args
        else
          @headers.field sym, *args or super
      end
    end

    def [] name, type = nil
      @headers[ name, type]
    end

    def is_multipart?
      Multipart === @body
    end
    alias mp? is_multipart?

    def inspect
      r = ""
      r << "#<#{cls}:"
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
          @headers.replace :content_type, c.fulltype, :boundary => u
        end
      end
      r << @headers.to_s << $/ << @body.to_s
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
          @body.new_string
      end
      if (c = @headers.content_type) and (s = c[ :charset]) then
        r.force_encoding s
      end
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

