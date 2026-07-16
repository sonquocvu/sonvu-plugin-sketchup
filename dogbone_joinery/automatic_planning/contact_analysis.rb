# frozen_string_literal: true

# Actual planar face overlap detection, contact classification, assignment, and
# orchestration of the pure automatic preview plan.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        module Polygon2
          EPSILON = 1.0e-9

          module_function

          def signed_area(polygon)
            return 0.0 if polygon.length < 3

            polygon.each_with_index.inject(0.0) do |sum, (point, index)|
              following = polygon[(index + 1) % polygon.length]
              sum + ((point[0] * following[1]) - (following[0] * point[1]))
            end / 2.0
          end

          def area(polygon)
            signed_area(polygon).abs
          end

          def centroid(polygon)
            polygon_area = signed_area(polygon)
            return average_point(polygon) if polygon_area.abs <= EPSILON

            factor_sum_x = 0.0
            factor_sum_y = 0.0
            polygon.each_with_index do |point, index|
              following = polygon[(index + 1) % polygon.length]
              factor = (point[0] * following[1]) - (following[0] * point[1])
              factor_sum_x += (point[0] + following[0]) * factor
              factor_sum_y += (point[1] + following[1]) * factor
            end
            divisor = 6.0 * polygon_area
            [factor_sum_x / divisor, factor_sum_y / divisor]
          end

          def triangulate(input, tolerance = EPSILON)
            polygon = normalize(input, tolerance)
            return [] if polygon.length < 3
            polygon = polygon.reverse if signed_area(polygon).negative?
            return [polygon] if polygon.length == 3

            remaining = polygon.dup
            triangles = []
            guard = polygon.length * polygon.length
            while remaining.length > 3 && guard.positive?
              ear_index = find_ear(remaining, tolerance)
              break unless ear_index

              previous = remaining[(ear_index - 1) % remaining.length]
              current = remaining[ear_index]
              following = remaining[(ear_index + 1) % remaining.length]
              triangles << [previous, current, following]
              remaining.delete_at(ear_index)
              guard -= 1
            end
            triangles << remaining if remaining.length == 3
            return triangles if triangles.length == polygon.length - 2

            # Degenerate imported loops can defeat ear clipping. The fan keeps
            # the adapter usable for convex faces while the diagnostic layer
            # still rejects zero-area intersections.
            (1...(polygon.length - 1)).map { |index| [polygon[0], polygon[index], polygon[index + 1]] }
          end

          def intersect_polygons(first, second, tolerance = EPSILON)
            intersections = []
            triangulate(first, tolerance).each do |first_triangle|
              triangulate(second, tolerance).each do |second_triangle|
                polygon = intersect_convex(first_triangle, second_triangle, tolerance)
                intersections << polygon if area(polygon) > EPSILON
              end
            end
            intersections
          end

          def intersect_convex(subject, clip, tolerance = EPSILON)
            output = normalize(subject, tolerance)
            clip_polygon = normalize(clip, tolerance)
            clip_polygon = clip_polygon.reverse if signed_area(clip_polygon).negative?
            clip_polygon.each_with_index do |clip_start, index|
              clip_end = clip_polygon[(index + 1) % clip_polygon.length]
              input = output
              output = []
              break if input.empty?

              segment_start = input.last
              input.each do |segment_end|
                end_inside = inside_half_plane?(segment_end, clip_start, clip_end, tolerance)
                start_inside = inside_half_plane?(segment_start, clip_start, clip_end, tolerance)
                if end_inside
                  output << line_intersection(segment_start, segment_end, clip_start, clip_end) unless start_inside
                  output << segment_end
                elsif start_inside
                  output << line_intersection(segment_start, segment_end, clip_start, clip_end)
                end
                segment_start = segment_end
              end
              output = normalize(output.compact, tolerance)
            end
            output
          end

          def touch_dimension(first, second, tolerance)
            points = []
            overlapping_length = false
            polygon_segments(first).each do |first_start, first_end|
              polygon_segments(second).each do |second_start, second_end|
                intersections, overlap = segment_intersections(
                  first_start, first_end, second_start, second_end, tolerance
                )
                points.concat(intersections)
                overlapping_length ||= overlap
              end
            end
            return :line if overlapping_length

            if points.empty?
              points << first.first if point_in_polygon?(first.first, second, tolerance)
              points << second.first if point_in_polygon?(second.first, first, tolerance)
            end
            points.empty? ? :none : :point
          end

          def point_in_polygon?(point, polygon, tolerance = EPSILON)
            return true if polygon_segments(polygon).any? { |start_point, end_point| point_segment_distance(point, start_point, end_point) <= tolerance }

            inside = false
            previous = polygon.last
            polygon.each do |current|
              crosses = ((current[1] > point[1]) != (previous[1] > point[1])) &&
                        (point[0] < ((previous[0] - current[0]) * (point[1] - current[1]) /
                          (previous[1] - current[1]).to_f) + current[0])
              inside = !inside if crosses
              previous = current
            end
            inside
          end

          def point_segment_distance(point, start_point, end_point)
            delta_x = end_point[0] - start_point[0]
            delta_y = end_point[1] - start_point[1]
            length_squared = (delta_x * delta_x) + (delta_y * delta_y)
            return distance(point, start_point) if length_squared <= EPSILON

            parameter = (((point[0] - start_point[0]) * delta_x) +
              ((point[1] - start_point[1]) * delta_y)) / length_squared
            parameter = [[parameter, 0.0].max, 1.0].min
            closest = [start_point[0] + (parameter * delta_x), start_point[1] + (parameter * delta_y)]
            distance(point, closest)
          end

          def normalize(points, tolerance)
            result = []
            points.each do |point|
              copy = [point[0].to_f, point[1].to_f]
              result << copy unless result.last && distance(result.last, copy) <= tolerance
            end
            result.pop if result.length > 1 && distance(result.first, result.last) <= tolerance
            result
          end

          def polygon_segments(polygon)
            polygon.each_with_index.map { |point, index| [point, polygon[(index + 1) % polygon.length]] }
          end

          def find_ear(polygon, tolerance)
            polygon.each_index.find do |index|
              previous = polygon[(index - 1) % polygon.length]
              current = polygon[index]
              following = polygon[(index + 1) % polygon.length]
              next false if cross(previous, current, following) <= tolerance

              triangle = [previous, current, following]
              polygon.each_with_index.none? do |point, point_index|
                next false if [index, (index - 1) % polygon.length, (index + 1) % polygon.length].include?(point_index)

                point_in_triangle?(point, triangle, tolerance)
              end
            end
          end

          def point_in_triangle?(point, triangle, tolerance)
            values = [
              cross(triangle[0], triangle[1], point),
              cross(triangle[1], triangle[2], point),
              cross(triangle[2], triangle[0], point)
            ]
            values.all? { |value| value >= -tolerance }
          end

          def inside_half_plane?(point, edge_start, edge_end, tolerance)
            cross(edge_start, edge_end, point) >= -tolerance
          end

          def line_intersection(segment_start, segment_end, line_start, line_end)
            start_distance = cross(line_start, line_end, segment_start)
            end_distance = cross(line_start, line_end, segment_end)
            divisor = start_distance - end_distance
            return segment_end if divisor.abs <= EPSILON

            parameter = start_distance / divisor
            [
              segment_start[0] + ((segment_end[0] - segment_start[0]) * parameter),
              segment_start[1] + ((segment_end[1] - segment_start[1]) * parameter)
            ]
          end

          def segment_intersections(first_start, first_end, second_start, second_end, tolerance)
            first_delta = [first_end[0] - first_start[0], first_end[1] - first_start[1]]
            second_delta = [second_end[0] - second_start[0], second_end[1] - second_start[1]]
            denominator = cross_vectors(first_delta, second_delta)
            offset = [second_start[0] - first_start[0], second_start[1] - first_start[1]]
            if denominator.abs <= tolerance
              return [[], false] if cross_vectors(offset, first_delta).abs > tolerance

              candidates = [first_start, first_end, second_start, second_end].select do |point|
                point_segment_distance(point, first_start, first_end) <= tolerance &&
                  point_segment_distance(point, second_start, second_end) <= tolerance
              end
              unique = unique_points(candidates, tolerance)
              overlap = unique.combination(2).any? { |first, second| distance(first, second) > tolerance }
              return [unique, overlap]
            end

            first_parameter = cross_vectors(offset, second_delta) / denominator
            second_parameter = cross_vectors(offset, first_delta) / denominator
            return [[], false] unless first_parameter >= -tolerance && first_parameter <= 1.0 + tolerance &&
              second_parameter >= -tolerance && second_parameter <= 1.0 + tolerance

            point = [
              first_start[0] + (first_parameter * first_delta[0]),
              first_start[1] + (first_parameter * first_delta[1])
            ]
            [[point], false]
          end

          def unique_points(points, tolerance)
            points.each_with_object([]) do |point, result|
              result << point unless result.any? { |existing| distance(existing, point) <= tolerance }
            end
          end

          def cross(first, second, third)
            ((second[0] - first[0]) * (third[1] - first[1])) -
              ((second[1] - first[1]) * (third[0] - first[0]))
          end

          def cross_vectors(first, second)
            (first[0] * second[1]) - (first[1] * second[0])
          end

          def distance(first, second)
            Math.sqrt(((first[0] - second[0])**2) + ((first[1] - second[1])**2))
          end

          def average_point(points)
            return [0.0, 0.0] if points.empty?

            [points.map { |point| point[0] }.sum / points.length.to_f,
             points.map { |point| point[1] }.sum / points.length.to_f]
          end
        end

        class ContactRegionBounds
          attr_reader :origin, :axis, :cross_axis, :axis_min, :axis_max,
                      :cross_min, :cross_max, :centroid_cross, :vertices, :area

          def initialize(origin:, axis:, cross_axis:, axis_min:, axis_max:, cross_min:, cross_max:,
                         centroid_cross:, vertices:, area:)
            @origin = origin
            @axis = axis
            @cross_axis = cross_axis
            @axis_min = axis_min
            @axis_max = axis_max
            @cross_min = cross_min
            @cross_max = cross_max
            @centroid_cross = centroid_cross
            @vertices = vertices.freeze
            @area = area
            freeze
          end

          def length
            axis_max - axis_min
          end

          def width
            cross_max - cross_min
          end

          def point_at_axis(value)
            origin + (axis * value) + (cross_axis * centroid_cross)
          end

          def to_h
            {
              origin: origin.to_h,
              axis: axis.to_h,
              cross_axis: cross_axis.to_h,
              axis_min: axis_min,
              axis_max: axis_max,
              cross_min: cross_min,
              cross_max: cross_max,
              length: length,
              width: width,
              area: area,
              vertices: vertices.map(&:to_h)
            }
          end
        end

        class ContactRegion
          attr_reader :plane, :polygons, :area, :centroid, :bounds

          def self.from_faces(first_face, second_face, tolerance)
            plane = first_face.plane
            basis_u, basis_v = plane.basis
            project = lambda do |point|
              offset = point - plane.origin
              [offset.dot(basis_u), offset.dot(basis_v)]
            end
            first_polygon = first_face.vertices.map { |point| project.call(point) }
            second_polygon = second_face.vertices.map { |point| project.call(point) }
            intersection_tolerance = [tolerance * 0.001, Polygon2::EPSILON].max
            intersections = Polygon2.intersect_polygons(
              first_polygon,
              second_polygon,
              intersection_tolerance
            )
            return nil if intersections.empty?

            axis_candidates = [first_face, second_face].flat_map do |face|
              face.vertices.each_with_index.map do |point, index|
                vector = face.vertices[(index + 1) % face.vertices.length] - point
                vector.length > tolerance ? vector.normalized.canonical : nil
              end
            end.compact

            polygons3 = intersections.map do |polygon|
              polygon.map do |point|
                plane.origin + (basis_u * point[0]) + (basis_v * point[1])
              end
            end
            new(
              plane: plane,
              polygons: polygons3,
              tolerance: tolerance,
              axis_candidates: axis_candidates
            )
          end

          def initialize(plane:, polygons:, tolerance:, axis_candidates: [])
            @plane = plane
            @polygons = polygons.map(&:freeze).freeze
            basis_u, basis_v = plane.basis
            polygon_data = @polygons.map do |polygon|
              points2 = polygon.map do |point|
                offset = point - plane.origin
                [offset.dot(basis_u), offset.dot(basis_v)]
              end
              [Polygon2.area(points2), Polygon2.centroid(points2)]
            end
            @area = polygon_data.map(&:first).sum
            centroid_u = polygon_data.sum { |item| item[0] * item[1][0] } / @area
            centroid_v = polygon_data.sum { |item| item[0] * item[1][1] } / @area
            @centroid = plane.origin + (basis_u * centroid_u) + (basis_v * centroid_v)
            all_points = unique_points(@polygons.flatten, tolerance)
            axis = longest_axis(axis_candidates, all_points)
            cross_axis = plane.normal.cross(axis).normalized
            axis_values = all_points.map { |point| (point - plane.origin).dot(axis) }
            cross_values = all_points.map { |point| (point - plane.origin).dot(cross_axis) }
            @bounds = ContactRegionBounds.new(
              origin: plane.origin,
              axis: axis,
              cross_axis: cross_axis,
              axis_min: axis_values.min,
              axis_max: axis_values.max,
              cross_min: cross_values.min,
              cross_max: cross_values.max,
              centroid_cross: (centroid - plane.origin).dot(cross_axis),
              vertices: all_points,
              area: @area
            )
            freeze
          end

          def fingerprint(first_part_id, second_part_id, tolerance)
            scale = tolerance.positive? ? tolerance : 1.0e-6
            center_key = centroid.to_a.map { |value| (value / scale).round }
            normal_key = plane.normal.to_a.map { |value| (value * 1_000_000).round }
            ([first_part_id.to_s, second_part_id.to_s].sort + center_key + normal_key).join('|')
          end

          private

          def unique_points(points, tolerance)
            points.each_with_object([]) do |point, result|
              result << point unless result.any? { |existing| existing.almost_equal?(point, tolerance) }
            end
          end

          def longest_axis(axis_candidates, points)
            candidates = axis_candidates
            candidates = plane.basis if candidates.empty?
            candidates.max_by do |candidate|
              projections = points.map { |point| (point - plane.origin).dot(candidate) }
              projections.max - projections.min
            end.canonical
          end
        end

        class ContactDetection
          attr_reader :first_board, :second_board, :first_face, :second_face,
                      :edge_face, :broad_face, :region, :validation

          def initialize(first_board:, second_board:, first_face:, second_face:, validation:,
                         edge_face: nil, broad_face: nil, region: nil)
            @first_board = first_board
            @second_board = second_board
            @first_face = first_face
            @second_face = second_face
            @edge_face = edge_face
            @broad_face = broad_face
            @region = region
            @validation = validation
            freeze
          end

          def valid?
            validation.valid?
          end
        end

        class BroadPhaseCandidatePairFinder
          def find(board_descriptors, tolerance)
            unique = {}
            board_descriptors.each { |board| unique[board.identity.stable_id] ||= board }
            boards = unique.values
            pairs = []
            boards.each_with_index do |first, index|
              boards[(index + 1)..-1].to_a.each do |second|
                pairs << [first, second] if first.bounds.overlaps?(second.bounds, tolerance)
              end
            end
            pairs
          end
        end

        class ContactDetector
          def initialize(tolerance)
            @tolerance = tolerance.to_f.positive? ? tolerance.to_f : 1.0e-6
          end

          def detect_all(first_board, second_board)
            positive_area = []
            touch_states = []
            first_board.faces.each do |first_face|
              second_board.faces.each do |second_face|
                next unless first_face.bounds.overlaps?(second_face.bounds, @tolerance)
                next unless first_face.plane.coplanar?(second_face.plane, @tolerance)

                region = ContactRegion.from_faces(first_face, second_face, @tolerance)
                if region
                  positive_area << detection_for_region(
                    first_board, second_board, first_face, second_face, region
                  )
                else
                  touch = coplanar_touch(first_face, second_face)
                  touch_states << [touch, first_face, second_face] unless touch == :none
                end
              end
            end

            valid = positive_area.select(&:valid?)
            return valid unless valid.empty?
            return [preferred_rejection(positive_area)] unless positive_area.empty?
            return [touch_detection(first_board, second_board, touch_states)] unless touch_states.empty?

            [ContactDetection.new(
              first_board: first_board,
              second_board: second_board,
              first_face: nil,
              second_face: nil,
              validation: ValidationResult.new(ValidationResult::NO_CONTACT)
            )]
          end

          private

          def detection_for_region(first_board, second_board, first_face, second_face, region)
            edge_face, broad_face = edge_and_broad(first_face, second_face)
            validation = if region.area <= @tolerance * @tolerance
                           ValidationResult.new(ValidationResult::CONTACT_AREA_TOO_SMALL, area: region.area)
                         elsif edge_face && broad_face
                           ValidationResult.valid(area: region.area)
                         else
                           ValidationResult.new(
                             ValidationResult::UNSUPPORTED_CONTACT_TYPE,
                             first_face_kind: first_face.kind,
                             second_face_kind: second_face.kind,
                             area: region.area
                           )
                         end
            ContactDetection.new(
              first_board: first_board,
              second_board: second_board,
              first_face: first_face,
              second_face: second_face,
              edge_face: edge_face,
              broad_face: broad_face,
              region: region,
              validation: validation
            )
          end

          def edge_and_broad(first_face, second_face)
            return [first_face, second_face] if first_face.edge_face? && second_face.broad_face?
            return [second_face, first_face] if second_face.edge_face? && first_face.broad_face?

            [nil, nil]
          end

          def coplanar_touch(first_face, second_face)
            plane = first_face.plane
            basis_u, basis_v = plane.basis
            convert = lambda do |point|
              offset = point - plane.origin
              [offset.dot(basis_u), offset.dot(basis_v)]
            end
            Polygon2.touch_dimension(
              first_face.vertices.map { |point| convert.call(point) },
              second_face.vertices.map { |point| convert.call(point) },
              @tolerance
            )
          end

          def preferred_rejection(detections)
            detections.find { |detection| detection.validation.code == ValidationResult::UNSUPPORTED_CONTACT_TYPE } || detections.first
          end

          def touch_detection(first_board, second_board, touch_states)
            state, first_face, second_face = touch_states.find { |item| item[0] == :line } || touch_states.first
            code = state == :line ? ValidationResult::LINE_ONLY_CONTACT : ValidationResult::POINT_ONLY_CONTACT
            ContactDetection.new(
              first_board: first_board,
              second_board: second_board,
              first_face: first_face,
              second_face: second_face,
              validation: ValidationResult.new(code)
            )
          end
        end

        class ContactClassifier
          def initialize(tolerance)
            @tolerance = tolerance
          end

          def classify(detection, male_board, female_board)
            roles = [male_board.identity.role_metadata, female_board.identity.role_metadata].compact.map(&:to_s)
            return 'back_joint' if roles.include?('back')

            broad_face = detection.broad_face
            region = detection.region
            plane = broad_face.plane
            basis_u, basis_v = plane.basis
            project = lambda do |point|
              offset = point - plane.origin
              [offset.dot(basis_u), offset.dot(basis_v)]
            end
            broad_polygon = broad_face.vertices.map { |point| project.call(point) }
            region_points = region.bounds.vertices.map { |point| project.call(point) }
            on_boundary = region_points.any? do |point|
              Polygon2.polygon_segments(broad_polygon).any? do |start_point, end_point|
                Polygon2.point_segment_distance(point, start_point, end_point) <= @tolerance
              end
            end
            return 'l_joint' if on_boundary

            return 't_joint' if region_points.all? { |point| Polygon2.point_in_polygon?(point, broad_polygon, @tolerance) }

            'edge_to_face'
          end
        end

        class AssignmentResolver
          SIDE_ROLES = %w[side_left side_right].freeze
          SIDE_MALE_ROLES = %w[bottom top shelf].freeze
          DIVIDER_RECEIVER_ROLES = %w[bottom top].freeze

          def resolve(detection)
            boards = [detection.first_board, detection.second_board]
            male = boards.find { |board| board.identity == detection.edge_face.board_identity }
            female = boards.find { |board| board.identity == detection.broad_face.board_identity }
            suggestion = role_suggestion(male, female, boards)
            {
              male_board: male,
              female_board: female,
              assignment_source: 'geometry',
              role_assignment_suggestion: suggestion
            }
          end

          private

          def role_suggestion(geometry_male, geometry_female, boards)
            first = boards[0]
            second = boards[1]
            first_role = first.identity.role_metadata.to_s
            second_role = second.identity.role_metadata.to_s
            suggested = suggested_pair(first, first_role, second, second_role)
            return nil unless suggested

            male, female, reason = suggested
            RoleAssignmentSuggestion.new(
              male_part_identity: male.identity,
              female_part_identity: female.identity,
              reason: reason,
              conflicts_with_geometry: male.identity != geometry_male.identity ||
                female.identity != geometry_female.identity
            )
          end

          def suggested_pair(first, first_role, second, second_role)
            if first_role == 'back' && second_role != 'back'
              return [second, first, 'back_receives_mortise']
            end
            if second_role == 'back' && first_role != 'back'
              return [first, second, 'back_receives_mortise']
            end
            if SIDE_ROLES.include?(first_role) && SIDE_MALE_ROLES.include?(second_role)
              return [second, first, 'side_receives_mortise']
            end
            if SIDE_ROLES.include?(second_role) && SIDE_MALE_ROLES.include?(first_role)
              return [first, second, 'side_receives_mortise']
            end
            if first_role == 'divider' && DIVIDER_RECEIVER_ROLES.include?(second_role)
              return [first, second, 'divider_uses_tenon']
            end
            if second_role == 'divider' && DIVIDER_RECEIVER_ROLES.include?(first_role)
              return [second, first, 'divider_uses_tenon']
            end

            nil
          end
        end

        class ConnectionPlanner
          def initialize(tolerance)
            @tolerance = tolerance
            @classifier = ContactClassifier.new(tolerance)
            @assignment_resolver = AssignmentResolver.new
            @layout_calculator = JointLayoutCalculator.new
            @dimension_resolver = JointDimensionResolver.new
          end

          def plan(detection, specification)
            assignment = @assignment_resolver.resolve(detection)
            male = assignment[:male_board]
            female = assignment[:female_board]
            region = detection.region
            male_inward = inward_direction(male, region, -region.plane.normal)
            female_inward = inward_direction(female, region, region.plane.normal)
            insertion_direction = female_inward
            contact_direction = direction_between(male.center, female.center, insertion_direction)
            type = @classifier.classify(detection, male, female)
            calculation = @layout_calculator.calculate(
              contact_length: region.bounds.length,
              axis_min: region.bounds.axis_min,
              specification: specification
            )
            dimensions = @dimension_resolver.resolve(
              male_board: male,
              female_board: female,
              contact_bounds: region.bounds,
              specification: specification
            )
            validation = calculation.valid? ? dimensions.validation : calculation.validation
            connection_id = stable_connection_id(detection, region)
            joints = build_joints(
              connection_id,
              calculation,
              dimensions,
              validation,
              region.bounds,
              insertion_direction
            )
            ConnectionPlan.new(
              stable_id: connection_id,
              first_part_identity: detection.first_board.identity,
              second_part_identity: detection.second_board.identity,
              male_part_identity: male.identity,
              female_part_identity: female.identity,
              assignment_source: assignment[:assignment_source],
              reversible: safely_reversible?(male, female, region.bounds, specification),
              connection_type: type,
              contact_plane: region.plane,
              contact_region_bounds: region.bounds,
              contact_direction: contact_direction,
              usable_joint_axis: region.bounds.axis,
              male_inward_direction: male_inward,
              female_inward_direction: female_inward,
              tenon_inward_direction: insertion_direction,
              mortise_inward_direction: insertion_direction,
              contact_length: region.bounds.length,
              male_board_thickness: male.thickness,
              female_board_thickness: female.thickness,
              requested_settings: specification,
              calculated_settings: calculation,
              validation: validation,
              joint_instances: joints,
              enabled: validation.valid?,
              user_override_state: 'none',
              role_assignment_suggestion: assignment[:role_assignment_suggestion]
            )
          end

          private

          def build_joints(connection_id, calculation, dimensions, validation, bounds, insertion_direction)
            return [] unless validation.valid?

            calculation.axis_centers.each_with_index.map do |axis_center, index|
              center = bounds.point_at_axis(axis_center)
              start_point = bounds.point_at_axis(calculation.axis_starts[index])
              end_point = bounds.point_at_axis(calculation.axis_ends[index])
              JointInstancePlan.new(
                stable_id: "#{connection_id}:joint:#{index + 1}",
                index: index,
                center_position: center,
                start_position: start_point,
                end_position: end_point,
                joint_length: dimensions.joint_length,
                detected_male_board_thickness: dimensions.detected_male_board_thickness,
                tenon_thickness: dimensions.tenon_thickness,
                mortise_opening_thickness: dimensions.mortise_opening_thickness,
                fit_clearance: dimensions.fit_clearance,
                tenon_height: dimensions.tenon_height,
                mortise_depth: dimensions.mortise_depth,
                cutter_radius: dimensions.cutter_radius,
                thickness_axis: dimensions.thickness_axis,
                male_placement: PlacementData.for_male(center, bounds.axis, insertion_direction),
                female_placement: PlacementData.for_female(center, bounds.axis, insertion_direction),
                enabled: true
              )
            end
          end

          def inward_direction(board, region, fallback)
            direction = board.center - region.centroid
            normal_component = region.plane.normal * direction.dot(region.plane.normal)
            normal_component.length > @tolerance ? normal_component.normalized : fallback.normalized
          end

          def direction_between(first, second, fallback)
            direction = second - first
            direction.length > @tolerance ? direction.normalized : fallback
          end

          def stable_connection_id(detection, region)
            "connection:#{region.fingerprint(
              detection.first_board.identity.stable_id,
              detection.second_board.identity.stable_id,
              @tolerance
            )}"
          end

          def safely_reversible?(current_male_board, current_female_board, contact_bounds, specification)
            new_male_board = current_female_board
            new_female_board = current_male_board
            return false if new_male_board.thickness_ambiguous || new_male_board.thickness.nil?
            return false if new_female_board.thickness_ambiguous || new_female_board.thickness.nil?
            return false unless ValueSupport.finite_number?(new_male_board.thickness)
            return false unless ValueSupport.finite_number?(new_female_board.thickness)
            return false unless ValueSupport.finite_number?(specification.fit_clearance)
            return false unless ValueSupport.finite_number?(specification.mortise_depth)

            new_male_board.thickness.to_f > specification.fit_clearance.to_f + @tolerance &&
              new_male_board.thickness.to_f <= contact_bounds.width.to_f + @tolerance &&
              specification.mortise_depth.to_f <= new_female_board.thickness.to_f + @tolerance
          end
        end

        class Analyzer
          def initialize(pair_finder: BroadPhaseCandidatePairFinder.new)
            @pair_finder = pair_finder
          end

          def analyze(board_descriptors, specification)
            tolerance = specification.geometric_tolerance.to_f
            tolerance = 1.0e-6 unless tolerance.positive?
            detector = ContactDetector.new(tolerance)
            planner = ConnectionPlanner.new(tolerance)
            connections = []
            diagnostics = []
            seen = {}
            @pair_finder.find(board_descriptors, tolerance).each do |first, second|
              detections = detector.detect_all(first, second)
              valid_detections = detections.select(&:valid?)
              if valid_detections.empty?
                rejection = detections.first
                diagnostics << diagnostic_for(first, second, rejection.validation)
                next
              end

              valid_detections.each do |detection|
                fingerprint = detection.region.fingerprint(
                  first.identity.stable_id,
                  second.identity.stable_id,
                  tolerance
                )
                if seen[fingerprint]
                  diagnostics << diagnostic_for(
                    first,
                    second,
                    ValidationResult.new(ValidationResult::DUPLICATE_CONNECTION)
                  )
                  next
                end

                seen[fingerprint] = true
                connections << planner.plan(detection, specification)
              end
            end
            PreviewPlan.new(connections: connections, diagnostics: diagnostics)
          end

          private

          def diagnostic_for(first, second, validation)
            AnalysisDiagnostic.new(
              first_part_id: first.identity.stable_id,
              second_part_id: second.identity.stable_id,
              validation: validation
            )
          end
        end
      end
    end
  end
end
