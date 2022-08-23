#
#  hermeneutics/cli/smtp.rb  --  SMTP client
#

require "hermeneutics/cli/protocol"

module Hermeneutics

  module Cli

    class SMTP < Protocol

      CRLF = true

      PORT, PORT_SSL = 25, 465

      class Error           < StandardError ; end
      class UnspecError     < Error         ; end
      class ServerNotReady  < Error         ; end
      class NotOk           < Error         ; end
      class NotReadyForData < Error         ; end
      class Unused          < Error         ; end
      class Uncaught        < Error         ; end

      class <<self
        private :new
        def open host, port = nil, timeout: nil, ssl: false
          port ||= ssl ? PORT_SSL : PORT
          super host, port, timeout: timeout, ssl: ssl
        end
      end

      attr_reader :domain, :greet
      attr_reader :advertised
      attr_reader :last_response

      def initialize *args
        super
        get_response.ok? or raise ServerNotReady, @last_response.msg
      end

      def size
        @advertised && @advertised[ :SIZE]
      end

      def auth
        @advertised && @advertised[ :AUTH]
      end

      def has_auth? meth
        a = auth
        a and a.include? meth
      end


      def helo host = nil
        cmd_hello "HELO", host
      end

      def ehlo host = nil
        @advertised = {}
        cmd_hello "EHLO", host do |code,msg|
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
      end

      def mail_from from
        cmd "MAIL", "FROM:<#{from}>"
      end

      def rcpt_to to
        cmd "RCPT", "TO:<#{to}>"
      end

      def data reader
        write_cmd "DATA"
        get_response.waiting? or raise NotReadyForData, @last_response.msg
        reader.each_line { |l|
          l =~ /\A\./ and l = ".#{l}"
          writeline l
        }
        writeline "."
        get_response_ok
      end

      def bdat data
        data.each { |d|
          write_cmd "BDAT", d.bytesize
          write d
          get_response_ok
        }
        write_cmd "BDAT", 0, "LAST"
        get_response_ok do |code,msg|
          yield msg if block_given?
        end
      end

      def rset
        cmd "RSET"
      end

      def help str = nil, &block
        cmd "HELP", str, &block
      end

      def noop str = nil
        cmd "NOOP"
      end

      def quit
        cmd "QUIT"
      end


      def plain user, password
        write_cmd "AUTH", "PLAIN"
        get_response.waiting? or raise NotReadyForData, @last_response.msg
        l = ["\0#{user}\0#{password}"].pack "m0"
        writeline l
        get_response_ok
      end


      def login user, password
        write_cmd "AUTH", "LOGIN"
        get_response.waiting? or raise NotReadyForData, @last_response.msg
        writeline [user].pack "m0"
        get_response.waiting? or raise NotReadyForData, @last_response.msg
        writeline [password].pack "m0"
        get_response_ok
      end


      private

      def cmd_hello name, host, &block
        host ||= Socket.gethostname
        write_cmd name, host
        get_response_ok &block
        unless @domain then
          @domain, @greet = @last_response.msg.split nil, 2
        end
      end

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
            break
          elsif r =~ /\A(\d\d\d)-/ then
            block_given? or raise Uncaught, r
            yield $1.to_i, $'
          else
            raise UnspecError, r
          end
        end
        @last_response
      ensure
        unless done? then
          r = readline
          r and raise Unused, "Unexpected data: #{r.inspect}"
        end
      end

    end

  end

end

