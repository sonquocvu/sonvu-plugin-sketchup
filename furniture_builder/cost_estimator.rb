# frozen_string_literal: true

# Pure Phase 3C costing rules. Dimensions come from the Phase 3A report in
# millimetres; prices are VND per square metre, metre, or hardware item.

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      module CostEstimator
        DEFAULT_WASTE_PERCENT = 10.0
        DEFAULT_EDGE_PRICE_PER_M = 0.0
        MAX_WASTE_PERCENT = 100.0

        module_function

        def default_catalog(report)
          normalize_catalog(report, {})
        end

        def normalize_catalog(report, values)
          values ||= {}
          material_prices = normalize_price_map(value_for(values, :material_prices))
          hardware_prices = normalize_price_map(value_for(values, :hardware_prices))
          Array(report[:board_rows]).each do |row|
            material_prices[row[:material_name].to_s] = 0.0 unless material_prices.key?(row[:material_name].to_s)
          end
          Array(report[:hardware_rows]).each do |row|
            hardware_prices[row[:name].to_s] = 0.0 unless hardware_prices.key?(row[:name].to_s)
          end
          {
            waste_percent: decimal(value_for(values, :waste_percent), DEFAULT_WASTE_PERCENT),
            edge_band_price_per_m: decimal(
              value_for(values, :edge_band_price_per_m),
              DEFAULT_EDGE_PRICE_PER_M
            ),
            material_prices: material_prices,
            hardware_prices: hardware_prices
          }
        end

        def validate_catalog(catalog)
          numeric_values = [catalog[:waste_percent], catalog[:edge_band_price_per_m]] +
                           catalog[:material_prices].values + catalog[:hardware_prices].values
          if numeric_values.any? { |value| value.nil? || !value.finite? }
            return 'Vui lòng nhập số hợp lệ cho toàn bộ đơn giá.'
          end
          unless catalog[:waste_percent].between?(0, MAX_WASTE_PERCENT)
            return "Tỷ lệ hao hụt phải từ 0 đến #{MAX_WASTE_PERCENT.to_i}%."
          end
          return 'Đơn giá vật liệu, dán cạnh và phụ kiện không được âm.' if numeric_values.drop(1).any?(&:negative?)

          nil
        end

        def calculate(report, values)
          catalog = normalize_catalog(report, values)
          error = validate_catalog(catalog)
          raise ArgumentError, error if error

          cabinet_totals = {}
          board_rows = Array(report[:board_rows]).map do |row|
            detail = cost_board_row(row, catalog)
            allocate_to_cabinets(row, detail[:total_cost], cabinet_totals)
            detail
          end
          hardware_rows = Array(report[:hardware_rows]).map do |row|
            detail = cost_hardware_row(row, catalog)
            allocate_to_cabinets(row, detail[:total_cost], cabinet_totals)
            detail
          end
          material_subtotal = board_rows.sum { |row| row[:material_cost] }
          edge_subtotal = board_rows.sum { |row| row[:edge_cost] }
          hardware_subtotal = hardware_rows.sum { |row| row[:hardware_cost] }
          {
            catalog: catalog,
            board_rows: board_rows,
            hardware_rows: hardware_rows,
            cabinet_totals: cabinet_totals.values.sort_by { |item| [item[:cabinet_name], item[:occurrence_key]] },
            material_subtotal: material_subtotal,
            edge_subtotal: edge_subtotal,
            hardware_subtotal: hardware_subtotal,
            project_total: material_subtotal + edge_subtotal + hardware_subtotal
          }
        end

        def cost_board_row(row, catalog)
          quantity = row[:quantity].to_i
          net_area = quantity * row[:length_mm].to_f * row[:width_mm].to_f / 1_000_000.0
          billable_area = net_area * (1.0 + (catalog[:waste_percent] / 100.0))
          material_price = catalog[:material_prices].fetch(row[:material_name].to_s, 0.0)
          edge_length = edge_length_m(row)
          material_cost = billable_area * material_price
          edge_cost = edge_length * catalog[:edge_band_price_per_m]
          row.merge(
            net_area_m2: net_area,
            billable_area_m2: billable_area,
            material_unit_price: material_price,
            material_cost: material_cost,
            edge_length_m: edge_length,
            edge_unit_price: catalog[:edge_band_price_per_m],
            edge_cost: edge_cost,
            total_cost: material_cost + edge_cost
          )
        end

        def cost_hardware_row(row, catalog)
          unit_price = catalog[:hardware_prices].fetch(row[:name].to_s, 0.0)
          hardware_cost = row[:quantity].to_i * unit_price
          row.merge(
            unit_price: unit_price,
            hardware_cost: hardware_cost,
            total_cost: hardware_cost
          )
        end

        def edge_length_m(row)
          length = row[:length_mm].to_f
          width = row[:width_mm].to_f
          total_mm = 0.0
          total_mm += length if row[:edge_front]
          total_mm += length if row[:edge_back]
          total_mm += width if row[:edge_left]
          total_mm += width if row[:edge_right]
          row[:quantity].to_i * total_mm / 1000.0
        end

        def allocate_to_cabinets(row, row_total, totals)
          quantity = row[:quantity].to_i
          return if quantity <= 0

          unit_total = row_total / quantity.to_f
          cabinet_breakdown(row).each do |item|
            key = item[:occurrence_key]
            total = totals[key] ||= {
              occurrence_key: key,
              cabinet_id: item[:cabinet_id],
              cabinet_name: item[:cabinet_name],
              total_cost: 0.0
            }
            total[:total_cost] += unit_total * item[:quantity].to_i
          end
        end

        def cabinet_breakdown(row)
          breakdown = Array(row[:cabinet_breakdown])
          return breakdown unless breakdown.empty?

          [{
            occurrence_key: Array(row[:cabinet_ids]).first.to_s,
            cabinet_id: Array(row[:cabinet_ids]).first.to_s,
            cabinet_name: Array(row[:cabinet_names]).first.to_s,
            quantity: row[:quantity].to_i
          }]
        end

        def normalize_price_map(value)
          return {} unless value.respond_to?(:each)

          value.each_with_object({}) do |(key, price), result|
            result[key.to_s] = decimal(price, 0.0)
          end
        end

        def value_for(values, key)
          return nil unless values.respond_to?(:[])
          return values[key] if values.respond_to?(:key?) && values.key?(key)
          return values[key.to_s] if values.respond_to?(:key?) && values.key?(key.to_s)

          nil
        end

        def decimal(value, fallback)
          return fallback if value.nil? || value.to_s.strip.empty?

          Float(value)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
