# frozen_string_literal: true

# Pure dashboard state builder. SketchUp inspection stays in Dashboard so the
# enablement and Vietnamese status rules remain testable without SketchUp.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module DashboardState
        module_function

        def build(report:, editable_selection:, selected_cabinet_name: '', license_view: {}, version: '')
          report ||= {}
          license_view ||= {}
          licensed = license_view.fetch(:licensed, true) == true
          cabinet_count = report[:cabinet_count].to_i
          board_count = report[:board_count].to_i
          hardware_count = report[:hardware_count].to_i
          part_count = report[:part_count].to_i
          has_cabinets = cabinet_count.positive?
          has_boards = board_count.positive?
          can_edit = licensed && editable_selection

          {
            version: version.to_s,
            scope: report[:scope].to_s.empty? ? 'Toàn bộ model' : report[:scope].to_s,
            cabinet_count: cabinet_count,
            board_count: board_count,
            hardware_count: hardware_count,
            part_count: part_count,
            warning_count: Array(report[:warnings]).length,
            editable_selection: editable_selection == true,
            selected_cabinet_name: selected_cabinet_name.to_s,
            selection_message: selection_message(
              cabinet_count, editable_selection, selected_cabinet_name, report[:scope]
            ),
            license: {
              licensed: licensed,
              state: license_view[:state].to_s,
              message: license_view[:message].to_s,
              customer: license_view[:customer].to_s,
              expires_at: license_view[:expires_at].to_s
            },
            actions: {
              create: licensed,
              edit_carcass: can_edit,
              edit_fittings: can_edit,
              cut_list: licensed && has_cabinets,
              cost_estimate: licensed && has_cabinets,
              sheet_optimization: licensed && has_boards,
              phase_five: licensed && has_boards
            }
          }
        end

        def selection_message(cabinet_count, editable_selection, selected_name, scope)
          if editable_selection
            name = selected_name.to_s.strip
            return name.empty? ? 'Đã chọn một tủ SonVu để chỉnh sửa.' : "Đang chọn: #{name}"
          end
          return 'Model chưa có tủ nội thất SonVu.' if cabinet_count.zero?
          return "Đang dùng #{cabinet_count} tủ trong vùng chọn." if scope.to_s == 'Các tủ đang chọn'

          "Không chọn riêng tủ; báo cáo sẽ dùng toàn bộ #{cabinet_count} tủ trong model."
        end
      end
    end
  end
end
