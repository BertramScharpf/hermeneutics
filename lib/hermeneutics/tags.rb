#
#  hermeneutics/tags.rb  --  Parse HTML code
#

=begin rdoc

:section: Classes defined here

Hermeneutics::Parser Parses HTML source and builds a tree

Hermeneutics::Tags Compiles parsed code to a tag tree

=end


require "hermeneutics/escape"


module Hermeneutics

  # Parse a HTML file or string.
  #
  class Parser

    class Error < StandardError ; end

    ren = /[a-z_][a-z0-9_.-]*/i

    RE_TAG     = %r{\A\s*(#{ren}(?::#{ren})?)\s*(.*?)\s*(/)?>}mx
    RE_INSTR   = %r{\A\?\s*(#{ren})\s*(.*)\s*\?>}m
    RE_COMMENT = %r{\A!--(.*?)-->}m
    RE_CDATA   = %r{\A!\[CDATA\[(.*?)\]\]>}m
    RE_BANG    = %r{\A!\s*([A-Z]+)\s*(.*?)>}m
    RE_CMD     = %r{\A!\s*(\[.*?\])\s*>}m

    RE_ATTR    = %r{\A(#{ren}(?::#{ren})?)(=)?}

    Tok = Struct[ :type, :tag, :attrs, :data]

    attr_reader :list

    def initialize str, term = nil
      @list = []
      s = str
      while s =~ /</ do
      add_data $`
        s = $'
        e = case s
          when %r{\A/\s*#{term}\s*>}im then
            nil
          when RE_TAG     then
            s = $'
            t =                Tok[ :tag,   $1.downcase, (attrs $2),
                                                  (sub_parser s, $1, $3)]
            s =~ %r{\A}
            t
          when RE_INSTR   then Tok[ :instr, $1.downcase, (attrs $2), nil]
          when RE_COMMENT then Tok[ :comm,  nil,         nil,        $1 ]
          when RE_CDATA   then Tok[ nil,    nil,         nil,        $1 ]
          when RE_BANG    then Tok[ :bang,  $1,          (attrl $2), nil]
          when RE_CMD     then Tok[ :cmd,   $1,          nil,        nil]
          else
            raise Error, "Unclosed standalone tag <#{term}>."
        end
        s = $'
        e or break
        add_tok e
      end
      if term then
        str.replace s
      else
        add_data s
      end
    end

    def find_encoding
      find_enc @list
    end

    def pretty_print
      puts_tree @list, 0
    end

    private

    def sub_parser s, tag, close
      self.class.new s, tag unless close
    end

    def add_data str
      if str.notempty? then
        add_tok Tok[ nil, nil, nil, str]
      end
    end

    def add_tok tok
      if not tok.type and (l = @list.last) and not l.type then
        l.data << tok.data
      else
        @list.push tok
      end
    end

    def attrs str
      a = {}
      while str.notempty? do
        str.slice! RE_ATTR or
          raise Error, "Illegal attribute specification: #{str}"
        k = $1.downcase
        a[ k] = if $2 then
          attr_val str
        else
          str.lstrip!
          k
        end
      end
      a
    end

    def attrl str
      a = []
      while str.notempty? do
        v = attr_val str
        a.push v
      end
      a
    end

    def attr_val str
      r = case str
        when /\A"(.*?)"/m then $1
        when /\A'(.*?)'/m then $1
        when /\A\S+/      then $&
      end
      str.replace $'
      str.lstrip!
      r
    end

    def find_enc p
      p.each { |e|
        r = case e.type
          when :tag   then
            case e.tag
              when "html", "head" then
                find_enc e.data.list
              when "meta" then
                e.attrs[ "charset"] || (
                  if e.attrs[ "http-equiv"] == "Content-Type" then
                    require "hermeneutics/contents"
                    c = Contents.parse e.attrs[ "content"]
                    c[ "charset"]
                  end
                )
            end
          when :query then
            e.attrs[ "encoding"]
        end
        return r if r
      }
      nil
    end

    def puts_tree p, indent
      p.each { |e|
        print "%s[%s] %s  " % [ "  "*indent, e.type, e.tag, ]
        r = case e.type
          when :tag   then puts ; puts_tree e.data.list, indent+1 if e.data
          when nil    then puts "%s%s" % [ "  "*(indent+1), e.data.inspect, ]
          else             puts
        end
      }
    end

  end


  # = Example
  #
  # This parses a table and outputs it as a CSV.
  #
  #   t = Tags.compile "<table><tr><td> ... </table>", "iso-8859-15"
  #   t.table.each :tr do |row|
  #     if row.has? :th then
  #       l = row.map :th do |h| h.data end.join ";"
  #     else
  #       l = row.map :td do |c| c.data end.join ";"
  #     end
  #     puts l
  #   end
  #
  class Tags

    class <<self

      def compile str, parser = nil
        p = (parser||Parser).new str
        enc = p.find_encoding||str.encoding
        l = lex p, enc
        new nil, nil, l
      end

      def lex parser, encoding = nil
        r = []
        while parser.list.any? do
          e = parser.list.shift
          case e.type
            when :tag
              a = {}
              e.attrs.each { |k,v|
                v.force_encoding encoding if encoding
                a[ k.downcase.to_sym] = Entities.new.decode v
              }
              i = new e.tag, a
              if e.data then
                f = lex e.data, encoding
                i.concat f
              end
              r.push i
            when nil
              d = e.data
              d.force_encoding encoding if encoding
              c = Entities.new.decode d
              r.push c
            when :instr then
            when :comm  then
            when :bang  then
            when :cmd   then
          end
        end
        r
      end

    end

    attr_reader :name, :attrs, :list

    def initialize name, attrs = nil, *elems
      @name = name.to_sym if name
      @attrs = {}.update attrs if attrs
      @list = []
      @list.concat elems.flatten
    end

    def push elem
      @list.push elem
    end

    def concat elems
      @list.concat elems
    end

    def inspect
      "<##@name [#{@list.length}]>"
    end

    def each t = nil
      if t then
        @list.each { |e|
          yield e if Tags === e and e.name == t
        }
      else
        @list.each { |e| yield e }
      end
    end

    def map t
      @list.map { |e|
        yield e if Tags === e and e.name == t
      }.compact
    end

    def has_tag? t
      @list.find { |e|
        Tags === e and e.name == t
      } and true
    end
    alias has? has_tag?

    def tag t, n = nil
      n ||= 0
      @list.each { |e|
        if Tags === e and e.name == t then
          return e if n.zero?
          n -= 1
        end
      }
      nil
    end

    private

    def method_missing sym, *args
      (tag sym, *args) or super
    rescue
      super
    end

    public

    def data
      d = ""
      gather_data self, d
      d
    end

    private

    def gather_data t, d
      t.list.each { |e|
        case e
          when Tags then gather_data e, d
          else           d << e
        end
      }
    end

  end

end

