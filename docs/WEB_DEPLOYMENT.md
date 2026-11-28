# GitHub Actions 自动发布 Web

工作流：[`deploy-web.yml`](../.github/workflows/deploy-web.yml)。

向 `fsship/TrackPlayground` 的 `main` 分支推送后，工作流使用 Windows runner 下载并校验 Godot 4.7.2 和官方 Web 导出模板，执行 `./Export.ps1 -Target Web`，然后将产物提交到 `fsship/fsship.github.io` 的 `master` 分支下的 `TrackPlayground/`。也可以在 [Actions](https://github.com/fsship/TrackPlayground/actions/workflows/deploy-web.yml) 点击 **Run workflow**，选择 `main` 手动发布。其他分支和 Fork 不会发布。

访问地址：<https://fsship.github.io/TrackPlayground/>。

## 首次配置

1. 在 [GitHub Fine-grained tokens](https://github.com/settings/personal-access-tokens/new) 创建专用 token：
   - Resource owner：`fsship`。
   - Repository access：**Only select repositories**，只选择 `fsship.github.io`。
   - Repository permissions → **Contents: Read and write**；Metadata 的读取权限会自动附带。
   - 设置合适的有效期，到期前更新下述 Secret。
2. 在 **源仓库 TrackPlayground** 的 [Settings → Secrets and variables → Actions](https://github.com/fsship/TrackPlayground/settings/secrets/actions) 添加 Repository secret：
   - Name：`PAGES_DEPLOY_TOKEN`。
   - Secret：刚创建的 token。不要将 token 写入代码或提交到 Git。
3. 检查 **目标仓库 fsship.github.io** 的 [Settings → Pages](https://github.com/fsship/fsship.github.io/settings/pages)：Source 为 **Deploy from a branch**，分支 `master`，目录 **/(root)**。如果已按此配置，无需更改。
4. 将工作流提交并推送到源仓库的 `main`，或在工作流已存在于 `main` 时手动运行。

跨仓库推送需要目标仓库的写权限，默认 `GITHUB_TOKEN` 的权限仅限当前仓库；而用该默认 token 推送也不会触发基于分支的 Pages 构建。因此这里使用专用 PAT。参见 [GitHub checkout 的跨仓库说明](https://github.com/actions/checkout#checkout-multiple-repos-private) 和 [Pages 发布说明](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)。

## 发布行为与排错

- 发布采用覆盖复制，只提交 `TrackPlayground/` 下的改动，保留现有 `TrackPlayground/layout/huge.railway` 等额外文件以及网站其他目录。不会清空整个网站或强制推送；将来废弃的导出文件需要按需单独清理。
- Web 构建产物保存为 Actions artifact，保留 14 天。缺少 Secret 时构建和产物上传仍会完成，发布步骤会明确失败；配置 Secret 后重新运行即可。
- 构建失败时会附加导出日志，保留 7 天。下载和校验失败时可重跑；成功下载的引擎和模板会缓存以节省后续构建时间。
- 没有文件变化时不创建空提交。同一源仓库的发布串行执行；若网站分支同时有其他提交，会尝试 rebase 一次，冲突则失败并保留远端内容。
- 工作流成功表示产物已推送到网站仓库；随后还要等待目标仓库的 Pages 构建完成。若网页未更新，检查目标仓库的 Actions 和 Pages 设置。
- 遇到 `403` 或推送被拒绝，检查 token 的目标仓库、Contents 权限、有效期，以及 `master` 的分支保护规则。
- 升级 Godot 时，应同时更新 `export_presets.cfg` 的模板路径、工作流中的 `GODOT_VERSION` 和两个官方发布包的 SHA-256；本机运行时也应使用同一版本。
