#
#  hermeneutics/cli/pop3.rb  --  POP3 client
#

require "hermeneutics/cli/protocol"

module Hermeneutics

  module Cli

    class POP3 < Protocol

      CRLF = true

      PORT, PORT_SSL = 110, 995

      class Error       < StandardError ; end
      class UnspecError < Error         ; end
      class AuthFail    < Error         ; end
      class Check       < Error         ; end
      class Unused      < Error         ; end

      class <<self
        private :new
        def open host, port = nil, timeout: nil, ssl: false
          port ||= ssl ? PORT_SSL : PORT
          super host, port, timeout: timeout, ssl: ssl
        end
      end

      attr_reader :last_response

      def initialize *args
        super
        @stamp = get_response.slice /<[!-~]+@[!-~]+>/
      end

      def authenticate name, pwd
        if @stamp then
          apop name, pwd
        else
          user name
          pass pwd
        end
      end

      def user name
        writeline "USER #{name}"
        get_response
      end

      def pass pwd
        writeline "PASS #{pwd}"
        get_response_auth
      end

      def apop name, pwd
        require "digest/md5"
        hash = Digest::MD5.hexdigest "#@stamp#{pwd}"
        writeline "APOP #{name} #{hash}"
        get_response_auth
      end

      def capa
        if block_given? then
          writeline "CAPA"
          get_response do |_|
            get_data { |l|
              c, *rest = l.split
              yield c, rest
            }
          end
        else
          r = Hash.new do |h,k| h[k] = [] end
          capa do |c,v|
            if v.notempty? then
              r[c].concat v
            else
              r[c] = true
            end
          end
          r
        end
      end

      def stat
        if block_given? then
          writeline "STAT"
          n, r = split_num_len get_response
          yield n, r
        else
          stat do |*a| a end
        end
      end

      def list n = nil
        n = n.to_i.nonzero?
        if block_given? then
          cmd = "LIST"
          cmd << " #{n}" if n
          writeline cmd
          if n then
            n_, len = split_num_len get_response
            n == n_ or raise Check, "Wrong LIST response: #{n} <-> #{n_}"
            yield n, len
          else
            get_response do |_|
              get_data do |l|
                n_, len = split_num_len l
                yield n_, len
              end
            end
          end
        else
          if n then
            list n do |*a| a end
          else
            h = {}
            list n do |n_,len|
              h[ n_] = len
            end
            h
          end
        end
      end

      def uidl n = nil
        n = n.to_i.nonzero?
        if block_given? then
          cmd = "UIDL"
          cmd << " #{n}" if n
          writeline cmd
          if n then
            n_, id = split_num get_response
            n == n_ or raise Check, "Wrong UIDL response: #{n} <-> #{n_}"
            yield n, id
          else
            get_response do |_|
              get_data do |l|
                n_, id = split_num l
                yield n_, id
              end
            end
          end
        else
          if n then
            uidl n do |*a| a end
          else
            h = {}
            uidl n do |n_,id|
              h[ n_] = id
            end
            h
          end
        end
      end

      def retr n, &block
        writeline "RETR #{n}"
        get_response do |_|
          get_data_str &block
        end
      end

      def top n, x, &block
        writeline "TOP #{n} #{x}"
        get_response do |_|
          get_data_str &block
        end
      end


      def dele n
        writeline "DELE #{n}"
        get_response
      end

      def rset
        writeline "RSET"
        get_response
      end

      def noop
        writeline "NOOP"
        get_response
      end

      def quit
        writeline "QUIT"
        get_response
      end

      private

      def get_response
        r = readline
        a = case r
          when /^\+OK */  then @last_response = $'.notempty?
          when /^\-ERR */ then raise Error, $'
          else                 raise UnspecError, r
        end
        if block_given? then
          yield a
        else
          a
        end
      ensure
        unless done? then
          r = readline
          r and raise Unused, "Discared data: #{r.inspect}"
        end
      end

      def get_response_auth
        begin
          get_response
        rescue Error
          err = $!.message
        end
        raise AuthFail, err if err
      end

      def get_data
        loop do
          l = readline
          break if l == "."
          l.slice /\A\./
          yield l
        end
      end

      def get_data_str
        if block_given? then
          get_data { |l| yield l }
        else
          r = ""
          get_data { |l| r << l << "\n" }
          r
        end
      end

      def split_num str
        n, r = str.split nil, 2
        [ n.to_i, r]
      end

      def split_num_len str
        n, r = split_num str
        [ n, r.to_i]
      end

    end

  end

end

