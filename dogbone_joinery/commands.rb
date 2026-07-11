# frozen_string_literal: true

# SketchUp command and menu registration for the Dogbone Joinery feature. This
# file wires the feature into Extensions > SonVu CNC Plugins > Mộng CNC.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module Commands
        module_function

        def register_menu
          register_menu_items
          register_toolbar
        end

        def register_menu_items
          return if @menu_registered

          root_menu = UI.menu('Extensions').add_submenu(CNCPlugins::PLUGIN_NAME)
          dogbone_menu = root_menu.add_submenu(CNCPlugins::MENU_DOGBONE_JOINERY)
          dogbone_menu.add_item(create_mortise_command)
          dogbone_menu.add_item(create_tenon_command)
          dogbone_menu.add_item(delete_templates_command)

          @menu_registered = true
        end

        def register_toolbar
          return if @toolbar_registered

          toolbar = UI::Toolbar.new(CNCPlugins::TOOLBAR_DOGBONE_JOINERY)
          toolbar.add_item(create_mortise_command)
          toolbar.add_item(create_tenon_command)
          toolbar.add_item(delete_templates_command)
          toolbar.restore
          toolbar.show

          @toolbar_registered = true
        end

        def create_mortise_command
          @create_mortise_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_CREATE_DOGBONE_MORTISE) { open_dialog(:mortise) }
            command.tooltip = 'Tạo mộng âm'
            command.status_bar_text = 'Tạo và đặt mẫu mộng âm xương chó.'
            assign_icon_if_available(command, 'create_dogbone_mortise')
            command
          end
        end

        def create_tenon_command
          @create_tenon_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_CREATE_DOGBONE_TENON) { open_dialog(:tenon) }
            command.tooltip = 'Tạo mộng dương'
            command.status_bar_text = 'Tạo mộng dương theo chiều cao mặt cạnh đã chọn.'
            assign_icon_if_available(command, 'create_dogbone_tenon')
            command
          end
        end

        def delete_templates_command
          @delete_templates_command ||= begin
            command = UI::Command.new(CNCPlugins::COMMAND_DELETE_GENERATED_TEMPLATES) { delete_generated_templates }
            command.tooltip = 'Xóa mẫu mộng đã tạo'
            command.status_bar_text = 'Xóa các nhóm mẫu mộng xương chó do plugin tạo.'
            assign_icon_if_available(command, 'delete_generated_templates')
            command
          end
        end

        def assign_icon_if_available(command, icon_basename)
          small_icon = available_icon_path("#{icon_basename}_small")
          large_icon = available_icon_path("#{icon_basename}_large")

          command.small_icon = small_icon if small_icon
          command.large_icon = large_icon if large_icon
        end

        def available_icon_path(icon_basename)
          %w[svg png].map { |extension| icon_path("#{icon_basename}.#{extension}") }.find do |path|
            File.exist?(path)
          end
        end

        def icon_path(filename)
          File.expand_path(File.join(__dir__, 'icons', filename))
        end

        def open_dialog(mode)
          selected_face = selected_placement_face
          return if selected_face == false

          DogboneJoinery::Dialog.show(selected_face: selected_face, mode: mode) do |params|
            begin
              start_placement_tool(params, selected_face)
            rescue StandardError => e
              CNCPlugins::UIHelpers.message("Không tạo được mẫu mộng xương chó:\n#{e.message}")
            end
          end
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không tạo được mẫu mộng xương chó:\n#{e.message}")
        end

        def start_placement_tool(params, selected_face)
          return unless params[:create_mortise] || params[:create_tenon] || params[:cut_mortise_into_selected_solid]

          cut_target = nil
          if params[:cut_mortise_into_selected_solid]
            cut_target = selected_cut_target
            return if cut_target == false
            return unless confirm_boolean_cut
          end

          if create_tenon_directly?(params, selected_face)
            DogboneJoinery::PlacementTool.create_on_face(params, selected_face)
            return
          end

          Sketchup.active_model.select_tool(DogboneJoinery::PlacementTool.new(params, selected_face, cut_target))
        end

        def create_tenon_directly?(params, selected_face)
          selected_face &&
            params[:create_tenon] &&
            !params[:create_mortise] &&
            !params[:cut_mortise_into_selected_solid]
        end

        def selected_placement_face
          faces = Sketchup.active_model.selection.grep(Sketchup::Face)
          return nil if faces.empty?
          return faces.first if faces.length == 1

          CNCPlugins::UIHelpers.message('Vui lòng chọn đúng 1 mặt phẳng nếu muốn đặt mộng lên mặt gỗ.')
          false
        end

        def selected_cut_target
          selection = Sketchup.active_model.selection
          solids = selection.grep(Sketchup::Group) + selection.grep(Sketchup::ComponentInstance)

          if selection.length != 1 || solids.length != 1
            CNCPlugins::UIHelpers.message('Vui lòng chọn đúng 1 nhóm hoặc component dạng khối đặc trước khi bật cắt mộng âm.')
            return false
          end

          solid = solids.first
          unless solid.respond_to?(:manifold?) && solid.manifold?
            CNCPlugins::UIHelpers.message('Đối tượng đã chọn chưa phải khối đặc của SketchUp. Vui lòng chọn 1 nhóm hoặc component dạng khối đặc.')
            return false
          end

          solid
        end

        def confirm_boolean_cut
          result = UI.messagebox(
            "Lệnh này sẽ chỉnh sửa solid đã chọn. Vui lòng lưu file trước khi cắt.\n\nTiếp tục?",
            ::MB_YESNO
          )
          result == ::IDYES
        end

        def delete_generated_templates
          model = Sketchup.active_model
          generated_groups = generated_template_groups(model.entities)

          if generated_groups.empty?
            CNCPlugins::UIHelpers.message('Không tìm thấy mẫu mộng xương chó nào do plugin tạo.')
            return
          end

          result = UI.messagebox(
            "Xóa #{generated_groups.length} nhóm mẫu mộng xương chó đã tạo?",
            ::MB_YESNO
          )
          return unless result == ::IDYES

          model.start_operation('Xóa mẫu mộng xương chó', true)
          begin
            generated_groups.each { |group| group.erase! if group.valid? }
            model.commit_operation
          rescue StandardError
            model.abort_operation
            raise
          end
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không xóa được mẫu mộng xương chó:\n#{e.message}")
        end

        def generated_template_groups(entities)
          entities.grep(Sketchup::Group).flat_map do |group|
            nested_groups = generated_template_groups(group.entities)
            DogboneJoinery::Geometry.generated_group?(group) ? [group] + nested_groups : nested_groups
          end
        end
      end
    end
  end
end
