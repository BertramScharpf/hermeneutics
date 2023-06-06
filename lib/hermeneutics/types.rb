#
#  hermeneutics/types.rb  --  Header field types
#

require "supplement"

require "time"
require "bigdecimal"

require "hermeneutics/escape"


class NilClass
  def each
  end
end

module Hermeneutics

  class PlainText
    class <<self
      def parse str
        t = HeaderExt.decode str
        new t
      end
    end
    attr_reader :value
    def initialize value
      self.value = value
    end
    def value= value
      @value = value
      @value.gsub! /\s+/, " "
      @value.strip!
      @value.freeze
    end
    def to_s ; @value ; end
    alias quote to_s
    def encode
      HeaderExt.encode @value
    end
  end

  class Timestamp
    attr_reader :value
    def initialize value = nil
      self.value = value
    end
    def value= value
      @value = case value
        when nil  then Time.now
        when Time then value
        else           Time.parse value.to_s
      end
    end
    def to_s ; @value.to_s ; end
    def quote
      to_s
    end
    def encode
      @value.rfc822
    end
  end

  class Id
    @host = nil
    class <<self
      attr_writer :host
      def host
        require "socket"
        @host ||= Socket.gethostname
      end
      def parse str
        str =~ /<(.*?)>/
        yield $' if block_given?
        $1
      end
    end
    attr_reader :value
    def initialize value = nil
      self.value = value
    end
    def value= value
      @value = value ? value.new_string : generate
      @value.freeze
    end
    def to_s ; @value ; end
    alias quote to_s
    def encode
      "<#{self}>"
    end
    alias inspect encode
    private
    def generate
      t = Time.now.strftime "%Y%m%d%H%M%S"
      h = self.class.host
      a = "a".ord
      r = ""
      8.times { r << (a + (rand 26)).chr }
      "#{t}.#$$.#{r}@#{h}"
    end
  end

  class IdList
    class <<self
      def parse str
        i = new
        loop do
          id = Id.parse str do |rest| str = rest end
          id or break
          i.push id
        end
        i
      end
    end
    attr_reader :value
    def initialize *ids
      ids.flatten!
      self.value = ids
    end
    def value= ids
      @list = []
      ids.each { |id|
        id = Id.new id unless Id === id
        @list.push id
      }
      @list.freeze
    end
    def to_s
      map { |i| i.quote }.join " "
    end
    alias quote to_s
    def encode
      map { |i| i.encode }.join " "
    end
  end

  class Count
    class <<self
      def parse str
        i = Integer str
        new i
      end
    end
    attr_reader :value
    def initialize num
      @value = num.to_i
    end
    def value= value
      @value = value
    end
    alias quote to_s
    alias encode to_s
  end

end

