# frozen_string_literal: true

if defined?(Sketchup) && Sketchup.respond_to?(:require)
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_execution/execution_values'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_execution/diagnostic_logger'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_execution/entity_registry'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_execution/transform_adapter'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_execution/geometry_adapter'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_execution/executor'
else
  require_relative 'execution_values'
  require_relative 'diagnostic_logger'
  require_relative 'entity_registry'
  require_relative 'transform_adapter'
  require_relative 'geometry_adapter'
  require_relative 'executor'
end
