#
#  hermes.gemspec  --  Hermeneutics Gem specification
#

require "./lib/hermes/version.rb"

Gem::Specification.new do |s|
  s.name              = Hermeneutics::NAME
  s.version           = Hermeneutics::VERSION
  s.summary           = Hermeneutics::SUMMARY
  s.description       = Hermeneutics::DESCRIPTION
  s.license           = Hermeneutics::LICENSE
  s.authors           = Hermeneutics::AUTHORS
  s.email             = Hermeneutics::MAIL
  s.homepage          = Hermeneutics::HOMEPAGE

  s.requirements      = "Just Ruby"
  s.add_dependency      "supplement", "~>2"

  s.require_paths     = %w(lib)
  s.extensions        = %w()
  s.files             = %w(
                          etc/exim.conf
                          lib/hermes/version.rb
                          lib/hermes/escape.rb
                          lib/hermes/html.rb
                          lib/hermes/css.rb
                          lib/hermes/types.rb
                          lib/hermes/addrs.rb
                          lib/hermes/contents.rb
                          lib/hermes/message.rb
                          lib/hermes/color.rb
                          lib/hermes/tags.rb
                          lib/hermes/cgi.rb
                          lib/hermes/boxes.rb
                          lib/hermes/mail.rb
                          lib/hermes/transports.rb
                          lib/hermes/cli/pop.rb
                        )
  s.executables       = %w(
                          hermesmail
                        )

  s.has_rdoc          = true
  s.rdoc_options.concat %w(--charset utf-8 --main lib/hermes/version.rb)
  s.extra_rdoc_files  = %w(
                          LICENSE
                        )
end

