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


      class Login < CommandNamed

        NAME = :LOGIN

        attr_reader :user, :passwd

        def initialize user, passwd
          super *[]
          @user, @passwd = user, passwd
        end

        def params ; [ @user, @passwd] ; end

      end


      class Auth < CommandNamed

        NAME = :AUTHENTICATE

        @sub = []
        class <<self
          def inherited cls
            @sub.push cls
          end
          def find type
            type = type.to_sym
            @sub.find { |c| c::TYPE == type }
          end
        end

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

        def stream_lines r
          a = super
          a = dec64 a
          w = crammd5_answer a
          l = enc64 w
          yield [l]
        end

        include CramMD5

      end


      class Logout < CommandNamed

        NAME = :LOGOUT

        def initialize
          super
        end

        def params ; [] ; end

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


      class Capability < CommandNamed

        NAME = :CAPABILITY

        def initialize
          super
        end

        def params ; [] ; end

      end


      class Fetch < CommandNamed

        NAME = :FETCH

        def initialize seqset, items
          super *[]
          @seqset = to_seqset seqset
          @items = items
        end

        def params ; [ @seqset, @items] ; end

        private

        def to_seqset s
          case s
            when String then s
            when Array  then ary_to_seqset s
            else             s.to_s
          end
        end

        def ary_to_seqset a
          a.map { |s|
            case s
              when Range then ([s.begin, s.end].join ":")
              else            s
            end
          }.join ","
        end

      end

      class Search < CommandNamed

        NAME = :SEARCH

        def initialize *criteria
          super *[]
          @criteria = criteria
        end

        def params ; @criteria ; end

      end

      class Status < CommandNamed

        NAME = :STATUS

        def initialize mailbox, *items
          super *[]
          @mailbox, @items = mailbox, items
        end

        def params ; [ @mailbox, items] ; end

      end

      class List < CommandNamed

        NAME = :LIST

        def initialize ref, mailbox
          super *[]
          @ref, @mailbox = ref, mailbox
        end

        def params ; [ @ref, @mailbox] ; end

      end

      class DataLsub < List

        NAME = :LSUB

      end

    end

  end

end

