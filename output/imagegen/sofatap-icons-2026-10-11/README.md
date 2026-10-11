# 图标候选说明

五张原稿均通过内置 image_gen 独立生成并逐张视觉检查，未使用代码绘图或修改图像。

- 原稿实际尺寸：1254 × 1254 像素；PNG、8-bit RGB、无透明通道。
- 画布为完整正方形、背景铺满、无预置圆角、无文字或水印。
- 尚未替换当前 AppIcon，也未选择正式上架方案。
- 原始 prompts 请求 1024 × 1024；生成器实际输出 1254 × 1254。对方案1尝试了仅改尺寸的 image_gen 编辑，仍返回 1254 × 1254，因此保留全部较高分辨率原稿，不再重复生成。正式上架尺寸待选定后处理。
- 页面中圆角和小图只用于预览，源图未做变换。

| 方案 | 文件 | 评价 |
| --- | --- | --- |
| 1. 沙发轻点 | [01-sofa-click.png](01-sofa-click.png) | 沙发与点击同时可读，最能直接解释 Sofa Tap；首选方向。 |
| 2. 手机光标 | [02-pocket-pointer.png](02-pocket-pointer.png) | 强调手机变光标，功能含义清楚，整体更像通用遥控工具。 |
| 3. 自在滑动 | [03-air-gesture.png](03-air-gesture.png) | 流动轨迹突出空中鼠标与轻松手势，品牌感强，场景含义较抽象。 |
| 4. 舒服沙发 | [04-comfy-sofa.png](04-comfy-sofa.png) | 柔软实体沙发最亲和，适合强调舒适与普通消费者；缩小时点击符号较弱。 |
| 5. 一触即达 | [05-one-tap.png](05-one-tap.png) | 简洁轻触符号有记忆点，图形更抽象，可能被看作绘画工具。 |

推荐优先考虑 1；若更重视家居般的温暖与舒适，可考虑 4。

尺寸编辑尝试 prompt：

> Edit target: the attached Sofa Tap app icon. Change only output pixel dimensions to EXACTLY 1024 by 1024 pixels, suitable for an App Store 1024-pixel icon. Preserve the entire visual composition, all shapes, placements, colors, lighting, edge-to-edge opaque square background and lack of typography. Do not redesign anything, do not crop, no rounded outer corners. Resample the complete image faithfully. The resulting image file must be 1024x1024 pixels, not 1254x1254.

