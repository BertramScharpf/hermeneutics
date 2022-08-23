#
#  hermeneutics/cli/imap.rb  --  IMAP client
#

require "hermeneutics/cli/protocol"
require "hermeneutics/cli/imap/commands"


module Hermeneutics

  module Cli

    class IMAP < Protocol

      CRLF = true

      PORT, PORT_SSL = 143, 993

      class Error          < StandardError ; end
      class UnspecResponse < Error         ; end
      class ServerBye      < Error         ; end
      class NotOk          < Error         ; end

      class <<self
        private :new
        def open host, port = nil, timeout: nil, ssl: false
          port ||= ssl ? PORT_SSL : PORT
          super host, port, timeout: timeout, ssl: ssl do |i|
            yield i
            i.stop_watch
          end
        end
      end

      TAG_PREFIX = "H"

      def initialize *args
        super
        @tag = "H%04d" % 0
        @info = [ get_response]
        start_watch
      end

      attr_reader :info

      def auths data = nil
        a = []
        (data||@info.first.data).params.each { |p|
          p =~ /\AAUTH=/ and a.push $'.to_s
        }
        a
      end

      def command cmd, *args, &block
        c = cmd.new *args
        r = write_request c, &block
        r.ok? or raise NotOk, r.text
        c.responses
      end


      include ImapTools

      alias readline! readline
      private :readline!

      def peekline
        @peek ||= readline!
      end

      def readline
        @peek or readline!
      ensure
        @peek = nil
      end


      def get_response_plain
        Response.create @tag, self
      end

      def get_response
        r = get_response_plain
        r.bye? and raise IMAP::ServerBye, "Server closed the connection"
        r
      end


      def start_watch
        @watch = Thread.new do
          Thread.current.report_on_exception = false
          while @socket.wait do
            r = get_response
            @info.push r
          end
        end
      end

      def stop_watch
        @watch or return
        @watch.kill if @watch.alive?
        @watch.value
        @watch = nil
      end

      def write_request cmd
        stop_watch
        @tag.succ!
        r = nil
        cmd.stream_lines "#@tag" do |a|
          a.each { |l| writeline l.to_s }
          r = get_response_plain
          r.wait? or break
          if block_given? then  # does only make sense for the IDLE command
            begin
              start_watch
              yield
            ensure
              stop_watch
            end
          end
          r.text
        end
        until r.done? do
          bye ||= r.bye?
          cmd.add_response r
          r = get_response_plain
        end
        bye or start_watch
        r
      end

    end

    module ImapTools

      class Response
        class <<self
          private :new
          def create tag, reader
            reader.peekline.slice! /\A(\S+) +/ or return
            r = case $1
              when tag then ResponseFinish.create reader
              when "+" then ResponseWait.  create reader
              when "*" then ResponseStatus.create reader or
                            ResponseData.  create reader
              else          raise UnspecResponse, reader.readline
            end
          end
          private
          def compile_string str
            r = StringReader.new str
            compile_stream r
          end
          def compile_stream reader
            c = Data::Compiler.new
            Parser.compile reader, c
          end
        attr_reader :status, :data, :num, :text
        end
        def done? ; false ; end
        def wait? ; false ; end
        def bye?  ; false ; end
      end

      class ResponseWait < Response
        class <<self
          def create reader
            new reader.readline
          end
        end
        attr_reader :text
        def initialize text ; @text = text ; end
        def wait? ; true  ; end
      end

      class ResponseData < Response
        class <<self
          def create reader
            if reader.peekline.slice! /\A(\d+) +/ then
              n = $1.to_i
            end
            data = compile_stream reader
            new n, data
          end
        end
        attr_reader :num, :data
        def initialize num, data
          @num, @data = num, data
        end
      end

      class ResponseStatus < Response
        class <<self
          def create reader
            l = compile_line reader
            new *l if l
          end
          private
          def compile_line reader
            if reader.peekline.slice! /\A(OK|NO|BAD|BYE|PREAUTH) +/ then
              status = $1.to_sym
              if reader.peekline.slice! /\[(.*)\] +/ then
                data = compile_string $1
              end
              [ status, data, reader.readline]
            end
          end
        end
        attr_reader :status, :data, :text
        def initialize status, data, text
          @status, @data, @text = status, data, text
        end
        def ok?  ; @status == :OK  ; end
        def bye? ; @status == :BYE ; end
      end

      class ResponseFinish < ResponseStatus
        class <<self
          def create reader
            l = compile_line reader
            new *l if l
          end
        end
        def done? ; true  ; end
      end

    end

  end

end

