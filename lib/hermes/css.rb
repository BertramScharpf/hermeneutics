#
#  hermes/css.rb  -- CSS generation
#

require "hermes/html"


module Hermes

  # == Example
  #
  #   require "hermes/css"
  #   require "hermes/color"
  #   class MyCss < Css
  #
  #     COL1  = "904f02".to_rgb
  #     COL2  = COL1.edit_hsv { |h,s,v| [h+15,s,v] }
  #
  #     ATTR_COL1  = { color: COL1 }
  #     ATTR_COL2  = { color: COL2 }
  #     ATTR_DECON = { text_decoration: "none" }
  #     ATTR_DECOU = { text_decoration: "underline" }
  #
  #     def build
  #       a ":link",    ATTR_COL1, ATTR_DECON
  #       a ":visited", ATTR_COL2, ATTR_DECON
  #       a ":active", ATTR_COL1, ATTR_DECON
  #       a ":focus",  ATTR_COL1, ATTR_DECOU
  #       space
  #
  #       body "#dummy" do
  #         properties :background_color => "f7f7f7".to_rgb
  #         div ".child", :background_color => "e7e7e7".to_rgb
  #         @b = selector
  #         td do
  #           @bt = selector
  #         end
  #       end
  #       selectors @b, @bt, :fon_size => :large
  #     end
  #   end
  #   Hermes::Css.document
  #
  class Css

    class <<self
      attr_accessor :main
      def inherited cls
        Css.main = cls
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

    class Selector
      def initialize
        @chain = []
      end
      def tag descend, name, sub
        descend and @chain.empty? and
          raise "Descendor without previous tag: #{descend} #{name}#{sub}."
        c = []
        c.push case descend
          when ">", :child   then "> "
          when "+", :sibling then "+ "
          when nil           then
          else
            raise "Unknown descendor: #{descend}"
        end
        c.push name if name == "*" or Html::TAGS[ name]
        if sub then
          sub =~ /\A(?:
                    [:.#]([a-z_0-9-]+)|
                    \[([a-z0-9-]+)([~|]?=)(.*)\]
                  )*\z/ix or
            raise "Improper tag specification: #{name}#{sub}."
          c.push sub
        end
        @chain.push c
        yield
      ensure
        @chain.pop
      end
      protected
      def replace chain
        @chain.replace chain
      end
      public
      def dup
        s = Selector.new
        s.replace @chain
        s
      end
      def to_s
        @chain.map { |c| c.join }.join " "
      end
    end

    def initialize
      @selector = Selector.new
    end

    def document out = nil
      @out = out||$stdout
      build
    ensure
      @out = nil
    end

    def path
      @out.path
    rescue NoMethodError
    end

    def comment str
      @out << "/*"
      str = mask_comment str
      ml = str =~ %r(#$/)
      if ml then
        @out << $/
        str.each_line { |l|
          l.chomp!
          @out << " * " << l << $/
        }
      else
        @out << " " << str
      end
      @out << " */"
      ml and @out << $/
    end

    def space
      @out << $/
    end

    def tag *args
      p = []
      while Hash === args.last do
        p.unshift args.pop
      end
      @selector.tag *args do
        if p.empty? then
          yield
        else
          properties *p
        end
      end
    end

    # remove Kernel methods of the same name: :p, :select, :sub
    m = Html::TAGS.keys & (private_instance_methods +
                              protected_instance_methods + instance_methods)
    undef_method *m

    def method_missing sym, *args, &block
      if Html::TAGS[ sym] then
        if args.any? and not Hash === args.first then
          sub = args.shift
        end
        if args.any? and not Hash === args.first then
          desc, sub = sub, args.shift
        elsif sub !~ /[a-z]/i or Symbol === sub then
          desc, sub = sub, nil
        end
        tag desc, sym, sub, *args, &block
      else
        super
      end
    end

    def properties *args
      write @selector.to_s, *args
    end

    def selector
      @selector.dup
    end

    def selectors *args
      s = []
      while Selector === args.first do
        s.push args.shift
      end
      t = s.join ", "
      write t, *args
    end

    private

    def mask_comment str
      str.gsub /\*\//, "* /"
    end

    INDENT = "  "

    def write sel, *args
      p = {}
      args.each { |a| p.update a }
      @out << sel << " {"
      nl, ind = if p.size > 1 then
        @out << $/
        [ $/, INDENT]
      else
        [ " ", " "]
      end
      p.each { |k,v|
        if Symbol === k then k = k.new_string ; k.gsub! /_/, "-" end
        if Array  === v then v = v.join " "                      end
        @out << ind << k << ": " << v << ";" << nl
      }
      @out << "}" << $/
    end

  end

end

