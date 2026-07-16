# frozen_string_literal: true

# Reload-safe menu commands for the Vietnamese furniture builder.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module Commands
        module_function

        def register_menu(root_menu = nil)
          register_menu_items(root_menu)
          register_toolbar
        end

        def register_menu_items(root_menu = nil)
          return if @menu_registered

          root_menu ||= CNCPlugins.extension_menu
          furniture_menu = root_menu.add_submenu(CNCPlugins::MENU_FURNITURE_BUILDER)
          furniture_menu.add_item(dashboard_command)
          furniture_menu.add_separator
          furniture_menu.add_item(create_command)
          furniture_menu.add_item(edit_command)
          furniture_menu.add_separator
          furniture_menu.add_item(cut_list_command)
          furniture_menu.add_item(cost_estimate_command)
          furniture_menu.add_item(sheet_optimization_command)
          furniture_menu.add_separator
          furniture_menu.add_item(machining_preview_command)
          @menu_registered = true
        end

        def register_toolbar
          return if @toolbar_registered

          toolbar = UI::Toolbar.new(CNCPlugins::TOOLBAR_FURNITURE_BUILDER)
          toolbar.add_item(dashboard_command)
          toolbar.add_separator
          toolbar.add_item(create_command)
          toolbar.add_item(edit_command)
          toolbar.add_separator
          toolbar.add_item(cut_list_command)
          toolbar.add_item(cost_estimate_command)
          toolbar.add_item(sheet_optimization_command)
          toolbar.add_separator
          toolbar.add_item(machining_preview_command)
          toolbar.restore
          toolbar.show
          @toolbar = toolbar
          @toolbar_registered = true
        end

        def dashboard_command
          @dashboard_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_FURNITURE_DASHBOARD) { Dashboard.show }
            command.tooltip = 'Trung tâm nội thất SonVu'
            command.status_bar_text = 'Mở quy trình thiết kế, báo giá và tối ưu cắt ván.'
            assign_command_icons(command, 'furniture_dashboard')
            command
          end
        end

        def create_command
          @create_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_CREATE_FURNITURE) { create_furniture }
            command.tooltip = 'Tạo tủ nội thất'
            command.status_bar_text = 'Tạo tủ bếp, tủ áo hoặc kệ tivi theo kích thước.'
            assign_command_icons(command, 'furniture_create')
            command
          end
        end

        def edit_command
          @edit_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_EDIT_FURNITURE) { edit_selected_furniture }
            command.tooltip = 'Chỉnh sửa tủ đã chọn'
            command.status_bar_text = 'Chỉnh sửa kích thước và cấu tạo tủ nội thất do SonVu tạo.'
            assign_command_icons(command, 'furniture_edit')
            command
          end
        end

        def cut_list_command
          @cut_list_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_SHOW_FURNITURE_CUT_LIST) { show_cut_list }
            command.tooltip = 'Danh sách chi tiết'
            command.status_bar_text = 'Thống kê chi tiết ván và phụ kiện của các tủ SonVu.'
            assign_command_icons(command, 'furniture_cut_list')
            command
          end
        end

        def cost_estimate_command
          @cost_estimate_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_SHOW_FURNITURE_COST_ESTIMATE) do
              show_cost_estimate
            end
            command.tooltip = 'Dự toán chi phí'
            command.status_bar_text = 'Tính chi phí vật liệu, dán cạnh và phụ kiện nội thất.'
            assign_command_icons(command, 'furniture_cost')
            command
          end
        end

        def sheet_optimization_command
          @sheet_optimization_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_OPTIMIZE_FURNITURE_SHEETS) do
              show_sheet_optimization
            end
            command.tooltip = 'Tối ưu cắt ván'
            command.status_bar_text = 'Xếp chi tiết lên tấm ván theo vật liệu, độ dày và chiều vân.'
            assign_command_icons(command, 'furniture_optimize')
            command
          end
        end

        def machining_preview_command
          @machining_preview_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_PREVIEW_FURNITURE_MACHINING) do
              show_machining_preview
            end
            command.tooltip = 'Xem trước gia công CNC'
            command.status_bar_text = 'Kiểm tra tọa độ khoan và mặt gia công của từng chi tiết ván.'
            assign_command_icons(command, 'furniture_cnc_preview')
            command
          end
        end

        def create_furniture(initial_section: :carcass)
          return unless licensed?

          FurnitureBuilder::Dialog.show(mode: :create, initial_section: initial_section) do |settings|
            begin
              Sketchup.active_model.select_tool(FurnitureBuilder::PlacementTool.new(settings))
            rescue StandardError => e
              CNCPlugins::UIHelpers.message("Không khởi động được công cụ đặt tủ:\n#{e.message}")
            end
          end
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được công cụ tạo tủ nội thất:\n#{e.message}")
        end

        def edit_selected_furniture(initial_section: :carcass)
          return unless licensed?

          group = selected_furniture_group
          return unless group

          settings = FurnitureBuilder::Geometry.settings_from_group(group)
          unless settings
            CNCPlugins::UIHelpers.message('Không đọc được thông số đã lưu của tủ này.')
            return
          end

          FurnitureBuilder::Dialog.show(
            initial_values: settings,
            mode: :edit,
            initial_section: initial_section
          ) do |updated_settings|
            begin
              FurnitureBuilder::Geometry.rebuild(group, updated_settings)
            rescue StandardError => e
              CNCPlugins::UIHelpers.message("Không cập nhật được tủ nội thất:\n#{e.message}")
            end
          end
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không chỉnh sửa được tủ nội thất:\n#{e.message}")
        end

        def show_cut_list
          return unless licensed?

          report = FurnitureBuilder::CutList.report_for_model(Sketchup.active_model)
          if report[:cabinet_count].zero?
            CNCPlugins::UIHelpers.message(
              'Không tìm thấy tủ nội thất SonVu trong vùng chọn hoặc trong model.'
            )
            return nil
          end

          FurnitureBuilder::CutListDialog.show(report)
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không tạo được danh sách chi tiết:\n#{e.message}")
          nil
        end

        def show_cost_estimate
          return unless licensed?

          report = FurnitureBuilder::CutList.report_for_model(Sketchup.active_model)
          if report[:cabinet_count].zero?
            CNCPlugins::UIHelpers.message(
              'Không tìm thấy tủ nội thất SonVu trong vùng chọn hoặc trong model.'
            )
            return nil
          end

          FurnitureBuilder::CostEstimateDialog.show(report)
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được dự toán chi phí:\n#{e.message}")
          nil
        end

        def show_sheet_optimization
          return unless licensed?

          report = FurnitureBuilder::CutList.report_for_model(Sketchup.active_model)
          if report[:cabinet_count].zero?
            CNCPlugins::UIHelpers.message(
              'Không tìm thấy tủ nội thất SonVu trong vùng chọn hoặc trong model.'
            )
            return nil
          end

          FurnitureBuilder::SheetOptimizationDialog.show(report)
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được công cụ tối ưu cắt ván:\n#{e.message}")
          nil
        end

        def show_machining_preview
          return unless licensed?

          FurnitureBuilder::MachiningPreviewDialog.show
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được xem trước gia công CNC:\n#{e.message}")
          nil
        end

        def selected_furniture_group
          selection = Sketchup.active_model.selection
          if selection.length != 1
            CNCPlugins::UIHelpers.message('Vui lòng chọn đúng một tủ nội thất do SonVu tạo.')
            return nil
          end

          entity = selection.first
          return entity if FurnitureBuilder::Geometry.editable_group?(entity)

          CNCPlugins::UIHelpers.message('Đối tượng đã chọn không phải tủ nội thất do SonVu tạo.')
          nil
        end

        def assign_command_icons(command, base_name)
          icon_root = File.join(__dir__, 'icons')
          shared = File.expand_path(File.join(icon_root, "#{base_name}.svg"))
          small_candidate = File.expand_path(File.join(icon_root, "#{base_name}_small.svg"))
          large_candidate = File.expand_path(File.join(icon_root, "#{base_name}_large.svg"))
          small = File.exist?(small_candidate) ? small_candidate : shared
          large = File.exist?(large_candidate) ? large_candidate : shared
          command.small_icon = small if File.exist?(small)
          command.large_icon = large if File.exist?(large)
        end

        def licensed?
          CNCPlugins::Licensing::Manager.require_feature(
            CNCPlugins::Licensing::Config::FEATURE_FURNITURE_BUILDER
          )
        end
      end
    end
  end
end
