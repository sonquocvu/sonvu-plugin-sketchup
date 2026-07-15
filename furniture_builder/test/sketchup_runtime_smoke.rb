# frozen_string_literal: true

# Launch from SketchUp's -RubyStartup command-line switch. This smoke test runs
# only in a blank disposable model and writes its report to the system temp
# directory. It validates behavior that pure Ruby stubs cannot prove.

require 'json'
require 'tmpdir'
require 'time'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module RuntimeSmoke
        REPORT_PATH = File.join(Dir.tmpdir, 'sonvu_furniture_builder_runtime_smoke.json')

        module_function

        def run
          load_extension_unless_available
          Sketchup.file_new
          model = Sketchup.active_model
          result = {
            sketchup_version: Sketchup.version,
            plugin_version: CNCPlugins::VERSION,
            started_at: Time.now.iso8601
          }

          original = Specification.defaults('tu_bep_duoi')
          group = Geometry.create(
            original,
            transformation: Geom::Transformation.translation([100.mm, 200.mm, 0])
          )
          cabinet_id = group.get_attribute(
            CNCPlugins::ATTRIBUTE_DICTIONARY,
            Geometry::CABINET_ID_ATTRIBUTE
          )
          original_transformation = group.transformation.to_a
          panels = generated_panels(group)

          assert('cabinet group is tagged') { Geometry.editable_group?(group) }
          assert('base cabinet creates 24 carcass, front, drawer, and hardware components') do
            panels.length == 24
          end
          assert('box and circular templates have the expected face topology') do
            panels.all? do |panel|
              face_count = panel.definition.entities.grep(Sketchup::Face).length
              shape = panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'geometry_shape')
              shape == 'cylinder_y' ? face_count == 26 : face_count == 6
            end
          end
          assert('every panel is a manifold solid') do
            panels.all? { |panel| panel.respond_to?(:manifold?) && panel.manifold? }
          end
          assert('every panel has Vietnamese name and production metadata') do
            panels.all? do |panel|
              !panel.name.to_s.empty? &&
                panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'part_name_vi') == panel.name &&
                panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'finished_length_mm').to_f.positive? &&
                panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'finished_width_mm').to_f.positive? &&
                panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'thickness_mm').to_f.positive? &&
                %w[length width].include?(
                  panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'grain_axis')
                )
            end
          end
          assert('base cabinet creates three separately tagged front components') do
            fronts = panels.select do |panel|
              panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'part_kind') == 'front'
            end
            fronts.length == 3 && fronts.all? do |front|
              front.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'material_name') == original[:front_material_name]
            end
          end
          assert('base cabinet creates one linked five-panel drawer box') do
            drawer_front = panels.find do |panel|
              panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'part_role') == 'drawer_front'
            end
            drawer_panels = panels.select do |panel|
              panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'part_kind') == 'drawer_box'
            end
            drawer_front &&
              drawer_front.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'drawer_index') == 1 &&
              drawer_panels.length == 5 && drawer_panels.all? do |panel|
              panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'drawer_index') == 1 &&
                panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'material_name') ==
                  original[:drawer_material_name]
            end
          end
          assert('base cabinet creates linked handles, hinge cups, and drawer slides') do
            hardware = panels.select do |panel|
              panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'part_kind') == 'hardware'
            end
            roles = hardware.map do |panel|
              panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'hardware_type')
            end
            hardware.length == 9 &&
              roles.count('handle') == 3 &&
              roles.count('hinge_cup') == 4 &&
              roles.count('drawer_slide_left') == 1 &&
              roles.count('drawer_slide_right') == 1 &&
              hardware.all? do |panel|
                panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'material_name') ==
                  original[:hardware_material_name] &&
                  !panel.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, 'owner_part_key').to_s.empty?
              end
          end
          assert('Phase 3A reads the selected cabinet without changing it') do
            report = CutList.report_for_model(model)
            report[:scope] == 'Các tủ đang chọn' &&
              report[:cabinet_count] == 1 &&
              report[:board_count] == 15 &&
              report[:hardware_count] == 9 &&
              report[:warnings].empty?
          end
          assert('Phase 3B builds separate UTF-8 board and hardware CSV documents') do
            report = CutList.report_for_model(model)
            board_csv = CutListCSVExporter.board_csv(report)
            hardware_csv = CutListCSVExporter.hardware_csv(report)
            board_csv.start_with?(CutListCSVExporter::UTF8_BOM) &&
              hardware_csv.start_with?(CutListCSVExporter::UTF8_BOM) &&
              board_csv.include?('Tên chi tiết') &&
              hardware_csv.include?('Phụ kiện')
          end
          assert('Phase 3C calculates one project and cabinet total without model writes') do
            report = CutList.report_for_model(model)
            catalog = CostEstimator.default_catalog(report)
            catalog[:edge_band_price_per_m] = 5000
            catalog[:material_prices].keys.each { |key| catalog[:material_prices][key] = 200_000 }
            catalog[:hardware_prices].keys.each { |key| catalog[:hardware_prices][key] = 20_000 }
            estimate = CostEstimator.calculate(report, catalog)
            quotation_csv = CostEstimateCSVExporter.csv(estimate)
            estimate[:project_total].positive? &&
              estimate[:cabinet_totals].length == 1 &&
              (estimate[:cabinet_totals].first[:total_cost] - estimate[:project_total]).abs < 0.001 &&
              quotation_csv.start_with?(CutListCSVExporter::UTF8_BOM) &&
              quotation_csv.include?('TỔNG CỘNG')
          end
          assert('Phase 4A packs every board part without changing the model') do
            report = CutList.report_for_model(model)
            entity_count = model.entities.length
            optimization = SheetOptimizer.optimize(report)
            optimization[:part_count] == 15 &&
              optimization[:placed_count] + optimization[:unplaced_count] == 15 &&
              optimization[:sheet_count].positive? &&
              optimization[:groups].all? { |item| item[:material_name] != original[:hardware_material_name] } &&
              model.entities.length == entity_count
          end
          assert('Phase 4B renders every optimized sheet and placed part without model writes') do
            report = CutList.report_for_model(model)
            entity_count = model.entities.length
            optimization = SheetOptimizer.optimize(report)
            maps = optimization[:groups].flat_map do |optimization_group|
              optimization_group[:sheets].map do |sheet|
                SheetLayoutSVG.render(sheet, optimization[:settings])
              end
            end
            rendered_parts = maps.sum { |svg| svg.scan('class="part-shape"').length }
            maps.length == optimization[:sheet_count] &&
              rendered_parts == optimization[:placed_count] &&
              maps.all? { |svg| svg.include?('class="sheet-map"') } &&
              model.entities.length == entity_count
          end
          assert('Phase 4C builds printable HTML and placement CSV without model writes') do
            report = CutList.report_for_model(model)
            entity_count = model.entities.length
            optimization = SheetOptimizer.optimize(report)
            printable = SheetLayoutExporter.report_html(report, optimization)
            placements = SheetLayoutExporter.placement_csv(optimization)
            printable.include?('SonVu Furniture Builder — Phase 4C') &&
              printable.scan('class="sheet-map"').length == optimization[:sheet_count] &&
              placements.start_with?(CutListCSVExporter::UTF8_BOM) &&
              placements.include?('Trạng thái') &&
              placements.include?('Đã xếp') &&
              model.entities.length == entity_count
          end

          model.start_operation('Chuẩn bị kiểm tra cập nhật tủ SonVu', true)
          marker = group.entities.add_group
          marker.name = 'Đối tượng người dùng cần giữ lại'
          model.commit_operation

          updated = original.merge(width_mm: 1000, shelf_count: 2, cabinet_name: 'Tủ bếp kiểm tra')
          Geometry.rebuild(group, updated)
          rebuilt_panels = generated_panels(group)

          assert('rebuild preserves cabinet ID') do
            group.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, Geometry::CABINET_ID_ATTRIBUTE) == cabinet_id
          end
          assert('rebuild preserves placement transformation') { group.transformation.to_a == original_transformation }
          assert('rebuild preserves unrelated user entity') { marker.valid? && group.entities.include?(marker) }
          assert('rebuild stores updated width') { Geometry.settings_from_group(group)[:width_mm] == 1000.0 }
          assert('rebuild updates panel count') { rebuilt_panels.length == 25 }

          Sketchup.undo
          restored_group = tagged_cabinet(model)
          assert('one Undo restores prior cabinet settings') do
            restored_group && Geometry.settings_from_group(restored_group)[:width_mm] == 800.0
          end
          assert('one Undo keeps the pre-existing user entity') do
            restored_group && restored_group.entities.grep(Sketchup::Group).any? do |entity|
              entity.name == 'Đối tượng người dùng cần giữ lại'
            end
          end

          Sketchup.undo
          Sketchup.undo
          assert('cleanup Undo removes the generated cabinet') { tagged_cabinet(model).nil? }

          result[:status] = 'passed'
          result[:assertions] = @assertions
          result
        rescue StandardError => e
          {
            status: 'failed',
            assertions: @assertions || [],
            error_class: e.class.name,
            error: e.message,
            backtrace: Array(e.backtrace).first(12)
          }
        ensure
          File.write(REPORT_PATH, JSON.pretty_generate(result || { status: 'failed', error: 'No result' }))
          UI.start_timer(0.25, false) do
            Sketchup.active_model.close(true)
            Sketchup.quit
          end
        end

        def assert(label)
          @assertions ||= []
          passed = yield
          @assertions << { label: label, passed: passed }
          raise "Kiểm tra thất bại: #{label}" unless passed

          true
        end

        def generated_panels(group)
          group.entities.grep(Sketchup::ComponentInstance).select do |instance|
            instance.get_attribute(CNCPlugins::ATTRIBUTE_DICTIONARY, Geometry::PANEL_ATTRIBUTE, false)
          end
        end

        def tagged_cabinet(model)
          model.entities.grep(Sketchup::Group).find { |group| Geometry.editable_group?(group) }
        end

        def load_extension_unless_available
          return if defined?(SonVu::CNCPlugins::FurnitureBuilder::Geometry)

          require_relative '../../main'
        end
      end
    end
  end
end

UI.start_timer(2.0, false) { SonVu::CNCPlugins::FurnitureBuilder::RuntimeSmoke.run }
