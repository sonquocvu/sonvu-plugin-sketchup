# frozen_string_literal: true

require 'json'

# Read-only unified Furniture Builder dashboard controller.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module Dashboard
        module_function

        def show
          return show_fallback unless defined?(::UI::HtmlDialog)

          if @dialog && @dialog.respond_to?(:visible?) && @dialog.visible?
            @dialog.bring_to_front if @dialog.respond_to?(:bring_to_front)
            refresh(@dialog)
            return @dialog
          end

          options = {
            dialog_title: 'Trung tâm nội thất SonVu',
            preferences_key: "#{CNCPlugins::PLUGIN_ID}.furniture_dashboard",
            scrollable: true,
            resizable: true,
            width: 980,
            height: 760
          }
          options[:style] = ::UI::HtmlDialog::STYLE_DIALOG if ::UI::HtmlDialog.const_defined?(:STYLE_DIALOG)
          dialog = ::UI::HtmlDialog.new(options)
          @dialog = dialog
          register_callbacks(dialog)
          refresh(dialog)
          dialog.center if dialog.respond_to?(:center)
          dialog.show
          dialog
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không mở được Trung tâm nội thất SonVu:\n#{e.message}")
          nil
        end

        def register_callbacks(dialog)
          dialog.add_action_callback('refreshFurnitureDashboard') { refresh(dialog) }
          dialog.add_action_callback('closeFurnitureDashboard') do
            @dialog = nil
            dialog.close
          end
          dialog.add_action_callback('openDashboardLicense') { Licensing::Dialog.show }
          dialog.add_action_callback('dashboardCreateFurniture') { run_action(dialog, :create) }
          dialog.add_action_callback('dashboardEditCarcass') { run_action(dialog, :edit_carcass) }
          dialog.add_action_callback('dashboardEditFittings') { run_action(dialog, :edit_fittings) }
          dialog.add_action_callback('dashboardOpenCutList') { run_action(dialog, :cut_list) }
          dialog.add_action_callback('dashboardOpenCostEstimate') { run_action(dialog, :cost_estimate) }
          dialog.add_action_callback('dashboardOpenSheetOptimization') do
            run_action(dialog, :sheet_optimization)
          end
          dialog.add_action_callback('dashboardOpenMachiningPreview') do
            run_action(dialog, :machining_preview)
          end
        end

        def run_action(dialog, action)
          case action
          when :create
            Commands.create_furniture(initial_section: :carcass)
          when :edit_carcass
            Commands.edit_selected_furniture(initial_section: :carcass)
          when :edit_fittings
            Commands.edit_selected_furniture(initial_section: :fronts)
          when :cut_list
            Commands.show_cut_list
          when :cost_estimate
            Commands.show_cost_estimate
          when :sheet_optimization
            Commands.show_sheet_optimization
          when :machining_preview
            Commands.show_machining_preview
          end
        rescue StandardError => e
          dialog.execute_script("showDashboardError(#{JSON.generate(e.message)});")
        end

        def refresh(dialog)
          dialog.set_html(DashboardHTML.html(current_state))
        rescue StandardError => e
          dialog.execute_script("showDashboardError(#{JSON.generate(e.message)});")
        end

        def current_state
          model = Sketchup.active_model
          selection = model.selection
          editable = selection.length == 1 && Geometry.editable_group?(selection.first)
          selected_name = editable && selection.first.respond_to?(:name) ? selection.first.name.to_s : ''
          report = CutList.report_for_model(model)
          license_view = Licensing::Manager.view_model(
            Licensing::Config::FEATURE_FURNITURE_BUILDER
          )
          DashboardState.build(
            report: report,
            editable_selection: editable,
            selected_cabinet_name: selected_name,
            license_view: license_view,
            version: CNCPlugins::VERSION
          )
        end

        def show_fallback
          state = current_state
          CNCPlugins::UIHelpers.message(
            "TRUNG TÂM NỘI THẤT SONVU\n\n" \
            "Phạm vi: #{state[:scope]}\n" \
            "Tủ: #{state[:cabinet_count]}\n" \
            "Chi tiết ván: #{state[:board_count]}\n" \
            "Phụ kiện: #{state[:hardware_count]}\n\n" \
            'Phiên bản SketchUp này không hỗ trợ bảng HTML. Hãy dùng các lệnh trong menu Thiết kế nội thất.'
          )
          state
        rescue StandardError => e
          CNCPlugins::UIHelpers.message("Không đọc được trạng thái nội thất:\n#{e.message}")
          nil
        end
      end
    end
  end
end
