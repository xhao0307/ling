# 动效资源规范（Lottie/Rive）

## 动效清单
- 页面转场（Page Transition）
  - 时长：220ms
  - 曲线：easeOutCubic
- 按钮反馈（Button Press）
  - 按下缩放：0.96
  - 恢复时长：120ms
- 角色呼吸（Character Breathing）
  - 缩放范围：0.98 ~ 1.02
  - 周期：2.6s
- 星光闪烁（Twinkle）
  - 透明度：0.3 ~ 1.0
  - 周期：1.4s

## 资源产出格式
- 优先：Lottie JSON
- 备选：Rive `.riv`

## 命名规范
- `transition_page_fade_slide.json`
- `button_press_pop.json`
- `character_breath_loop.json`
- `sparkle_twinkle_loop.json`

## 验收标准
- 60fps 下无明显掉帧
- iOS/Android/Web 视觉节奏一致
- 不能出现眩晕感（过快闪烁和大幅位移）
