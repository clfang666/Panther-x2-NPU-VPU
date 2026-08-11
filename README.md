# Panther X2 NPU/VPU Armbian

🚀本项目完全由chatgpt完成
让Panther X2可以驱动NPU和VPU

GitHub Actions 会获取固定版本的 Armbian 构建框架，生成 Ubuntu 24.04 Noble 镜像，并校验
Rockchip BSP 6.1 的 VPU、NPU、RGA 和 IEP 驱动配置。

## 固定构建输入

- Armbian build：`70a242faa308c57be5ed636897dfee77de350773`
- 系统：Ubuntu 24.04 Noble
- 板卡：`panther-x2-vendor`
- 内核：Rockchip vendor BSP 6.1
- 内核源码提交：`5280f9b4336199c4025c8eed894d2b4e2268dcc6`
- 预期内核版本：`6.1.115-vendor-rk35xx`
- U-Boot 源码提交：`c55987146f4f9b20f7cb2f917ca88300419afe8d`
- U-Boot 来源：Radxa `stable-4.19-rock3`

内核补丁加入 `rk3566-panther-x2.dts`，启用 BSP MPP、RGA、IEP、RKVDEC、
RKVENC 和 RKNPU 节点，并加入实体板已经验证的 NPU 电源引用。U-Boot 补丁修复旧版
Radxa 源码与较新 GCC 的两处兼容性问题。

## 云端编译

推送到 `main` 后，工作流
`.github/workflows/build-pantherx2-noble.yml` 会自动开始编译。也可以在 GitHub 的
**Actions → Build Panther X2 Noble BSP 6.1 → Run workflow** 中手动启动。

构建产物包括：

- `*.img.xz`：压缩后的 Armbian 镜像；
- `*.img.xz.sha256`：镜像 SHA-256；
- `pantherx2-validation.txt`：镜像内容与 VPU/NPU DTB 校验报告。

工作流会分别挂载镜像的根分区和 FAT `/boot` 分区，然后检查 Ubuntu 24.04、内核
配置、启动 DTB、加速器节点状态及 NPU 电源引用。只有全部通过，镜像才会作为
Actions Artifact 上传。

## 本地复现

```bash
git clone https://github.com/armbian/build.git
cd build
git checkout 70a242faa308c57be5ed636897dfee77de350773
rsync -a ../Panther-x2-NPU-VPU/armbian/ ./
./compile.sh \
  RELEASE=noble \
  BUILD_DESKTOP=no \
  BUILD_MINIMAL=no \
  KERNEL_CONFIGURE=no \
  KERNEL_BTF=no \
  EXPERT=yes \
  pantherx2-image build
```

本仓库负责内核、U-Boot、设备树和系统镜像。Rockchip MPP/RGA/RKNN 用户态库及
具体推理模型运行环境需要在系统启动后另行安装和验证。

## 上游项目

- [Armbian build](https://github.com/armbian/build)
- [Armbian Rockchip kernel](https://github.com/armbian/linux-rockchip)
- [Radxa U-Boot](https://github.com/radxa/u-boot)

仓库中的上游补丁和衍生源码片段继续遵循各自上游项目的许可证。
