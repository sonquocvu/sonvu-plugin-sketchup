# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../sheet_optimizer'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class SheetOptimizerTest < Minitest::Test
        def test_packs_four_equal_parts_on_one_sheet_without_overlap
          result = SheetOptimizer.optimize(
            report(board_row(quantity: 4, length_mm: 500, width_mm: 250)),
            settings(sheet_length_mm: 1000, sheet_width_mm: 500)
          )

          assert_equal 1, result[:sheet_count]
          assert_equal 4, result[:placed_count]
          assert_equal 0, result[:unplaced_count]
          assert_in_delta 100.0, result[:utilization_percent], 0.001
          assert_valid_placements(result, 1000, 500, 0)
        end

        def test_groups_parts_by_material_and_thickness
          rows = [
            board_row(material_name: 'MDF trắng', thickness_mm: 18),
            board_row(material_name: 'MDF trắng', thickness_mm: 17),
            board_row(material_name: 'Plywood', thickness_mm: 18)
          ]

          result = SheetOptimizer.optimize(report(*rows), settings)

          assert_equal 3, result[:groups].length
          assert_equal [['MDF trắng', 17.0], ['MDF trắng', 18.0], ['Plywood', 18.0]],
                       result[:groups].map { |group| [group[:material_name], group[:thickness_mm]] }
        end

        def test_opens_another_sheet_and_reports_oversized_parts
          rows = [
            board_row(name: 'Vừa tấm', quantity: 2, length_mm: 900, width_mm: 450),
            board_row(name: 'Quá khổ', length_mm: 1200, width_mm: 600)
          ]

          result = SheetOptimizer.optimize(report(*rows), settings(sheet_length_mm: 1000, sheet_width_mm: 500))

          assert_equal 2, result[:sheet_count]
          assert_equal 2, result[:placed_count]
          assert_equal 1, result[:unplaced_count]
          assert_match(/lớn hơn vùng sử dụng/i, result[:groups].first[:unplaced].first[:reason])
        end

        def test_respects_explicit_grain_axis
          rows = [
            board_row(name: 'Theo chiều dài', length_mm: 800, width_mm: 400,
                      grain_direction: 'dọc', grain_axis: 'length'),
            board_row(name: 'Theo chiều rộng', length_mm: 800, width_mm: 400,
                      grain_direction: 'ngang', grain_axis: 'width')
          ]

          result = SheetOptimizer.optimize(report(*rows), settings(sheet_length_mm: 1000, sheet_width_mm: 1000))
          placements = result[:groups].first[:sheets].flat_map { |sheet| sheet[:placements] }

          refute placements.find { |item| item[:name] == 'Theo chiều dài' }[:rotated]
          assert placements.find { |item| item[:name] == 'Theo chiều rộng' }[:rotated]
        end

        def test_reports_grained_width_axis_as_unplaced_when_rotation_is_disabled
          row = board_row(
            grain_direction: 'ngang', grain_axis: 'width', length_mm: 800, width_mm: 400
          )

          result = SheetOptimizer.optimize(
            report(row),
            settings(sheet_length_mm: 1000, sheet_width_mm: 1000, allow_rotation: false)
          )

          assert_equal 0, result[:placed_count]
          assert_equal 1, result[:unplaced_count]
          assert_match(/hướng xoay hợp lệ/i, result[:groups].first[:unplaced].first[:reason])
        end

        def test_can_ignore_grain_and_rotate_to_fit
          row = board_row(
            grain_direction: 'dọc', grain_axis: 'length', length_mm: 700, width_mm: 900
          )

          result = SheetOptimizer.optimize(
            report(row),
            settings(sheet_length_mm: 1000, sheet_width_mm: 800, respect_grain: false)
          )
          placement = result[:groups].first[:sheets].first[:placements].first

          assert placement[:rotated]
          assert_equal 900.0, placement[:placed_length_mm]
          assert_equal 700.0, placement[:placed_width_mm]
        end

        def test_uses_larger_of_kerf_and_part_spacing
          result = SheetOptimizer.optimize(
            report(board_row(quantity: 2, length_mm: 400, width_mm: 400)),
            settings(sheet_length_mm: 1000, sheet_width_mm: 500, kerf_mm: 3.2, part_spacing_mm: 8)
          )
          placements = result[:groups].first[:sheets].first[:placements]

          assert_equal 2, placements.length
          assert pair_separated_by?(placements[0], placements[1], 8.0)
          assert_valid_placements(result, 1000, 500, 0, 8)
        end

        def test_trim_keeps_every_part_inside_the_usable_sheet_area
          result = SheetOptimizer.optimize(
            report(board_row(quantity: 2, length_mm: 450, width_mm: 450)),
            settings(sheet_length_mm: 1000, sheet_width_mm: 500, edge_trim_mm: 20)
          )

          assert_valid_placements(result, 1000, 500, 20)
        end

        def test_returns_identical_layout_for_identical_input
          rows = [
            board_row(name: 'A', quantity: 3, length_mm: 450, width_mm: 300),
            board_row(name: 'B', quantity: 2, length_mm: 300, width_mm: 200)
          ]
          options = settings(sheet_length_mm: 1000, sheet_width_mm: 600, part_spacing_mm: 5)

          first = SheetOptimizer.optimize(report(*rows), options)
          second = SheetOptimizer.optimize(report(*rows), options)

          assert_equal first, second
        end

        def test_validates_settings_and_maximum_part_count_in_vietnamese
          invalid_sheet = settings(sheet_length_mm: 0)
          negative_trim = settings(edge_trim_mm: -1)
          too_many = report(board_row(quantity: SheetOptimizer::MAX_PARTS + 1))

          assert_match(/lớn hơn 0/i, assert_raises(ArgumentError) {
            SheetOptimizer.optimize(report(board_row), invalid_sheet)
          }.message)
          assert_match(/không được âm/i, assert_raises(ArgumentError) {
            SheetOptimizer.optimize(report(board_row), negative_trim)
          }.message)
          assert_match(/không được vượt quá/i, assert_raises(ArgumentError) {
            SheetOptimizer.optimize(too_many, settings)
          }.message)
        end

        private

        def report(*rows)
          { board_rows: rows.flatten }
        end

        def board_row(overrides = {})
          {
            category: 'Thùng tủ', name: 'Chi tiết', quantity: 1,
            length_mm: 500, width_mm: 250, thickness_mm: 18,
            material_name: 'MDF trắng', grain_direction: '', grain_axis: 'length',
            cabinet_names: ['Tủ A']
          }.merge(overrides)
        end

        def settings(overrides = {})
          {
            sheet_length_mm: 2440, sheet_width_mm: 1220, edge_trim_mm: 0,
            kerf_mm: 0, part_spacing_mm: 0, allow_rotation: true, respect_grain: true
          }.merge(overrides)
        end

        def assert_valid_placements(result, sheet_length, sheet_width, trim, gap = 0)
          result[:groups].each do |group|
            group[:sheets].each do |sheet|
              placements = sheet[:placements]
              placements.each do |item|
                assert_operator item[:x], :>=, trim
                assert_operator item[:y], :>=, trim
                assert_operator item[:x] + item[:placed_length_mm], :<=, sheet_length - trim + 0.0001
                assert_operator item[:y] + item[:placed_width_mm], :<=, sheet_width - trim + 0.0001
              end
              placements.combination(2) do |first, second|
                assert pair_separated_by?(first, second, gap), "overlap: #{first[:id]} / #{second[:id]}"
              end
            end
          end
        end

        def pair_separated_by?(first, second, gap)
          first[:x] + first[:placed_length_mm] + gap <= second[:x] + 0.0001 ||
            second[:x] + second[:placed_length_mm] + gap <= first[:x] + 0.0001 ||
            first[:y] + first[:placed_width_mm] + gap <= second[:y] + 0.0001 ||
            second[:y] + second[:placed_width_mm] + gap <= first[:y] + 0.0001
        end
      end
    end
  end
end
