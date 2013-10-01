#!/usr/bin/env ruby
# encoding: UTF-8

#
#  index.rb  --  Redirection
#

require "hermes/html"


module HermesDemo

  class IndexHtml < Hermes::Html

    DELAY = 0
    REDIR = Hermes::Contents.new DELAY, :url => "cgi-bin/index.rb"

    TITLE = "Hermes Demo"

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

Hermes::Html.document

