# encoding: UTF-8

#
#  hermes/addrs.rb  --  Extract addresses out of a string
#

=begin rdoc

:section: Classes definied here

Hermeneutics::Addr      is a single address
Hermeneutics::AddrList  is a list of addresses in mail header fields.

= Remark

In my opinion, RFC 2822 allows too much features for address
fields (see A.5). Most of them I have never seen anywhere in
practice but only in the RFC. I doubt whether any mail-related
software implements the specification correctly. Maybe this
library does, but I cannot judge it as, after once tested, I
never again understood my own code. The specification
inevitably leeds to code of such kind. RFC 2822 address
specification is a pain.

=end

require "hermes/escape"


class NilClass
  def has? *args
  end
  def under_domain *args
  end
end


module Hermeneutics

  # A parser and generator for mail address fields.
  #
  # = Examples
  #
  #   a = Addr.create "dummy@example.com", "John Doe"
  #   a.to_s      #=>  "John Doe <dummy@example.com>"
  #   a.quote     #=>  "John Doe <dummy@example.com>"
  #   a.encode    #=>  "John Doe <dummy@example.com>"
  #
  #   a = Addr.create "dummy@example.com", "Müller, Fritz"
  #   a.to_s      #=>  "Müller, Fritz <dummy@example.com>"
  #   a.quote     #=>  "\"Müller, Fritz\" <dummy@example.com>"
  #   a.encode    #=>  "=?utf-8?q?M=C3=BCller=2C_Fritz?= <dummy@example.com>"
  #
  # = Parsing
  #
  #   x = <<-'EOT'
  #   Jörg Q. Müller <jmuell@example.com>, "Meier, Hans"
  #     <hmei@example.com>, Möller\, Fritz <fmoel@example.com>
  #   EOT
  #   Addr.parse x do |a,g|
  #     puts a.quote
  #   end
  #
  #   # Output:
  #   #   Jörg Q. Müller <jmuell@example.com>
  #   #   "Meier, Hans" <hmei@example.com>
  #   #   "Möller, Fritz" <fmoel@example.com>
  #
  #   x = "some: =?utf-8?q?M=C3=B6ller=2C_Fritz?= " +
  #       "<fmoeller@example.com> webmaster@example.com; foo@example.net"
  #   Addr.parse_decode x do |a,g|
  #     puts g.to_s
  #     puts a.quote
  #   end
  #
  #   # Output:
  #   #   some
  #   #   "Möller, Fritz" <fmoeller@example.com>
  #   #   some
  #   #   <webmaster@example.com>
  #   #
  #   #   <foo@example.net>
  #
  class Addr

    class <<self

      def create mail, real = nil
        m = Token[ :addr, (Token.lexer mail)]
        r = Token[ :text, (Token.lexer real)] if real
        new m, r
      end
      alias [] create
      private :new

    end

    attr_reader :mail, :real

    def initialize mail, real
      @mail, @real = mail, real
      @mail.compact!
      @real.compact! if @real
    end

    def == oth
      plain == case oth
        when Addr then oth.plain
        else           oth.to_s.downcase
      end
    end

    def plain
      @plain ||= mk_plain
    end

    def real
      @real.to_s if @real
    end

    def inspect
      "<##{self.class}: mail=#{@mail.inspect} real=#{@real.inspect}>"
    end

    def to_s
      tokenized.to_s
    end

    def quote
      tokenized.quote
    end

    def encode
      tokenized.encode
    end

    def tokenized
      r = Token[ :addr, [ Token[ :lang] , @mail, Token[ :rang]]]
      if @real then
        r = Token[ :text, [ @real, Token[ :space], r]]
      end
      r
    end

    private

    def mk_plain
      p = @mail.to_s
      p.downcase!
      p
    end

    @encoding_parameters = {}
    class <<self
      attr_reader :encoding_parameters
    end

    class Token

      attr_accessor :sym, :data, :quot

      class <<self
        alias [] new
      end

      def initialize sym, data = nil, quot = nil
        @sym, @data, @quot = sym, data, quot
      end

      def inspect
        d = ": #{@data.inspect}" if @data
        d << " Q" if @quot
        "<##@sym#{d}>"
      end

      def === oth
        case oth
          when Symbol then @sym == oth
          when Token  then self == oth
        end
      end

      def force_encoding enc
        case @sym
          when :text  then @data.each { |x| x.force_encoding enc }
          when :char  then @data.force_encoding enc
        end
      end

      def to_s
        text
      end

      def text
        case @sym
          when :addr  then data_map_join { |x| x.quote }
          when :text  then data_map_join { |x| x.text }
          when :char  then @data
          when :space then " "
          else             SPECIAL_CHARS[ @sym]||""
        end
      rescue Encoding::CompatibilityError
        force_encoding Encoding::ASCII_8BIT
        retry
      end

      def quote
        case @sym
          when :text,
               :addr  then data_map_join { |x| x.quote }
          when :char  then quoted
          when :space then " "
          else             SPECIAL_CHARS[ @sym]||""
        end
      rescue Encoding::CompatibilityError
        force_encoding Encoding::ASCII_8BIT
        retry
      end

      def encode
        case @sym
          when :addr  then data_map_join { |x| x.quote }
          when :text  then data_map_join { |x| x.encode }
          when :char  then encoded
          when :space then " "
          else             SPECIAL_CHARS[ @sym]||""
        end
      end

      def compact!
        case @sym
          when :text then
            return if @data.length <= 1
            @data = [ Token[ :char, text, needs_quote?]]
          when :addr then
            d = []
            while @data.any? do
              x, y = d.last, @data.shift
              if y === :char and x === :char then
                x.data << y.data
                x.quot ||= y.quot
              else
                y.compact!
                d.push y
              end
            end
            @data = d
        end
      end

      def needs_quote?
        case @sym
          when :text  then @data.find { |x| x.needs_quote? }
          when :char  then @quot
          when :space then false
          when :addr  then false
          else             true
        end
      end

      private

      def data_map_join
        @data.map { |x| yield x }.join
      end

      def quoted
        if @quot then
          q = @data.gsub "\"" do |c| "\\" + c end
          %Q%"#{q}"%
        else
          @data
        end
      end

      def encoded
        if @quot or HeaderExt.needs? @data then
          c = HeaderExt.new Addr.encoding_parameters
          c.encode_whole @data
        else
          @data
        end
      end

      class <<self

        def lexer str
          if block_given? then
            while str =~ /./m do
              h, str = $&, $'
              t = SPECIAL[ h]
              if respond_to? t, true then
                t = send t, h, str
              end
              unless Token === t then
                t = Token[ *t]
              end
              yield t
            end
          else
            r = []
            lexer str do |t| r.push t end
            r
          end
        end

        def lexer_decode str, &block
          if block_given? then
            HeaderExt.lexer str do |k,s|
              case k
                when :decoded then yield Token[ :char, s, true]
                when :plain   then lexer s, &block
                when :space   then yield Token[ :space]
              end
            end
          else
            r = []
            lexer_decode str do |t| r.push t end
            r
          end
        end

        private

        def escaped h, c
          if h then
            [h].pack "H2"
          else
            case c
              when "n" then "\n"
              when "r" then "\r"
              when "t" then "\t"
              when "f" then "\f"
              when "v" then "\v"
              when "b" then "\b"
              when "a" then "\a"
              when "e" then "\e"
              when "0" then "\0"
              else          c
            end
          end
        end

        def lex_space h, str
          str.slice! /\A\s*/
          :space
        end
        def lex_bslash h, str
          str.slice! /\A(?:x(..)|.)/
          y = escaped $1, $&
          Token[ :char, y, true]
        end
        def lex_squote h, str
          str.slice! /\A((?:[^\\']|\\.)*)'?/
          y = $1.gsub /\\(x(..)|.)/ do |c,x|
            escaped x, c
          end
          Token[ :char, y, true]
        end
        def lex_dquote h, str
          str.slice! /\A((?:[^\\"]|\\.)*)"?/
          y = $1.gsub /\\(x(..)|.)/ do |c,x|
            escaped x, c
          end
          Token[ :char, y, true]
        end
        def lex_other h, str
          until str.empty? or SPECIAL.has_key? str.head do
            h << (str.eat 1)
          end
          Token[ :char, h]
        end

      end

      # :stopdoc:
      SPECIAL = {
        "<"  => :lang,
        ">"  => :rang,
        "("  => :lparen,
        ")"  => :rparen,
        ","  => :comma,
        ";"  => :semicol,
        ":"  => :colon,
        "@"  => :at,
        "["  => :lbrack,
        "]"  => :rbrack,
        " "  => :lex_space,
        "'"  => :lex_squote,
        "\"" => :lex_dquote,
        "\\" => :lex_bslash,
      }
      "\t\n\f\r".each_char do |c| SPECIAL[ c] = SPECIAL[ " "] end
      SPECIAL.default = :lex_other
      SPECIAL_CHARS = SPECIAL.invert
      # :startdoc:

    end

    class <<self

      # Parse a line from a string that was entered by the user.
      #
      #   x = "Meier, Hans <hmei@example.com>, foo@example.net"
      #   Addr.parse x do |a,g|
      #     puts a.quote
      #   end
      #
      #   # Output:
      #     "Meier, Hans" <hmei@example.com>
      #     <foo@example.net>
      #
      def parse str, &block
        l = Token.lexer str
        compile l, &block
      end

      # Parse a line from a mail header field and make addresses of it.
      #
      # Internally the encoding class +HeaderExt+ will be used.
      #
      #   x = "some: =?utf-8?q?M=C3=B6ller=2C_Fritz?= <fmoeller@example.com>"
      #   Addr.parse_decode x do |addr,group|
      #     puts group.to_s
      #     puts addr.quote
      #   end
      #
      #   # Output:
      #   #   some
      #   #   "Möller, Fritz" <fmoeller@example.com>
      #
      def parse_decode str, &block
        l = Token.lexer_decode str
        compile l, &block
      end

      private

      def compile l, &block
        l = unspace l
        l = uncomment l
        g = split_groups l
        groups_compile g, &block
      end

      def groups_compile g
        if block_given? then
          g.each { |k,v|
            split_list v do |m,r|
              a = new m, r
              yield a, k
            end
          }
          return
        end
        t = []
        groups_compile g do |a,| t.push a end
        t
      end

      def matches l, *tokens
        z = tokens.zip l
        z.each { |(s,e)|
          e === s or return
        }
        true
      end

      def unspace l
        r = []
        while l.any? do
          if matches l, :space then
            l.shift
            next
          end
          if matches l, :char then
            e = Token[ :text, [ l.shift]]
            loop do
              if matches l, :char then
                e.data.push l.shift
              elsif matches l, :space, :char then
                e.data.push l.shift
                e.data.push l.shift
              else
                break
              end
            end
            l.unshift e
          end
          r.push l.shift
        end
        r
      end

      def uncomment l
        r = []
        while l.any? do
          if matches l, :lparen then
            l.shift
            l = uncomment l
            until matches l, :rparen or l.empty? do
              l.shift
            end
            l.shift
          end
          r.push l.shift
        end
        r
      end

      def split_groups l
        g = []
        n = nil
        while l.any? do
          n = if matches l, :text, :colon then
            e = l.shift
            l.shift
            e.to_s
          end
          s = []
          until matches l, :semicol or l.empty? do
            s.push l.shift
          end
          l.shift
          g.push [ n, s]
        end
        g
      end

      def split_list l
        while l.any? do
          if matches l, :text, :comma, :text, :lang then
            t = l.first.to_s
            if t =~ /[^a-z0-9_]/ then
              e = Token[ :text, []]
              e.data.push l.shift
              e.data.push l.shift, Token[ :space]
              e.data.push l.shift
              l.unshift e
            end
          end
          a, c = find_one_of l, :lang, :comma
          if a then
            real = l.shift a if a.nonzero?
            l.shift
            a, c = find_one_of l, :rang, :comma
            mail = l.shift a||c||l.length
            l.shift
            l.shift if matches l, :comma
          else
            mail = l.shift c||l.length
            l.shift
            real = nil
          end
          yield Token[ :addr, mail], real&&Token[ :text, real]
        end
      end

      def find_one_of l, s, t
        l.each_with_index { |e,i|
          if e === s then
            return i, nil
          elsif e === t then
            return nil, i
          end
        }
        nil
      end

    end

  end

  class AddrList

    class <<self
      def parse cont
        new.add_encoded cont
      end
    end

    private

    def initialize *addrs
      @list = []
      push addrs
    end

    public

    def push addrs
      case addrs
        when nil    then
        when String then add_encoded addrs
        when Addr   then @list.push addrs
        else             addrs.each { |a| push a }
      end
    end

    def inspect
      "<#{self.class}: " + (@list.map { |a| a.inspect }.join ", ") + ">"
    end

    def to_s
      @list.map { |a| a.to_s }.join ", "
    end

    def quote
      @list.map { |a| a.quote }.join ", "
    end

    def encode
      r = []
      @list.map { |a|
        if r.last then r.last << "," end
        r.push a.encode.dup
      }
      r
    end

    # :call-seq:
    #   each { |addr| ... }     -> self
    #
    # Call block for each address.
    #
    def each
      @list.each { |a| yield a }
    end
    include Enumerable

    def has? *mails
      mails.find { |m|
        case m
          when Regexp then
            @list.find { |a|
              if a.plain =~ m then
                yield *$~.captures if block_given?
                true
              end
            }
          else
            self == m
        end
      }
    end
    alias has has?

    def under_domain *args
      @list.each { |a|
        a.plain =~ /(.*)@/ or next
        l, d = $1, $'
        case d
          when *args then yield l
        end
      }
    end

    def == str
      @list.find { |a| a == str }
    end

    def add mail, real = nil
      if real or not Addr === mail then
        mail = Addr.create mail, real
      end
      @list.push mail
      self
    end

    def add_quoted str
      Addr.parse str.to_s do |a,|
        @list.push a
      end
      self
    end

    def add_encoded cont
      Addr.parse_decode cont.to_s do |a,|
        @list.push a
      end
      self
    end

  end

end

