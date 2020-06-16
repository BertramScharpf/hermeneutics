#
#  hermes/cli/pop.rb  --  POP client
#

module Hermeneutics

  module Cli

    class Pop

      class Keep < Exception ; end

      def initialize host, port = nil
        if not port and host =~ /:(\d+)\z/ then
          host, port = $`, $1.to_i
        end
        @host, @port = host, port
        require "net/pop"
      end

      def login user, password
        do_apop do
          @pop = Net::POP3.new @host, @port, @apop
          do_ssl
          @pop.start user, password do |pop|
            @user = user
            yield
          end
        end
      ensure
        @user = nil
      end

      def name
        @user or raise "Not logged in."
        r = "#@user@#@host"
        r << ":#@port" if @port
        r
      end

      def count ; @pop.n_mails ; end

      def each
        @pop.mails.each do |m|
          begin
            yield m.pop
            m.delete
          rescue Keep
          end
        end
      end

      private

      def do_apop
        @apop = true
        begin
          yield
        rescue Net::POPAuthenticationError
          raise unless @apop
          @apop = false
          retry
        end
      end

      def do_ssl
        @pop.disable_ssl
      end

    end

    class Pops < Pop

      def initialize host, port = nil, certs = nil
        unless certs or Integer === port then
          port, certs = nil, port
        end
        @certs = File.expand_path certs if certs
        super host, port
      end

      private

      def do_apop
        yield
      end

      def do_ssl
        v = if @certs then
          OpenSSL::SSL::VERIFY_PEER
        else
          OpenSSL::SSL::VERIFY_NONE
        end
        @pop.enable_ssl v, @certs
      end

    end

  end

end

