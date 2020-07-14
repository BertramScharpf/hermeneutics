# encoding: UTF-8

#
#  hermeneutics/escape.rb  --  Various encoding schemes for internet purposes
#

require "supplement"


=begin rdoc

:section: Classes definied here

Hermeneutics::Entities encodes to and decodes from HTML-Entities
(<code>&amp;</code> etc.)

Hermeneutics::URLText encodes to and decodes from URLs
(<code>%2d</code> etc.)

Hermeneutics::HeaderExt encodes to and decodes from E-Mail Header fields
(<code>=?UTF-8?Q?=C3=B6?=</code> etc.).

=end

module Hermeneutics

  # Translate HTML and XML character entities: <code>"&"</code> to
  # <code>"&amp;"</code> and vice versa.
  #
  # == What actually happens
  #
  # HTML pages usually come in with characters encoded <code>&lt;</code>
  # for <code><</code> and <code>&euro;</code> for <code>€</code>.
  #
  # Further, they may contain a meta tag in the header like this:
  #
  #   <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  #   <meta charset="utf-8" />                        (HTML5)
  #
  # or
  #
  #   <?xml version="1.0" encoding="UTF-8" ?>         (XHTML)
  #
  # When +charset+ is <code>utf-8</code> and the file contains the byte
  # sequence <code>"\303\244"</code>/<code>"\xc3\xa4"</code> then there will
  # be displayed a character <code>"ä"</code>.
  #
  # When +charset+ is <code>iso8859-15</code> and the file contains the byte
  # sequence <code>"\344"</code>/<code>"\xe4"</code> then there will be
  # displayed a character <code>"ä"</code>, too.
  #
  # The sequence <code>"&auml;"</code> will produce an <code>"ä"</code> in any
  # case.
  #
  # == What you should do
  #
  # Generating your own HTML pages you will always be safe when you only
  # produce entity tags as <code>&auml;</code> and <code>&euro;</code> or
  # <code>&#x00e4;</code> and <code>&#x20ac;</code> respectively.
  #
  # == What this module does
  #
  # This module translates strings to a HTML-masked version.  The encoding will
  # not be changed and you may demand to keep 8-bit-characters.
  #
  # == Examples
  #
  #   Entities.encode "<"                           #=> "&lt;"
  #   Entities.decode "&lt;"                        #=> "<"
  #   Entities.encode "äöü"                         #=> "&auml;&ouml;&uuml;"
  #   Entities.decode "&auml;&ouml;&uuml;"          #=> "äöü"
  #
  class Entities

    # :stopdoc:
    SPECIAL_ASC = {
      '"' => "quot",    "&" => "amp",     "<" => "lt",      ">" => "gt",
    }
    RE_ASC = /[#{SPECIAL_ASC.keys.map { |x| Regexp.quote x }.join}]/

    SPECIAL = {
      "\u00a0" => "nbsp",
                        "¡" => "iexcl",   "¢" => "cent",    "£" => "pound",   "€" => "euro",    "¥" => "yen",     "Š" => "Scaron",
                                                                              "¤" => "curren",                    "¦" => "brvbar",
      "§" => "sect",    "š" => "scaron",  "©" => "copy",    "ª" => "ordf",    "«" => "laquo",   "¬" => "not",     "­" => "shy",
                        "¨" => "uml",
      "®" => "reg",     "¯" => "macr",

      "°" => "deg",     "±" => "plusmn",  "²" => "sup2",    "³" => "sup3",                      "µ" => "micro",   "¶" => "para",
                                                                              "´" => "acute",
      "·" => "middot",                    "¹" => "sup1",    "º" => "ordm",    "»" => "raquo",   "Œ" => "OElig",   "œ" => "oelig",
                        "¸" => "cedil",                                                         "¼" => "frac14",  "½" => "frac12",
      "Ÿ" => "Yuml",    "¿" => "iquest",
      "¾" => "frac34",

      "À" => "Agrave",  "Á" => "Aacute",  "Â" => "Acirc",   "Ã" => "Atilde",  "Ä" => "Auml",    "Å" => "Aring",   "Æ" => "AElig",
      "Ç" => "Ccedil",  "È" => "Egrave",  "É" => "Eacute",  "Ê" => "Ecirc",   "Ë" => "Euml",    "Ì" => "Igrave",  "Í" => "Iacute",
      "Î" => "Icirc",   "Ï" => "Iuml",
      "Ð" => "ETH",     "Ñ" => "Ntilde",  "Ò" => "Ograve",  "Ó" => "Oacute",  "Ô" => "Ocirc",   "Õ" => "Otilde",  "Ö" => "Ouml",
      "×" => "times",   "Ø" => "Oslash",  "Ù" => "Ugrave",  "Ú" => "Uacute",  "Û" => "Ucirc",   "Ü" => "Uuml",    "Ý" => "Yacute",
      "Þ" => "THORN",   "ß" => "szlig",

      "à" => "agrave",  "á" => "aacute",  "â" => "acirc",   "ã" => "atilde",  "ä" => "auml",    "å" => "aring",   "æ" => "aelig",
      "ç" => "ccedil",  "è" => "egrave",  "é" => "eacute",  "ê" => "ecirc",   "ë" => "euml",    "ì" => "igrave",  "í" => "iacute",
      "î" => "icirc",   "ï" => "iuml",
      "ð" => "eth",     "ñ" => "ntilde",  "ò" => "ograve",  "ó" => "oacute",  "ô" => "ocirc",   "õ" => "otilde",  "ö" => "ouml",
      "÷" => "divide",  "ø" => "oslash",  "ù" => "ugrave",  "ú" => "uacute",  "û" => "ucirc",   "ü" => "uuml",    "ý" => "yacute",
      "þ" => "thorn",   "ÿ" => "yuml",

      "‚" => "bsquo",   "‘" => "lsquo",   "„" => "bdquo",   "“" => "ldquo",   "‹" => "lsaquo",  "›" => "rsaquo",
      "–" => "ndash",   "—" => "mdash",   "‰" => "permil",  "…" => "hellip",  "†" => "dagger",  "‡" => "Dagger",
    }.update SPECIAL_ASC
    NAMES = SPECIAL.invert
    # :startdoc:

    attr_accessor :keep_8bit

    # :call-seq:
    #   new( keep_8bit: bool)     -> ent
    #
    # Creates an <code>Entities</code> converter.
    #
    #   ent = Entities.new keep_8bit: true
    #
    def initialize keep_8bit: nil
      @keep_8bit = keep_8bit
    end

    # :call-seq:
    #   ent.encode( str)      -> str
    #
    # Create a string thats characters are masked the HTML style:
    #
    #   ent = Entities.new
    #   ent.encode "&<\""    #=> "&amp;&lt;&quot;"
    #   ent.encode "äöü"     #=> "&auml;&ouml;&uuml;"
    #
    # The result will be in the same encoding as the source even if it will
    # not contain any 8-bit characters (what can only happen when +keep_8bit+
    # is set).
    #
    #   ent = Entities.new true
    #
    #   uml = "<ä>".encode "UTF-8"
    #   ent.encode uml             #=> "&lt;\xc3\xa4&gt;" in UTF-8
    #
    #   uml = "<ä>".encode "ISO-8859-1"
    #   ent.encode uml             #=> "&lt;\xe4&gt;"     in ISO-8859-1
    #
    def encode str
      r = str.new_string
      r.gsub! RE_ASC do |x| "&#{SPECIAL_ASC[ x]};" end
      unless @keep_8bit then
        r.gsub! /[^\0-\x7f]/ do |c|
          c.encode! __ENCODING__
          s = SPECIAL[ c] || ("#x%04x" % c.ord)
          "&#{s};"
        end
      end
      r
    end

    def decode str
      self.class.decode str
    end

    public

    class <<self

      def std
        @std ||= new
      end

      def encode str
        std.encode str
      end

      # :call-seq:
      #   Entities.decode( str)       -> str
      #
      # Replace HTML-style masks by normal characters:
      #
      #   Entities.decode "&lt;"                       #=> "<"
      #   Entities.decode "&auml;&ouml;&uuml;"         #=> "äöü"
      #
      # Unmasked 8-bit-characters (<code>"ä"</code> instead of
      # <code>"&auml;"</code>) will be kept but translated to
      # a unique encoding.
      #
      #   s = "ä &ouml; ü"
      #   s.encode! "utf-8"
      #   Entities.decode s                            #=> "ä ö ü"
      #
      #   s = "\xe4 &ouml; \xfc &#x20ac;"
      #   s.force_encoding "iso-8859-15"
      #   Entities.decode s                            #=> "ä ö ü €"
      #                                                    (in iso8859-15)
      #
      def decode str
        str.gsub /&(.+?);/ do
          (named_decode $1) or (numeric_decode $1) or $&
        end
      end

      private

      def named_decode s
        c = NAMES[ s]
        if c then
          if c.encoding != s.encoding then
            c.encode s.encoding
          else
            c
          end
        end
      end

      def numeric_decode s
        if s =~ /\A#(?:(\d+)|x([0-9a-f]+))\z/i then
          c = ($1 ? $1.to_i : ($2.to_i 0x10)).chr Encoding::UTF_8
          c.encode! s.encoding
        end
      end

    end

  end



  # URL-able representation
  #
  # == What's acually happening
  #
  # URLs may not contain spaces and serveral character as slashes, ampersands
  # etc.  These characters will be masked by a percent sign and two hex digits
  # representing the ASCII code.  Eight bit characters should be masked the
  # same way.
  #
  # An URL line does not store encoding information by itself.  A locator may
  # either say one of these:
  #
  #    http://www.example.com/subdir/index.html?umlfield=%C3%BCber+alles
  #    http://www.example.com/subdir/index.html?umlfield=%FCber+alles
  #
  # The reading CGI has to decide on itself how to treat it.
  #
  # == Examples
  #
  #   URLText.encode "'Stop!' said Fred."     #=> "%27Stop%21%27+said+Fred."
  #   URLText.decode "%27Stop%21%27+said+Fred%2e"
  #                                           #=> "'Stop!' said Fred."
  #
  class URLText

    attr_accessor :keep_8bit, :keep_space, :mask_space

    # :call-seq:
    #   new( hash)  -> urltext
    #
    # Creates a <code>URLText</code> converter.
    #
    # The parameters may be given as values or as a hash.
    #
    #   utx = URLText.new keep_8bit: true, keep_space: false
    #
    # See the +encode+ method for an explanation of these parameters.
    #
    def initialize keep_8bit: nil, keep_space: nil, mask_space: nil
      @keep_8bit  = keep_8bit
      @keep_space = keep_space
      @mask_space = mask_space
    end

    # :call-seq:
    #   encode( str)     -> str
    #
    # Create a string that contains <code>%XX</code>-encoded bytes.
    #
    #   utx = URLText.new
    #   utx.encode "'Stop!' said Fred."       #=> "%27Stop%21%27+said+Fred."
    #
    # The result will not contain any 8-bit characters, except when
    # +keep_8bit+ is set.  The result will be in the same encoding as the
    # argument although this normally has no meaning.
    #
    #   utx = URLText.new keep_8bit: true
    #   s = "< ä >".encode "UTF-8"
    #   utx.encode s                    #=> "%3C+\u{e4}+%3E"  in UTF-8
    #
    #   s = "< ä >".encode "ISO-8859-1"
    #   utx.encode s                    #=> "%3C+\xe4+%3E"      in ISO-8859-1
    #
    # A space <code>" "</code> will not be replaced by a plus <code>"+"</code>
    # if +keep_space+ is set.
    #
    #   utx = URLText.new keep_space: true
    #   s = "< x >"
    #   utx.encode s                    #=> "%3C x %3E"
    #
    # When +mask_space+ is set, then a space will be represented as
    # <code>"%20"</code>,
    #
    def encode str
      r = str.new_string
      r.force_encoding Encoding::ASCII_8BIT unless @keep_8bit
      r.gsub! %r/([^a-zA-Z0-9_.-])/ do |c|
        if c == " " and not @mask_space then
          @keep_space ? c : "+"
        elsif not @keep_8bit or c.ascii_only? then
          "%%%02X" % c.ord
        else
          c
        end
      end
      r.encode! str.encoding
    end


    class Dict < Hash
      class <<self
        def create
          i = new
          yield i
          i
        end
      end
      def initialize
        super
        yield self if block_given?
      end
      def [] key
        super key.to_sym
      end
      def []= key, val
        super key.to_sym, val
      end
      def update hash
        hash.each { |k,v| self[ k] = v }
      end
      alias merge! update
      def parse key, val
        self[ key] = case val
          when nil                             then nil
          when /\A(?:[+-]?[1-9][0-9]{,9}|0)\z/ then val.to_i
          else                                      val.to_s.notempty?
        end
      end
      def method_missing sym, *args
        if args.empty? and not sym =~ /[!?=]\z/ then
          self[ sym]
        else
          first, *rest = args
          if rest.empty? and sym =~ /=\z/ then
            self[ sym] = first
          else
            super
          end
        end
      end
    end

    # :stopdoc:
    PAIR_SET = "="
    PAIR_SEP = "&"
    # :startdoc:

    # :call-seq:
    #   encode_hash( hash)     -> str
    #
    # Encode a <code>Hash</code> to a URL-style string.
    #
    #   utx = URLText.new
    #
    #   h = { name: "John Doe", age: 42 }
    #   utx.encode_hash h
    #       #=> "name=John+Doe&age=42"
    #
    #   h = { a: ";;;", x: "äöü" }
    #   utx.encode_hash h
    #       #=> "a=%3B%3B%3B&x=%C3%A4%C3%B6%C3%BC"
    #
    def encode_hash hash
      hash.map { |(k,v)|
        case v
          when nil   then next
          when true  then v = k
          when false then v = ""
        end
        [k, v].map { |x| encode x.to_s }.join PAIR_SET
      }.compact.join PAIR_SEP
    end

    # :call-seq:
    #   mkurl( path, hash, anchor = nil)     -> str
    #
    # Make an URL.
    #
    #   utx = URLText.new
    #   h = { name: "John Doe", age: "42" }
    #   utx.encode_hash "myscript.rb", h, "chapter"
    #       #=> "myscript.rb?name=John+Doe&age=42#chapter"
    #
    def mkurl path, hash = nil, anchor = nil
      unless Hash === hash then
        hash, anchor = anchor, hash
      end
      r = "#{path}"
      r << "?#{encode_hash hash}" if hash
      r << "##{anchor}" if anchor
      r
    end

    public

    def decode str
      self.class.decode str
    end

    def decode_hash qstr, &block
      self.class.decode_hash qstr, &block
    end

    class <<self

      def std
        @std ||= new
      end

      def encode str
        std.encode str
      end

      def encode_hash hash
        std.encode_hash hash
      end

      def mkurl path, hash, anchor = nil
        std.mkurl path, hash, anchor
      end

      # :call-seq:
      #   decode( str)                 -> str
      #   decode( str, encoding)       -> str
      #
      # Decode the contained string.
      #
      #   utx = URLText.new
      #   utx.decode "%27Stop%21%27+said+Fred%2e"       #=> "'Stop!' said Fred."
      #
      # The encoding will be kept.  That means that an invalidly encoded
      # string could be produced.
      #
      #   a = "bl%F6d"
      #   a.encode! "utf-8"
      #   d = utx.decode a
      #   d =~ /./        #=> "invalid byte sequence in UTF-8 (ArgumentError)"
      #
      def decode str
        r = str.new_string
        r.tr! "+", " "
        r.gsub! /(?:%([0-9A-F]{2}))/i do $1.hex.chr end
        r.force_encoding str.encoding
        r
      end

      # :call-seq:
      #   decode_hash( str)                      -> hash
      #   decode_hash( str) { |key,val| ... }    -> nil or int
      #
      # Decode a URL-style encoded string to a <code>Hash</code>.
      # In case a block is given, the number of key-value pairs is returned.
      #
      #   str = "a=%3B%3B%3B&x=%26auml%3B%26ouml%3B%26uuml%3B"
      #   URLText.decode_hash str do |k,v|
      #     puts "#{k} = #{v}"
      #   end
      #
      # Output:
      #
      #   a = ;;;
      #   x = äöü
      #
      def decode_hash qstr
        if block_given? then
          i = 0
          each_pair qstr do |k,v|
            yield k, v
            i += 1
          end
          i.nonzero?
        else
          Dict.create do |h|
            each_pair qstr do |k,v| h.parse k, v end
          end
        end
      end

      private

      def each_pair qstr
        qstr or return
        h = qstr.to_s.split PAIR_SEP
        h.each do |pair|
          kv = pair.split PAIR_SET, 2
          kv.map! { |x| decode x if x }
          yield *kv
        end
      end

    end

  end

  # Header field contents (RFC 2047) encoding
  #
  # == Examples
  #
  #   HeaderExt.encode "Jörg Müller"
  #                                 #=> "=?utf-8?Q?J=C3=B6rg_M=C3=BCller?="
  #   HeaderExt.decode "=?UTF-8?Q?J=C3=B6rg_M=C3=BCller?="
  #                                 #=> "Jörg Müller"
  #
  class HeaderExt

    # :call-seq:
    #   new( [ parameters] )    -> con
    #
    # Creates a <code>HeaderExt</code> converter.
    #
    # See the +encode+ method for an explanation of the parameters.
    #
    # == Examples
    #
    #   con = HeaderExt.new
    #   con = HeaderExt.new base64: true, limit: 32, lower: true
    #   con = HeaderExt.new mask: /["'()]/
    #
    def initialize params = nil
      if params then
        @base64 = params.delete :base64
        @limit  = params.delete :limit
        @lower  = params.delete :lower
        @mask   = params.delete :mask
        params.empty? or
          raise ArgumentError, "invalid parameter: #{params.keys.first}."
      end
    end

    # :call-seq:
    #   needs? str  -> true or false
    #
    # Check whether a string needs encoding.
    #
    def needs? str
      (not str.ascii_only? or str =~ @mask) and true or false
    end

    # :call-seq:
    #   encode( str)   -> str
    #
    # Create a header field style encoded string.  The following parameters
    # will be evaluated:
    #
    #   :base64    # build ?B? instead of ?Q?
    #   :limit     # break words longer than this
    #   :lower     # build lower case ?b? and ?q?
    #   :mask      # a regular expression detecting characters to mask
    #
    # The result will not contain any 8-bit characters. The encoding will
    # be kept although it won't have a meaning.
    #
    # The parameter <code>:mask</code> will have no influence on the masking
    # itself but will guarantee characters to be masked.
    #
    # == Examples
    #
    #   yodel = "Holleri du dödl di, diri diri dudl dö."
    #
    #   con = HeaderExt.new
    #   con.encode yodel
    #     #=> "Holleri du =?UTF-8?Q?d=C3=B6dl?= di, diri diri dudl =?UTF-8?Q?d=C3=B6=2E?="
    #
    #   yodel.encode! "iso8859-1"
    #   con.encode yodel
    #     #=> "Holleri du =?ISO8859-1?Q?d=F6dl?= di, diri diri dudl =?ISO8859-1?Q?d=F6=2E?="
    #
    #   e = "€"
    #   e.encode! "utf-8"      ; con.encode e      #=> "=?UTF-8?Q?=E2=82=AC?="
    #   e.encode! "iso8859-15" ; con.encode e      #=> "=?ISO8859-15?Q?=A4?="
    #   e.encode! "ms-ansi"    ; con.encode e      #=> "=?MS-ANSI?Q?=80?="
    #
    #   con = HeaderExt.new mask: /["'()]/
    #   con.encode "'Stop!' said Fred."
    #     #=> "=?UTF-8?Q?=27Stop=21=27?= said Fred."
    #
    def encode str
      do_encoding str do
        # I don't like this kind of programming style but it seems to work. BS
        r, enc = "", ""
        while str =~ /\S+/ do
          if needs? $& then
            (enc.notempty? || r) << $`
            enc << $&
          else
            if not enc.empty? then
              r << (mask enc)
              enc.clear
            end
            r << $` << $&
          end
          str = $'
        end
        if not enc.empty? then
          enc << str
          r << (mask enc)
        else
          r << str
        end
        r
      end
    end

    # :call-seq:
    #   encode_whole( str)   -> str
    #
    # The unlike +encode+ the whole string as one piece will be encoded.
    #
    #   yodel = "Holleri du dödl di, diri diri dudl dö."
    #   HeaderExt.encode_whole yodel
    #     #=> "=?UTF-8?Q?Holleri_du_d=C3=B6dl_di,_diri_diri_dudl_d=C3=B6=2E?="
    #
    def encode_whole str
      do_encoding str do
        mask str
      end
    end

    private

    def do_encoding str
      @charset = str.encoding
      @type, @encoder = @base64 ? [ "B", :base64] : [ "Q", :quopri ]
      if @lower then
        @charset.downcase!
        @type.downcase!
      end
      yield.force_encoding str.encoding
    ensure
      @charset = @type = @encoder = nil
    end

    # :stopdoc:
    SPACE = " "
    # :startdoc:

    def mask str
      r, i = [], 0
      while i < str.length do
        l = @limit||str.length
        r.push "=?#@charset?#@type?#{send @encoder, str[ i, l]}?="
        i += l
      end
      r.join SPACE
    end

    def base64 c
      c = [c].pack "m*"
      c.gsub! /\s/, ""
      c
    end

    def quopri c
      c.force_encoding Encoding::ASCII_8BIT
      c.gsub! /([^ a-zA-Z0-9])/ do |s| "=%02X" % s.ord end
      c.tr! " ", "_"
      c
    end

    public

    def decode str
      self.class.decode str
    end

    class <<self

      # The standard header content encoding has a word break limit of 64.
      #
      def std
        @std ||= new limit: 64
      end

      # :call-seq:
      #   needs? str  -> true or false
      #
      # Use the standard content encoding.
      #
      def needs? str
        std.needs? str
      end

      # :call-seq:
      #   encode( str)   -> str
      #
      # Use the standard content encoding.
      #
      def encode str
        std.encode str
      end

      # :call-seq:
      #   encode_whole( str)   -> str
      #
      # Use the standard content encoding.
      #
      def encode_whole str
        std.encode_whole str
      end

      # :call-seq:
      #   decode( str)     -> str
      #
      # Remove header field style escapes.
      #
      #   HeaderExt.decode "=?UTF-8?Q?J=C3=B6rg_M=C3=BCller?="
      #                                 #=> "Jörg Müller"
      #
      def decode str
        r, e = [], []
        v, l = nil, nil
        lexer str do |type,piece|
          case type
            when :decoded then
              e.push piece.encoding
              if l == :space and (v == :decoded or not v) then
                r.pop
              elsif l == :plain then
                r.push SPACE
              end
            when :space then
              nil
            when :plain then
              if l == :decoded then
                r.push SPACE
              end
          end
          r.push piece
          v, l = l, type
        end
        if l == :space and v == :decoded then
          r.pop
        end
        e.uniq!
        begin
          r.join
        rescue EncodingError
          raise if e.empty?
          f = e.shift
          r.each { |x| x.encode! f }
          retry
        end
      end

      def lexer str
        while str do
          str =~ /(\s+)|\B=\?(\S*?)\?([QB])\?(\S*?)\?=\B/i
          if $1 then
            yield :plain, $` unless $`.empty?
            yield :space, $&
          elsif $2 then
            yield :plain, $` unless $`.empty?
            d = unmask $2, $3, $4
            yield :decoded, d
          else
            yield :plain, str
          end
          str = $'.notempty?
        end
      end

      private

      def unmask cs, tp, txt
        case tp.upcase
          when "B" then                    txt, = txt.unpack "m*"
          when "Q" then txt.tr! "_", " " ; txt, = txt.unpack "M*"
        end
        cs.slice! /\*\w+\z/    # language as in rfc2231, 5.
        case cs
          when /\Autf-?7\z/i then
            # Ruby doesn't seem to do that.
            txt.force_encoding Encoding::US_ASCII
            txt.gsub! /\+([0-9a-zA-Z+\/]*)-?/ do
              if $1.empty? then
                "+"
              else
                s = ("#$1==".unpack "m*").join
                (s.unpack "S>*").map { |x| x.chr Encoding::UTF_8 }.join
              end
            end
            txt.force_encoding Encoding::UTF_8
          when /\Aunknown/i then
            txt.force_encoding Encoding::US_ASCII
          else
            txt.force_encoding cs
        end
        txt
      end

    end

  end

end

