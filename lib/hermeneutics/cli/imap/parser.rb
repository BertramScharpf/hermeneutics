#
#  hermeneutics/cli/imap/parser.rb  --  Parsing IMAP responses
#

require "supplement"

require "hermeneutics/cli/imap/utf7imap"


module Hermeneutics

  module Cli

    module ImapTools

      class StringReader
        def initialize src
          @src = src.lines
          @src.each { |l| l.chomp! }
        end
        def readline
          @src.shift
        end
        def eof? ; @src.empty? ; end
      end


      class Parser

        RE = %r/\A\s*(?:
          (\()|
          (\))|
          ("(?:[^\\"]|\\.)*")|
          (\{\d+\}\z)|
          ((?:\[[^\]]*\]|[^ \t)])+)|
        )/x

        class <<self

          def run input
            p = new
            l = input.readline
            loop do
              if l.empty? then
                break if p.closed?
                l = input.readline
              end
              l.slice! RE
              case
                when $1 then
                  p.step_in
                when $2 then
                  p.step_out
                when $3 then
                  r = UTF7.decode $3
                  p.add r
                when $4 then
                  n = $4[1,$4.length-2].to_i
                  r = ""
                  while n > 0 do
                    l = input.readline
                    l or raise "No more data after {#$4}"
                    m = l.length
                    if n <= m then
                      r << (l.slice! 0, n)
                    else
                      r << l << "\n"
                      l.clear
                      n -= 2
                    end
                    n -= m
                  end
                  p.add r
                when $5 then
                  r = $5.nil_if "NIL"
                  r = UTF7.decode r if r
                  p.add r
                else
                  raise "Error reading '#$''"
              end
            end
            p
          end

          def compile input, compiler
            p = run input
            p.walk compiler
            compiler.result
          end

        end

        def initialize
          @list = []
        end

        def step_in
          if @sub then
            @sub.step_in
          else
            @sub = self.class.new
          end
        end

        def step_out
          if @sub.closed? then
            @list.push @sub
            @sub = nil
          else
            @sub.step_out
          end
        end

        def add token
          if @sub then
            @sub.add token
          else
            @list.push token
          end
        end

        def closed?
          not @sub
        end

        def walk compiler
          closed? or raise "Object was not fully parsed. Rest: #@sub"
          @list.each { |x|
            case x
              when self.class then compiler.step do x.walk compiler end
              else                 compiler.add x
            end
          }
          compiler.finish
        end

      end


      class Data

        class <<self
          alias [] new
        end

        attr_reader :name, :params

        def initialize name, *params
          @name, @params = name, params
        end

        def stream_lines r, &block
          r << " " << @name.to_s
          add_to_stream r, @params, &block
          yield [r]
        end

        private

        # If you think this is too complicated, then complain to
        # the designers of IMAP.
        #
        def add_to_stream r, ary, &block
          ary.each { |a|
            r << " " unless @opened
            @opened = false
            case a
              when Array then
                r << "("
                @opened = true
                add_to_stream r, a, &block
                r << ")"
                @opened = false
              else
                a = a.to_s
                s = a.notempty? ? (a.split /\r?\n/, -1) : [""]
                l = s.length - 1
                if l > 0 then
                  m = 0
                  s.each { |e| m += e.length }
                  m += l*2
                  r << "{#{m}}"
                  _ = yield [r]
                  r.clear
                  yield s
                else
                  r << (UTF7.encode a).to_s
                end
            end
          }
        end

        public

        class Compiler

          def initialize
            @list = []
          end

          def result
            Data.new @name, *@list
          end

          def step
            list_, @list = @list, []
            sub_, @sub = @sub, true
            yield
          ensure
            list_.push @list
            @list, @sub = list_, sub_
          end

          def add x
            if @sub then
              @list.push x
            else
              if not @name then
                is_name? x or raise "Not an item name: #{x}"
                @name = x.to_sym
              else
                @list.push x
              end
            end
          end

          def finish
          end

          private

          def is_name? x
            x =~ /\A[A-Z]+\z/
          end

        end

      end

    end

  end

end

