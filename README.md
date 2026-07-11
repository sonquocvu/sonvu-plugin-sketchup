# SonVu CNC Plugins

SketchUp Ruby extension for CNC and woodworking workflows.

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
   - Mộng âm: rộng, cao, sâu, đường kính dao và kiểu dog-bone.
   - Mộng dương: rộng, độ vươn, khoảng cách mép, đường kính dao và độ hở. Mỗi lần chạy tạo đúng một mộng dương.
3. Cấu hình kiểu khoét phù hợp với loại mộng đang tạo.
4. Bấm tạo mẫu. Mộng dương được đặt tự động trên mặt đã chọn; mộng âm dùng công cụ đặt mẫu.
5. Mẫu mộng âm màu đỏ và mộng dương màu xanh sẽ được tạo thành các group riêng để dễ kiểm tra.

### Lưu ý CNC

- `Mộng âm` là phần hốc cắt vào ván.
- `Mộng dương` là phần tab lồi để lắp vào mộng âm.
- `Đường kính dao CNC` ảnh hưởng trực tiếp đến kích thước khoét góc xương chó và khoét góc chân mộng.
- `Độ hở lắp ráp tổng` được trừ một lần khỏi tổng chiều rộng và tổng chiều cao mộng dương. Ví dụ, mặt 18 mm với độ hở 0,2 mm tạo mộng cao 17,8 mm và căn giữa trên mặt.
- Mỗi mộng dương là một group chứa một khối liên tục. Biên dạng vai mộng và hai khoét bán nguyệt được dựng trong mặt phẳng dọc cạnh × hướng vươn, sau đó đùn xuyên qua chiều dày của mặt cạnh đã chọn.
- Plugin đo kích thước theo hệ trục của mặt đã chọn, vì vậy có thể dùng với chi tiết đã xoay khỏi trục thế giới.
- Nếu khoảng cách mép cộng chiều rộng mộng vượt khỏi mặt đã chọn, plugin sẽ báo lỗi trước khi tạo hình học.
- Tính năng cắt boolean vào solid là tùy chọn nâng cao. Hãy lưu file trước khi bật tùy chọn này.

### Kiểm tra hồi quy phần hình học

Từ thư mục Plugins, chạy:

```powershell
ruby sonvu_cnc_plugins\dogbone_joinery\test\geometry_test.rb
```
