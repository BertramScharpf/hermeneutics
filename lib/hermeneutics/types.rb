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

  class PlainText < String
    class <<self
      def parse str
        t = HeaderExt.decode str
        new t
      end
    end
    def initialize text
      super
      gsub! /\s+/, " "
      strip!
    end
    def quote
      to_s
    end
    def encode
      (HeaderExt.encode self).split
    end
  end

  class Timestamp < Time
    class <<self
      def new time = nil
        case time
          when nil  then now
          when Time then mktime *time.to_a
          else           parse time.to_s
        end
      end
    end
    def quote
      to_s
    end
    def encode
      rfc822
    end
  end

  class Id < String
    @host = nil
    class <<self
      attr_writer :host
      autoload :Socket, "socket"
      def host
        @host ||= socket.gethostname
      end
      def parse str
        str =~ /<(.*?)>/
        yield $' if block_given?
        $1
      end
    end
    attr_reader :id
    def initialize id = nil
      super id || generate
    end
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

  class IdList < Array
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
    def initialize
      super
    end
    def add id
      id = Id.new id.to_s unless Id === id
      puts id
    end
    def quote
      map { |i| i.quote }.join " "
    end
    alias to_s quote
    def encode
      map { |i| i.encode }.join " "
    end
  end

  class Count < BigDecimal
    class <<self
      def parse str
        new str
      end
    end
    def initialize num
      super num.to_i.to_s
    end
    def to_s *args
      to_i.to_s
    end
    alias quote to_s
    alias encode to_s
  end

end

