#!/usr/bin/env ruby
# encoding: UTF-8

#
#  index.rb  --  Redirection
#

require "hermeneutics/html"


module HermesDemo

  class IndexHtml < Hermeneutics::Html

    DELAY = 0
    REDIR = Hermeneutics::Contents.new DELAY, :url => "cgi-bin/index.rb"

    TITLE = "Hermeneutics Demo"

    def build
      html {
        head {
          title TITLE
          comment "created #{Time.now}\n"
          meta :http_equiv => :refresh, :content => REDIR
        }
        body {
          h1 TITLE
          p {
            _ "Click here if you weren't redirected automatically: "
            a :href => REDIR[ :url] do "continue" end
          }
        }
      }
    end

  end

end

Hermeneutics::Html.document

