#
#  hermeneutics/cli/protocol.rb  --  Basic communication
#

require "supplement"
require "socket"
require "io/wait"


if RUBY_VERSION < "3" then
  class TCPSocket
    class <<self
      alias open_orig open
      def open host, port, connect_timeout: nil, &block
        open_orig host, port, &block
      end
    end
  end
end

module Hermeneutics

  module Cli


    class Protocol

      class Error   < StandardError ; end
      class Timeout < Error         ; end

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
        l.chomp!
        @trace and $stderr.puts "C: #{l}"
        @socket.write l
        @socket.write self.class::CRLF ? "\r\n" : "\n"
      end

      def readline
        wait
        r = @socket.readline
        r.chomp!
        @trace and $stderr.puts "S: #{r}"
        r
      rescue EOFError
      end

      def write data
        @trace and $stderr.puts "C- #{data.inspect}"
        @socket.write data
      end

      def read bytes
        wait
        r = @socket.read bytes
        @trace and $stderr.puts "S- #{r.inspect}"
        r
      rescue EOFError
      end

      def done?
        not @socket.ready?
      end

      def wait
        if @timeout then
          raise Timeout unless @socket.wait @timeout
        end
      end

    end


    module CramMD5

      class <<self
        def included cls
          require "digest/md5"
        end
      end

      private

      def crammd5_answer a
        "#@user #{hmac_md5 a, @passwd}"
      end

      MASKS = [ 0x36, 0x5c, ]
      IMASK, OMASK = *MASKS

      def hmac_md5 text, key
        key = Digest::MD5.digest key if key.length > 64
        nulls = [ 0]*64
        k_ip, k_op = *MASKS.map { |m|
          (nulls.zip key.bytes).map { |n,k| ((k||n) ^ m).chr }.join
        }
        Digest::MD5.hexdigest k_op + (Digest::MD5.digest k_ip + text)
      end

    end

  end

end

