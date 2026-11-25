# Mod API v1

复制 `mods/alpine_pack/` 开始自定义。每个包有 `manifest.json`，以及可选 GLB 文件。启动时扫描项目 `mods/` 和用户数据 `mods/` 的一级子目录。安装后重启，在顶部「Mod」窗口查看加载结果。

## 清单

```json
{
  "api_version": 1,
  "id": "my_railway",
  "name": "我的铁路",
  "version": "1.0.0",
  "tracks": [
    {"id": "straight", "name": "长直轨", "scale": "HO", "kind": "straight", "length_mm": 460},
    {"id": "curve", "name": "大半径曲线", "scale": "HO", "kind": "curve", "radius_mm": 650, "angle_deg": 15},
    {"id": "turnout", "name": "缓角道岔", "scale": "N", "kind": "turnout", "length_mm": 180, "radius_mm": 500, "angle_deg": 18}
  ],
  "vehicles": [
    {"id": "diesel", "name": "我的柴油机车", "kind": "locomotive", "length_m": 18,
     "width_m": 3.1, "height_m": 4.2, "mass_kg": 100000, "power_w": 2000000,
     "tractive_n": 250000, "max_kmh": 100, "color": "467b83"}
  ],
  "scenery": [
    {"id": "pine", "name": "深色松树", "kind": "tree", "color": "335c4c"}
  ]
}
```

最终零件 ID 为 `包ID:零件ID`，例如 `my_railway:diesel`。包 ID 不可重复或使用 `core`；更新时保持已有零件 ID 稳定。任意定义无效时整个包拒绝加载，错误原因在 Mod 窗口显示。

## 轨道

长度与半径为**实际模型毫米**。`scale` 是 `HO` 或 `N`；要支持两种比例需分别定义。`kind` 支持 `straight`、`curve`、`turnout`。

直轨长度 10–2000 mm，曲线半径 80–5000 mm，转角 1–90°。道岔有共起点的直股与圆弧侧股，界面镜像可改变左右。API v1 提供直线/圆弧几何；任意样条、复式交分道岔或自定义轨道网格需要扩展 `RailGraph.make_paths()` 和 `RailGeometry.track()`。

## 车辆与布景

车辆使用**原型 SI 单位**：米、千克、瓦、牛顿；`max_kmh` 为 km/h。`kind` 支持 `locomotive`、`coach`、`freight`、`tanker`，机车必须提供功率与牵引力。车辆可用于两种模型比例，程序自动缩放。`color` 为十六进制 RGB 字符串。

布景 `kind` 支持 `tree`、`house`、`station`、`platform`、`rock`、`custom`。前五种可程序生成；`custom` 必须指定 GLB 模型。

为车辆或布景添加 `"model": "my_model.glb"` 与可选 `"model_scale": 1.0` 即可替换外观。GLB 必须存在于包目录内，不接受绝对路径或上级目录引用。

## GLB 约定

- glTF 2.0 二进制 `.glb`，材质和纹理嵌入文件。
- Y 向上，车辆 X 为长度方向、正 X 为车头、Z 为宽度方向。
- 默认按原型米建模；厘米模型设置 `model_scale: 0.01`。
- 车辆原点在长宽中心与车轮接触轨面处；布景原点在地面。
- manifest 中的尺寸用于编组长度与碰撞包络，应与模型一致。
- 通过 `GLTFDocument.append_from_file()` 动态加载；当前使用静态模型，不自动驱动车轮、车门、骨骼或嵌入动画。

`alpine_pack/water_tower.glb` 是可用实例，其原创几何由 `tools/build_example_model.py` 生成。

## 源码扩展

`RailCatalog.register_package(dictionary, base_directory) -> bool` 支持程序注册。数据包不执行脚本；行为扩展可在 Godot 项目中添加节点并接入信号：

```gdscript
func _ready():
    var app = get_parent()
    app.layout_changed.connect(func(): print("线路已更新"))
    app.scenery_placed.connect(func(id, position): print(id, position))
    app.simulation.train_event.connect(func(id, message): print(id, message))
    app.simulation.train_added.connect(func(train): print(train.name))
    app.simulation.train_removed.connect(func(id): print("移除：", id))
```

这些连接须在主场景已完成 `_ready()` 后建立，例如扩展节点中使用 `call_deferred()`。

轨道查询：`RailGraph.sample()`、`nearest()`、`next_edge()`。列车操作：`RailSimulation.add_train()`、`reconfigure()`、`reverse()`、`emergency()`、`reset_train()`、`occupancy()`。地形接口：`RailTerrain.brush()`。完整参数以 `scripts/` 源码签名为准。

场景按 ID 引用零件，缺失 Mod 时拒绝载入并保留当前场景。v1 尚未提供脚本热加载、依赖下载、Workshop 或自定义 UI 插件。
