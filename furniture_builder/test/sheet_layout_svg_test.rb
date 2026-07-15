# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../sheet_layout_svg'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class SheetLayoutSVGTest < Minitest::Test
        def test_renders_stock_trim_and_exact_part_coordinates
          svg = SheetLayoutSVG.render(sheet([part]), settings, identifier: 'layout-1')

          assert_includes svg, '<svg id="layout-1"'
          assert_includes svg, 'viewBox="0 0 1000 500"'
          assert_includes svg, 'class="stock-sheet" x="0" y="0" width="1000" height="500"'
          assert_includes svg, 'class="usable-area" x="10" y="10" width="980" height="480"'
          assert_includes svg, 'class="part-rectangle" x="20" y="30" width="400" height="200"'
          assert_includes svg, 'data-part-id="1-1"'
          assert_includes svg, 'data-rotated="false"'
        end

        def test_escapes_model_text_in_labels_and_tooltips
          unsafe = part(
            name: 'Hông <trái> & "A"',
            cabinet_names: ['Tủ <B> & C']
          )

          svg = SheetLayoutSVG.render(sheet([unsafe]), settings)

          assert_includes svg, 'Hông &lt;trái&gt; &amp; &quot;A&quot;'
          assert_includes svg, 'Tủ &lt;B&gt; &amp; C'
          refute_includes svg, 'Hông <trái>'
          refute_includes svg, 'Tủ <B>'
        end

        def test_grain_arrow_follows_original_axis_after_rotation
          placements = [
            part(id: 'length-normal', grain_axis: 'length', rotated: false),
            part(id: 'length-rotated', x: 450, grain_axis: 'length', rotated: true,
                 placed_length_mm: 200, placed_width_mm: 400),
            part(id: 'width-normal', y: 250, grain_axis: 'width', rotated: false),
            part(id: 'width-rotated', x: 450, y: 250, grain_axis: 'width', rotated: true,
                 placed_length_mm: 200, placed_width_mm: 400)
          ]

          svg = SheetLayoutSVG.render(sheet(placements), settings)

          assert_match(/data-part-id="length-normal"[^>]*data-grain-axis-on-sheet="horizontal"/, svg)
          assert_match(/data-part-id="length-rotated"[^>]*data-grain-axis-on-sheet="vertical"/, svg)
          assert_match(/data-part-id="width-normal"[^>]*data-grain-axis-on-sheet="vertical"/, svg)
          assert_match(/data-part-id="width-rotated"[^>]*data-grain-axis-on-sheet="horizontal"/, svg)
          assert_equal 4, svg.scan('class="grain-arrow"').length
          assert_equal 2, svg.scan('class="rotation-badge"').length
        end

        def test_omits_grain_arrow_and_large_label_for_tiny_ungrained_part
          tiny = part(
            grain_direction: '', placed_length_mm: 50, placed_width_mm: 40,
            length_mm: 50, width_mm: 40
          )

          svg = SheetLayoutSVG.render(sheet([tiny]), settings)

          assert_includes svg, 'data-grain-axis-on-sheet="none"'
          refute_includes svg, 'class="grain-arrow"'
          refute_includes svg, 'class="part-label"'
          assert_includes svg, '<title>'
        end

        def test_rejects_invalid_sheet_dimensions_in_vietnamese
          error = assert_raises(ArgumentError) do
            SheetLayoutSVG.render(sheet([part]), settings.merge(sheet_length_mm: 0))
          end

          assert_match(/chiều dài tấm/i, error.message)
          assert_match(/lớn hơn 0/i, error.message)
        end

        private

        def settings
          { sheet_length_mm: 1000, sheet_width_mm: 500, edge_trim_mm: 10 }
        end

        def sheet(placements)
          { index: 1, placements: placements }
        end

        def part(overrides = {})
          {
            id: '1-1', name: 'Hông trái', source_row_index: 0,
            x: 20, y: 30, placed_length_mm: 400, placed_width_mm: 200,
            length_mm: 400, width_mm: 200, rotated: false,
            grain_direction: 'dọc', grain_axis: 'length', cabinet_names: ['Tủ A']
          }.merge(overrides)
        end
      end
    end
  end
end
