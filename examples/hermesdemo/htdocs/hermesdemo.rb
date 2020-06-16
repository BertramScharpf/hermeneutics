#!/usr/bin/env ruby
# encoding: UTF-8

#
#  htdocs/hermesdemo.rb  --  Build the CSS
#

require "hermes/css"
require "hermes/color"


module HermesDemo

  class MainCss < Hermeneutics::Css

    BG_BLUE = "dfdfff".to_rgb

    def build
      body :background_color => BG_BLUE
    end

  end

end

Hermeneutics::Css.document

