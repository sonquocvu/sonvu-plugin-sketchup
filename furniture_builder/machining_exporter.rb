# frozen_string_literal: true

# Controller-neutral Step 5C export. The package contains one millimetre DXF
# for each machined panel face and one UTF-8 operation manifest. It never writes
# to the SketchUp model and deliberately does not emit G-code or machine data.

require 'csv'
require 'fileutils'
require 'securerandom'
require_relative 'cut_list_csv_exporter'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module MachiningExporter
        DIRECTORY_SUFFIX = '_cnc'
        MANIFEST_FILENAME = 'nguyen_cong.csv'
        MARKER_FILENAME = '.sonvu_cnc_export'
        MARKER_CONTENT = "SonVu CNC Plugins - Step 5C\n"
        OUTLINE_LAYER = 'PANEL_OUTLINE'
        CSV_HEADERS = [
          'STT', 'Tủ', 'Mã tủ', 'Chi tiết', 'Mã chi tiết', 'Mặt',
          'Nguyên công', 'Hình dạng', 'X (mm)', 'Y (mm)',
          'Đường kính (mm)', 'Chiều dài (mm)', 'Chiều rộng (mm)',
          'Chiều sâu (mm)', 'Layer DXF', 'File DXF', 'Trạng thái'
        ].freeze
        TYPE_LAYER_NAMES = {
          'hinge_cup' => 'DRILL_HINGE',
          'dowel' => 'DRILL_DOWEL',
          'cam_pocket' => 'POCKET_CAM',
          'shelf_pin' => 'DRILL_SHELF',
          'back_groove' => 'GROOVE_BACK'
        }.freeze

        module_function

        def output_directory(base_path)
          path = base_path.to_s.strip
          raise ArgumentError, 'Vui lòng chọn tên gói gia công CNC.' if path.empty?

          expanded = File.expand_path(path)
          stem = expanded.sub(/\.(?:dxf|csv)\z/i, '')
          stem.end_with?(DIRECTORY_SUFFIX) ? stem : "#{stem}#{DIRECTORY_SUFFIX}"
        end

        def package(project)
          validate_project!(project)
          faces = face_views(project).each_with_index.map do |view, index|
            filename = face_filename(view, index + 1)
            view.merge(
              filename: filename,
              content: dxf(view[:panel], view[:face], view[:operations])
            )
          end
          {
            faces: faces,
            manifest_filename: MANIFEST_FILENAME,
            manifest_content: manifest_csv(faces)
          }
        end

        def write(project, base_path, overwrite: false)
          payload = package(project)
          target = output_directory(base_path)
          parent = File.dirname(target)
          raise ArgumentError, "Thư mục xuất không tồn tại: #{parent}" unless Dir.exist?(parent)

          if File.exist?(target)
            raise ArgumentError, "Đường dẫn xuất đã tồn tại nhưng không phải thư mục: #{target}" unless Dir.exist?(target)
            unless owned_directory?(target)
              raise ArgumentError, 'Thư mục đích không do SonVu CNC Plugins tạo. Hãy chọn tên gói khác.'
            end
            raise ArgumentError, 'Gói gia công CNC đã tồn tại.' unless overwrite
          end

          temporary = unique_sibling(target, 'tmp')
          backup = unique_sibling(target, 'bak')
          moved_existing = false
          begin
            FileUtils.mkdir_p(temporary)
            write_binary(File.join(temporary, MARKER_FILENAME), MARKER_CONTENT)
            payload[:faces].each do |face|
              write_binary(File.join(temporary, face[:filename]), face[:content])
            end
            write_binary(
              File.join(temporary, payload[:manifest_filename]),
              payload[:manifest_content].encode(Encoding::UTF_8)
            )

            if Dir.exist?(target)
              FileUtils.mv(target, backup)
              moved_existing = true
            end
            FileUtils.mv(temporary, target)
            FileUtils.rm_rf(backup) if moved_existing && Dir.exist?(backup)
          rescue StandardError
            FileUtils.rm_rf(temporary) if Dir.exist?(temporary)
            if moved_existing && Dir.exist?(backup) && !File.exist?(target)
              FileUtils.mv(backup, target)
            end
            raise
          ensure
            FileUtils.rm_rf(temporary) if Dir.exist?(temporary)
          end

          {
            directory: target,
            dxf_count: payload[:faces].length,
            manifest_path: File.join(target, payload[:manifest_filename]),
            dxf_paths: payload[:faces].map { |face| File.join(target, face[:filename]) }
          }
        end

        def owned_directory?(path)
          marker = File.join(path.to_s, MARKER_FILENAME)
          File.file?(marker) && File.binread(marker) == MARKER_CONTENT
        rescue StandardError
          false
        end

        def validate_project!(project)
          cabinets = Array(project && project[:cabinets])
          raise ArgumentError, 'Không có tủ nội thất để xuất gia công CNC.' if cabinets.empty?

          operations = cabinets.flat_map do |cabinet|
            Array(cabinet[:panels]).flat_map { |panel| Array(panel[:operations]) }
          end
          invalid_count = operations.count { |operation| operation[:status].to_s != 'ready' }
          if invalid_count.positive?
            raise ArgumentError, "Không thể xuất: còn #{invalid_count} nguyên công cần kiểm tra."
          end
          raise ArgumentError, 'Không có nguyên công sẵn sàng để xuất.' if operations.empty?

          unsupported = operations.reject { |operation| %w[circle groove].include?(operation[:shape].to_s) }
          raise ArgumentError, 'Có nguyên công chưa được hỗ trợ để xuất DXF.' unless unsupported.empty?

          true
        end

        def face_views(project)
          Array(project[:cabinets]).flat_map do |cabinet|
            Array(cabinet[:panels]).flat_map do |panel|
              Array(panel[:operations]).group_by { |operation| operation[:face].to_s }.sort.map do |face, operations|
                {
                  cabinet: cabinet,
                  panel: panel,
                  face: face,
                  operations: operations
                }
              end
            end
          end
        end

        def face_filename(view, index)
          cabinet_name = view[:cabinet][:cabinet_name]
          panel_name = view[:panel][:name]
          slug = slugify([cabinet_name, panel_name, "mat #{view[:face]}"].join(' '))
          format('%03d_%s.dxf', index, slug[0, 100])
        end

        def slugify(value)
          text = value.to_s.tr('Đđ', 'Dd')
          text = text.unicode_normalize(:nfkd) if text.respond_to?(:unicode_normalize)
          ascii = text.encode(Encoding::ASCII, invalid: :replace, undef: :replace, replace: '')
          slug = ascii.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
          slug.empty? ? 'chi_tiet' : slug
        end

        def dxf(panel, _face, operations)
          layers = [OUTLINE_LAYER] + operations.map { |operation| operation_layer(operation) }
          lines = []
          append_pairs(lines, 0, 'SECTION', 2, 'HEADER')
          append_pairs(lines, 9, '$ACADVER', 1, 'AC1015')
          append_pairs(lines, 9, '$INSUNITS', 70, 4)
          append_pairs(lines, 0, 'ENDSEC', 0, 'SECTION', 2, 'TABLES')
          append_pairs(lines, 0, 'TABLE', 2, 'LAYER', 70, layers.uniq.length)
          layers.uniq.each do |layer|
            append_pairs(lines, 0, 'LAYER', 2, layer, 70, 0, 62, layer == OUTLINE_LAYER ? 8 : 3, 6, 'CONTINUOUS')
          end
          append_pairs(lines, 0, 'ENDTAB', 0, 'ENDSEC', 0, 'SECTION', 2, 'ENTITIES')
          append_polyline(
            lines,
            OUTLINE_LAYER,
            [[0, 0], [panel[:length_mm], 0], [panel[:length_mm], panel[:width_mm]], [0, panel[:width_mm]]]
          )
          operations.each { |operation| append_operation(lines, operation) }
          append_pairs(lines, 0, 'ENDSEC', 0, 'EOF')
          lines.join("\r\n") + "\r\n"
        end

        def append_operation(lines, operation)
          layer = operation_layer(operation)
          if operation[:shape].to_s == 'circle'
            append_pairs(
              lines, 0, 'CIRCLE', 8, layer,
              10, number(operation[:x_mm]), 20, number(operation[:y_mm]), 30, 0,
              40, number(operation[:diameter_mm].to_f / 2.0)
            )
          else
            x = operation[:x_mm].to_f
            y = operation[:y_mm].to_f
            length = operation[:length_mm].to_f
            width = operation[:width_mm].to_f
            append_polyline(lines, layer, [[x, y], [x + length, y], [x + length, y + width], [x, y + width]])
          end
        end

        def append_polyline(lines, layer, points)
          append_pairs(lines, 0, 'LWPOLYLINE', 8, layer, 90, points.length, 70, 1)
          points.each { |x, y| append_pairs(lines, 10, number(x), 20, number(y)) }
        end

        def operation_layer(operation)
          prefix = TYPE_LAYER_NAMES.fetch(operation[:type].to_s) do
            "OP_#{slugify(operation[:type]).upcase}"
          end
          if operation[:shape].to_s == 'groove'
            "#{prefix}_W#{layer_number(operation[:width_mm])}_Z#{layer_number(operation[:depth_mm])}"
          else
            "#{prefix}_D#{layer_number(operation[:diameter_mm])}_Z#{layer_number(operation[:depth_mm])}"
          end
        end

        def manifest_csv(faces)
          index = 0
          rows = faces.flat_map do |face|
            face[:operations].map do |operation|
              index += 1
              [
                index,
                safe_text(face[:cabinet][:cabinet_name]),
                safe_text(face[:cabinet][:cabinet_id]),
                safe_text(face[:panel][:name]),
                safe_text(face[:panel][:key]),
                safe_text("Mặt #{face[:face]}"),
                safe_text(operation[:label]),
                operation[:shape].to_s == 'groove' ? 'Rãnh chữ nhật' : 'Khoan tròn',
                dimension(operation[:x_mm]),
                dimension(operation[:y_mm]),
                operation[:shape].to_s == 'circle' ? dimension(operation[:diameter_mm]) : '',
                operation[:shape].to_s == 'groove' ? dimension(operation[:length_mm]) : '',
                operation[:shape].to_s == 'groove' ? dimension(operation[:width_mm]) : '',
                dimension(operation[:depth_mm]),
                operation_layer(operation),
                face[:filename],
                'Sẵn sàng'
              ]
            end
          end
          body = CSV.generate(row_sep: "\r\n", force_quotes: true) do |csv|
            csv << CSV_HEADERS
            rows.each { |row| csv << row }
          end
          CutListCSVExporter::UTF8_BOM + body
        end

        def append_pairs(lines, *pairs)
          pairs.each_slice(2) do |code, value|
            lines << code.to_s
            lines << value.to_s
          end
        end

        def number(value)
          dimension(value)
        end

        def dimension(value)
          CutListCSVExporter.dimension(value)
        end

        def layer_number(value)
          dimension(value).tr('-.', 'MP')
        end

        def safe_text(value)
          CutListCSVExporter.spreadsheet_text(value)
        end

        def unique_sibling(target, suffix)
          "#{target}.sonvu-#{Process.pid}-#{SecureRandom.hex(6)}.#{suffix}"
        end

        def write_binary(path, payload)
          File.open(path, 'wb') { |file| file.write(payload) }
        end
      end
    end
  end
end
