# frozen_string_literal: true

require 'minitest/autorun'

module UI
  class Command
    attr_reader :name
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon

    def initialize(name, &_block)
      @name = name
    end
  end

  class Toolbar
    class << self
      attr_reader :last_created
    end

    attr_reader :name, :items

    def initialize(name)
      @name = name
      @items = []
      self.class.instance_variable_set(:@last_created, self)
    end

    def add_item(command)
      @items << command
    end

    def add_separator
      @items << :separator
    end

    def restore; end

    def show; end
  end
end

require_relative '../../constants'
require_relative '../commands'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class CommandsToolbarTest < Minitest::Test
        def test_toolbar_exposes_every_primary_furniture_workflow_with_icons
          Commands.register_toolbar
          toolbar = UI::Toolbar.last_created
          commands = toolbar.items.reject { |item| item == :separator }

          assert_equal CNCPlugins::TOOLBAR_FURNITURE_BUILDER, toolbar.name
          assert_equal 3, toolbar.items.count(:separator)
          assert_equal [
            CNCPlugins::COMMAND_FURNITURE_DASHBOARD,
            CNCPlugins::COMMAND_CREATE_FURNITURE,
            CNCPlugins::COMMAND_EDIT_FURNITURE,
            CNCPlugins::COMMAND_SHOW_FURNITURE_CUT_LIST,
            CNCPlugins::COMMAND_SHOW_FURNITURE_COST_ESTIMATE,
            CNCPlugins::COMMAND_OPTIMIZE_FURNITURE_SHEETS,
            CNCPlugins::COMMAND_PREVIEW_FURNITURE_MACHINING
          ], commands.map(&:name)

          commands.each do |command|
            refute_empty command.tooltip.to_s
            assert File.file?(command.small_icon), "Missing small icon for #{command.name}"
            assert File.file?(command.large_icon), "Missing large icon for #{command.name}"
          end
        end
      end
    end
  end
end
