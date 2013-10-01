#
#  hermes/html.rb  -- smart HTML generation
#

require "hermes/escape"
require "hermes/contents"


module Hermes

  # = Example
  #
  # require "hermes/color"
  # require "hermes/html"
  # class MyHtml < Html
  #   def build
  #     html {
  #       head {
  #         title { "Example" }
  #         comment "created as an example, #{Time.now}\n"
  #       }
  #       body( :bgcolor => Color.from_s( "ffffef")) {
  #         h1 {
  #           pcdata "Ruby "
  #           a( :href => "www.w3.org") { "Html" }
  #           _ { " example" }
  #         }
  #         p { "Some text.\nBye." }
  #         p {
  #           self << "link"
  #           br
  #           a( :href => "www.w3.org") { "Html" }
  #         }
  #       }
  #     }
  #   end
  # end
  # Html.document
  #
  class Html

    class <<self
      attr_accessor :main
      def inherited cls
        Html.main = cls
      end
      def document out = nil
        open_out out do |o|
          @main.new.document o
        end
      end
      private
      def open_out out
        if out or $*.empty? then
          yield out
        else
          File.open $*.shift, "w" do |f| yield f end
        end
      end
    end

    def language
    end

    def build
      html { body { p { "It works." } } }
    end

    def document out = nil
      if String === out and out.ascii_only? then
        out.force_encoding Encoding.default_external
      end
      @generator = Generator.new out
      doctype_header
      build
    ensure
      @generator = nil
    end

    DOCTYPE = "transitional"

    private

    def doctype_header
      doctype_header_data do |type,dtd,dir,variant,file|
        file or raise ArgumentError, "No header data for #{self.class}"
        name = ["DTD", dtd, variant].compact.join " "
        path = ["-", "W3C", name, "EN"].join "//"
        link = "http://www.w3.org/TR/#{dir}/#{file}.dtd"
        @generator.doctype type, path, link
      end
    end

    def doctype_header_data
      vf = case DOCTYPE
        when "strict"       then [ nil,            "strict"  ]
        when "transitional" then [ "Transitional", "loose"   ]
        when "frameset"     then [ "Frameset",     "frameset"]
      end
      yield "HTML", "HTML 4.01", "html4", *vf
    end

  end

  class XHtml < Html

    def document out = nil
      super do
        @generator.close_standalone = true
        @generator.assign_attributes = true
        yield
      end
    end

    def html attrs = nil
      attrs ||= {}
      attrs[ :xmlns] ||= "http://www.w3.org/1999/xhtml"
      super
    end

    def a attrs = nil
      attrs[ :name] ||= attrs[ :id] if attrs
      super
    end

    def quote_script str
      @generator.commented_cdata str
    end

    private

    def doctype_header
      prop = { version: "1.0", encoding: @generator.encoding }
      @generator.pi_tag :xml, prop
      super
    end

    def doctype_header_data
      vf = case DOCTYPE
        when "strict"       then [ "Strict",       "xhtml1-strict"      ]
        when "transitional" then [ "Transitional", "xhtml1-transitional"]
        when "frameset"     then [ "Frameset",     "xhtml1-frameset"    ]
      end
      yield "html", "XHTML 1.0", "xhtml1/DTD", *vf
    end

  end

  class Html

    class Generator
      attr_accessor :close_standalone, :assign_attributes
      def initialize out
        @out = out||$stdout
        @ent = Entities.new
        @nl, @ind = true, [ ""]
      end
      def encoding
        case @out
          when IO then @out.external_encoding||ENCODING
          else         @out.encoding
        end
      end
      def path
        @out.path
      rescue NoMethodError
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
      def tag nls, tag, attrs = nil
        if String === attrs then
          tag nls, tag, nil do attrs end
          return
        end
        if Symbol === tag then tag = tag.new_string ; tag.gsub! /_/, "-" end
        if block_given? then
          begin
            brk if nls>1
            brace nls>1 do
              @out << tag
              mkattrs attrs
            end
            indent_if nls>2 do
              r = yield
              plain r if String === r
            end
          ensure
            brk if nls>1
            brace nls>0 do
              @out << "/" << tag
            end
          end
        else
          brk if nls>1
          brace nls>0 do
            @out << tag
            mkattrs attrs
            @out << " /" if @close_standalone
          end
        end
        nil
      end
      # Processing Instruction
      def pi_tag tag, attrs = nil
        brace true do
          begin
            @out << "?" << tag
            mkattrs attrs
          ensure
            @out << " ?"
          end
        end
      end
      def doctype type, path, link
        brace true do
          @out << "!DOCTYPE"
          %W(#{type} PUBLIC "#{path}" "#{link}").each { |x| @out << " " << x }
        end
      end
      def comment str
        brace true do
          nl = str =~ %r(#$/\z)
          @out << "!--"
          brk if nl
          @out << str
          do_ind if nl
          @out << "--"
        end
      end
      def commented_cdata str
        @out << $/ << "/* "
        brace false do
          @out << "![CDATA["
          @out << " */" << $/
          @out << str
          @out << $/ << "/* "
          @out << "]]"
        end
        @out << " */" << $/
      end
      private
      def brk
        unless @nl then
          @nl = true
          @out << $/
        end
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
      def indent_if flag, &block
        if flag then
          indent &block
        else
          yield
        end
      end
      def indent
        @ind.push @ind.last + "  "
        yield
      ensure
        @ind.pop
      end
      def mkattrs attrs
        attrs or return
        attrs.each { |k,v|
          if Symbol === k then k = k.new_string ; k.gsub! /_/, "-" end
          v or next
          @out << " " << k
          case v
            when true then
              next unless @assign_attributes
              v = k
            when Array then
              v = v.compact.join " "
          end
          @out << "=\"" << (@ent.encode v) << "\""
        }
      end
    end

    def path ; @generator.path ; end

    NBSP = Entities::NAMES[ "nbsp"]

    TAGS = {
      a: 0, abbr: 0, acronym: 0, address: 1, applet: 0, area: 1, b: 0, base:
      1, basefont: 1, bdo: 0, big: 0, blockquote: 3, body: 2, br: 1, button:
      3, caption: 1, center: 3, cite: 0, code: 0, col: 1, colgroup: 3, dd: 1,
      del: 0, dfn: 0, dir: 3, div: 3, dl: 3, dt: 1, em: 0, fieldset: 3, font:
      0, form: 3, frame: 1, frameset: 3, h1: 1, h2: 1, h3: 1, h4: 1, h5: 1,
      h6: 1, head: 3, hr: 1, html: 2, i: 0, iframe: 3, img: 0, input: 0, ins:
      0, isindex: 1, kbd: 0, label: 0, legend: 1, li: 1, link: 1, map: 3,
      menu: 3, meta: 1, noframes: 3, noscript: 3, object: 3, ol: 3, optgroup:
      3, option: 1, p: 3, param: 1, pre: 1, q: 0, s: 0, samp: 0, script: 3,
      select: 3, small: 0, span: 0, strike: 0, strong: 0, style: 2, sub: 0,
      sup: 0, table: 3, tbody: 3, td: 1, textarea: 1, tfoot: 3, th: 1, thead:
      3, title: 1, tr: 3, tt: 0, u: 0, ul: 3, var: 0,
    }

    # remove Kernel methods of the same name: :p, :select, :sub
    m = TAGS.keys & (private_instance_methods +
                              protected_instance_methods + instance_methods)
    undef_method *m

    def method_missing name, *args, &block
      t = TAGS[ name]
      t or super
      @generator.tag t, name, *args, &block
    end

    def pcdata *strs
      strs.each { |s|
        next unless s
        @generator.plain s
      }
      nil
    end

    def << str
      @generator.plain str if str
      self
    end

    def _ str = nil
      @generator.plain str||yield
      nil
    end

    def comment str
      @generator.comment str
    end

    def quote_script str
      comment str+$/+"// "
    end

    def javascript str
      mime = { type: "text/javascript" }
      script mime do quote_script str end
    end

    def css str
      mime = { type: "text/css" }
      script mime do quote_script str end
    end

    def head attrs = nil
      method_missing :head, attrs do
        c = ContentType.new "text/html", charset: @generator.encoding
        meta http_equiv: "Content-Type",     content: c
        l = language
        meta http_equiv: "Content-Language", content: l if l
        yield
      end
    end

    def form attrs, &block
      attrs[ :method] ||= if attrs[ :enctype] == "multipart/form-data" then
        "post"
      else
        "get"
      end
      @tabindex = 0
      method_missing :form, attrs, &block
    ensure
      @tabindex = nil
    end

    Field = Struct[ :type, :attrs]

    def field type, attrs
      attrs[ :id] ||= attrs[ :name]
      @tabindex += 1
      attrs[ :tabindex] ||= @tabindex
      Field[ type, attrs]
    end

    def label field, attrs = nil, &block
      if String === attrs then
        label field do attrs end
        return
      end
      if Field === field or attrs then
        a = attrs
        attrs = { for: field.attrs[ :id] }
        attrs.merge! a if a
      else
        attrs = field
      end
      method_missing :label, attrs, &block
    end

    def input arg, &block
      if Field === arg then
        case arg.type
          when /select/i   then
            method_missing :select, arg.attrs, &block
          when /textarea/i then
            block and
              raise ArgumentError, "Field textarea: use the value attribute."
            v = arg.attrs.delete :value
            method_missing :textarea, arg.attrs do v end
          else
            arg.attrs[ :type] ||= arg.type
            method_missing :input, arg.attrs, &block
        end
      else
        method_missing :input, arg, &block
      end
    end

  end

end

