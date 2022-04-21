#
#  hermeneutics/cli/imap/commands.rb  --  Commands for IMAP
#

require "hermeneutics/cli/imap/parser"

module Hermeneutics

  module Cli

    module ImapTools

      class Command

        class <<self
          alias [] new
        end

        attr_reader :responses

        def initialize
          @responses = []
        end

        def stream_lines r, &block
          mkdata.stream_lines r, &block
        end

        def add_response resp
          @responses.push resp
        end

        private

        def mkdata
          Data[ name, *params]
        end

      end

      class CommandGeneric < Command

        attr_reader :name, :params

        def initialize name, *params
          super *[]
          @name, @params = name, params
        end

      end

      class CommandNamed < Command
        def name ; self.class::NAME ; end
      end

      class Auth < CommandNamed

        NAME = :AUTHENTICATE

        attr_reader :user, :passwd

        def initialize user, passwd
          super *[]
          @user, @passwd = user, passwd
        end

        def params ; [ self.class::TYPE] ; end

        private

        def enc64 str
          [str].pack "m0"
        end

        def dec64 str
          (str.unpack "m0").join
        end

      end

      class AuthPlain < Auth

        TYPE = :PLAIN

        def stream_lines r
          _ = super
          r.clear
          r << (enc64 "\0#@user\0#@passwd")
          yield [r]
        end

      end

      class AuthLogin < Auth

        TYPE = :LOGIN

        def stream_lines r
          a = super
          loop do
            a = dec64 a
            l = case a
              when /user/i then @user
              when /pass/i then @passwd
            end
            l = enc64 l
            a = yield [l]
          end
        end

      end

      class AuthCramMD5 < Auth

        TYPE = :"CRAM-MD5"

        def initialize *args
          require "digest/md5"
          super
        end

        def stream_lines r
          a = super
          a = dec64 a
          l = enc64 "#@user #{hmac_md5 a, @passwd}"
          yield [l]
        end

        private

        def hmac_md5 text, key
          key = Digest::MD5.digest key if key.length > 64
          nulls = [ 0]*64
          k_ip, k_op = *[ 0x36, 0x5c].map { |m|
            (nulls.zip key.bytes).map { |n,k| ((k||n) ^ m).chr }.join
          }
          Digest::MD5.hexdigest k_op + (Digest::MD5.digest k_ip + text)
        end

      end


      class Idle < CommandNamed

        NAME = :IDLE
        DONE = :DONE

        def params ; [] ; end

        def stream_lines r
          _ = super
          yield [DONE]
        end

      end

    end

  end

end

