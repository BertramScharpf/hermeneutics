#
#  hermeneutics/html.rb  -- smart HTML generation
#

require "hermeneutics/escape"
require "hermeneutics/contents"


module Hermeneutics

  # = Example
  #
  # require "hermeneutics/color"
  # require "hermeneutics/html"
  #
  # class MyHtml < Hermeneutics::Html
  #   def build
  #     html {
  #       head {
  #         title { "Example" }
  #         comment "created as an example, #{Time.now}"
  #       }
  #       body bgcolor: Hermeneutics::Color.from_s( "ffffef") do
  #         h1 {
  #           pcdata "Ruby "
  #           a href: "www.w3.org" do "Html" end
  #           _ { " example" }
  #         }
  #         p { "Some text.\nBye." }
  #         p {
  #           self << "link"
  #           br
  #           a href: "www.w3.org" do "Html" end
  #         }
  #       end
  #     }
  #   end
  # end
  #
  # Hermeneutics::Html.document
  #
  class Html

    class <<self
      attr_accessor :main
      def inherited cls
        Html.main = cls
      end
      def open out = nil
        i = (@main||self).new
        i.generate out do
          yield i
        end
      end
      def document *args, **kwargs, &block
        open do |i|
          i.document *args, **kwargs, &block
        end
      end
      def write_file name = nil
        name ||= (File.basename $0, ".rb") + ".html"
        File.open name, "w" do |f|
          open f do |i|
            if block_given? then
              yield i
            else
              i.document
            end
          end
        end
      end
    end

    def generate out = nil
      g = @generator
      begin
        @generator = Generator.new out||$stdout
        yield
      ensure
        @generator = g
      end
    end

    def document *args, **kwargs, &block
      doctype_header
      build *args, **kwargs, &block
    end

    def doctype_header
      @generator.doctype "html"
    end

    def build
      html { body { h1 { "It works." } } }
    end


    def language
      if ENV[ "LANG"] =~ /\A\w{2,}/ then
        r = $&
        r.gsub! /_/, "-"
        r
      end
    end


    class Generator
      attr_accessor :close_standalone, :assign_attributes, :cdata_block
      def initialize out
        @out = out
        @ent = Entities.new
        @nl, @ind = true, [ ""]
      end
      def encoding
        case @out
          when IO then @out.external_encoding||Encoding.default_external
          else         @out.encoding
        end
      end
      def file_path
        @out.path
      rescue NoMethodError
      end
      def merge str
        do_ind
        @out << str
      end
      def plain str
        do_ind
        @out << (@ent.encode str)
      end
      # nls
      # 0 = no newline
      # 1 = newline after
      # 2 = newline after both
      # 3 = and advance indent
      # 4 = Block without any indent
      def tag tag, type, attrs = nil
        tag = tag.to_s
        nls = type & 0xf
        if (type & 0x10).nonzero? then
          brace nls>0 do
            @out << tag
            mkattrs attrs
            @out << " /" if @close_standalone
          end
        else
          begin
            brk if nls>1
            brace nls>1 do
              @out << tag
              mkattrs attrs
            end
            if nls >3 then
              verbose_block yield
            else
              indent_if nls>2 do
                if block_given? then
                  r = yield
                  plain r if String === r
                end
              end
            end
          ensure
            brk if nls>1
            brace nls>0 do
              @out << "/" << tag
            end
          end
        end
        nil
      end
      # Processing Instruction
      def pi_tag tag, attrs = nil
        tag = tag.to_s
        brace true do
          begin
            @out << "?" << tag
            mkattrs attrs
          ensure
            @out << " ?"
          end
        end
      end
      def doctype *args
        brace true do
          @out << "!DOCTYPE"
          args.each { |x|
            @out << " "
            if x =~ /\W/ then
              @out << '"' << (@ent.encode x) << '"'
            else
              @out << x
            end
          }
        end
      end
      def comment str
        if str =~ /\A.*\z/ then
          brace_comment do
            @out << " " << str << " "
          end
        else
          brace_comment do
            brk
            out_brk str
            do_ind
          end
        end
      end
      def verbose_block str
        if @cdata_block then
          @out << "/* "
          brace false do
            @out << "![CDATA["
            @out << " */" << $/
            @out << str
            @out << $/ << "/* "
            @out << "]]"
          end
          @out << " */"
        else
          out_brk str
        end
      end
      private
      def brk
        unless @nl then
          @nl = true
          @out << $/
        end
      end
      def out_brk str
        @out << str
        @nl = str !~ /.\z/
        brk
      end
      def do_ind
        if @nl then
          @out << @ind.last
          @nl = false
        end
      end
      def brace nl
        do_ind
        @out << "<"
        yield
        nil
      ensure
        @out << ">"
        brk if nl
      end
      def brace_comment
        brace true do
          @out << "!--"
          yield
          @out << "--"
        end
      end
      def indent_if flag
        if flag then
          indent do yield end
        else
          yield
        end
      end
      INDENT = 2
      def indent
        @ind.push @ind.last + " "*INDENT
        yield
      ensure
        @ind.pop
      end
      def mkattrs attrs
        attrs or return
        attrs.each { |k,v|
          if Symbol === k then k = k.to_s ; k.gsub! /_/, "-" end
          v = case v
            when Array      then v.compact.join " "
            when true       then k.to_s if @assign_attributes
            when nil, false then next
            else                 v.to_s
          end
          @out << " " << k
          @out << "=\"" << (@ent.encode v) << "\"" if v.notempty?
        }
      end
    end

    def file_path ; @generator.file_path ; end

    NBSP = Entities::NAMES[ "nbsp"]

    TAGS = {
      a:0, abbr:0, address:1, article:3, aside:3, audio:3, b:0, bdi:0, bdo:2,
      blockquote:3, body:2, button:3, canvas:1, caption:1, cite:0, code:0,
      colgroup:3, data:0, datalist:3, dd:1, del:0, details:3, dfn:0, dialog:0,
      div:3, dl:3, dt:1, em:0, fieldset:3, figcaption:1, figure:3, footer:3,
      form:3, h1:1, h2:1, h3:1, h4:1, h5:1, h6:1, head:3, header:3, html:2,
      i:0, iframe:3, ins:0, kbd:0, label:0, legend:1, li:1, main:3, map:3,
      mark:0, meter:0, nav:3, noscript:3, object:3, ol:3, optgroup:3,
      option:1, output:0, p:2, picture:3, pre:1, progress:0, q:0, rp:0, rt:0,
      ruby:2, s:0, samp:0, section:3, select:3, small:0, span:0, strong:0,
      sub:0, summary:1, sup:0, svg:3, table:3, tbody:3, td:1, template:3,
      textarea:1, tfoot:3, th:1, thead:3, time:0, title:1, tr:3, u:0, ul:3,
      var:0, video:3,

      # tags containing foreign code blocks
      script:4, style:4,

      # void tags
      area:0x11, base:0x11, br:0x11, col:0x11, embed:0x11, hr:0x11, img:0x10,
      input:0x10, keygen:0x11, link:0x11, meta:0x11, param:0x11, source:0x11,
      track:0x11, wbr:0x10,
    }

    # remove Kernel methods of the same name: :p, :select, :sub
    (TAGS.keys & (private_instance_methods +
                  protected_instance_methods +
                  instance_methods)).each { |m| undef_method m }

    def tag? name
      TAGS[ name]
    end

    private

    def method_missing name, *args, &block
      t = tag? name
      t or super
      if String === args.last then
        b = args.pop
        @generator.tag name, t, *args do b end
      else
        @generator.tag name, t, *args, &block
      end
    end

    public

    def merge str
      @generator.merge str
      nil
    end

    def pcdata *strs
      strs.each { |s|
        @generator.plain s if s.notempty?
      }
      nil
    end

    def << str
      @generator.plain str if str
      self
    end

    def _ *strs
      if strs.notempty? then
        pcdata *strs
      else
        @generator.plain yield
        nil
      end
    end

    def comment str
      @generator.comment str
    end

    def javascript str = nil, &block
      mime = { type: "text/javascript" }
      script mime, str, &block
    end

    def html **attrs
      attrs[ :"lang"] ||= language
      method_missing :html, **attrs do yield end
    end

    def head **attrs
      method_missing :head, **attrs do
        meta charset: @generator.encoding
        yield
      end
    end

    def h i, **attrs, &block
      method_missing :"h#{i.to_i}", **attrs, &block
    end

    def form **attrs, &block
      attrs[ :method] ||=
              attrs[ :enctype] == "multipart/form-data" ? "post" : "get"
      method_missing :form, **attrs, &block
    end

    def input **attrs, &block
      attrs[ :id] ||= attrs[ :name]
      method_missing :input, **attrs, &block
    end

  end

  class XHtml < Html

    def html **attrs
      attrs[ :xmlns] ||= "http://www.w3.org/1999/xhtml"
      attrs[ :"xml:lang"] = language
      attrs[ :lang] = ""
      super
    end

    def a **attrs
      attrs[ :name] ||= attrs[ :id]
      super
    end

    private

    def generate out
      super do
        @generator.close_standalone = true
        @generator.assign_attributes = true
        @generator.cdata_block = true
        yield
      end
    end

    def doctype_header
      prop = { version: "1.0", encoding: @generator.encoding }
      @generator.pi_tag :xml, prop
      @generator.doctype "html", "PUBLIC", "-//W3C//DTD XHTML 1.1//EN",
                          "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd"
    end

  end

end

