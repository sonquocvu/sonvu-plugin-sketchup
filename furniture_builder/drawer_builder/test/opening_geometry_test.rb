# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../opening_geometry'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DrawerBuilder
        class OpeningGeometryTest < Minitest::Test
          PointStub = Struct.new(:y)
          BoundsStub = Struct.new(:min, :max) do
            def self.with_y_extent(value)
              new(PointStub.new(0.0), PointStub.new(value))
            end
          end
          DefinitionStub = Struct.new(:bounds)
          AxisStub = Struct.new(:length)
          TransformationStub = Struct.new(:yaxis)

          class EntityStub
            attr_reader :definition, :transformation, :bounds

            def initialize(local_depth: nil, y_scale: 1.0, world_depth: nil)
              @definition = DefinitionStub.new(BoundsStub.with_y_extent(local_depth)) unless local_depth.nil?
              @transformation = TransformationStub.new(AxisStub.new(y_scale))
              @bounds = BoundsStub.with_y_extent(world_depth) unless world_depth.nil?
            end
          end

          def test_uses_local_y_depth_and_instance_scale
            entity = EntityStub.new(local_depth: 500.0, y_scale: 1.25, world_depth: 900.0)

            assert_in_delta 625.0, OpeningGeometry.depth(entity), 0.001
          end

          def test_falls_back_to_entity_bounds_when_local_bounds_are_unavailable
            entity = EntityStub.new(world_depth: 480.0)

            assert_in_delta 480.0, OpeningGeometry.depth(entity), 0.001
          end

          def test_rejects_empty_or_nonpositive_openings
            assert_nil OpeningGeometry.depth(nil)
            assert_nil OpeningGeometry.depth(EntityStub.new(local_depth: 0.0))
            assert_nil OpeningGeometry.depth(EntityStub.new(local_depth: -10.0))
          end
        end
      end
    end
  end
end
