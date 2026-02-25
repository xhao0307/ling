# Fairy Design Resource Pack v1

本目录是“童话儿童风”资源底座，覆盖品牌、视觉规范、文案、动效规范、验收与用户测试模板。

## 目录
- `design/brand/`：品牌视觉资产规范、色板、字体策略
- `design/tokens/`：design tokens
- `design/illustration/`：插画/角色素材批量生成计划
- `design/motion/`：动效资源规范（Lottie/Rive产出目标）
- `design/pages/`：核心页面高保真落地规范
- `design/copy/`：儿童化文案资源
- `design/qa/`：多端适配验收清单
- `design/research/`：可用性测试模板与样例

## 批量生图
执行：

```bash
scripts/gen-fairy-asset-pack.sh "<参考图URL或本地路径>"
```

默认读取 `design/illustration/asset_generation_plan.json`，生成结果落到：
- `flutter_client/assets/fairy/illustrations/`
- `flutter_client/assets/fairy/illustrations/index.json`
