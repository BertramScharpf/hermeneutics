#
#  hermeneutics/mail.rb  --  A mail
#

require "hermeneutics/message"

module Hermeneutics

  class Mail < Message

    # :stopdoc:
    class FromReader
      class <<self
        def open file
          i = new file
          yield i
        end
        private :new
      end
      attr_reader :from
      def initialize file
        @file = file
        @file.eat_lines { |l|
          l =~ /^From .*/ rescue nil
          if $& then
            @from = l
            @from.chomp!
          else
            @first = l
          end
          break
        }
      end
      def eat_lines &block
        if @first then
          yield @first
          @first = nil
        end
        @file.eat_lines &block
      end
    end
    # :startdoc:

    class <<self

      def parse input
        FromReader.open input do |fr|
          parse_hb fr do |h,b|
            new fr.from, h, b
          end
        end
      end

      def create
        new nil, nil, nil
      end

    end

    def initialize from, headers, body
      super headers, body
      @from = from
    end

    # String representation with "From " line.
    # Mails reside in mbox files etc. and so have to end in a newline.
    def to_s
      set_unix_from
      r = ""
      r << @from << $/ << super
      r.ends_with? $/ or r << $/
      r
    end

    def receivers
      addresses_of :to, :cc, :bcc
    end

    private

    def addresses_of *args
      l = args.map { |f| @headers.field f }
      AddrList.new *l
    end

    def set_unix_from
      return if @from
      # Common MTA's will issue a proper "From" line; some MDA's
      # won't.  Then, build it using the "From:" header.
      addr = nil
      l = addresses_of :from, :return_path
      # Prefer the non-local version if present.
      l.each { |a|
        if not addr or addr !~ /@/ then
          addr = a
        end
      }
      addr or raise ArgumentError, "No From: field present."
      @from = "From #{addr.plain} #{Time.now.gmtime.asctime}"
    end

  end

end

