#
#  hermeneutics.gemspec  --  Hermeneutics Gem specification
#

require "./lib/hermeneutics/version.rb"

Gem::Specification.new do |s|
  s.name              = Hermeneutics::NAME
  s.version           = Hermeneutics::VERSION
  s.summary           = Hermeneutics::SUMMARY
  s.description       = Hermeneutics::DESCRIPTION
  s.license           = Hermeneutics::LICENSE
  s.authors           = Hermeneutics::AUTHORS
  s.email             = Hermeneutics::MAIL
  s.homepage          = Hermeneutics::HOMEPAGE

  s.requirements      = "Ruby, at least 3.0"
  s.add_dependency      "supplement", "~>2"
  s.add_dependency      "appl",       "~>1"

  s.require_paths     = %w(lib)
  s.extensions        = %w()
  s.files             = %w(
                          README
                          etc/exim.conf
                          lib/hermeneutics/version.rb
                          lib/hermeneutics/escape.rb
                          lib/hermeneutics/html.rb
                          lib/hermeneutics/css.rb
                          lib/hermeneutics/types.rb
                          lib/hermeneutics/addrs.rb
                          lib/hermeneutics/contents.rb
                          lib/hermeneutics/message.rb
                          lib/hermeneutics/color.rb
                          lib/hermeneutics/tags.rb
                          lib/hermeneutics/cgi.rb
                          lib/hermeneutics/boxes.rb
                          lib/hermeneutics/mail.rb
                          lib/hermeneutics/cli/protocol.rb
                          lib/hermeneutics/cli/openssl.rb
                          lib/hermeneutics/cli/smtp.rb
                          lib/hermeneutics/cli/pop3.rb
                          lib/hermeneutics/cli/lmtp.rb
                          lib/hermeneutics/cli/imap/commands.rb
                          lib/hermeneutics/cli/imap/parser.rb
                          lib/hermeneutics/cli/imap/utf7imap.rb
                          lib/hermeneutics/cli/imap.rb
                        )
  s.executables       = %w(
                          hermesmail
                        )

  s.rdoc_options.concat %w(--charset utf-8 --main lib/hermeneutics/version.rb)
  s.extra_rdoc_files  = %w(
                          LICENSE
                        )
end

