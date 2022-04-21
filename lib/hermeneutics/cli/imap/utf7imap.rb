#
#  hermeneutics/cli/imap/utf7imap.rb  --  IMAP's UTF-7
#

require "supplement"

module Hermeneutics

  module Cli

    module ImapTools

      class UTF7

        class <<self

          def encode str
            e = str.gsub /&|([^ -~]+)/ do
              if $1 then
                b64 = [($1.encode Encoding::UTF_16BE)].pack "m0"
                b64.slice! %r/=+\z/
                b64.tr! "/", ","
              end
              "&#{b64}-"
            end
            if e.empty? or e =~ %r/[ "]/ then
              e = %Q["#{e.gsub /(["\\])/ do "\\#$1" end}"]
            end
            new e
          end

          def decode txt
            (new txt).decode
          end

        end

        def initialize txt
          @txt = txt
        end

        def to_s ; @txt ; end

        def decode
          t = @txt
          if t =~ /\A"(.*)"\z/ then
            t = $1
            t.gsub! /\\(.)/ do $1 end
          end
          t.gsub /&(.*?)-/ do
            if $1.empty? then
              "&"
            else
              r = $1
              r.tr! ",", "/"
              f = -r.length % 4
              if f.nonzero? then
                r << "=" * f
              end
              r, = r.unpack "m"
              r.force_encoding Encoding::UTF_16BE
              r.encode! Encoding.default_external
              r
            end
          end
        end

      end

    end

  end

end

