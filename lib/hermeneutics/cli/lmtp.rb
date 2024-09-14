#
#  lib/hermeneutics/cli/lmtp.rb  --  LMTP client
#

require "hermeneutics/cli/protocol"

module Hermeneutics

  module Cli

    class LMTP < Protocol

      CRLF = true

      class UnspecError     < Error         ; end
      class ServerNotReady  < Error         ; end
      class NotOk           < Error         ; end
      class NotReadyForData < Error         ; end
      class Unused          < Error         ; end
      class Uncaught        < Error         ; end

      class <<self
        private :new
        def open socketfile
          UNIXSocket.open socketfile do |s|
            i = new s, nil
            yield i
          end
        end
      end

      attr_reader :domain, :greet
      attr_reader :advertised
      attr_reader :last_response

      def initialize *args
        super
        get_response.ok? or raise ServerNotReady, @last_response.msg
        @rcpt = 0
      end

      def size
        @advertised && @advertised[ :SIZE]
      end


      def lhlo host = nil
        @advertised = {}
        write_cmd "LHLO", host||Socket.gethostname
        get_response_ok do |code,msg|
          unless @domain then
            @domain, @greet = msg.split nil, 2
            next
          end
          keyword, param = msg.split nil, 2
          keyword.upcase!
          keyword = keyword.to_sym
          case keyword
            when :SIZE then param = Integer param
            when :AUTH then param = param.split.map { |p| p.upcase! ; p.to_sym }
          end
          @advertised[ keyword] = param || true
        end
        unless @domain then
          @domain, @greet = @last_response.msg.split nil, 2
        end
      end

      def mail_from from
        cmd "MAIL", "FROM:<#{from}>"
      end

      def rcpt_to to
        cmd "RCPT", "TO:<#{to}>"
        @rcpt += 1
      end

      def data reader
        write_cmd "DATA"
        get_response.waiting? or raise NotReadyForData, @last_response.msg
        reader.each_line { |l|
          l =~ /\A\./ and l = ".#{l}"
          writeline l
        }
        writeline "."
        get_response_rcpts
      end

      def bdat data
        data.each { |d|
          write_cmd "BDAT", d.bytesize
          write d
          get_response_ok
        }
        write_cmd "BDAT", 0, "LAST"
        get_response_rcpts
      end

      def rset
        cmd "RSET"
      ensure
        @rcpt = 0
      end

      def noop str = nil
        cmd "NOOP"
      end

      def quit
        cmd "QUIT"
      end


      private

      def cmd name, *args, &block
        write_cmd name, *args
        get_response_ok &block
      end

      def write_cmd name, *args
        l = [ name, *args].join " "
        writeline l
      end

      class Response

        attr_reader :code, :msg

        def initialize code, msg
          @code, @msg = code, msg
        end

        def kat ; code / 100 ; end

        def to_s ; "%03d %s" % [ @code, @msg] ; end

        def prelim?  ; kat == 1 ; end
        def ok?      ; kat == 2 ; end
        def waiting? ; kat == 3 ; end
        def error?   ; kat == 4 ; end
        def fatal?   ; kat == 5 ; end

      end

      def get_response_ok &block
        get_response &block
        @last_response.ok? or raise NotOk, @last_response.msg
        true
      end

      def get_response
        loop do
          r = readline
          if r =~ /\A(\d\d\d) / then
            @last_response = Response.new $1.to_i, $'
            break @last_response
          elsif r =~ /\A(\d\d\d)-/ then
            block_given? or raise Uncaught, r
            yield $1.to_i, $'
          else
            raise UnspecError, r
          end
        end
      end

      def get_response_rcpts
        r = []
        @rcpt.times {
          r.push get_response
          @last_response.ok? or raise NotOk, @last_response.msg
        }
        r
      ensure
        @rcpt = 0
      end

    end

  end

end

