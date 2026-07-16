# Kiến trúc phân tích mộng tự động

## Phân tích kiến trúc hiện có

Luồng tạo mộng thủ công vẫn là nguồn sự thật và không bị thay đổi:

- `dogbone_joinery/commands.rb` kiểm tra giấy phép, mặt đang chọn, solid đích và xác nhận thao tác phá hủy.
- `dogbone_joinery/dialog.rb` xác thực dữ liệu tiếng Việt rồi đổi milimét sang đơn vị nội bộ của SketchUp.
- `dogbone_joinery/tool.rb` tạo hệ trục cục bộ của mặt và ghép transformation của edit context.
- `dogbone_joinery/geometry.rb` là nguồn sự thật cho biên dạng dog-bone, solid mộng âm, biên dạng vai mộng dương, khoảng hở, bản sao lưu, phép union và thao tác Undo nguyên tử.

Các điểm mở rộng dùng chung là `Geometry.create_mortise_template`,
`Geometry.create_tenon_template`, `Geometry.cut_mortise_into_solid` và
`Geometry.union_tenons_into_solid`. Bộ lập kế hoạch không gọi các hàm này.
`AutomaticJointGeometryExecutor` chỉ gọi chúng sau khi người dùng bấm `Tạo
mộng`, chuyển từng `JointInstancePlan` sang context chứa solid và không tính
lại tâm mộng âm/mộng dương riêng rẽ.

Luồng tự động có đúng một cấu hình hình học: mộng dương dùng generator đơn hiện
có và mộng âm dùng `Mộng âm dọc (T-bone)`. Hộp thoại, settings snapshot và plan
không lưu lựa chọn kiểu mộng. Các field kiểu cũ trong payload được bỏ qua; công
cụ mộng thủ công vẫn giữ nguyên các lựa chọn riêng.

## Hợp đồng kích thước tự động

Luồng tự động dùng tên rõ nghĩa và không cho nhập một độ dày mộng chung:

- `joint_length`: chiều dài một mộng theo trục phân bố trên cạnh tiếp xúc;
- `detected_male_board_thickness`: độ dày vật lý do `BoardDescriptor` suy ra từ
  cặp broad face của chính tấm male;
- `tenon_thickness`: độ dày mộng dương thực sau khi trừ một lần tổng
  `fit_clearance`;
- `mortise_opening_thickness`: kích thước miệng mộng âm, bằng
  `tenon_thickness + fit_clearance` và vì vậy bằng độ dày tấm male đã phát hiện;
- `tenon_height`: độ nhô của mộng dương khỏi tấm male;
- `mortise_depth`: chiều sâu cắt vào tấm female.

Đây là ánh xạ có chủ ý sang API thủ công vốn dùng tên cũ: `joint_length` đi vào
`mortise_width`/`tenon_width`, còn `mortise_opening_thickness` đi vào
`mortise_height`/`tenon_height`. Generator mộng dương thủ công trừ `clearance`
đúng một lần, nên hình học hoàn tất khớp `tenon_thickness`; không có allowance
ẩn mới. Công cụ thủ công không đổi hợp đồng hay điều khiển.

Mỗi `JointInstancePlan` chốt toàn bộ kích thước trên, cutter radius, trục độ dày
và placement. Preview và executor chỉ đọc snapshot này; chúng không đo lại
board thickness. Vì vậy tấm 17 mm và 18 mm trong cùng vùng chọn tạo các cặp
mộng khác độ dày, không dùng một giá trị toàn cục.

## Kiến trúc mới

Luồng dữ liệu chỉ đọc:

```text
Group/ComponentInstance được chọn
  -> SketchupBoardScanner
  -> BoardDescriptor trong tọa độ world
  -> BroadPhaseCandidatePairFinder
  -> ContactDetector (giao đa giác phẳng thực)
  -> ContactClassifier + AssignmentResolver
  -> JointLayoutCalculator
  -> JointDimensionResolver (độ dày riêng theo tấm male + clearance)
  -> ConnectionPlan
  -> BulkPreviewAnalyzer
  -> PreviewPlan hợp lệ + SkippedConnectionRecord
  -> PreviewState + PreviewStateSerializer
  -> HtmlDialog và PreviewOverlayTool
  -> AutomaticJointExecutionRequest (snapshot đã chốt)
  -> AutomaticJointGeometryExecutor
  -> Geometry.union_tenons_into_solid + Geometry.cut_mortise_into_solid
```

