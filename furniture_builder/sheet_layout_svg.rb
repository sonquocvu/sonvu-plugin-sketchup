# frozen_string_literal: true

require 'cgi'

# Pure Phase 4B SVG renderer for a single optimized stock sheet. Coordinates
# stay in millimetres and map directly to the Phase 4A placement result.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module SheetLayoutSVG
        PALETTE = %w[
          #b8dfca #f6d7a7 #bdd8ee #dfc4e8 #f2b9b5 #cbd7a3
          #d5c3a7 #a9dada #ecc5a0 #bec6ea #d8d0a8 #c6d9bf
        ].freeze
        MIN_LABEL_WIDTH_MM = 150.0
        MIN_LABEL_HEIGHT_MM = 70.0
        MIN_GRAIN_LENGTH_MM = 70.0

        module_function

        def render(sheet, settings, identifier: nil)
          sheet_length = positive_dimension(settings[:sheet_length_mm], 'chiều dài tấm')
          sheet_width = positive_dimension(settings[:sheet_width_mm], 'chiều rộng tấm')
          trim = [settings[:edge_trim_mm].to_f, 0.0].max
          svg_id = identifier.to_s.empty? ? "sheet-#{sheet[:index].to_i}" : identifier.to_s
          marker_id = "#{safe_id(svg_id)}-grain-arrow"
          placements = Array(sheet[:placements])

          <<~SVG
            <svg id="#{h(svg_id)}" class="sheet-map" viewBox="0 0 #{number(sheet_length)} #{number(sheet_width)}" role="img" aria-label="Sơ đồ cắt tấm #{sheet[:index].to_i}" data-sheet-index="#{sheet[:index].to_i}" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <marker id="#{h(marker_id)}" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,4 L0,8 z" fill="#315b46"/></marker>
              </defs>
              <rect class="stock-sheet" x="0" y="0" width="#{number(sheet_length)}" height="#{number(sheet_width)}" rx="6"/>
              #{usable_area_rect(sheet_length, sheet_width, trim)}
              #{placements.each_with_index.map { |item, index| part_group(item, index, svg_id, marker_id) }.join}
              #{axis_labels(sheet_length, sheet_width)}
            </svg>
          SVG
        end

        def part_group(item, index, svg_id, marker_id)
          x = item[:x].to_f
          y = item[:y].to_f
          width = item[:placed_length_mm].to_f
          height = item[:placed_width_mm].to_f
          clip_id = "#{safe_id(svg_id)}-clip-#{index + 1}"
          color = PALETTE[item[:source_row_index].to_i % PALETTE.length]
          grain_axis = placed_grain_axis(item)
          label = item[:name].to_s
          dimensions = "#{number(item[:length_mm])} × #{number(item[:width_mm])} mm"
          tooltip = [
            label,
            dimensions,
            "Vị trí X/Y: #{number(x)} / #{number(y)} mm",
            "Xoay 90°: #{item[:rotated] ? 'Có' : 'Không'}",
            Array(item[:cabinet_names]).join(' / ')
          ].reject(&:empty?).join(' · ')

          <<~SVG
            <g class="part-shape" data-part-id="#{h(item[:id])}" data-rotated="#{item[:rotated] ? 'true' : 'false'}" data-grain-axis-on-sheet="#{grain_axis || 'none'}">
              <title>#{h(tooltip)}</title>
              <clipPath id="#{h(clip_id)}"><rect x="#{number(x)}" y="#{number(y)}" width="#{number(width)}" height="#{number(height)}"/></clipPath>
              <rect class="part-rectangle" x="#{number(x)}" y="#{number(y)}" width="#{number(width)}" height="#{number(height)}" fill="#{color}"/>
              #{part_labels(label, dimensions, x, y, width, height, clip_id)}
              #{rotation_badge(item, x, y, width, height)}
              #{grain_arrow(item, grain_axis, x, y, width, height, marker_id)}
            </g>
          SVG
        end

        def usable_area_rect(sheet_length, sheet_width, trim)
          return '' unless trim.positive?

          width = [sheet_length - (2 * trim), 0].max
          height = [sheet_width - (2 * trim), 0].max
          "<rect class=\"usable-area\" x=\"#{number(trim)}\" y=\"#{number(trim)}\" width=\"#{number(width)}\" height=\"#{number(height)}\"/>"
        end

        def part_labels(label, dimensions, x, y, width, height, clip_id)
          return '' if width < MIN_LABEL_WIDTH_MM || height < MIN_LABEL_HEIGHT_MM

          font_size = [[height * 0.16, width * 0.055, 38.0].min, 18.0].max
          first_y = y + (height / 2.0) - (font_size * 0.15)
          second_y = first_y + (font_size * 1.05)
          <<~SVG
            <g class="part-label" clip-path="url(##{h(clip_id)})">
              <text x="#{number(x + (width / 2.0))}" y="#{number(first_y)}" font-size="#{number(font_size)}">#{h(short_label(label))}</text>
              <text class="part-dimensions" x="#{number(x + (width / 2.0))}" y="#{number(second_y)}" font-size="#{number(font_size * 0.72)}">#{h(dimensions)}</text>
            </g>
          SVG
        end

        def grain_arrow(item, axis, x, y, width, height, marker_id)
          return '' unless axis

          if axis == 'horizontal'
            return '' if width < MIN_GRAIN_LENGTH_MM

            margin = [width * 0.18, 45.0].min
            y_position = y + (height * 0.78)
            coordinates = [x + margin, y_position, x + width - margin, y_position]
          else
            return '' if height < MIN_GRAIN_LENGTH_MM

            margin = [height * 0.18, 45.0].min
            x_position = x + (width * 0.82)
            coordinates = [x_position, y + margin, x_position, y + height - margin]
          end
          "<line class=\"grain-arrow\" x1=\"#{number(coordinates[0])}\" y1=\"#{number(coordinates[1])}\" x2=\"#{number(coordinates[2])}\" y2=\"#{number(coordinates[3])}\" marker-end=\"url(##{h(marker_id)})\"/>"
        end

        def rotation_badge(item, x, y, width, height)
          return '' unless item[:rotated] && width >= 55.0 && height >= 55.0

          font_size = [[width, height].min * 0.16, 30.0].min
          "<text class=\"rotation-badge\" x=\"#{number(x + (font_size * 0.8))}\" y=\"#{number(y + (font_size * 1.15))}\" font-size=\"#{number(font_size)}\">↻</text>"
        end

        def placed_grain_axis(item)
          direction = item[:grain_direction].to_s.strip.downcase
          return nil if direction.empty? || direction == 'không áp dụng'

          original_axis = item[:grain_axis].to_s == 'width' ? 'width' : 'length'
          horizontal = original_axis == 'length'
          horizontal = !horizontal if item[:rotated]
          horizontal ? 'horizontal' : 'vertical'
        end

        def axis_labels(sheet_length, sheet_width)
          font_size = [[sheet_width * 0.035, 32.0].min, 14.0].max
          <<~SVG
            <g class="sheet-axes" font-size="#{number(font_size)}">
              <text x="#{number(sheet_length * 0.5)}" y="#{number(font_size * 1.25)}">X → #{number(sheet_length)} mm</text>
              <text x="#{number(font_size * 0.45)}" y="#{number(sheet_width * 0.5)}" transform="rotate(-90 #{number(font_size * 0.45)} #{number(sheet_width * 0.5)})">Y → #{number(sheet_width)} mm</text>
            </g>
          SVG
        end

        def short_label(value)
          text = value.to_s
          text.length > 34 ? "#{text[0, 31]}…" : text
        end

        def positive_dimension(value, label)
          number = Float(value)
          raise ArgumentError, "#{label.capitalize} phải lớn hơn 0." unless number.finite? && number.positive?

          number
        rescue ArgumentError, TypeError
          raise ArgumentError, "#{label.capitalize} phải là số hợp lệ lớn hơn 0."
        end

        def safe_id(value)
          value.to_s.gsub(/[^a-zA-Z0-9_-]/, '-')
        end

        def number(value)
          format('%.3f', value.to_f).sub(/0+\z/, '').sub(/\.\z/, '')
        end

        def h(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
