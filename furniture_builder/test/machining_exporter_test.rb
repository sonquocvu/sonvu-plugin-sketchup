# frozen_string_literal: true

require 'csv'
require 'minitest/autorun'
require 'tmpdir'

require_relative '../presets'
require_relative '../specification'
require_relative '../machining_planner'
require_relative '../machining_exporter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class MachiningExporterTest < Minitest::Test
        def test_package_builds_one_dxf_per_panel_face_with_deterministic_ascii_names
          payload = MachiningExporter.package(standard_project)

          assert_equal 6, payload[:faces].length
          assert_equal MachiningExporter::MANIFEST_FILENAME, payload[:manifest_filename]
          assert_equal payload[:faces].map { |face| face[:filename] }.uniq.length, payload[:faces].length
          payload[:faces].each_with_index do |face, index|
            assert_match(/\A#{format('%03d', index + 1)}_[a-z0-9_]+\.dxf\z/, face[:filename])
            assert face[:filename].ascii_only?
          end
        end

        def test_dxf_declares_millimetres_outline_and_operation_layers
          payload = MachiningExporter.package(standard_project)
          documents = payload[:faces].map { |face| face[:content] }.join

          assert_includes documents, "$INSUNITS\r\n70\r\n4"
          assert_includes documents, 'PANEL_OUTLINE'
          assert_includes documents, 'DRILL_HINGE_D35_Z12'
          assert_includes documents, 'DRILL_DOWEL_D8_Z8'
          assert_includes documents, 'POCKET_CAM_D15_Z12'
          assert_includes documents, 'DRILL_SHELF_D5_Z10'
          assert_includes documents, 'GROOVE_BACK_W10_Z6'
          assert_includes documents, "0\r\nCIRCLE\r\n"
          assert_includes documents, "0\r\nLWPOLYLINE\r\n"
          assert payload[:faces].all? { |face| face[:content].end_with?("0\r\nEOF\r\n") }
        end

        def test_manifest_is_utf8_bom_crlf_and_neutralizes_spreadsheet_formulas
          settings = Specification.defaults('tu_bep_duoi').merge(cabinet_name: '=CMD')
          project = MachiningPlanner.project(
            [{ settings: settings, cabinet_id: '+danger', cabinet_name: '=CMD' }]
          )
          document = MachiningExporter.package(project)[:manifest_content]
          rows = CSV.parse(document.delete_prefix(CutListCSVExporter::UTF8_BOM))

          assert document.start_with?(CutListCSVExporter::UTF8_BOM)
          assert_includes document, "\r\n"
          assert_equal MachiningExporter::CSV_HEADERS, rows.first
          assert_equal 101, rows.length
          assert_equal "'=CMD", rows[1][1]
          assert_equal "'+danger", rows[1][2]
          assert_equal 'Sẵn sàng', rows[1][-1]
        end

        def test_write_creates_owned_package_and_safely_replaces_it
          Dir.mktmpdir do |directory|
            selected = File.join(directory, 'cong_trinh.dxf')
            first = MachiningExporter.write(standard_project, selected)
            stale = File.join(first[:directory], 'stale.txt')
            File.write(stale, 'old')

            assert_equal File.join(directory, 'cong_trinh_cnc'), first[:directory]
            assert MachiningExporter.owned_directory?(first[:directory])
            assert_equal 6, first[:dxf_count]
            assert first[:dxf_paths].all? { |path| File.file?(path) }
            assert File.file?(first[:manifest_path])

            second = MachiningExporter.write(standard_project, selected, overwrite: true)

            refute File.exist?(stale)
            assert_equal first[:directory], second[:directory]
            assert_empty Dir.glob("#{first[:directory]}.sonvu-*")
          end
        end

        def test_write_never_replaces_an_unmarked_directory
          Dir.mktmpdir do |directory|
            selected = File.join(directory, 'customer_job.dxf')
            target = MachiningExporter.output_directory(selected)
            Dir.mkdir(target)
            File.write(File.join(target, 'customer.txt'), 'keep')

            error = assert_raises(ArgumentError) do
              MachiningExporter.write(standard_project, selected, overwrite: true)
            end

            assert_includes error.message, 'không do SonVu CNC Plugins tạo'
            assert File.file?(File.join(target, 'customer.txt'))
          end
        end

        def test_invalid_operations_block_the_entire_package
          project = MachiningPlanner.project(
            [{ settings: Specification.defaults('tu_ao'), cabinet_id: 'wardrobe' }]
          )

          assert_operator project[:invalid_operation_count], :>, 0
          error = assert_raises(ArgumentError) { MachiningExporter.package(project) }
          assert_includes error.message, 'nguyên công cần kiểm tra'
        end

        private

        def standard_project
          @standard_project ||= MachiningPlanner.project(
            [{
              settings: Specification.defaults('tu_bep_duoi'),
              cabinet_id: 'cab-1', cabinet_name: 'Tủ bếp A'
            }]
          )
        end
      end
    end
  end
end
