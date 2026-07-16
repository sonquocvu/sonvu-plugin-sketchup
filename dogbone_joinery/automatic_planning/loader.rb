# frozen_string_literal: true

# Dependency entry point for the read-only automatic joint planning layer.

if defined?(Sketchup) && Sketchup.respond_to?(:require)
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/vertical_tbone_geometry'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/geometry_values'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/joint_layout'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/joint_dimensions'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/preview_plan'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/contact_analysis'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/bulk_preview'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/sketchup_adapter'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/preview_settings'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/preview_display'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/preview_state'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/preview_primitives'
  Sketchup.require 'sonvu_cnc_plugins/dogbone_joinery/automatic_planning/preview_session'
else
  require_relative '../vertical_tbone_geometry'
  require_relative 'geometry_values'
  require_relative 'joint_layout'
  require_relative 'joint_dimensions'
  require_relative 'preview_plan'
  require_relative 'contact_analysis'
  require_relative 'bulk_preview'
  require_relative 'sketchup_adapter'
  require_relative 'preview_settings'
  require_relative 'preview_display'
  require_relative 'preview_state'
  require_relative 'preview_primitives'
  require_relative 'preview_session'
end