Trách nhiệm từng tệp:

- `geometry_values.rb`: điểm, véc-tơ, transformation, mặt, tấm ván và identity thuần Ruby.
- `joint_layout.rb`: thông số không phụ thuộc đơn vị, mã kiểm tra ổn định, thông báo tiếng Việt và phép chia vị trí dùng chung.
- `joint_dimensions.rb`: resolve kích thước male/female dùng chung từ độ dày
  `BoardDescriptor`, kiểm tra ambiguity, chiều sâu và fit clearance.
- `preview_plan.rb`: dữ liệu xem trước bất biến/copy-on-write, đảo âm-dương, bật/tắt liên kết và từng vị trí mộng.
- `contact_analysis.rb`: lọc cặp bằng bounds, chứng minh giao nhau trên mặt phẳng, phân loại T/L/back, gán male/female và chống trùng.
- `bulk_preview.rb`: giữ toàn bộ plan hợp lệ và chuyển lỗi cục bộ thành bản ghi bỏ qua nhẹ, có mã lý do ổn định.
- `sketchup_adapter.rb`: đọc Group/ComponentInstance lồng nhau, transformation và metadata; không ghi thuộc tính và không mở model operation.
- `preview_settings.rb`: nhận trường milimét từ hộp thoại, xác thực và đổi đơn vị đúng một lần ở biên UI.
- `preview_display.rb`: tùy chọn hiển thị thuần túy và style tập trung; không tham gia tính hình học hoặc plan cuối.
- `preview_state.rb`: giữ thông số chung, plan hợp lệ, tổng hợp vị trí bỏ qua và trạng thái calculated/input/stale.
- `preview_primitives.rb`: tạo đường/vùng vẽ tạm từ chính `JointInstancePlan`, không tạo SketchUp entity.
- `preview_session.rb`: vòng đời HtmlDialog, callback JSON, observer, kiểm tra model thay đổi và View overlay.
- `ui/automatic_preview.*`: tài nguyên cục bộ HTML/CSS/JavaScript, chỉ hiển thị và chuyển ý định người dùng về Ruby.
- `../automatic_execution/`: kiểm tra snapshot, bảo vệ component dùng chung,
  đổi world-space sang context local, điều phối boolean và trả kết quả có cấu trúc.

Quy tắc mặc định luôn là hình học: tấm đưa `edge_face` là `male_part`, tấm đưa
`broad_face` là `female_part`. Metadata `part_role` đáng tin cậy chỉ tạo
`role_assignment_suggestion`; nó không tự ý đổi kết quả hình học. Mọi tâm mộng,
điểm đầu và điểm cuối của hai phía được tạo từ cùng một danh sách tọa độ trên
trục tiếp xúc.

## UI xem trước hàng loạt

Lệnh `Tạo mộng tự động` nằm trong menu và toolbar `Mộng CNC`. Dialog chỉ có bộ
thông số dùng chung, ba công tắc hiển thị, bốn số tổng hợp và các nút `Xem
trước`, `Tính lại`, `Tạo mộng`, `Đóng`. Không có bảng liên kết, lựa chọn từng
liên kết, checkbox từng mộng hoặc đảo âm/dương. JavaScript không tính hình học;
mọi giá trị được kiểm tra và đổi đơn vị trong Ruby.
Dialog dùng `Chiều dài mộng` và `Chiều cao mộng dương`; không có field
`Chiều dày mộng`. Ghi chú cho biết bề dày được tính riêng theo từng tấm.

`BulkPreviewAnalyzer` nhận kết quả đầy đủ của `Analyzer`. Connection hợp lệ có
đủ số lượng yêu cầu được giữ trong plan bulk. Connection lỗi và diagnostic tiếp
xúc được chuyển thành `SkippedConnectionRecord`; không tạo joint instance một
phần và không chặn các connection hợp lệ khác. Dialog chỉ hiển thị số vị trí bỏ
qua và, khi mở phần nhỏ `Xem lý do bỏ qua`, số lượng theo nhóm mã lỗi.

