from PIL import Image
import os

def create_combined_ground(carpet_path, field_path, output_path, scale_x=0.1, scale_y=0.1):
    """
    将地毯图片平铺，并将带有透明通道的球场线叠加在上面。
    """
    print("正在加载图片...")
    if not os.path.exists(carpet_path) or not os.path.exists(field_path):
        print("错误: 找不到图片文件，请检查路径。")
        return

    # 1. 打开图片
    # 将 carpet 转换为 RGBA 方便后续统一处理
    carpet_img = Image.open(carpet_path).convert("RGBA")
    # field2.png 必须包含透明通道，所以也转为 RGBA
    field_img = Image.open(field_path).convert("RGBA")

    # 我们以球场(field2.png)的尺寸作为最终输出的全局尺寸
    target_width, target_height = field_img.size
    print(f"目标贴图尺寸: {target_width}x{target_height}")

    # 2. 计算地毯(carpet)单次平铺的尺寸
    # 之前 material 里的 scale 0.1 0.1 意味着在整个面上平铺 10x10 次
    tile_width = max(1, int(target_width * scale_x))
    tile_height = max(1, int(target_height * scale_y))
    
    # 缩放地毯图片以适应单个 tile 的大小
    carpet_tile = carpet_img.resize((tile_width, tile_height), Image.Resampling.LANCZOS)

    # 3. 创建一张空白的背景图来铺地毯
    background = Image.new("RGBA", (target_width, target_height))

    print("正在平铺地毯背景...")
    # 循环拼接地毯
    for x in range(0, target_width, tile_width):
        for y in range(0, target_height, tile_height):
            background.paste(carpet_tile, (x, y))

    print("正在叠加球场线 (Alpha Blending)...")
    # 4. 将带有透明度的球场线覆盖上去
    # 第三个参数 field_img 作为 mask，告诉 Pillow 哪里透明、哪里不透明
    background.paste(field_img, (0, 0), field_img)

    # 5. 保存最终图片
    # 仿真环境的 Albedo map 不需要透明度了，转回 RGB 可以大幅减小文件体积
    final_image = background.convert("RGB")
    final_image.save(output_path, quality=95)
    
    print(f"✅ 合成成功！图片已保存至: {output_path}")

if __name__ == "__main__":
    # 输入文件路径
    CARPET_FILE = "carpet.jpg"
    FIELD_FILE = "field2.png"
    # 输出文件路径
    OUTPUT_FILE = "combined_ground.jpg"
    
    # 执行合成 (缩放比例 0.1 对应原脚本的 scale 0.1 0.1)
    create_combined_ground(CARPET_FILE, FIELD_FILE, OUTPUT_FILE, scale_x=0.1, scale_y=0.1)