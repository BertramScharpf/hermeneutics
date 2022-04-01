require "openssl"

module OpenSSL
  module SSL
    class SSLSocket
      def wait timeout = :read ; @io.wait timeout ; end
      def ready?               ; @io.ready?       ; end
    end
  end
end

