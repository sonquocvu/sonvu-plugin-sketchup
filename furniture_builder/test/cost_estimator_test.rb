# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../cost_estimator'

module SonVu
  module CNCPlugins
    module FurnitureBuilder
      class CostEstimatorTest < Minitest::Test
        def test_calculates_material_waste_edge_hardware_and_project_totals
          estimate = CostEstimator.calculate(sample_report, sample_catalog)
          board = estimate[:board_rows].first
          hardware = estimate[:hardware_rows].first

          assert_in_delta 1.0, board[:net_area_m2], 0.0001
          assert_in_delta 1.1, board[:billable_area_m2], 0.0001
          assert_in_delta 220_000, board[:material_cost], 0.001
          assert_in_delta 4.0, board[:edge_length_m], 0.0001
          assert_in_delta 20_000, board[:edge_cost], 0.001
          assert_in_delta 240_000, board[:total_cost], 0.001
          assert_in_delta 120_000, hardware[:hardware_cost], 0.001
          assert_in_delta 360_000, estimate[:project_total], 0.001
        end

        def test_allocates_aggregated_cost_back_to_each_cabinet_occurrence
          estimate = CostEstimator.calculate(sample_report, sample_catalog)

          assert_equal 2, estimate[:cabinet_totals].length
          assert_equal %w[Tủ-A Tủ-B], estimate[:cabinet_totals].map { |item| item[:cabinet_name] }
          estimate[:cabinet_totals].each do |cabinet|
            assert_in_delta 180_000, cabinet[:total_cost], 0.001
          end
          assert_in_delta estimate[:project_total],
                          estimate[:cabinet_totals].sum { |item| item[:total_cost] }, 0.001
        end

        def test_default_catalog_contains_every_report_material_and_hardware_type
          catalog = CostEstimator.default_catalog(sample_report)

          assert_equal 10.0, catalog[:waste_percent]
          assert_equal 0.0, catalog[:edge_band_price_per_m]
          assert_equal({ 'MDF 18' => 0.0 }, catalog[:material_prices])
          assert_equal({ 'Bản lề chén' => 0.0 }, catalog[:hardware_prices])
        end

        def test_edge_length_uses_long_edges_and_short_edges_once_each
          row = sample_report[:board_rows].first.merge(
            quantity: 1,
            edge_front: true,
            edge_back: false,
            edge_left: true,
            edge_right: false
          )

          assert_in_delta 1.5, CostEstimator.edge_length_m(row), 0.0001
        end

        def test_rejects_invalid_or_negative_catalog_values_in_vietnamese
          invalid = sample_catalog.merge(waste_percent: 'không phải số')
          negative = sample_catalog.merge(edge_band_price_per_m: -1)
          excessive = sample_catalog.merge(waste_percent: 101)
          infinite = sample_catalog.merge(material_prices: { 'MDF 18' => 'Infinity' })

          assert_raises(ArgumentError) { CostEstimator.calculate(sample_report, invalid) }
          assert_match(/không được âm/i, assert_raises(ArgumentError) {
            CostEstimator.calculate(sample_report, negative)
          }.message)
          assert_match(/0 đến 100%/i, assert_raises(ArgumentError) {
            CostEstimator.calculate(sample_report, excessive)
          }.message)
          assert_match(/số hợp lệ/i, assert_raises(ArgumentError) {
            CostEstimator.calculate(sample_report, infinite)
          }.message)
        end

        private

        def sample_catalog
          {
            waste_percent: 10,
            edge_band_price_per_m: 5000,
            material_prices: { 'MDF 18' => 200_000 },
            hardware_prices: { 'Bản lề chén' => 30_000 }
          }
        end

        def sample_report
          {
            board_rows: [
              {
                category: 'Thùng tủ', name: 'Hông trái / Hông phải', quantity: 2,
                length_mm: 1000, width_mm: 500, thickness_mm: 18,
                material_name: 'MDF 18', grain_direction: 'dọc',
                edge_front: true, edge_back: true, edge_left: false, edge_right: false,
                cabinet_names: %w[Tủ-A Tủ-B], cabinet_ids: %w[a b],
                cabinet_breakdown: [
                  { occurrence_key: 'a#1', cabinet_id: 'a', cabinet_name: 'Tủ-A', quantity: 1 },
                  { occurrence_key: 'b#2', cabinet_id: 'b', cabinet_name: 'Tủ-B', quantity: 1 }
                ]
              }
            ],
            hardware_rows: [
              {
                name: 'Bản lề chén', quantity: 4,
                length_mm: 35, width_mm: 35, thickness_mm: 12,
                material_name: 'Phụ kiện kim khí',
                cabinet_names: %w[Tủ-A Tủ-B], cabinet_ids: %w[a b],
                cabinet_breakdown: [
                  { occurrence_key: 'a#1', cabinet_id: 'a', cabinet_name: 'Tủ-A', quantity: 2 },
                  { occurrence_key: 'b#2', cabinet_id: 'b', cabinet_name: 'Tủ-B', quantity: 2 }
                ]
              }
            ]
          }
        end
      end
    end
  end
end
