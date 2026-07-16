# frozen_string_literal: true

# SketchUp-free world-space geometry values used by automatic joint analysis.

module SonVu
  module CNCPlugins
    module DogboneJoinery
      module AutomaticPlanning
        module ValueSupport
          module_function

          def finite_number?(value)
            value.is_a?(Numeric) && (!value.respond_to?(:finite?) || value.finite?)
          end

          def freeze_hash(hash)
            hash.each_with_object({}) do |(key, value), copy|
              copy[key] = freeze_value(value)
            end.freeze
          end

          def freeze_value(value)
            case value
            when Hash
              freeze_hash(value)
            when Array
              value.map { |item| freeze_value(item) }.freeze
            else
              value.frozen? ? value : value.freeze
            end
          end
        end

        class Vector3
          EPSILON = 1.0e-9

          attr_reader :x, :y, :z

          def initialize(x, y, z)
            values = [x, y, z]
            raise ArgumentError, 'Tọa độ véc-tơ phải là số hữu hạn.' unless values.all? { |value| ValueSupport.finite_number?(value) }

            @x = x.to_f
            @y = y.to_f
            @z = z.to_f
            freeze
          end

          def +(other)
            Vector3.new(x + other.x, y + other.y, z + other.z)
          end

          def -(other)
            Vector3.new(x - other.x, y - other.y, z - other.z)
          end

          def -@
            Vector3.new(-x, -y, -z)
          end

          def *(scalar)
            Vector3.new(x * scalar, y * scalar, z * scalar)
          end

          def /(scalar)
            raise ArgumentError, 'Không thể chia véc-tơ cho 0.' if scalar.to_f.abs <= EPSILON

            self * (1.0 / scalar.to_f)
          end

          def dot(other)
            (x * other.x) + (y * other.y) + (z * other.z)
          end

          def cross(other)
            Vector3.new(
              (y * other.z) - (z * other.y),
              (z * other.x) - (x * other.z),
              (x * other.y) - (y * other.x)
            )
          end

          def length
            Math.sqrt(dot(self))
          end

          def normalized
            magnitude = length
            raise ArgumentError, 'Không thể chuẩn hóa véc-tơ có độ dài bằng 0.' if magnitude <= EPSILON

            self / magnitude
          end

          def parallel?(other, tolerance = 1.0e-6)
            normalized.cross(other.normalized).length <= tolerance
          rescue ArgumentError
            false
          end

          def perpendicular?(other, tolerance = 1.0e-6)
            normalized.dot(other.normalized).abs <= tolerance
          rescue ArgumentError
            false
          end

          def canonical
            components = [x, y, z]
            first = components.find { |value| value.abs > EPSILON }
            first && first.negative? ? -self : self
          end

          def almost_equal?(other, tolerance = 1.0e-6)
            (x - other.x).abs <= tolerance &&
              (y - other.y).abs <= tolerance &&
              (z - other.z).abs <= tolerance
          end

          def to_a
            [x, y, z]
          end

          def to_h
            { x: x, y: y, z: z }
          end

          def ==(other)
            other.is_a?(Vector3) && x == other.x && y == other.y && z == other.z
          end

          alias eql? ==

          def hash
            [x, y, z].hash
          end
        end

        class Point3
          attr_reader :x, :y, :z

          def initialize(x, y, z)
            values = [x, y, z]
            raise ArgumentError, 'Tọa độ điểm phải là số hữu hạn.' unless values.all? { |value| ValueSupport.finite_number?(value) }

            @x = x.to_f
            @y = y.to_f
            @z = z.to_f
            freeze
          end

          def +(vector)
            Point3.new(x + vector.x, y + vector.y, z + vector.z)
          end

          def -(other)
            if other.is_a?(Point3)
              Vector3.new(x - other.x, y - other.y, z - other.z)
            else
              Point3.new(x - other.x, y - other.y, z - other.z)
            end
          end

          def distance(other)
            (self - other).length
          end

          def almost_equal?(other, tolerance = 1.0e-6)
            distance(other) <= tolerance
          end

          def to_a
            [x, y, z]
          end

          def to_h
            { x: x, y: y, z: z }
          end

          def ==(other)
            other.is_a?(Point3) && x == other.x && y == other.y && z == other.z
          end

          alias eql? ==

          def hash
            [x, y, z].hash
          end
        end

        class Transform3
          attr_reader :values

          def self.identity
            new([
              1, 0, 0, 0,
              0, 1, 0, 0,
              0, 0, 1, 0,
              0, 0, 0, 1
            ])
          end

          def self.translation(x, y, z)
            new([
              1, 0, 0, 0,
              0, 1, 0, 0,
              0, 0, 1, 0,
              x, y, z, 1
            ])
          end

          def self.rotation(axis, angle_radians)
            unit = axis.normalized
            cosine = Math.cos(angle_radians)
            sine = Math.sin(angle_radians)
            one_minus = 1.0 - cosine
            x = unit.x
            y = unit.y
            z = unit.z
            new([
              cosine + (x * x * one_minus),
              (y * x * one_minus) + (z * sine),
              (z * x * one_minus) - (y * sine),
              0,
              (x * y * one_minus) - (z * sine),
              cosine + (y * y * one_minus),
              (z * y * one_minus) + (x * sine),
              0,
              (x * z * one_minus) + (y * sine),
              (y * z * one_minus) - (x * sine),
              cosine + (z * z * one_minus),
              0,
              0, 0, 0, 1
            ])
          end

          def self.from_sketchup(transformation)
            return identity unless transformation
            return transformation if transformation.is_a?(Transform3)

            new(transformation.to_a)
          end

          def initialize(values)
            raise ArgumentError, 'Ma trận biến đổi phải có 16 phần tử.' unless values && values.length == 16
            raise ArgumentError, 'Ma trận biến đổi phải chứa số hữu hạn.' unless values.all? { |value| ValueSupport.finite_number?(value) }

            @values = values.map(&:to_f).freeze
            freeze
          end

          def apply_point(point)
            Point3.new(
              (values[0] * point.x) + (values[4] * point.y) + (values[8] * point.z) + values[12],
              (values[1] * point.x) + (values[5] * point.y) + (values[9] * point.z) + values[13],
              (values[2] * point.x) + (values[6] * point.y) + (values[10] * point.z) + values[14]
            )
          end

          def apply_vector(vector)
            Vector3.new(
              (values[0] * vector.x) + (values[4] * vector.y) + (values[8] * vector.z),
              (values[1] * vector.x) + (values[5] * vector.y) + (values[9] * vector.z),
              (values[2] * vector.x) + (values[6] * vector.y) + (values[10] * vector.z)
            )
          end

          def *(other)
            left = values
            right = other.values
            result = Array.new(16, 0.0)
            4.times do |column|
              4.times do |row|
                result[(column * 4) + row] = 4.times.inject(0.0) do |sum, index|
                  sum + (left[(index * 4) + row] * right[(column * 4) + index])
                end
              end
            end
            Transform3.new(result)
          end

          def determinant
            a00 = values[0]
            a01 = values[4]
            a02 = values[8]
            a10 = values[1]
            a11 = values[5]
            a12 = values[9]
            a20 = values[2]
            a21 = values[6]
            a22 = values[10]
            (a00 * ((a11 * a22) - (a12 * a21))) -
              (a01 * ((a10 * a22) - (a12 * a20))) +
              (a02 * ((a10 * a21) - (a11 * a20)))
          end

          def inverse
            determinant_value = determinant
            if determinant_value.abs <= Vector3::EPSILON
              raise ArgumentError, 'Transformation không thể nghịch đảo.'
            end

            a00 = values[0]
            a01 = values[4]
            a02 = values[8]
            a10 = values[1]
            a11 = values[5]
            a12 = values[9]
            a20 = values[2]
            a21 = values[6]
            a22 = values[10]
            inverse_values = [
              ((a11 * a22) - (a12 * a21)) / determinant_value,
              ((a12 * a20) - (a10 * a22)) / determinant_value,
              ((a10 * a21) - (a11 * a20)) / determinant_value,
              ((a02 * a21) - (a01 * a22)) / determinant_value,
              ((a00 * a22) - (a02 * a20)) / determinant_value,
              ((a01 * a20) - (a00 * a21)) / determinant_value,
              ((a01 * a12) - (a02 * a11)) / determinant_value,
              ((a02 * a10) - (a00 * a12)) / determinant_value,
              ((a00 * a11) - (a01 * a10)) / determinant_value
            ]
            translation = Vector3.new(values[12], values[13], values[14])
            inverse_transform = Transform3.new([
              inverse_values[0], inverse_values[1], inverse_values[2], 0,
              inverse_values[3], inverse_values[4], inverse_values[5], 0,
              inverse_values[6], inverse_values[7], inverse_values[8], 0,
              0, 0, 0, 1
            ])
            inverse_translation = -inverse_transform.apply_vector(translation)
            Transform3.new([
              inverse_values[0], inverse_values[1], inverse_values[2], 0,
              inverse_values[3], inverse_values[4], inverse_values[5], 0,
              inverse_values[6], inverse_values[7], inverse_values[8], 0,
              inverse_translation.x, inverse_translation.y, inverse_translation.z, 1
            ])
          end

          def to_a
            values.dup
          end
        end

        class Bounds3
          attr_reader :minimum, :maximum

          def self.from_points(points)
            raise ArgumentError, 'Cần ít nhất một điểm để tạo giới hạn.' if points.nil? || points.empty?

            new(
              Point3.new(points.map(&:x).min, points.map(&:y).min, points.map(&:z).min),
              Point3.new(points.map(&:x).max, points.map(&:y).max, points.map(&:z).max)
            )
          end

          def initialize(minimum, maximum)
            @minimum = minimum
            @maximum = maximum
            freeze
          end

          def overlaps?(other, tolerance = 0.0)
            interval_overlap?(minimum.x, maximum.x, other.minimum.x, other.maximum.x, tolerance) &&
              interval_overlap?(minimum.y, maximum.y, other.minimum.y, other.maximum.y, tolerance) &&
              interval_overlap?(minimum.z, maximum.z, other.minimum.z, other.maximum.z, tolerance)
          end

          def center
            Point3.new(
              (minimum.x + maximum.x) / 2.0,
              (minimum.y + maximum.y) / 2.0,
              (minimum.z + maximum.z) / 2.0
            )
          end

          def to_h
            { minimum: minimum.to_h, maximum: maximum.to_h }
          end

          private

          def interval_overlap?(first_min, first_max, second_min, second_max, tolerance)
            first_max + tolerance >= second_min && second_max + tolerance >= first_min
          end
        end

        class Plane3
          attr_reader :origin, :normal

          def initialize(origin, normal)
            @origin = origin
            @normal = normal.normalized.canonical
            freeze
          end

          def signed_distance(point)
            (point - origin).dot(normal)
          end

          def coplanar?(other, tolerance)
            normal.parallel?(other.normal, tolerance) && signed_distance(other.origin).abs <= tolerance
          end

          def project(point)
            point - (normal * signed_distance(point))
          end

          def basis
            helper = normal.x.abs < 0.8 ? Vector3.new(1, 0, 0) : Vector3.new(0, 1, 0)
            first = normal.cross(helper).normalized.canonical
            second = normal.cross(first).normalized
            [first, second]
          end

          def to_h
            { origin: origin.to_h, normal: normal.to_h }
          end
        end

        class PartIdentity
          attr_reader :stable_id, :persistent_id, :definition_id, :instance_path, :display_name, :role_metadata

          def initialize(stable_id:, persistent_id: nil, definition_id: nil, instance_path: [], display_name: '', role_metadata: nil)
            raise ArgumentError, 'Mã chi tiết không được để trống.' if stable_id.to_s.empty?

            @stable_id = stable_id.to_s.freeze
            @persistent_id = persistent_id
            @definition_id = definition_id
            @instance_path = instance_path.map(&:to_s).freeze
            @display_name = display_name.to_s.freeze
            @role_metadata = role_metadata.nil? ? nil : role_metadata.to_s.freeze
            freeze
          end

          def to_h
            {
              stable_id: stable_id,
              persistent_id: persistent_id,
              definition_id: definition_id,
              instance_path: instance_path,
              display_name: display_name,
              role_metadata: role_metadata
            }
          end

          def ==(other)
            other.is_a?(PartIdentity) && stable_id == other.stable_id
          end

          alias eql? ==

          def hash
            stable_id.hash
          end
        end

        class FaceDescriptor
          KINDS = %w[broad_face edge_face unknown].freeze

          attr_reader :stable_id, :board_identity, :vertices, :kind, :plane, :area, :centroid, :bounds

          def initialize(stable_id:, board_identity:, vertices:, kind: 'unknown')
            raise ArgumentError, 'Một mặt phải có ít nhất 3 đỉnh.' if vertices.nil? || vertices.length < 3
            raise ArgumentError, 'Loại mặt không được hỗ trợ.' unless KINDS.include?(kind.to_s)

            normalized_vertices = normalize_vertices(vertices)
            raise ArgumentError, 'Mặt không đủ 3 đỉnh phân biệt.' if normalized_vertices.length < 3

            normal, calculated_area = polygon_normal_and_area(normalized_vertices)
            raise ArgumentError, 'Mặt có diện tích bằng 0.' if calculated_area <= Vector3::EPSILON

            @stable_id = stable_id.to_s.freeze
            @board_identity = board_identity
            @vertices = normalized_vertices.freeze
            @kind = kind.to_s.freeze
            @plane = Plane3.new(@vertices.first, normal)
            @area = calculated_area
            @centroid = Point3.new(
              @vertices.map(&:x).sum / @vertices.length.to_f,
              @vertices.map(&:y).sum / @vertices.length.to_f,
              @vertices.map(&:z).sum / @vertices.length.to_f
            )
            @bounds = Bounds3.from_points(@vertices)
            freeze
          end

          def with_kind(new_kind)
            FaceDescriptor.new(
              stable_id: stable_id,
              board_identity: board_identity,
              vertices: vertices,
              kind: new_kind
            )
          end

          def broad_face?
            kind == 'broad_face'
          end

          def edge_face?
            kind == 'edge_face'
          end

          def to_h
            {
              stable_id: stable_id,
              board_id: board_identity.stable_id,
              kind: kind,
              vertices: vertices.map(&:to_h),
              plane: plane.to_h,
              area: area,
              centroid: centroid.to_h
            }
          end

          private

          def normalize_vertices(input)
            result = []
            input.each do |point|
              result << point unless result.last && result.last.almost_equal?(point, Vector3::EPSILON)
            end
            result.pop if result.length > 1 && result.first.almost_equal?(result.last, Vector3::EPSILON)
            result
          end

          def polygon_normal_and_area(points)
            cross_sum = Vector3.new(0, 0, 0)
            points.each_with_index do |current, index|
              following = points[(index + 1) % points.length]
              cross_sum = cross_sum + Vector3.new(current.x, current.y, current.z).cross(
                Vector3.new(following.x, following.y, following.z)
              )
            end
            [cross_sum.normalized, cross_sum.length / 2.0]
          end
        end

        class BoardDescriptor
          attr_reader :identity, :faces, :thickness, :thickness_ambiguous, :center, :bounds, :source_data

          def self.infer(identity:, faces:, tolerance:, source_data: {})
            raise ArgumentError, 'Chi tiết phải có các mặt hình học.' if faces.nil? || faces.empty?

            pairs = parallel_face_pairs(faces, tolerance)
            sorted = pairs.sort_by { |pair| -pair[:mean_area] }
            primary = sorted.first
            ambiguous = primary.nil? || primary[:distance] <= tolerance
            if primary && sorted[1]
              scale = [primary[:mean_area].abs, 1.0].max
              ambiguous ||= (primary[:mean_area] - sorted[1][:mean_area]).abs / scale <= 0.01
            end

            broad_ids = primary ? primary[:faces].map(&:stable_id) : []
            classified = faces.map do |face|
              face.with_kind(broad_ids.include?(face.stable_id) ? 'broad_face' : 'edge_face')
            end
            new(
              identity: identity,
              faces: classified,
              thickness: primary ? primary[:distance] : nil,
              thickness_ambiguous: ambiguous,
              source_data: source_data
            )
          end

          def self.parallel_face_pairs(faces, tolerance)
            pairs = []
            faces.each_with_index do |first, index|
              faces[(index + 1)..-1].to_a.each do |second|
                next unless first.plane.normal.parallel?(second.plane.normal, 1.0e-5)

                distance = first.plane.signed_distance(second.centroid).abs
                next if distance <= tolerance

                pairs << {
                  faces: [first, second],
                  distance: distance,
                  mean_area: (first.area + second.area) / 2.0
                }
              end
            end
            pairs
          end

          def initialize(identity:, faces:, thickness:, thickness_ambiguous: false, center: nil, source_data: {})
            raise ArgumentError, 'Chi tiết phải có ít nhất một mặt.' if faces.nil? || faces.empty?

            @identity = identity
            @faces = faces.freeze
            @thickness = thickness.nil? ? nil : thickness.to_f
            @thickness_ambiguous = !!thickness_ambiguous
            all_points = faces.flat_map(&:vertices)
            @bounds = Bounds3.from_points(all_points)
            @center = center || @bounds.center
            @source_data = ValueSupport.freeze_hash(source_data)
            freeze
          end

          def broad_faces
            faces.select(&:broad_face?)
          end

          def edge_faces
            faces.select(&:edge_face?)
          end

          def to_h
            {
              identity: identity.to_h,
              thickness: thickness,
              thickness_ambiguous: thickness_ambiguous,
              center: center.to_h,
              bounds: bounds.to_h,
              faces: faces.map(&:to_h),
              source_data: source_data
            }
          end
        end
      end
    end
  end
end
