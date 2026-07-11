# SonVu CNC Plugins

SketchUp Ruby extension for CNC and woodworking workflows.

Tài liệu dành cho nhà phát triển và Codex: [`DEVELOPMENT.md`](DEVELOPMENT.md).

## Hướng dẫn tiếng Việt

### Cài đặt

1. Chép file `sonvu_cnc_plugins.rb` và thư mục `sonvu_cnc_plugins` vào thư mục Plugins của SketchUp.
2. Khởi động lại SketchUp.
3. Mở menu `Extensions > SonVu CNC Plugins > Mộng CNC`.

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
```
