#
#  hermeneutics/cli/protocol.rb  --  Basic communication
#

require "supplement"
require "socket"


if RUBY_VERSION < "3" then
  class TCPSocket
    class <<self
      alias open_orig open
      def open host, port, timeout: nil, &block
        open_orig host, port, &block
      end
    end
  end
end

module Hermeneutics

  module Cli

    class Protocol

      class <<self
        private :new
        def open host, port, timeout: nil, ssl: false
          open_socket host, port, timeout, ssl do |s|
            i = new s, timeout
            yield i
          end
        end
        private
        def open_socket host, port, timeout, ssl
          TCPSocket.open host, port, connect_timeout: timeout do |s|
            if ssl then
              require "hermeneutics/cli/openssl"
              if Hash === ssl then
                if ssl[ :ca_file] || ssl[ :ca_path] then
                  ssl[ :verify_mode] ||= OpenSSL::SSL::VERIFY_PEER
                end
              else
                vfm = case ssl
                  when true    then OpenSSL::SSL::VERIFY_NONE
                  when Integer then ssl
                  when :none   then OpenSSL::SSL::VERIFY_NONE
                  when :peer   then OpenSSL::SSL::VERIFY_PEER
                end
                ssl = { verify_mode: vfm}
              end
              ctx = OpenSSL::SSL::SSLContext.new
              ctx.set_params ssl
              s = OpenSSL::SSL::SSLSocket.new s, ctx
              s.connect
            end
            yield s
          end
        end
      end

      CRLF = false

      attr_writer :timeout

      def initialize socket, timeout
        @socket, @timeout = socket, timeout
      end

      def trace!
        @trace = true
      end

      def writeline l
        @trace and $stderr.puts "C: #{l}"
        @socket.write l
        @socket.write self.class::CRLF ? "\r\n" : "\n"
      end

      def readline
        @socket.wait @timeout||0
        r = @socket.readline
        r.chomp!
        @trace and $stderr.puts "S: #{r}"
        r
      rescue EOFError
      end

      def done?
        not @socket.ready?
      end

    end

  end

end

