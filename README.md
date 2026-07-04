# SonVu CNC Plugins

SketchUp Ruby extension for CNC and woodworking workflows.

## Hướng dẫn tiếng Việt

### Cài đặt

1. Chép file `sonvu_cnc_plugins.rb` và thư mục `sonvu_cnc_plugins` vào thư mục Plugins của SketchUp.
2. Khởi động lại SketchUp.
3. Mở menu `Extensions > SonVu CNC Plugins > Mộng CNC`.

### Kiểm tra nhanh trong SketchUp

1. Chọn `Extensions > SonVu CNC Plugins > Mộng CNC > Tạo mộng xương chó`.
2. Nhập kích thước theo milimét:
   - `Rộng mộng âm (mm)`
   - `Cao mộng âm (mm)`
   - `Sâu mộng âm (mm)`
   - `Dài mộng dương (mm)`
   - `Đường kính dao CNC (mm)`
   - `Độ hở lắp ráp (mm)`
3. Bật hoặc tắt `Tạo mộng âm?`, `Tạo mộng dương?`, `Khoét góc mộng âm?`, và `Khoét góc chân mộng dương?` theo nhu cầu.
4. Bấm OK, sau đó bấm một điểm trong mô hình để đặt mẫu mộng.
5. Mẫu mộng âm màu đỏ và mộng dương màu xanh sẽ được tạo thành các group riêng để dễ kiểm tra.

### Lưu ý CNC

- `Mộng âm` là phần hốc cắt vào ván.
- `Mộng dương` là phần tab lồi để lắp vào mộng âm.
- `Đường kính dao CNC` ảnh hưởng trực tiếp đến kích thước khoét góc xương chó và khoét góc chân mộng.
- `Độ hở lắp ráp` giúp mộng dương nhỏ hơn mộng âm để dễ lắp sau khi gia công.
- Tính năng cắt boolean vào solid là tùy chọn nâng cao. Hãy lưu file trước khi bật tùy chọn này.
