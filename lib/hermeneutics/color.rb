#
#  hermeneutics/color.rb  -- Color calculation
#

=begin rdoc

:section: Classes definied here

Hermeneutics::Color handles 24-bit colors.

Hermeneutics::Colour is an alias for <code>Hermeneutics::Color</code>.

=end



module Hermeneutics

  # Generate HTML color values.
  #
  # = Examples
  #
  #   red = Color.new 0xff, 0, 0
  #   black = Color.grey 0
  #   red.to_s                           #=> "#ff0000"
  #   red.to_fract                       #=> [ 1.0, 0.0, 0.0]
  #
  #   (Color.new 0xff, 0, 0).to_hsv      #=> [0.0, 1.0, 1.0]
  #   (Color.new 0, 0xff, 0).to_hsv      #=> [120.0, 1.0, 1.0]
  #   (Color.new 0, 0x7f, 0x7f).to_hsv   #=> [180.0, 1.0, 0.49804]
  #   (Color.new 0, 0x80, 0x80).to_hsv   #=> [180.0, 1.0, 0.50196]
  #   (Color.from_hsv 180, 1, 0.5).to_s  #=> "#007f7f"
  #
  class Color

    attr_reader :r, :g, :b

    private

    # :call-seq:
    #   new( r, g, b)           -> clr
    #
    # Create a color with red, green and blue values.  They are in range
    # <code>0..255</code>.
    #
    def initialize r, *gb
      if gb.any? then
        @r, @g, @b = *[ r, *gb].map { |x| ff x }
      else
        @r = @g = @b = (ff r)
      end
    end

    def ff x ; (Integer x) & 0xff ; end

    public

    def r= x ; @r = ff x ; end
    def g= x ; @g = ff x ; end
    def b= x ; @b = ff x ; end

    # :call-seq:
    #   to_a()    -> ary
    #
    # Return RGB values as an array.
    #
    def to_a ; [ @r, @g, @b] ; end
    alias tuple to_a

    def == oth
      case oth
        when Color then to_a == oth.to_a
        when Array then to_a == oth
      end
    end

    class <<self

      # :call-seq:
      #   gray( num)           -> clr
      #
      # Create a gray color (r=b=g). <code>num</code> is in range
      # <code>0..255</code>.
      #
      def gray i
        new i, i, i
      end
      alias grey gray

    end

    # :call-seq:
    #   to_s()    -> str
    #
    # Return color as an HTML tags key.
    #
    def to_s ; "#" + tuple.map { |x| "%02x" % x }.join ; end

    def inspect ; "#<#{cls}:#{'0x%08x' % (object_id << 1)} #{to_s}>" ; end

    class <<self

      # :call-seq:
      #   from_s( str)    -> clr
      #
      # Build a Color from an HTML tags key.
      #
      def from_s str
        rgb = str.scan( /[0-9a-f]{2}/i).map do |x| x.to_i 0x10 end
        new *rgb
      end

    end


    # :call-seq:
    #   to_fract()    -> ary
    #
    # Return three values in range 0..1 where 1.0 means 255.
    #
    def to_fract
      tuple.map { |x| x / 255.0 }
    end

    class <<self

      # :call-seq:
      #   from_fract( rf, gf, bf)    -> clr
      #
      # Build a Color from three values in range 0..1 where 1.0 means 255.
      #
      def from_fract rf, gf, bf
        rgb = [rf, gf, bf].map { |x| 0xff * x }
        new *rgb
      end

    end


    # :call-seq:
    #   to_long()    -> ary
    #
    # Extend it to a 48-bit color triple.
    #
    def to_long
      tuple.map { |x| x * 0x100 + x }
    end

    class <<self

      # :call-seq:
      #   from_fract( rl, gl, bl)    -> clr
      #
      # Build a Color from three values in range 0..0xffff.
      #
      def from_long rl, gl, bl
        rgb = [rl, gl, bl].map { |x| x / 0x100 }
        new *rgb
      end

    end


    # :call-seq:
    #   to_hsv()    -> ary
    #
    # Convert it to an HSV triple.
    #
    def to_hsv
      rgb = [ @r, @g, @b].map { |x| (Integer x) / 255.0 }
      v = rgb.max
      delta = v - rgb.min
      unless delta > 0.0 then
        h = s = 0.0
      else
        s = delta / v
        r, g, b = rgb
        case v
          when r then h =     (g - b) / delta ; h += 6 if h < 0
          when g then h = 2 + (b - r) / delta
          when b then h = 4 + (r - g) / delta
        end
        h *= 60
      end
      [ h, s, v]
    end

    class <<self

      # :call-seq:
      #   from_hsv( h, s, v)    -> clr
      #
      # Build a Color from HSV parameters.
      #
      # Ranges are:
      #
      #   h    0...360
      #   s    0.0..1.0
      #   v    0.0..1.0
      #
      def from_hsv h, s, v
        if s.nonzero? then
          h /= 60.0
          i = h.to_i % 6
          f = h - i
          rgb = []
          if (i%2).zero? then
            rgb.push v
            rgb.push v * (1.0 - s * (1.0 - f))
          else
            rgb.push v * (1.0 - s * f)
            rgb.push v
          end
          rgb.push v * (1.0 - s)
          rgb.rotate! -(i/2)
          from_fract *rgb
        else
          from_fract v, v, v
        end
      end

    end

    # :call-seq:
    #   edit_hsv() { |h,s,v| ... }    -> clr
    #
    # Convert it to an HSV triple, yield that to the block and build a
    # new <code>Color</code> from the blocks result.
    #
    def edit_hsv
      hsv = yield *to_hsv
      self.class.from_hsv *hsv
    end

    # :call-seq:
    #   complementary()                -> clr
    #
    # Build the complementary color.
    #
    def complementary ; Color.new *(tuple.map { |x| 0xff - x }) ; end

  end

  # Alias for class <code>Hermeneutics::Color</code> in British English.
  Colour = Color

end


class Float
  def to_gray
    Hermeneutics::Color.gray self
  end
  alias to_grey to_gray
end

class String
  def to_gray
    (Integer self).to_gray
  end
  alias to_grey to_gray
  def to_rgb
    Hermeneutics::Color.from_s self
  end
end

class Array
  def to_rgb
    Hermeneutics::Color.new *self
  end
  def to_hsv
    Hermeneutics::Color.from_hsv *self
  end
end