Overlay luôn vẽ đồng thời mọi mộng hợp lệ trong plan: mộng dương là lăng trụ
dây nét liền xanh, mộng âm dọc (T-bone) là hốc dây nét đứt cam kèm bốn marker
bán kính dao. Marker dùng trục X/Y của `female_placement`, không dùng trục global.
Biên mộng dương dùng `tenon_thickness`, biên T-bone female dùng
`mortise_opening_thickness`; cả hai lấy từ cùng joint snapshot và cùng trục độ
dày.
Vị trí bị bỏ qua không được vẽ. Người dùng có thể tắt toàn cục mộng dương, mộng
âm hoặc vùng tiếp xúc; không có trạng thái hiển thị theo connection.

`VerticalTBoneGeometry` giữ phép đo offset/độ vươn relief dùng chung cho profile
thủ công, preview và kiểm tra khả thi. Connection không đủ chiều rộng cho bán
kính dao được chuyển thành skip `infeasible_vertical_tbone`; các connection hợp
lệ khác vẫn tiếp tục.

Nút `Tạo mộng` chốt snapshot plan và thông số rồi gọi executor đồng bộ. Nó bị
khóa nếu chưa tính preview, input lỗi, model stale hoặc không còn mộng hợp lệ;
các vị trí đã bỏ qua không làm nút bị khóa. Toàn bộ batch dùng đúng một model
operation. Thành công sẽ xóa overlay, đóng dialog và có thể Undo toàn bộ bằng
một lần; lỗi bất ngờ sẽ abort batch và bắt buộc xem trước lại.

Executor sắp xếp theo mã connection rồi mã joint. Cả hai phía dùng chính
`male_placement`/`female_placement` đã lưu trong joint plan. Component hoặc edit
context đang dùng chung definition được `make_unique` bên trong cùng operation
trước khi sửa; sibling ngoài vùng chọn không bị sửa và instance không dùng
chung không bị unique thừa. Tên, material, layer/tag và các attribute dictionary
của solid đích được chuyển sang kết quả boolean. Solid tạm không tạo material
hiển thị và được boolean/rollback dọn dẹp.

## Giới hạn hình học đã biết

- Chỉ các mặt phẳng trong outer loop được phân tích; lỗ bên trong mặt chưa được trừ khỏi vùng tiếp xúc.
- Broad face được suy ra từ cặp mặt song song có diện tích lớn nhất. Khối gần hình lập phương, thanh tiết diện vuông hoặc solid không giống tấm ván sẽ báo chiều dày mơ hồ.
- Đa giác lõm đơn giản được tam giác hóa. Loop tự cắt, mặt suy biến và topology nhập lỗi có thể bị bỏ qua.
- Tiếp xúc đường/điểm đồng phẳng được phân loại rõ. Giao tuyến của hai mặt không đồng phẳng hiện có thể chỉ được báo `no_contact`.
- Mặt cong, solid bo tròn phức tạp và contact region có nhiều đảo rời nhau chưa phải phạm vi hỗ trợ đáng tin cậy.
- Group có hình học mặt trực tiếp được coi là một tấm ván; group lắp ráp nên chứa các Group/ComponentInstance con riêng biệt.
- Bounding box chỉ dùng ở broad phase. Một liên kết chỉ hợp lệ sau khi hai polygon mặt đồng phẳng có diện tích giao thực lớn hơn dung sai.
- Chưa có metadata đáng tin cậy để nhận diện mộng tự động đã tạo ở lần chạy
  trước. Chạy lại trên chi tiết đã gia công giữ hành vi hiện tại của công cụ thủ
  công và có thể tạo hình học lặp.

## Bước tiếp theo an toàn

Chạy checklist `SKETCHUP_2023_PREVIEW_SMOKE_TEST.md` thủ công trong SketchUp
2023 trước khi phát hành. Bước phát triển tiếp theo là nhận diện mộng tự động đã
tạo, chặn chạy lặp ngoài ý muốn và hỗ trợ xóa/tạo lại bằng metadata do plugin sở
hữu; không thuộc phạm vi hiện tại.
