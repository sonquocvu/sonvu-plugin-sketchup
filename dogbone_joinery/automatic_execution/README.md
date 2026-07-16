# Automatic geometry execution

Thư mục này là ranh giới ghi model của luồng `Tạo mộng tự động`.

- `execution_values.rb`: request snapshot, lỗi có mã và kết quả an toàn cho UI.
- `entity_registry.rb`: kiểm tra persistent ID/transformation, theo dõi kết quả
  boolean và cô lập Group/ComponentInstance dùng chung bằng `make_unique`.
- `transform_adapter.rb`: đổi placement đã chốt từ world-space sang context
  chứa solid, gồm nested/rotated/mirrored transform có ma trận khả nghịch.
- `geometry_adapter.rb`: chuyển kích thước đã chốt trong từng joint plan sang
  API hình học thủ công, không đọc lại độ dày từ settings hoặc model, và
  luôn gọi với `manage_operation: false`; female cố định
  `DOGBONE_STYLE_VERTICAL_TBONE`, male cố định generator mộng dương đơn hiện có.
- `executor.rb`: preflight toàn bộ plan, sắp xếp xác định, mở đúng một operation,
  tạo tenon trước rồi mortise, commit toàn bộ hoặc abort toàn bộ.

Executor không chạy lại contact detection, không giảm số mộng, không thực thi
`SkippedConnectionRecord` và không có background thread. Công thức profile,
dog-bone, clearance và union/subtract tiếp tục nằm trong
`dogbone_joinery/geometry.rb`.

Adapter ánh xạ rõ ràng `joint_length` sang chiều theo cạnh của generator cũ,
`mortise_opening_thickness` sang kích thước nominal theo chiều dày và truyền
`fit_clearance` đúng một lần. `Geometry.effective_tenon_height` vì vậy bằng
`tenon_thickness` đã chốt, còn mortise female giữ đúng
`mortise_opening_thickness`. `male_board_thickness` chỉ đến từ plan; female
thickness chỉ giới hạn `mortise_depth`.

Không có `mortise_style`, `dogbone_style`, `tenon_style` hoặc lựa chọn tương tự
trong automatic settings. Các tên style chỉ xuất hiện nội bộ tại ranh giới gọi
generator thủ công và không nhận từ HtmlDialog.

Chưa có cơ chế phát hiện batch đã tạo ở lần chạy trước. Không tự động xóa hoặc
tạo lại hình học cũ cho tới khi có metadata regeneration riêng.
