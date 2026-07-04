# frozen_string_literal: true

# Main entry point for the SonVu CNC Plugins extension. It loads shared helpers,
# feature modules, and registers SketchUp menus for enabled extension features.

require 'sketchup.rb'

require_relative 'version'
require_relative 'constants'
require_relative 'shared/units'
require_relative 'shared/ui_helpers'
require_relative 'shared/materials'
require_relative 'dogbone_joinery/commands'
require_relative 'dogbone_joinery/dialog_html'
require_relative 'dogbone_joinery/dialog'
require_relative 'dogbone_joinery/geometry'
require_relative 'dogbone_joinery/tool'

module SonVu
  module CNCPlugins
    def self.load_extension
      DogboneJoinery::Commands.register_menu
    end
  end
end

SonVu::CNCPlugins.load_extension
