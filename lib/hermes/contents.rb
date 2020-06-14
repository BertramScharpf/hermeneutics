#
#  hermes/contents.rb  --  Handle header fields like Content-Type
#

=begin rdoc

:section: Classes definied here

Hermes::Contents is a content field parser.

Hermes::ContentType parses "Content-Type" header fields.

=end

require "hermes/escape"


module Hermes

  # A parser for header fields like DKIM-Signature
  #
  # === Example
  #
  #   ds = Dictionary.new v: 1, a: "rsa-sha256", c: "relaxed/relaxed", ...
  #
  #   ds = Dictionary.parse "v=1; a=rsa-sha256; c=relaxed/relaxed; ..."
  #   ds[ "a"]  #=> "0123456"
  #
  class Dictionary

    # :stopdoc:
    SEP = ";"
    SEA = "="
    RES = /#{SEP}\s*/
    REA = /((?:\*(\d+))?\*)?#{SEA}/
    # :startdoc:

    class <<self

      # Create a +Dictionary+ object out of a string from a
      # mail header field.
      #
      #   ds = Dictionary.parse "v=1; a=rsa-sha256; c=relaxed/relaxed; ..."
      #   ds[ "a"]  #=> "0123456"
      #
      def parse line
        rest = line.strip
        hash = parse_hash rest
        new hash
      end

      def urltext
        @urltext ||= URLText.new mask_space: true
      end

      private

      def parse_hash rest
        hash = Hash.new { |h,k| h[ k] = [] }
        asts = {}
        while rest.notempty? do
          key, rest = if rest =~ REA then
            ast = $1
            ord = $2.to_i if $2
            [ $`, $']
          else
            [ rest.dup, ""]
          end
          key.downcase!
          key = key.to_sym
          asts[ key] = ast
          val, rest = if not ast and rest =~ /\A"(.*?)"(?:#{SEP}\s*|\z)/ then
            [ $1, $']
          else
            rest.split RES, 2
          end
          if ord then
            hash[ key][ ord] = val
          else
            hash[ key] = val
          end
        end
        r = URLText::Dict.new
        hash.keys.each { |k|
          v = hash[ k]
          Array === v and v = v.join
          if asts[ k] then
            enc, lang, val = v.split "'"
            val.force_encoding enc
            v = URLText.decode val
          end
          r[ k] = v
        }
        r
      end

    end

    attr_reader :hash
    alias to_hash hash
    alias to_h to_hash

    # Create a +Dictionary+ object from a value and a hash.
    #
    #   ds = Dictionary.new :v => 1, :a => "rsa-sha256",
    #                               :c => "relaxed/relaxed", ...
    #
    def initialize hash = nil
      case hash
        when URLText::Dict then
          @hash = hash
        else
          @hash = URLText::Dict.new
          @hash.merge! hash if hash
      end
    end

    # :call-seq:
    #   []( key)      -> str or nil
    #
    # Find value of +key+.
    #
    def [] key ; @hash[ key.to_sym] ; end
    alias field []

    def method_missing sym, *args
      if sym =~ /[^a-z_]/ or args.any? then
        super
      else
        field sym
      end
    end

    # :call-seq:
    #   keys()       -> ary
    #
    # Returns a list of all contained keys
    #
    #   c = Contents.new "text/html; boundary=0123456"
    #   c.keys                #=> [ :boundary]
    #
    def keys ; @hash.keys ; end


    # :stopdoc:
    TSPECIAL = %r_[()<>@,;:\\"\[\]/?=]_    # RFC 1521
    # :startdoc:

    # Show the line as readable text.
    #
    def to_s
      quoted_parts.join "#{SEP} "
    end
    alias quote to_s

    private
    def quoted_parts
      @hash.map { |k,v|
        case v
          when true                            then v = k
          when false                           then v = nil
          when TSPECIAL, /\s/, /[\0-\x1f\x7f]/ then v = v.inspect
        end
        "#{k}=#{v}"
      }
    end
    public

    # Encode it for a mail header field.
    #
    def encode
      f, *rest = encoded_parts
      if f then
        r = [ f]
        rest.each { |e|
          r.last << SEP
          r.push e
        }
      end
      r
    end

    private
    def encoded_parts
      r = @hash.map { |k,v|
        case v
          when nil    then next
          when true   then v = k
          when false  then v = ""
          when String then nil
          else             v = v.to_s
        end
        if not v.ascii_only? or v =~ /[=;"]/ then
          enc = v.encoding
          if (l = ENV[ "LANG"]) then
            l, = l.split /\W/, 2
            lang = l.gsub "_", "-"
          end
          v = [ enc, lang, (Dictionary.urltext.encode v)].join "'"
        end
        "#{k}=#{v}"
      }
      r.compact!
      r
    end
    public

  end

  # A parser for header fields in Content-Type style
  #
  # === Example
  #
  #   content_disposition = Contents.new "form-data", :name => "mycontrol"
  #
  #   content_type = Contents.parse "text/html; boundary=0123456"
  #   content_type.caption       #=>  "text/html"
  #   content_type[ :boundary]   #=> "0123456"
  #     # (Subclass ContentType even splits the caption into type/subtype.)
  #
  class Contents < Dictionary

    class <<self

      # Create a +Contents+ object out of a string from a
      # mail header field.
      #
      #   c = Contents.parse "text/html; boundary=0123456"
      #   c.caption         #=> "text/html"
      #   c[ :boundary]     #=> "0123456"
      #
      def parse line
        rest = line.strip
        caption, rest = rest.split Dictionary::RES, 2
        hash = parse_hash rest
        new caption, hash
      end

    end

    attr_reader :caption

    # Create a +Contents+ object from a value and a hash.
    #
    #   c = Contents.new "text/html", :boundary => "0123456"
    #
    def initialize caption, hash = nil
      if caption =~ RES or caption =~ REA then
        raise "Invalid content caption '#{caption}'."
      end
      @caption = caption.new_string
      super hash
    end

    def =~ re
      @caption =~ re
    end


    def quoted_parts
      r = [ "#@caption"]
      r.concat super
      r
    end

    def encoded_parts
      r = [ "#@caption"]
      r.concat super
      r
    end

  end

  class ContentType < Contents

    # :call-seq:
    #   new( str)      -> cts
    #
    # Create a +ContentType+ object either out of a string from an
    # E-Mail header field or from a value and a hash.
    #
    #   c = ContentType.parse "text/html; boundary=0123456"
    #   c = ContentType.new "text/html", :boundary => "0123456"
    #
    def initialize line, sf = nil
      line = line.join "/" if Array === line
      super
    end

    # :call-seq:
    #   split_type      -> str
    #
    # Find caption value of Content-Type style header field as an array
    #
    #   c = ContentType.new "text/html; boundary=0123456"
    #   c.split_type       #=>  [ "text", "html"]
    #   c.type           #=>  "text"
    #   c.subtype        #=>  "html"
    #
    def split_type ; @split ||= (@caption.split "/", 2) ; end

    # :call-seq:
    #   fulltype      -> str
    #
    # Find caption value of Content-Type style header field.
    #
    #   c = ContentType.new "text/html; boundary=0123456"
    #   c.fulltype       #=>  "text/html"
    #   c.type           #=>  "text"
    #   c.subtype        #=>  "html"
    #
    def fulltype ; caption ; end

    # :call-seq:
    #   type      -> str
    #
    # See +fulltype+ or +split_type+.
    #
    def type    ; split_type.first ; end

    # :call-seq:
    #   subtype      -> str
    #
    # See +fulltype+ or +split_type+.
    #
    def subtype ; split_type.last  ; end

    def parse_mime input
      m = Mime.find @caption
      m and m.parse input, @hash
    end

  end

  class Mime
    @types = []
    class <<self
      def inherited cls
        Mime.types.push cls
      end
      protected
      attr_reader :types
      public
      def find type
        Mime.types.find { |t| t::MIME === type }
      end
    end
  end

end

