# SonVu CNC Plugins

SketchUp Ruby extension for CNC and woodworking workflows.

Tài liệu dành cho nhà phát triển và Codex: [`DEVELOPMENT.md`](DEVELOPMENT.md).

## Hướng dẫn tiếng Việt

### Cài đặt

1. Chép file `sonvu_cnc_plugins.rb` và thư mục `sonvu_cnc_plugins` vào thư mục Plugins của SketchUp.
2. Khởi động lại SketchUp.
3. Mở menu `Extensions > SonVu CNC Plugins > Mộng CNC`.

### Thiết kế nội thất — Giai đoạn 1 đến 4C

Mở `Extensions > SonVu CNC Plugins > Thiết kế nội thất`:

- `Tạo tủ nội thất`: chọn mẫu `Tủ bếp dưới`, `Tủ bếp treo`, `Tủ áo` hoặc
  `Kệ tivi`; nhập kích thước bằng milimét rồi bấm một điểm trong model để đặt tủ.
- `Chỉnh sửa tủ đã chọn`: chọn đúng một nhóm tủ do SonVu tạo, thay đổi thông số
  rồi cập nhật tại đúng vị trí hiện tại.
- `Danh sách chi tiết`: thống kê các tủ SonVu trong vùng chọn; nếu vùng chọn
  không chứa tủ, plugin tự thống kê toàn bộ model.
- `Dự toán chi phí`: mở trực tiếp bảng đơn giá và tổng chi phí cho cùng phạm vi
  vùng chọn/toàn model.
- `Tối ưu cắt ván`: xếp các chi tiết ván hình chữ nhật lên tấm nguyên theo vật
  liệu, độ dày và chiều vân.

Phiên bản này tạo phần thùng tủ gồm hông trái/phải, nóc, đáy, hậu tùy chọn,
vách đứng, các hàng đợt và chân tủ. Khi có vách đứng, mỗi hàng đợt được tách
thành từng tấm theo từng khoang để không chồng hình học.

Giai đoạn 2A bổ sung các bố trí mặt trước bằng tiếng Việt:

- không cánh;
- một hoặc hai cánh mở;
- một ngăn kéo trên và hai cánh dưới;
- hai, ba hoặc bốn mặt ngăn kéo;
- cánh lật cho kệ tivi.

Mặt cánh hỗ trợ kiểu `Phủ ngoài` và `Lọt lòng`, khe hở tùy chỉnh, vật liệu và
hướng vân riêng, cùng dữ liệu dán cạnh bốn phía.

Giai đoạn 2B bổ sung hộp ngăn kéo năm tấm cho từng mặt ngăn kéo: hai hông,
mặt trong, hậu và đáy. Người dùng có thể đặt độ hở ray cho mỗi bên, chiều cao,
độ dày thành/đáy, khoảng lùi trước/sau và vật liệu hộp riêng. Nhập chiều sâu
hộp bằng `0` để plugin tự tính theo chiều sâu hữu dụng của tủ.

Giai đoạn 2C bổ sung phụ kiện mẫu: một tay nắm cho mỗi mặt trước, bản lề chén
cho cánh mở/cánh lật và một cặp ray cho mỗi hộp ngăn kéo. Số bản lề có thể nhập
trực tiếp hoặc để `0` để tự động theo chiều cao cánh; chiều dài ray cũng hỗ trợ
chế độ tự động. Đây là các component bố trí và thống kê, plugin chưa khoan hay
cắt trực tiếp vào tấm ván.

Mỗi tấm là một component có tên tiếng Việt và dữ liệu phục vụ các giai đoạn sau:

- vai trò chi tiết;
- kích thước thành phẩm và độ dày;
- vật liệu;
- hướng vân;
- trạng thái dán cạnh trước.

Mặt cánh và mặt ngăn kéo được đánh dấu riêng bằng loại chi tiết `front`, nhưng
vẫn là component có kích thước thành phẩm để dùng cho báo cáo và CNC sau này.
Các tấm hộp được đánh dấu bằng loại `drawer_box`; mặt ngăn kéo và năm tấm hộp
tương ứng dùng chung chỉ số ngăn kéo để truy vết cụm khi xuất dữ liệu.
Tay nắm, bản lề và ray dùng loại `hardware`, vật liệu riêng và metadata chỉ rõ
chi tiết mặt trước chủ quản. Mẫu chén bản lề được dựng tròn theo đường kính đã
nhập; ray và tay nắm dùng khối đại diện đơn giản.

