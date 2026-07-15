# frozen_string_literal: true

# Deterministic Phase 4A rectangular sheet nesting. The engine is read-only,
# groups boards by material/thickness, and uses a MaxRects-style free-rectangle
# strategy without depending on SketchUp.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module SheetOptimizer
        DEFAULT_SETTINGS = {
          sheet_length_mm: 2440.0,
          sheet_width_mm: 1220.0,
          edge_trim_mm: 10.0,
          kerf_mm: 3.2,
          part_spacing_mm: 3.2,
          allow_rotation: true,
          respect_grain: true
        }.freeze
        MAX_PARTS = 10_000
        MAX_SHEETS = 1000
        EPSILON = 0.0001

        module_function

        def normalize_settings(values)
          values ||= {}
          DEFAULT_SETTINGS.merge(
            sheet_length_mm: decimal(value_for(values, :sheet_length_mm), DEFAULT_SETTINGS[:sheet_length_mm]),
            sheet_width_mm: decimal(value_for(values, :sheet_width_mm), DEFAULT_SETTINGS[:sheet_width_mm]),
            edge_trim_mm: decimal(value_for(values, :edge_trim_mm), DEFAULT_SETTINGS[:edge_trim_mm]),
            kerf_mm: decimal(value_for(values, :kerf_mm), DEFAULT_SETTINGS[:kerf_mm]),
            part_spacing_mm: decimal(value_for(values, :part_spacing_mm), DEFAULT_SETTINGS[:part_spacing_mm]),
            allow_rotation: boolean(value_for(values, :allow_rotation), DEFAULT_SETTINGS[:allow_rotation]),
            respect_grain: boolean(value_for(values, :respect_grain), DEFAULT_SETTINGS[:respect_grain])
          )
        end

        def validate(report, settings)
          numeric = %i[sheet_length_mm sheet_width_mm edge_trim_mm kerf_mm part_spacing_mm]
          return 'Vui lòng nhập số hợp lệ cho thông số tối ưu ván.' if numeric.any? { |key| settings[key].nil? || !settings[key].finite? }
          unless settings[:sheet_length_mm].positive? && settings[:sheet_width_mm].positive?
            return 'Kích thước tấm ván phải lớn hơn 0.'
          end
          if settings[:edge_trim_mm].negative? || settings[:kerf_mm].negative? || settings[:part_spacing_mm].negative?
            return 'Lề xén, đường cưa và khoảng cách chi tiết không được âm.'
          end
          if settings[:sheet_length_mm] <= (2 * settings[:edge_trim_mm]) ||
             settings[:sheet_width_mm] <= (2 * settings[:edge_trim_mm])
            return 'Lề xén quá lớn so với kích thước tấm ván.'
          end
          part_count = Array(report[:board_rows]).sum { |row| row[:quantity].to_i }
          return "Số chi tiết không được vượt quá #{MAX_PARTS}." if part_count > MAX_PARTS

          nil
        end

        def optimize(report, values = {})
          settings = normalize_settings(values)
          error = validate(report, settings)
          raise ArgumentError, error if error

          items = expand_items(report)
          groups = items.group_by { |item| [item[:material_name], item[:thickness_mm]] }.map do |key, matches|
            pack_group(key, matches, settings)
          end.sort_by { |group| [group[:material_name], group[:thickness_mm]] }
          sheets = groups.sum { |group| group[:sheets].length }
          placed = groups.sum { |group| group[:placed_count] }
          unplaced = groups.sum { |group| group[:unplaced].length }
          used_area = groups.sum { |group| group[:used_area_mm2] }
          stock_area = groups.sum { |group| group[:stock_area_mm2] }
          {
            settings: settings,
            groups: groups,
            part_count: items.length,
            placed_count: placed,
            unplaced_count: unplaced,
            sheet_count: sheets,
            used_area_m2: used_area / 1_000_000.0,
            stock_area_m2: stock_area / 1_000_000.0,
            waste_area_m2: (stock_area - used_area) / 1_000_000.0,
            utilization_percent: stock_area.positive? ? (used_area / stock_area * 100.0) : 0.0
          }
        end

        def expand_items(report)
          Array(report[:board_rows]).each_with_index.flat_map do |row, row_index|
            row[:quantity].to_i.times.map do |item_index|
              {
                id: "#{row_index + 1}-#{item_index + 1}",
                name: row[:name].to_s,
                category: row[:category].to_s,
                material_name: row[:material_name].to_s,
                thickness_mm: row[:thickness_mm].to_f,
                length_mm: row[:length_mm].to_f,
                width_mm: row[:width_mm].to_f,
                grain_direction: row[:grain_direction].to_s,
                grain_axis: row[:grain_axis].to_s == 'width' ? 'width' : 'length',
                cabinet_names: Array(row[:cabinet_names]),
                source_row_index: row_index
              }
            end
          end
        end

        def pack_group(key, items, settings)
          material_name, thickness = key
          sorted = items.sort_by do |item|
            [-item[:length_mm] * item[:width_mm], -[item[:length_mm], item[:width_mm]].max, item[:name], item[:id]]
          end
          sheets = []
          unplaced = []
          sorted.each do |item|
            candidate = best_existing_candidate(sheets, item, settings)
            unless candidate
              if sheets.length >= MAX_SHEETS
                unplaced << item.merge(reason: 'Vượt quá giới hạn số tấm ván.')
                next
              end
              sheet = new_sheet(sheets.length + 1, settings)
              candidate = best_candidate_on_sheet(sheet, item, settings)
              unless candidate
                unplaced << item.merge(reason: unplaced_reason(item, settings))
                next
              end
              sheets << sheet
            end
            place(candidate[:sheet], item, candidate, settings)
          end
          finalize_group(material_name, thickness, items.length, sheets, unplaced, settings)
        end

        def new_sheet(index, settings)
          gap = effective_gap(settings)
          usable_length = settings[:sheet_length_mm] - (2 * settings[:edge_trim_mm])
          usable_width = settings[:sheet_width_mm] - (2 * settings[:edge_trim_mm])
          {
            index: index,
            placements: [],
            free_rectangles: [{
              x: settings[:edge_trim_mm],
              y: settings[:edge_trim_mm],
              width: usable_length + gap,
              height: usable_width + gap
            }]
          }
        end

        def best_existing_candidate(sheets, item, settings)
          sheets.filter_map { |sheet| best_candidate_on_sheet(sheet, item, settings) }
                .min_by { |candidate| candidate[:score] }
        end

        def best_candidate_on_sheet(sheet, item, settings)
          gap = effective_gap(settings)
          candidates = sheet[:free_rectangles].flat_map do |rectangle|
            orientations(item, settings).filter_map do |orientation|
              footprint_width = orientation[:width] + gap
              footprint_height = orientation[:height] + gap
              next unless fits?(footprint_width, footprint_height, rectangle)

              remaining_width = rectangle[:width] - footprint_width
              remaining_height = rectangle[:height] - footprint_height
              {
                sheet: sheet,
                rectangle: rectangle,
                x: rectangle[:x],
                y: rectangle[:y],
                width: orientation[:width],
                height: orientation[:height],
                footprint_width: footprint_width,
                footprint_height: footprint_height,
                rotated: orientation[:rotated],
                score: [
                  [remaining_width, remaining_height].min,
                  [remaining_width, remaining_height].max,
                  rectangle[:y], rectangle[:x],
                  orientation[:rotated] ? 1 : 0,
                  sheet[:index]
                ]
              }
            end
          end
          candidates.min_by { |candidate| candidate[:score] }
        end

        def orientations(item, settings)
          base = { width: item[:length_mm], height: item[:width_mm], rotated: false }
          rotated = { width: item[:width_mm], height: item[:length_mm], rotated: true }
          grained = !item[:grain_direction].empty? && item[:grain_direction] != 'không áp dụng'
          unless settings[:respect_grain] && grained
            return settings[:allow_rotation] && different_orientation?(base, rotated) ? [base, rotated] : [base]
          end
          return [base] if item[:grain_axis] == 'length'
          return [rotated] if settings[:allow_rotation]

          []
        end

        def place(sheet, item, candidate, _settings)
          placed_rectangle = {
            x: candidate[:x], y: candidate[:y],
            width: candidate[:footprint_width], height: candidate[:footprint_height]
          }
          sheet[:free_rectangles] = split_free_rectangles(
            sheet[:free_rectangles], placed_rectangle
          )
          sheet[:placements] << item.merge(
            x: candidate[:x],
            y: candidate[:y],
            placed_length_mm: candidate[:width],
            placed_width_mm: candidate[:height],
            rotated: candidate[:rotated]
          )
        end

        def split_free_rectangles(rectangles, placed)
          split = rectangles.flat_map do |free|
            if intersects?(free, placed)
              split_rectangle(free, placed)
            else
              [free]
            end
          end
          prune_contained(split.select { |rectangle| rectangle[:width] > EPSILON && rectangle[:height] > EPSILON })
        end

        def split_rectangle(free, placed)
          rectangles = []
          free_right = free[:x] + free[:width]
          free_bottom = free[:y] + free[:height]
          placed_right = placed[:x] + placed[:width]
          placed_bottom = placed[:y] + placed[:height]
          if placed[:x] > free[:x] + EPSILON
            rectangles << free.merge(width: placed[:x] - free[:x])
          end
          if placed_right < free_right - EPSILON
            rectangles << free.merge(x: placed_right, width: free_right - placed_right)
          end
          if placed[:y] > free[:y] + EPSILON
            rectangles << free.merge(height: placed[:y] - free[:y])
          end
          if placed_bottom < free_bottom - EPSILON
            rectangles << free.merge(y: placed_bottom, height: free_bottom - placed_bottom)
          end
          rectangles
        end

        def prune_contained(rectangles)
          rectangles.each_with_index.reject do |rectangle, index|
            rectangles.each_with_index.any? do |other, other_index|
              index != other_index && contains?(other, rectangle)
            end
          end.map(&:first)
        end

        def finalize_group(material_name, thickness, part_count, sheets, unplaced, settings)
          sheet_area = settings[:sheet_length_mm] * settings[:sheet_width_mm]
          finalized_sheets = sheets.map do |sheet|
            used = sheet[:placements].sum { |item| item[:length_mm] * item[:width_mm] }
            sheet.merge(
              part_count: sheet[:placements].length,
              used_area_mm2: used,
              utilization_percent: used / sheet_area * 100.0,
              waste_area_m2: (sheet_area - used) / 1_000_000.0
            ).reject { |key, _value| key == :free_rectangles }
          end
          used_area = finalized_sheets.sum { |sheet| sheet[:used_area_mm2] }
          stock_area = finalized_sheets.length * sheet_area
          {
            material_name: material_name,
            thickness_mm: thickness,
            part_count: part_count,
            placed_count: part_count - unplaced.length,
            unplaced: unplaced,
            sheets: finalized_sheets,
            used_area_mm2: used_area,
            stock_area_mm2: stock_area,
            utilization_percent: stock_area.positive? ? used_area / stock_area * 100.0 : 0.0
          }
        end

        def unplaced_reason(item, settings)
          return 'Không có hướng xoay hợp lệ theo chiều vân.' if orientations(item, settings).empty?

          'Chi tiết lớn hơn vùng sử dụng của tấm ván.'
        end

        def effective_gap(settings)
          [settings[:kerf_mm], settings[:part_spacing_mm]].max
        end

        def fits?(width, height, rectangle)
          width <= rectangle[:width] + EPSILON && height <= rectangle[:height] + EPSILON
        end

        def intersects?(first, second)
          first[:x] < second[:x] + second[:width] - EPSILON &&
            first[:x] + first[:width] > second[:x] + EPSILON &&
            first[:y] < second[:y] + second[:height] - EPSILON &&
            first[:y] + first[:height] > second[:y] + EPSILON
        end

        def contains?(outer, inner)
          inner[:x] >= outer[:x] - EPSILON &&
            inner[:y] >= outer[:y] - EPSILON &&
            inner[:x] + inner[:width] <= outer[:x] + outer[:width] + EPSILON &&
            inner[:y] + inner[:height] <= outer[:y] + outer[:height] + EPSILON
        end

        def different_orientation?(first, second)
          (first[:width] - second[:width]).abs > EPSILON ||
            (first[:height] - second[:height]).abs > EPSILON
        end

        def value_for(values, key)
          return nil unless values.respond_to?(:[])
          return values[key] if values.respond_to?(:key?) && values.key?(key)
          return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

          nil
        end

        def decimal(value, fallback)
          return fallback if value.nil? || value.to_s.strip.empty?

          Float(value)
        rescue ArgumentError, TypeError
          nil
        end

        def boolean(value, fallback)
          return fallback if value.nil?
          return value if value == true || value == false

          %w[true yes 1 có].include?(value.to_s.strip.downcase)
        end
      end
    end
  end
end
