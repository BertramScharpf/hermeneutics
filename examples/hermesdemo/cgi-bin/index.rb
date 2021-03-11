#!/usr/bin/env ruby
# encoding: UTF-8

#
#  index.rb  --  Just show some Hermeneutics features
#

require "hermeneutics/cgi"


module HermesDemo

  class IndexHtml < Hermeneutics::Html

    def initialize cgi
      super
      @now = Time.now
    end

    def build
      html {
        head {
          title { "Hermeneutics Demo" }
          comment "created by Hermeneutics at #@now\n"
          link :rel => "stylesheet", :type => "text/css",
                                      :href => "../hermesdemo.css"
        }
        body do
          build_contents
          hr
          mention_source
          hr
          show_environment
        end
      }
    end

    def build_contents
      h1 { "Welcome to Hermeneutics" }
      p "This page was built at #@now by a process with the id #$$."
      p "This page was transmitted by #{cgi.https? ? :HTTPS : :HTTP}."
      previous_parameters
      show_sent
      simple_form
      data_link
    end

    def previous_parameters
      h3 "Previously sumbitted parameters"
      pre {
        cgi.parameters.each { |k,v|
          _ "#{k} = #{v.inspect}" << $/
        }
        _ "(none)" if cgi.parameters.empty?
      }
    end

    def show_sent
      cgi.mailto or return
      h3 "Mail"
      p "Mail to #{cgi.mailto} has been sent."
    end

    def simple_form
      h3 "Simple form"
      form! "simple", method: "POST", enctype: "multipart/form-data" do
        ft = field :text,   name: "foo", size: 32, value: cgi.param[ :foo]
        fs = field :submit, name: "bar", value: " submit this data "
        label ft, "Enter some data: "
        input ft
        br
        input fs
        br
        _ "To send a mail to the address entered, push here: "
        fn = field :submit, name: "mail", value: " send "
        input fn
      end
      p <<~EOT
        To raise an error while page building, start the input field with the word
        'raise'.
      EOT
      p "To ask Google, say 'google' as first word."
    end

    def data_link
      h3 "Data link"
      _ "This is a "
      h = href nil, info: "INFO", further:"Hi, there!"
      a :href => h do "link with parameters" end
      _ " that cannot be modified by input fields."
    end

    def mention_source
      p {
        _ "Please have a look at the source. "
        l = 0
        File.open __FILE__ do |f| f.each_line { l += 1 } end
        _ "It's just #{l} lines of Ruby code!"
      }
    end

    def show_environment
      h3 "Called"
      pre {
        _ "wd = #{Dir.getwd}#$/"
        _ "$0 = #$0#$/"
        _ "$* = #{$*.inspect}#$/"
      }
      h2 "Environment"
      pre {
        ENV.sort.each { |k,v| _ "#{k} = #{v}#$/" }
      }
    end

  end

  class IndexCgi < Hermeneutics::Cgi

    attr_reader :mailto

    def run
      if parameters[ :foo] =~ /\As*raise\s+/ then
        raise $'
      end
      if parameters[ :foo] =~ /\As*google\s+/ then
        location "http://www.google.de/search", q: $'
      end
      do_mail
      document IndexHtml
    end

    private

    def do_mail
      parameters[ :mail] or return
      @mailto = parameters[ :foo]
      require "hermeneutics/transports"
      require "socket"
      m = Hermeneutics::Mail.create
      m.headers.add :from, "webmaster@#{Socket.gethostname}"
      m.headers.add :to, @mailto
      m.headers.add :subject, "The Lizard-Spock Expansion"
      m.headers.add :date
      m.headers.add :content_type, "text/plain", charset: "utf-8"
      m.body = <<~EOT
        Scissors cuts Paper, Paper covers Rock. Rock crushes Lizard,
        Lizard poisons Spock. Spock smashes Scissors, Scissors decapitates
        Lizard. Lizard eats Paper, Paper disproves Spock, Spock vaporizes
        Rock, and as it always has, Rock crushes Scissors.
      EOT
      m.send!
    end

  end

end

Hermeneutics::Cgi.execute