Giai đoạn 3A hiển thị hai bảng tiếng Việt riêng cho chi tiết ván và phụ kiện.
Các tấm có cùng vật liệu, kích thước, hướng vân và dán cạnh được gom số lượng;
ví dụ hông trái/phải giống nhau có thể nằm chung một dòng. Bảng hiển thị nhóm,
tên chi tiết, số lượng, dài × rộng × dày, vật liệu, vân, dán cạnh và tủ sử dụng.
Phase 3A chỉ đọc metadata trong model và không thay đổi hình học. Phase 3B bổ
sung nút `Xuất CSV`, cho phép chọn tên file và tạo hai bảng UTF-8 riêng:

- `<tên>_chi_tiet_van.csv`;
- `<tên>_phu_kien.csv`.

Hai file có tiêu đề cột tiếng Việt, mở được trong Excel và giữ các liên kết mã
tủ, chỉ số ngăn kéo, mã chi tiết chủ quản. Plugin hỏi xác nhận trước khi ghi đè
file đã tồn tại.

Phase 3C bổ sung nút `Dự toán chi phí` trong bảng danh sách. Người dùng nhập:

- đơn giá từng vật liệu theo m²;
- tỷ lệ hao hụt vật liệu;
- đơn giá dán cạnh theo mét;
- đơn giá từng loại phụ kiện theo cái.

Plugin tính tiền vật liệu, dán cạnh, phụ kiện, tổng theo từng tủ và tổng toàn
công trình. Đơn giá được lưu trong tùy chọn SketchUp trên máy, không ghi vào
model. Kết quả có thể xuất thành một file báo giá CSV tiếng Việt. Đơn giá nhân
công, thuế và xuất CNC chưa thuộc Phase 3C.

Phase 4A bổ sung công cụ `Tối ưu cắt ván`. Người dùng nhập kích thước tấm
nguyên, lề xén, bề rộng đường cưa và khoảng cách giữa các chi tiết. Plugin:

- nhóm riêng từng vật liệu và độ dày;
- cho phép bật/tắt xoay 90° và giữ đúng chiều vân đã thiết kế;
- xếp hình chữ nhật theo một thuật toán xác định, cho cùng kết quả khi dữ liệu
  đầu vào không đổi;
- hiển thị số tấm, hiệu suất, diện tích thừa, tọa độ từng chi tiết và danh sách
  chi tiết chưa xếp được.

Thông số được lưu trong tùy chọn SketchUp sau một lần tính thành công. Phase 4A
chỉ đọc danh sách chi tiết và không sửa model.

Phase 4B trực quan hóa từng phương án bằng sơ đồ tấm ván theo đúng tỷ lệ và tọa
độ của Phase 4A. Mỗi nhóm vật liệu/độ dày có nút chuyển giữa các tấm. Trên sơ
đồ, người dùng có thể:

- nhận biết từng chi tiết bằng màu, tên và kích thước;
- xem lề xén, chiều X/Y và mũi tên chiều vân;
- rê chuột lên chi tiết để xem đầy đủ vị trí, trạng thái xoay và tủ sử dụng;
- phóng to, thu nhỏ hoặc đưa sơ đồ về vừa khung;
- mở lại bảng tọa độ để đối chiếu số liệu.

Phase 4B vẫn chỉ đọc dữ liệu và không tạo hình học trong model.

Phase 4C bổ sung nút `Xuất phương án` sau khi tính thành công. Người dùng chọn
một tên cơ sở như `cong_trinh.html`; plugin hỏi trước khi ghi đè rồi tạo hai file:

- `cong_trinh_phuong_an_cat.html`: báo cáo tự chứa gồm thông số, tổng hợp, sơ đồ
  từng tấm, bảng tọa độ và danh sách chi tiết chưa xếp. Mở file trong trình
  duyệt rồi bấm `In / Lưu PDF` để in hoặc tạo PDF khổ ngang;
- `cong_trinh_toa_do_cat.csv`: bảng UTF-8 cho Excel, mỗi chi tiết đã xếp hoặc
  chưa xếp là một dòng với vật liệu, độ dày, thông số tấm, tọa độ X/Y, kích
  thước đặt, xoay, chiều vân, tủ sử dụng, trạng thái và lý do lỗi.

Việc xuất chỉ xảy ra khi người dùng bấm nút, không ghi dữ liệu vào model. Phase
4C chưa tính trình tự cưa, quản lý ván thừa hoặc tạo đường chạy dao CNC.

Lệnh chỉnh sửa chỉ xây dựng lại các component tấm ván do SonVu đánh dấu; đối
tượng khác mà người dùng thêm vào trong nhóm tủ được giữ nguyên.

### Giấy phép

- Mở `Extensions > SonVu CNC Plugins > Quản lý giấy phép` để xem mã thiết bị,
  kích hoạt online, dán token đã ký, làm mới hoặc hủy kích hoạt.
- Lần đầu extension được tải, thiết bị bắt đầu 14 ngày dùng thử và được sử dụng
  toàn bộ module hiện tại. License Manager hiển thị ngày hết hạn và số ngày còn
  lại. Sau khi hết hạn, người dùng phải kích hoạt token hợp lệ.
