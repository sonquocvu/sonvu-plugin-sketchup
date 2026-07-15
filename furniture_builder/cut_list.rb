# frozen_string_literal: true

# Read-only Phase 3A collection and aggregation for SonVu furniture. This file
# intentionally uses duck typing so its production-data rules can be tested
# without loading SketchUp.

require_relative '../constants'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CutList
        KIND_LABELS = {
          'carcass' => 'Thùng tủ',
          'front' => 'Mặt cánh',
          'drawer_box' => 'Hộp ngăn kéo',
          'hardware' => 'Phụ kiện'
        }.freeze
        HARDWARE_LABELS = {
          'handle' => 'Tay nắm',
          'hinge_cup' => 'Bản lề chén',
          'drawer_slide_left' => 'Ray ngăn kéo',
          'drawer_slide_right' => 'Ray ngăn kéo'
        }.freeze
        KIND_ORDER = %w[carcass front drawer_box hardware].freeze

        module_function

        def report_for_model(model)
          selected = find_cabinets(enumerable_entities(model.selection))
          cabinets = selected.empty? ? find_cabinets(enumerable_entities(model.entities)) : selected
          scope = selected.empty? ? 'Toàn bộ model' : 'Các tủ đang chọn'
          build_report(cabinets, scope: scope)
        end

        def find_cabinets(entities, ancestry = [])
          entities.flat_map do |entity|
            if cabinet?(entity)
              [entity]
            else
              nested = nested_entities(entity)
              identity = nested_identity(entity)
              next [] if nested.empty? || ancestry.include?(identity)

              find_cabinets(nested, ancestry + [identity])
            end
          end
        end

        def build_report(cabinets, scope: 'Tủ nội thất')
          warnings = []
          entries = cabinets.each_with_index.flat_map do |cabinet, index|
            collect_cabinet_entries(cabinet, index, warnings)
          end
          rows = aggregate(entries)
          {
            scope: scope,
            cabinet_count: cabinets.length,
            part_count: entries.length,
            board_count: entries.count { |entry| entry[:kind] != 'hardware' },
            hardware_count: entries.count { |entry| entry[:kind] == 'hardware' },
            board_rows: rows.reject { |row| row[:kind] == 'hardware' },
            hardware_rows: rows.select { |row| row[:kind] == 'hardware' },
            warnings: warnings
          }
        end

        def collect_cabinet_entries(cabinet, cabinet_index, warnings)
          cabinet_name = cabinet_attribute(cabinet, 'furniture_name_vi').to_s.strip
          cabinet_name = cabinet.name.to_s.strip if cabinet_name.empty? && cabinet.respond_to?(:name)
          cabinet_name = "Tủ #{cabinet_index + 1}" if cabinet_name.empty?
          cabinet_id = cabinet_attribute(cabinet, Geometry::CABINET_ID_ATTRIBUTE).to_s
          cabinet_id = "tu-#{cabinet_index + 1}" if cabinet_id.empty?

          enumerable_entities(cabinet.entities).filter_map do |panel|
            next unless panel_attribute(panel, Geometry::PANEL_ATTRIBUTE, false) == true

            occurrence_key = "#{cabinet_id}##{cabinet_index + 1}"
            entry = entry_from_panel(panel, cabinet_name, cabinet_id, occurrence_key)
            if valid_dimensions?(entry)
              entry
            else
              name = entry[:name].to_s.empty? ? 'chi tiết không tên' : entry[:name]
              warnings << "Bỏ qua #{name} trong #{cabinet_name} vì thiếu kích thước thành phẩm."
              nil
            end
          end
        end

        def entry_from_panel(panel, cabinet_name, cabinet_id, occurrence_key)
          kind = panel_attribute(panel, 'part_kind', 'carcass').to_s
          hardware_type = panel_attribute(panel, 'hardware_type', '').to_s
          {
            cabinet_name: cabinet_name,
            cabinet_id: cabinet_id,
            cabinet_occurrence_key: occurrence_key,
            part_key: panel_attribute(panel, 'part_key', '').to_s,
            name: panel_attribute(panel, 'part_name_vi', panel_name(panel)).to_s,
            role: panel_attribute(panel, 'part_role', '').to_s,
            kind: KIND_LABELS.key?(kind) ? kind : 'carcass',
            hardware_type: canonical_hardware_type(hardware_type),
            owner_part_key: panel_attribute(panel, 'owner_part_key', '').to_s,
            drawer_index: optional_integer(panel_attribute(panel, 'drawer_index')),
            length_mm: numeric(panel_attribute(panel, 'finished_length_mm')),
            width_mm: numeric(panel_attribute(panel, 'finished_width_mm')),
            thickness_mm: numeric(panel_attribute(panel, 'thickness_mm')),
            material_name: panel_attribute(panel, 'material_name', '').to_s,
            grain_direction: panel_attribute(panel, 'grain_direction', '').to_s,
            grain_axis: normalized_grain_axis(panel_attribute(panel, 'grain_axis', 'length')),
            geometry_shape: panel_attribute(panel, 'geometry_shape', 'box').to_s,
            edge_front: boolean(panel_attribute(panel, 'edge_band_front', false)),
            edge_back: boolean(panel_attribute(panel, 'edge_band_back', false)),
            edge_left: boolean(panel_attribute(panel, 'edge_band_left', false)),
            edge_right: boolean(panel_attribute(panel, 'edge_band_right', false))
          }
        end

        def aggregate(entries)
          entries.group_by { |entry| aggregation_key(entry) }.map do |_key, matches|
            first = matches.first
            {
              kind: first[:kind],
              category: KIND_LABELS.fetch(first[:kind]),
              name: aggregate_name(matches),
              quantity: matches.length,
              length_mm: first[:length_mm],
              width_mm: first[:width_mm],
              thickness_mm: first[:thickness_mm],
              material_name: first[:material_name],
              grain_direction: first[:grain_direction],
              grain_axis: first[:grain_axis],
              edge_front: first[:edge_front],
              edge_back: first[:edge_back],
              edge_left: first[:edge_left],
              edge_right: first[:edge_right],
              cabinet_names: matches.map { |entry| entry[:cabinet_name] }.uniq.sort,
              cabinet_ids: matches.map { |entry| entry[:cabinet_id] }.uniq.sort,
              cabinet_breakdown: cabinet_breakdown(matches),
              drawer_indices: matches.filter_map { |entry| entry[:drawer_index] }.uniq.sort,
              owner_part_keys: matches.map { |entry| entry[:owner_part_key] }.reject(&:empty?).uniq.sort,
              hardware_type: first[:hardware_type]
            }
          end.sort_by { |row| row_sort_key(row) }
        end

        def aggregation_key(entry)
          common = [
            entry[:kind],
            rounded(entry[:length_mm]),
            rounded(entry[:width_mm]),
            rounded(entry[:thickness_mm]),
            entry[:material_name]
          ]
          if entry[:kind] == 'hardware'
            common + [entry[:hardware_type], entry[:geometry_shape]]
          else
            common + [
              entry[:grain_direction], entry[:grain_axis], entry[:edge_front], entry[:edge_back],
              entry[:edge_left], entry[:edge_right]
            ]
          end
        end

        def aggregate_name(entries)
          first = entries.first
          return HARDWARE_LABELS.fetch(first[:hardware_type], 'Phụ kiện') if first[:kind] == 'hardware'

          entries.map { |entry| entry[:name] }.reject(&:empty?).uniq.sort.join(' / ')
        end

        def cabinet_breakdown(entries)
          entries.group_by { |entry| entry[:cabinet_occurrence_key] }.map do |occurrence_key, matches|
            first = matches.first
            {
              occurrence_key: occurrence_key,
              cabinet_id: first[:cabinet_id],
              cabinet_name: first[:cabinet_name],
              quantity: matches.length
            }
          end.sort_by { |item| [item[:cabinet_name], item[:occurrence_key]] }
        end

        def row_sort_key(row)
          [
            KIND_ORDER.index(row[:kind]) || KIND_ORDER.length,
            row[:material_name],
            -row[:thickness_mm],
            -row[:length_mm],
            -row[:width_mm],
            row[:name]
          ]
        end

        def cabinet?(entity)
          cabinet_attribute(entity, Geometry::CABINET_ATTRIBUTE, false) == true
        end

        def cabinet_attribute(entity, key, default = nil)
          return default unless entity.respond_to?(:get_attribute)

          value = entity.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, key, nil)
          value.nil? ? default : value
        end

        def panel_attribute(entity, key, default = nil)
          value = cabinet_attribute(entity, key, nil)
          if value.nil? && entity.respond_to?(:definition)
            value = cabinet_attribute(entity.definition, key, nil)
          end
          value.nil? ? default : value
        end

        def nested_entities(entity)
          if entity.respond_to?(:entities)
            enumerable_entities(entity.entities)
          elsif entity.respond_to?(:definition) && entity.definition.respond_to?(:entities)
            enumerable_entities(entity.definition.entities)
          else
            []
          end
        end

        def nested_identity(entity)
          entity.respond_to?(:definition) ? entity.definition.object_id : entity.object_id
        end

        def enumerable_entities(value)
          return [] if value.nil?
          return value.to_a if value.respond_to?(:to_a)

          Array(value)
        end

        def panel_name(panel)
          panel.respond_to?(:name) ? panel.name.to_s : ''
        end

        def valid_dimensions?(entry)
          entry[:length_mm].positive? && entry[:width_mm].positive? && entry[:thickness_mm].positive?
        end

        def canonical_hardware_type(value)
          return 'drawer_slide_left' if value == 'drawer_slide_left'
          return 'drawer_slide_left' if value == 'drawer_slide_right'

          value
        end

        def normalized_grain_axis(value)
          value.to_s == 'width' ? 'width' : 'length'
        end

        def numeric(value)
          Float(value)
        rescue ArgumentError, TypeError
          0.0
        end

        def rounded(value)
          value.to_f.round(3)
        end

        def optional_integer(value)
          return nil if value.nil? || value.to_s.empty?

          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end

        def boolean(value)
          value == true || value.to_s.downcase == 'true' || value.to_s == '1'
        end
      end
    end
  end
end