- Lệnh xóa mẫu đã tạo luôn khả dụng để giấy phép không khóa hình học của người
  dùng trong model.

### Kiểm tra nhanh trong SketchUp

1. Chọn đúng một lệnh riêng biệt:
   - `Tạo mộng âm` hoặc biểu tượng mộng âm trên thanh công cụ.
   - `Tạo mộng dương` hoặc biểu tượng mộng dương trên thanh công cụ.
2. Hộp thoại chỉ hiển thị thông số của loại mộng đã chọn:
   - Mộng âm: rộng, cao, sâu, bán kính dao và kiểu dog-bone.
   - Mộng dương: rộng, độ vươn, số lượng, lề hai đầu cạnh, bán kính dao cho hai vai mộng và độ hở. Plugin tự tính khoảng cách đều giữa các mộng.
3. Cấu hình kiểu khoét phù hợp với loại mộng đang tạo.
4. Với mộng âm, bấm tạo mẫu rồi di chuyển bản xem trước trên mặt đã chọn và bấm để đặt tâm. Màu xanh là vị trí hợp lệ; màu đỏ nghĩa là biên dạng vượt khỏi mặt. Mộng dương vẫn được bố trí tự động.
5. Mộng âm được tạo thành group mẫu riêng. Mộng dương được hợp khối với solid chứa mặt đã chọn để CNC nhận diện toàn bộ chi tiết là một khối.

### Lưu ý CNC

- `Mộng âm` là phần hốc cắt vào ván.
- Khối mẫu mộng âm luôn bắt đầu tại mặt đã chọn và đi vào trong theo chiều sâu âm của hệ trục cục bộ; nó không nhô lên trên bề mặt.
- Trước khi tạo mộng âm, phải chọn đúng một mặt của model. Plugin lấy trục X theo cạnh dài nhất của mặt, trục Y vuông góc với X trên mặt, rồi dùng điểm bấm làm tâm của toàn bộ biên dạng dog-bone.
- Plugin đo chiều sâu model theo phương vuông góc với mặt đã chọn và từ chối mộng âm sâu hơn model. Bản xem trước kiểm tra biên dạng dog-bone nằm hoàn toàn trong mặt trước khi cho phép đặt.
- `Mộng dương` là phần tab lồi để lắp vào mộng âm.
- `Bán kính dao` của mộng âm ảnh hưởng trực tiếp đến kích thước khoét góc xương chó.
- `Bán kính dao` của mộng dương điều khiển trực tiếp hai khoét bán nguyệt ở vai mộng và độc lập với bán kính dao của mộng âm.
- Với một mộng dương, plugin tự căn giữa trên cạnh. Với hai mộng trở lên, khoảng cách trống được tính bằng `(chiều rộng mặt - 2 × lề - số lượng × rộng mộng sau độ hở) / (số lượng - 1)`.
- `Độ hở lắp ráp tổng` được trừ một lần khỏi tổng chiều rộng và tổng chiều cao mộng dương. Ví dụ, mặt 18 mm với độ hở 0,2 mm tạo mộng cao 17,8 mm và căn giữa trên mặt.
- Trước khi hợp khối, mỗi mộng dương là một khối liên tục. Biên dạng vai mộng và hai khoét bán nguyệt được dựng trong mặt phẳng dọc cạnh × hướng vươn, sau đó đùn xuyên qua chiều dày của mặt cạnh đã chọn.
- Để tạo mộng dương, hãy mở một group/component solid để chỉnh sửa rồi chọn mặt cạnh bên trong. Plugin tạo bản sao lưu ẩn, hợp mộng vào solid và cho phép Undo toàn bộ trong một bước.
- Plugin đo kích thước theo hệ trục của mặt đã chọn, vì vậy có thể dùng với chi tiết đã xoay khỏi trục thế giới.
- Nếu biên dạng mộng vượt khỏi mặt đã chọn, bản xem trước chuyển sang màu đỏ và plugin không tạo hình học.
- Tính năng cắt boolean vào solid là tùy chọn nâng cao. Hãy lưu file trước khi bật tùy chọn này.

### Kiểm tra hồi quy phần hình học

Từ thư mục Plugins, chạy:

```powershell
ruby sonvu_cnc_plugins\dogbone_joinery\test\geometry_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\specification_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cut_list_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cut_list_csv_exporter_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cost_estimator_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cost_estimate_dialog_html_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\cost_estimate_csv_exporter_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_optimizer_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_layout_svg_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_layout_exporter_test.rb
ruby sonvu_cnc_plugins\furniture_builder\test\sheet_optimization_dialog_html_test.rb
ruby sonvu_cnc_plugins\shared\licensing\test\license_test.rb
```
