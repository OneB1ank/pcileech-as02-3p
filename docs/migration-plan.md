# AS02MC04 asmcehnk 25G Migration Plan

> 本文保留迁移期的工程记录。文中 `validation/`、`artifacts/`、临时工程和
> 本地复核报告路径属于未随公开源码发布的历史证据；当前可复现状态与开放
> 实板门槛以 [validation.md](validation.md) 为准。

## 1. 目标与不可变约束

把 **AMDUSB4 的 asmcehnk 工程移植到 AS02MC04**，只替换板卡、传输和 PCIe IP 边界。目标器件为 `xcku3p-ffvb676-2-e`，构建工具为 Vivado 2024.2。

不可变约束：

- AMDUSB4 是功能、协议和目录组织底座；芯片无关的 asmcehnk 代码能直接复用就不改。
- Taxi 只提供 AS02MC04 板级 shell、XDC、GTY、25G MAC/PHY、PCIe hard IP 和相关时钟/复位逻辑。
- Corundum 只提供 64-bit Ethernet/ARP/IPv4/UDP 最小依赖，不引入 NIC、DMA、驱动、Nexus 板级 top 或其他网络栈。
- NeTV2 只作为 rawudp wire-format 和 host 行为参考，不复制 RMII、FC1003 或 Artix-7 板级实现。
- **物理 SFP1 是唯一 transport 端口**，对应 RTL/MAC index 0；**物理 SFP2 对应 index 1，AXIS 侧保持 TX idle/RX drain，不承载 transport 帧**。
- 主机侧用于 LC-LC 直连的物理 25G NIC 与 FPGA PCIe edge connector 枚举出的 PF0 是两个独立平面：前者配置 IPv4 只为 ARP/UDP transport，后者的 VID/DID/class/BAR 由 PCIe profile 决定。任何主机 NIC 地址都不改变或暗示 PF0 是网卡。
- 不使用 Makefile；只使用根目录 Vivado Tcl 和 Windows `.bat` 入口。
- 工程主目录保持精简：`src/`、`ip/`、根目录 Vivado Tcl/批处理入口。Vivado 生成目录不纳入源码。
- 不修改原始 `AMDUSB4/`；所有兼容性改动只发生在 `as02_asmcehnk_25g/`。
- 不做 activation lock/DNA gate；AS02 工程中的合法 TLP command 直接进入原 `dtlp` 路径。
- 迁移实施采用只读 Preflight、Builder 实现、只读 Reviewer 复核和按需专家咨询；公共贡献要求见根目录 `CONTRIBUTING.md`。

默认网络参数：

| 参数 | 默认值 |
|---|---|
| MAC | `02:00:00:00:00:de` |
| IPv4 | `192.168.0.222` |
| UDP port | `28474` / `16'h6f3a` |
| 模式 | 静态 IPv4、单一最近合法 peer |

第一版明确不实现 DHCP、TCP、IPv4 分片、jumbo、多会话和高级网络管理。

文档口径：第 1 至 8 节是稳定的架构、接口和验收契约；第 9、10 节是随实现推进更新的状态与执行清单。任何“通过”结论都必须绑定 Git commit、复现命令、testbench/top、工具版本和报告路径；工作区 WIP 或单个 focused test 通过不能提升为整个 Gate 通过。

## 2. 唯一架构

```text
Host rawudp
    <-> controller-side physical 25G NIC / IPv4 routing
    <-> LC-LC optics
    <-> physical SFP1 / RTL index 0
    <-> Taxi 25G GTY + 64-bit MAC AXIS
    <-> Corundum eth_axis + ARP/IPv4/UDP 64-bit minimum stack
    <-> thin asmcehnk UDP payload adapter
    <-> IfComToFifo: RX 64-bit / TX 256-bit
    <-> original AMDUSB4 asmcehnk_fifo + asmcehnk_mux
    <-> original AMDUSB4 CFG/TLP/BAR/shadow helpers
    <-> AS02 UltraScale+ CQ/CC/RQ/RC adapters
    <-> pcie4_uscale_plus_0
```

时钟域固定为：

```text
SFP1 recovered RX clock
    -> one Taxi asynchronous frame FIFO
SFP1 TX/network clock (~402.8 MHz)
    -> Ethernet/ARP/IPv4/UDP
    -> asmcehnk UDP adapter
    -> asmcehnk_fifo/mux
    -> existing/new narrow asynchronous FIFOs only
PCIe user clock (250 MHz)
    -> cfg_mgmt
    -> CQ/CC/RQ/RC adapters
    -> BAR/shadow/TLP logic
```

规则：

- 整帧 Ethernet 流量不能进入 PCIe 250 MHz 域。
- SFP1 RX 完整帧只跨一次到 SFP1 TX/network 域。
- TX 在 network 域直接进入 SFP1 MAC，不再增加 PCIe-to-MAC 整帧 CDC。
- TLP、CFG 和 shadow 使用 AMDUSB4 原有双时钟设计意图；缺少的 CFG CDC 只补薄 FIFO，不重写寄存器语义。
- 不保留旧 byte-at-a-time UDP parser、FT601 `256->32` transport 窄化或 Taxi/Zircon 32-bit parser 作为备用路径。

## 3. 复用边界

### 3.1 原样复用或仅做连接级调整

- `asmcehnk_header.svh`
- `asmcehnk_fifo.sv`：保留 `0x77` 分类、command、loopback、CFG/TLP mux；仅在 AS02 副本删除 activation lock。
- `asmcehnk_mux.sv`
- `asmcehnk_tlps128_bar_controller.sv`
- `asmcehnk_tlps128_cfgspace_shadow.sv`
- `asmcehnk_pcie_tlp_a7.sv` 仅作为历史 A7 参考；AS02 不把该 A7 wrapper 或其文件加入 active source roots。
- AMDUSB4 的 FIFO/BRAM/DROM XCI、COE，只保留当前实例化依赖。
- Taxi 的 AS02 top shell、PCIe/SFP pinout、GTY/MAC 和必要 reset/clock helper。

允许的连接级调整仅包括 include path、模块名冲突、显式 clock/reset 接线、UltraScale+ 边界 adapter 和已证明必要的 CDC。不得为了统一代码风格重写已工作的 AMDUSB4 framework。

当前复用审计结论：

- `asmcehnk_header.svh`、`asmcehnk_tlps128_bar_controller.sv` 和 active `asmcehnk_tlps128_cfgspace_shadow.sv` 与 AMDUSB4 副本逐字节一致。
- `asmcehnk_mux.sv` 仅有行尾差异，RTL 语义未改。
- `asmcehnk_fifo.sv` 的协议分类、command/loopback/CFG/TLP 数据路径未重写；差异集中在删除 activation/DNA lock 及屏蔽 AS02 不适用的 `STARTUPE2`。
- `asmcehnk_pcie_tlp_a7.sv` 不实例化 A7 wrapper；AS02 的 raw-128 FIFO/filter/mux 连接由 `asmcehnk_pcie_tlp_us.sv` 和 `asmcehnk_tlps128_dst_fifo_us.sv` 承担，AMDUSB4 的 packet/FIFO 语义保持不变。
- AS02 新代码集中在 board top、25G UDP transport、UltraScale+ cfg/CQ/CC/RQ/RC adapter 和必要 CDC，不向 AMDUSB4 核心反向渗透板级逻辑。

### 3.2 必须替换

| 原实现 | AS02 实现 |
|---|---|
| FT601/FT245 transport | SFP1 25G UDP AXIS transport |
| NeTV2 RMII/FC1003 | Taxi 25G MAC/GTY + Corundum 64-bit UDP minimum stack |
| `pcie_7x_0` / A7 wrapper | `pcie4_uscale_plus_0` + CQ/CC/RQ/RC adapter |
| A7 config-management glue | UltraScale+ `cfg_mgmt` bridge |
| board-specific top/XDC | `asmcehnk_as02mc04_top.sv` / `asmcehnk_as02mc04.xdc` |

### 3.3 明确不导入

- `pcie_7x_0.xci`、`pcie_7x_0_core_top.v` 或其 generated wrapper。
- NeTV2 `FC1003_RMII.*`、`asmcehnk_netv2_top.sv`、A7 board/XDC。
- Corundum mqnic、DMA、PCIe、驱动和 Nexus K3P S board top。
- 第二套 ARP/IPv4/UDP stack。
- 未实例化的兼容 stub、历史 top、重复 XDC 和手工复制的 Vivado generated output products。

## 4. 工程结构与构建入口

```text
as02_asmcehnk_25g/
  src/
    asmcehnk_as02mc04_top.sv
    asmcehnk_as02mc04.xdc
    asmcehnk_as02_core.sv
    asmcehnk_com_axis_udp_25g.sv
    asmcehnk_eth_axis_udp_25g.sv
    asmcehnk_udp_tx_packetizer_256.v
    asmcehnk_pcie_cfg_us.sv
    asmcehnk_pcie_tlp_us.sv
    <reused AMDUSB4 framework and Taxi shell sources>
  ip/
    pcie4_uscale_plus_0.xci
    pcie4_uscale_plus_0.tcl
    pcie4_uscale_plus_0_profile.tcl
    <only instantiated FIFO/BRAM/DROM XCI and COE>
  vivado_generate_project.tcl
  vivado_generate_project_as02.tcl
  vivado_build.tcl
  vivado_build_as02.tcl
  generate_as02mc04.bat
  build_as02mc04.bat
  run_as02_udp_tests.ps1
  run_as02_pcie_tests.ps1
  run_as02_pcie_profile_tests.ps1
  tests/
    tb_udp_rx.sv
    tb_udp_arp_tx.sv
    tb_udp_packetizer.sv
    tb_pcie_flow_control.sv
    tb_pcie_leechcore_128_256.sv
```

构建规则：

- `vivado_generate_project.tcl` 是统一生成入口，调用 `vivado_generate_project_as02.tcl`。
- `vivado_build.tcl` 是统一构建入口，调用 `vivado_build_as02.tcl`。
- `vivado_generate_project_as02.tcl` 是 source roots、XCI、XDC、top 和 generics 的权威清单。
- clean/QoR 工程通过环境变量 `AS02_PROJECT_DIR=<temporary-directory>` 隔离生成；未设置时仍保持 AMDUSB4 风格，在工程根目录生成 `fpga.xpr`。
- PCIe XCI 是工程主输入；`pcie4_uscale_plus_0_profile.tcl` 是项目自有的 UltraScale+ 配置画像，承担 AMDUSB4 手改 `pcie_7x_0_core_top.v` 参数区的同等角色；`pcie4_uscale_plus_0.tcl` 使用该画像重建 XCI，工程生成入口逐项校验已提交 XCI，避免两者漂移。
- 构建前校验 part 已安装；禁止依赖 `git rev-parse` 才能生成工程。
- 临时 project、reports、`.Xil`、`*.runs`、`*.gen`、`*.cache` 不提交。

标准 Vivado-only 验证入口：

```powershell
Set-Location <repository>\as02_asmcehnk_25g
.\run_as02_udp_tests.ps1
.\run_as02_pcie_tests.ps1
.\run_as02_pcie_profile_tests.ps1
$env:AS02_PROJECT_DIR = '.tmp_vivado_release_<commit>'
vivado -mode batch -source vivado_build.tcl -notrace
```

两个仿真入口均执行 `xvlog -> xelab -> xsim`，逐 top 检查独立 PASS marker，并把 UTF-8 transcript 保存到 `.tmp_udp_tests/*_xsim.log` 或 `.tmp_pcie_tests/*_xsim.log`。这些 focused test 不替代 Root Complex、MAC/GT 或实板测试。

## 5. PCIe 功能边界

### 5.0 LeechCore/raw-TLP 兼容边界

- LeechCore/AMDUSB4 的协议契约继续锁定在原 `IfAXIS128` raw TLP：`tdata[31:0]=DW0`、`tdata[63:32]=DW1`、`tdata[95:64]=DW2`、`tdata[127:96]=DW3/payload`，`tkeepdw[3:0]` 表示有效 DWORD，`tuser[0]`/`tuser[1]` 表示 first/last，`tuser[8:2]` 表示 one-hot BAR hit。
- `pcie4_uscale_plus_0` 的 256-bit CQ/CC/RQ/RC 只是 UltraScale+ PCIe IP 边界，不改变 LeechCore host/rawudp 协议，也不把 AMDUSB4 BAR、shadow、FIFO、mux 或 raw-TLP engine 改成 256 bit。
- 128/256 descriptor、payload、DWORD byte order、`tkeep/tlast/tuser` 和 backpressure 转换只允许位于 `asmcehnk_pcie_tlp_us.sv`；AMDUSB4 reusable framework 仍只观察 128-bit raw TLP。
- 兼容性回归的 raw header/byte-order 基准来自 LeechCore 风格 3DW/4DW MRd/MWr/CplD builder（本地交叉参考 `dmac/proxy_driver/test/proxy_test_common.h`），必须覆盖 CQ MRd32/MWr32、RQ MRd32/MRd64/MWr32/MWr64、RC CplD、CC CplD、multi-beat 和输出 backpressure；这些 valid-path golden vectors 通过后，才能把 256-bit 边界标为 `FOCUSED_SIM_PASS`。
- focused xsim 证明的是 RTL 边界逐字段兼容性；Root Complex、真实 PCIe hard IP、LeechCore host transaction 和实板 DMA 仍按独立 Gate 取证。

### 5.1 CQ/CC：Host 访问 FPGA BAR0（P0）

当前状态：`IMPLEMENTED` / `FOCUSED_SIM_PASS` / `ROOT_COMPLEX_AND_BOARD_PENDING`。AMDUSB4 原 BAR controller 已原样复用，AS02 CQ-to-raw-TLP 与 raw-Cpl-to-CC 适配器已接入；以下条目同时包含已实现的有效请求路径和仍需补齐的异常请求验收，不表示 BAR 主体尚未移植。

```text
Host BAR MRd/MWr -> CQ descriptor -> raw 128-bit TLP
    -> reused cfgspace/BAR controller
    -> raw Cpl/CplD -> CC descriptor -> Host
```

要求：

- 支持当前 non-straddled 256-bit CQ/CC 接口。
- 正确生成/解析 `tdata/tkeep/tlast/tuser`。
- CQ BAR id 映射到 AMDUSB4 one-hot BAR hit 语义。
- payload DWORD 字节序必须和 AMDUSB4 BAR engine 一致。
- CQ 一旦接收首拍，unsupported、malformed 或长度不一致的请求也必须继续 drain 到该包 `tlast`，不能阻塞后续合法请求。
- posted MWr 失败时整包丢弃且 BAR/shadow 不得发生部分写入；多拍 MWr 必须在向原 BAR engine 暴露前完成长度、`tkeep`、`tlast` 和 request type 校验，或使用等价的原子提交机制。
- 可安全提取 requester/tag 的 unsupported non-posted MRd 必须返回不带数据的 UR Completion；只有连请求身份都无法可信提取的 malformed 包才允许 drain/drop，并记录 sticky error/counter。静默丢弃 MRd 会使 host 超时，不算合法拒绝。

### 5.2 RQ/RC：FPGA 主动访问 Host 内存（P0）

当前状态：`IMPLEMENTED` / `FOCUSED_SIM_PASS` / `ROOT_COMPLEX_AND_BOARD_PENDING`。AMDUSB4 `IfPCIeFifoTlp` raw MRd/MWr 数据面已通过 AS02 RQ 发出，RC Cpl/CplD 已转换回原 raw completion 路径；剩余工作是扩大错误矩阵并做真实 Root Complex/host memory 端到端验收。

- raw MRd/MWr -> RQ descriptor。
- RC Cpl/CplD -> raw completion -> `IfPCIeFifoTlp`。
- 必须验证 length、byte-enable、背压、多 beat completion 和 outstanding limit。
- 第一阶段允许限制 outstanding 数量，但必须显式施加 backpressure 并导出状态，不能静默丢 TLP。

RQ sequence、MRd tag 和 RC completion progress 是三套独立生命周期，不能共用一个“outstanding”概念：

| 生命周期 | 分配/占用点 | 唯一释放点 | 禁止行为 |
|---|---|---|---|
| RQ sequence credit | 合法 MRd/MWr 首拍被 RQ adapter 接收 | PCIe core 返回匹配的 `pcie_rq_seq_num*_vld` | 不得等 RC completion 才释放，也不得用 tag 释放 |
| MRd client tag | 合法 MRd 首拍被接收；保留原 raw TLP 8-bit tag | 匹配 tag 的 terminal RC completion 被完整接收 | split CplD 的中间分片不得释放；MWr 不占 tag |
| RC completion progress | 第一份匹配 Cpl/CplD 到达 | 成功 completion 的剩余 byte count 归零，或匹配的终止错误 completion 完整转发 | 不得只看到 tag 或第一拍就认定完成 |

第一版基线为最多 32 个尚未收到 sequence acknowledgement 的 RQ packet；MRd 使用 256-bit pending-tag bitmap，重复 tag 必须 backpressure 到原 tag terminal completion。成功 split CplD 只有在 `byte_count` 已由本 completion payload 覆盖时才能释放 tag；UR/CA 等无后续 payload 的终止状态在错误 completion 完整转发后释放。unknown sequence acknowledgement、unknown completion tag、重复 tag 和计数下溢必须形成独立 sticky error/counter，并进入 debug/evidence map。

### 5.3 Config management 与两类 shadow（P1）

两个文件不是重复实现：

- `asmcehnk_tlps128_cfgspace_shadow.sv`：当前 raw-128 TLP 路径使用的 active shadow。
- `asmcehnk_pcie_cfgspace_shadow.sv`：较旧 `IfShadow2Tlp` 版本，仅作兼容参考，不加入 active source roots。

CFG bridge 保持 AMDUSB4 语义：

- system/network -> PCIe：64-bit async command FIFO。
- PCIe -> system/network：32-bit async response FIFO。
- `rw[20] = 1`：`CFGSPACE_STATUS_REGISTER_AUTO_CLEAR`。
- `rw[21] = 0`：`CFGSPACE_COMMAND_REGISTER_AUTO_SET`。
- 1 ms tick 按 250 MHz 为 `250000` cycles。
- DRP 兼容门不再以 stub 作为当前状态：LeechCore 固定读取完整 128 个 16-bit word（0x100 bytes），word 7/8 必须分别返回 `16'hf000`/`16'hffff`，其余未写地址确定返回 0；AS02 边界保留 0..127 任意地址写入后读回语义，地址 >=128 返回 0。该镜像属于 UltraScale+ 适配层，不改 AMDUSB4 framework。

### 5.4 PCIe XCI 配置策略

- `pcie_7x_0.xci` 只用于核对 VID/DID、class、BAR、PM、DSN、AER、MSI、VSEC 等意图；不能导入或 retarget。
- UltraScale+ GUI/XCI 不会暴露和 7-series wrapper 完全同名的参数；以 `pcie4_uscale_plus_0.xci` 实际属性和 generated core 为准。
- AMDUSB4 的 `pcie_7x_0_core_top.v` 不是纯净生成物：文件骨架来自 7-series IP generator，但 CFG ID、capability order、BAR 和多项 capability 默认值由项目手工维护。AS02 不复制该 generated RTL，而在 `ip/pcie4_uscale_plus_0_profile.tcl` 中维护对应的 `PF0_*`/BAR/capability/link 属性，再由 XCI 和 Vivado generated wrapper 落到 `PCIE40E4`。
- `pcie4_uscale_plus_0_profile.tcl` 顶部提供与 7-series 手工参数区同角色的可读变量，包括 `PCIE_ID_IF`、`CFG_VEND_ID/CFG_DEV_ID`、`CLASS_CODE`、BAR0、link/data-width、MSI/MSI-X、DSN、AER、PM、VC、RBAR、ARI、SR-IOV、VSEC 和 extended CFG；下方映射字典直接使用这些变量设置 XCI，参数区不是仅供阅读的副本。
- `vivado_generate_project_as02.tcl` 在导入 XCI 后立即执行 profile 一致性检查；`run_as02_pcie_profile_tests.ps1` 还会在独立 KU3P 工程中验证 checked-in XCI、profile apply 路径、`generate_target all`，并核对 generated synthesis wrapper 中的 link/AXI/ID/BAR/capability 实参。任何硬 IP 字段修改必须先改 profile，再重建 XCI并通过该回归。
- 当前 checked-in XCI/Profile 为 `10EE:0666`、revision `02`、subsystem `10EE:0007`、class `0C0340`、MSI 1 vector、DSN enabled、MPS 512 B、extended tag enabled。上游 `pcileech-fpga` commit `c538c4170678c13f723dc921905fb81ff3c71d8e` 的 AC701/FT601、NeTV2、75T、100T、ZDMA 等历史 `pcie_7x_0.xci` 使用 `10EE:0666`/`020000`/4 KiB 32-bit BAR/MSI-on/MSI-X-off；AS02 保留其 VID/DID、BAR 和 MSI envelope，只执行 class-only `020000 -> 0C0340` 修正，使 PF0 不再声明为 network controller。该改动不改变 SFP1 UDP transport；PF0 与控制端物理 25G NIC 仍是两个独立平面。
- 当前 `CFG_EXT_IF=false`，并且 `EXTENDED_CFG_EXTEND_INTERFACE_ENABLE=false`、`LEGACY_CFG_EXTEND_INTERFACE_ENABLE=false` 已在 checked-in XCI 与生成 wrapper 中核对。这样 optional extended-CFG 端口由 PCIe4 primitive 以零值关闭，活动 RTL 只依赖 `cfg_mgmt` 与 raw-TLP shadow；后续若要开放 extended configuration，必须新增独立 adapter 和专门回归，不在本轮隐式打开。
- `AMDUSB4/pcie_7x/pcie_7x_0_core_top.v` 的活动手工画像为 `1022:1669`、revision `01`、subsystem `1179:01BA`、class `0C0340`，BAR0/BAR1 表达 64-bit non-prefetchable 512 KiB，MSI 与 8-vector MSI-X 打开；这与旧 `AMDUSB4/ip/pcie_7x_0.xci` 的 `10EE:0666` 默认值不是同一权威来源。
- 当前 AS02 BAR0 配置为 4 KiB、32-bit、non-prefetchable，与上游 PCILeech/NeTV2 transport contract 一致。完整切换到 AMDUSB4 活动 `1022:1669 / 64-bit BAR / MSI-X` 画像属于独立 personality 变更，需同时补齐 64-bit BAR 高地址/CQ 4DW、MSI-X table/PBA/trigger 和 UltraScale+ config-shadow 边界；这些门槛关闭前保持现有 VID/DID、BAR 和 MSI-only envelope。
- AER 已按 AMDUSB4 基线关闭；除非后续实现并验证完整 AER 行为，不得重新启用。
- `legacy_ext_pcie_cfg_space_enabled` 和 `ext_pcie_cfg_space_enabled` 均已关闭，外层 `cfg_ext_*` 端口已删除；配置访问继续使用已实现的 `cfg_mgmt` 和 raw-TLP shadow 路径。
- PM/DSN/MSI/AER/VSEC 是否存在必须以 Vivado/SynthPilot 读取 XCI/generated-IP 属性的结果记录，不能按旧 wrapper 参数名猜测。
- 7-series generated hierarchy 为 `pcie_7x_0_core_top.v -> pcie_7x_0_pcie_top`；AS02 的对应 hierarchy 为 `pcie4_uscale_plus_0.v -> pcie4_uscale_plus_0_pcie4_uscale_core_top.v -> pcie4_uscale_plus_0_pipe.v -> PCIE40E4`。其中与 `pcie_7x_0_core_top.v` 最接近的一一对应文件是 `pcie4_uscale_plus_0_pcie4_uscale_core_top.v`。
- AS02 source-control 只保存权威输入 `ip/pcie4_uscale_plus_0.xci` 和可复现 Tcl。Vivado 在 `<AS02_PROJECT_DIR>/fpga.gen/sources_1/ip/pcie4_uscale_plus_0/` 生成上述 wrapper/core/PIPE/GT RTL，并在 top synthesis compile order 中使用 `pcie4_uscale_plus_0.dcp`；generated `core_top.v` 不作为手工维护源码复制回仓库。
- `asmcehnk_pcie_cfg_us.sv`、`asmcehnk_pcie_tlp_us.sv` 是 AMDUSB4 raw CFG/TLP 与 UltraScale+ `cfg_mgmt/CQ/CC/RQ/RC` 的用户逻辑适配层，不替代 generated PCIe core top。实际层级为 `asmcehnk_as02mc04_top -> fpga -> pcie4_uscale_plus_0`，并行的用户逻辑层级为 `fpga_core -> asmcehnk_as02_core -> asmcehnk_pcie_cfg_us/asmcehnk_pcie_tlp_us`。
- 2026-08-03 对 clean release 工程执行 Vivado/SynthPilot 核查：project part 为 `xcku3p-ffvb676-2-e`，IP 为 `pcie4_uscale_plus:1.3 Rev.28`、`IS_LOCKED=0`、Up-to-date，OOC `pcie4_uscale_plus_0_synth_1` 与 top `synth_1/impl_1` 均完成；OOC synthesis log 明确综合 `pcie4_uscale_plus_0_pcie4_uscale_core_top`、`pcie4_uscale_plus_0_pipe` 和硬核 primitive `PCIE40E4`。

## 6. 25G UDP 数据面

### 6.0 LeechCore RawUDP wire contract

LeechCore 的 UDP transport 直接把原 FPGA 写缓冲区作为 UDP payload 发送，AS02 必须复现 NeTV2/AMDUSB4 transport 的字节和分段顺序，host 端不增加 AS02 专用 endian workaround：

| 方向 | LeechCore/NeTV2 wire 顺序 | AS02 边界处理 | AMDUSB4 内部保持 |
|---|---|---|---|
| Host -> FPGA | 每个 8-byte command 按 C buffer 顺序发送，`0x77` 为最后一个 wire byte | 64-bit Ethernet AXIS beat 做完整 byte reversal | `dcom.com_dout[7:0]=8'h77`、`[63:32]=TLP/data` |
| FPGA -> Host | 每个 32-byte mux block 为 status DWORD first，再 data0..data6；每个 DWORD 为 MSB byte first | 256-bit mux word在进入 width adapter 前做完整 byte reversal | 原 `asmcehnk_mux` 的 status/data/context 布局不改 |
| PCIe TLP | LeechCore 标准 3DW/4DW MRd/MWr/Cpl/CplD | 仅在 PCIe IP 边界做 raw-128 与 CQ/CC/RQ/RC-256 转换 | `IfAXIS128`、BAR、shadow、FIFO/mux 不改 |

权威 golden vector 包括 LeechCore UDP read/inactivity command `01 00 01 00 80 02 23 77`，进入 `asmcehnk_fifo` 后必须为 `64'h01000100_80022377`。旧 AMDUSB4 `fifo_256_32_clk2_comtx` 的 Vivado behavioral model已实测为 bits `[255:224]` 到 `[31:0]` 依次读出，不能用 AXIS adapter 默认的低位分段顺序直接替代。

### 6.1 RX

- Taxi MAC 输出 64-bit AXIS。
- 完整 RX frame 通过 Taxi async frame FIFO 跨到 SFP1 TX/network 域。
- `eth_axis_rx` 拆 Ethernet header/payload。
- `udp_complete_64` 处理 ARP、IPv4 checksum、UDP RX/TX 和 ARP cache。
- 仅接收目标 IP、目标 UDP port、非分片、payload 长度为 8-byte 对齐的合法 UDP frame。
- Ethernet AXIS lane 0 是首个 wire byte；transport 边界完整反转 8 个 byte lane，使 LeechCore payload 的尾部 `0x77` 回到 `IfComToFifo.com_dout[7:0]`。
- `IfComToFifo.com_dout[63:0]` 每拍一个完整 protocol word，进入原 `asmcehnk_fifo` 后的位布局与 AMDUSB4/NeTV2 一致。
- 错误帧、partial word 和 unsupported frame 不得向 asmcehnk 提交半包状态。

### 6.2 TX

- `IfComToFifo.com_din[255:0]` 不再经过 FT601 `256->32` FIFO。
- 原 `asmcehnk_mux` 256-bit word先做完整 byte reversal，恢复旧 AMDUSB4 width-conversion FIFO 的 status-first、data0..data6 和 DWORD MSB-byte-first wire顺序，再进入 `asmcehnk_udp_tx_packetizer_256.v`。
- `asmcehnk_udp_tx_packetizer_256.v` 把 wire-order 256-bit word 分成有边界的 UDP payload frame。
- 单包最大 32 个 256-bit word，即 1024-byte payload；短响应通过 16-cycle idle boundary 结束。
- 16-cycle idle 只统计“已缓存至少一个响应字且上游 `i_data_valid=0`”的连续 network-clock 周期；新响应字在阈值前出现时计数清零，当前缓存字按普通 body word 推进。
- idle 阈值到达后帧边界即被锁定；若 payload FIFO 或 descriptor FIFO backpressure，尾字、`tlast` 和 length 必须保持稳定直到两者同周期握手，等待周期不得重新计数、拆成新包或接收下一响应字。
- payload frame FIFO 做 `256->64` width conversion；独立 descriptor FIFO保存对应 UDP length。
- frame tail 与 length descriptor 必须原子提交；payload/descriptor 不能错位。
- 只回复最近一次通过过滤的合法 peer IP/port；没有合法 peer 时必须对 asmcehnk TX 施加回压。

### 6.3 吞吐目标

- Corundum `udp_complete_64` RX/TX 均可持续 64 bit/周期。
- AS02 Taxi low-latency network clock 约 402.8 MHz，总线能力约 25.78 Gbit/s，可覆盖 25GbE MAC 线速。
- 标准 MTU 1500、UDP payload 1472 bytes 时，计入 preamble/SFD、L2/L3/L4 header、FCS 和 IFG，理论应用净荷约 `23.93 Gbit/s`。
- 该数字是理论上限，不是板上测量结果。只有连续帧、背压、丢包计数和 host 实测通过后才能宣称达到 25 Gbit/s 级 transport。

### 6.4 SFP lane 与电气策略

- 板卡物理 SFP1 映射到 `sfp_tx/rx[0]` 和 Taxi lane 0，作为唯一 UDP transport。
- 板卡物理 SFP2 映射到 `sfp_tx/rx[1]` 和 Taxi lane 1；`asmcehnk_as02_core.sv` 固定其 AXIS `tvalid=0` 并持续 RX drain，因此不会产生或接收业务 transport 帧。
- AXIS idle 时 PCS 仍可能发送 64b/66b idle；当前 top 也没有独立 SFP2 `TX_DISABLE`/模块电源控制端口。因此“空闲”指不承载数据帧，不把它表述为光模块断电或激光关闭。曾评估的 `GT_TX_PD/GT_RX_PD` 静态参数方案因其同步链依赖 lane user clock，未在没有 post-route/实板闭环证据时纳入正常图像。
- 活动 XDC 当前保持 SFP GPIO/I2C `LVCMOS33`；板卡库中的 `LVCMOS18` 元数据不作为本工程约束来源。Bank 86/87 的 VCCO 实测记录必须进入实板 evidence 后，才把该电气项标记为关闭。

## 7. 强制开发与核查流程

### 7.1 Erie Verilog Generator Skill（必须）

所有新增或修改的 AS02 边界 RTL 在提交前必须调用 **`erie-verilog-generator` skill**：

- 新生成的 synthesizable Verilog 使用 `.v`、Verilog-2001、Erie strict，避免 `function/task`。
- 新 `.v` 必须执行 formatter-AST deliverable gate，验收为 `errors=0` 且 `strict_warnings=0`。
- 现有 `.sv` 边界层至少执行 Erie independent static lint/结构审查，再由 Vivado `read_verilog -sv`/综合确认。
- AMDUSB4 原 framework 不做纯风格重写；Erie 用于核查新增/改写边界，不用于制造无意义 diff。
- 任何 gate 报告只能证明对应静态规则，不等价于仿真、综合、实现或实板通过。

标准命令：

```powershell
python <verilog-generator>/scripts/python/validation/verilog_generated_deliverable_gate.py `
  src/asmcehnk_udp_tx_packetizer_256.v --json deliverable_gate.json --markdown deliverable_gate.md
```

### 7.2 SynthPilot MCP（必须）

Vivado 工程核查、IP 属性查询、综合/实现状态、timing、CDC、methodology 和仿真必须优先使用 **SynthPilot MCP**，而不是只看 GUI 截图或旧日志：

1. `list_vivado` / `switch_vivado` 确认目标实例和工程路径。
2. `get_project_info` 确认 part、top、source roots 和 Vivado version。
3. 查询/核对 `pcie4_uscale_plus_0` 的真实 XCI/generated-IP 属性。
4. clean synthesis 后检查 error、critical warning、black box、locked IP。
5. implementation 后读取 WNS/TNS、pulse-width、utilization、CDC 和 methodology。
6. 仿真使用 `sim_compile`、`sim_run` 和结构化 report；长任务使用 async/status 接口。

不得关闭或终止用户正在使用的其他 Vivado 实例。若 SynthPilot transport 暂时不可用，可用同一 Vivado 的 Tcl/batch 路径继续，但必须在记录中说明 fallback，恢复后再用 MCP 复核。

### 7.3 Git（必须）

- 工程是 Git 仓库；每个完成且验证过的代码/文档修改都要提交。
- 每个提交只包含一个清晰主题，例如 `25G datapath`、`PCIe XCI capability fix`、`documentation cleanup`。
- 临时工程、生成物、验证报告和未完成实验不得混入正式提交。
- 不把“综合通过”和“功能通过”写进同一个未经证据支持的提交说明。
- 状态文档中的每条 PASS 至少记录 `<commit, command/script, testbench/top, Vivado version, report/log path, timestamp>`；临时大日志可以不提交，但其路径和 SHA256 必须进入状态/evidence index。
- 工作区有未提交 RTL 时，测试结果标记为 WIP evidence；只有对应 RTL 和测试一起提交后，才能成为 commit-bound evidence。

### 7.4 实板可观测性与证据采集（必须）

实板联调不依赖 GUI 截图或人工抄数。权威调试图像由
`as02_asmcehnk_25g/vivado_build_debug_as02.tcl` 在独立
`.tmp_vivado_debug` 工程中产生：

- 只有定义 `AS02_HW_DEBUG` 的调试图像保留观测总线；正常图像没有这些总线或 ILA 负载。
- `as02_net_ila` 位于 SFP1/network 时钟域，深度 2048，输入 pipeline 为 2；捕获 MAC RX/TX、`IfComToFifo` RX64/TX256 和网络/asmcehnk handshake。
- `as02_pcie_ila` 位于 PCIe 250 MHz user clock 域，深度 2048，输入 pipeline 为 2；捕获 CQ/CC/RQ/RC 的 256-bit data、`tkeep`、`tuser`、link/LTSSM、cfg_mgmt 和 sequence 状态。
- 两个时钟域必须使用两个 ILA，禁止把异步网络和 PCIe 信号塞入同一个采样时钟。
- 第一版不放能改变功能状态的 VIO output。静态状态用 ILA immediate capture 读取；需要 soft reset、force-ready 或 loopback 时，必须另行评审，不得让 VIO 绕过真实协议路径。
- `as02_net_vio` 和 `as02_pcie_vio` 均为只读 input probe，没有 VIO output；用于不触发深度采集时读取稳定状态，不改变协议状态。
- 调试 constraint 使用 `save_constraints_as` 保存到临时工程的本地副本；禁止 `save_constraints` 改写 source-controlled board XDC。
- 调试图像 route 后仍必须同时满足 setup/hold slack 非负，失败时脚本不交付可烧录图像。

关键 trigger 位：

| ILA | probe | 位 | 事件 |
|---|---|---:|---|
| `as02_net_ila` | `dbg_net_control` | 2 | SFP1 MAC RX valid，适合抓 ARP/任意入帧 |
| `as02_net_ila` | `dbg_net_control` | 9 | 合法 UDP payload 已到 `IfComToFifo` |
| `as02_net_ila` | `dbg_net_control` | 10 | asmcehnk 产生 TX256 response |
| `as02_net_ila` | `dbg_net_control` | 6 | SFP1 MAC TX valid |
| `as02_pcie_ila` | `dbg_pcie_control` | 1 | PCIe `user_lnk_up` |
| `as02_pcie_ila` | `dbg_pcie_control` | 16 / 19 | CQ request / CC response |
| `as02_pcie_ila` | `dbg_pcie_control` | 22 / 25 | RQ request / RC completion |
| `as02_pcie_ila` | `dbg_pcie_control` | 28 / 29 | RQ sequence acknowledgement 0/1 |

推荐实板协作方式：

1. 板卡 PCIe x8、JTAG 和 physical SFP1/index 0 接到运行 Codex/Vivado 的同一台主机；SFP2 不参与测试。
2. LC-LC 只表示光纤连接器；两端仍必须使用同类型/同波长的 25G SFP28 光模块，TX/RX 极性交叉，主机网卡必须支持 25 Gbit/s。10G SFP+/Intel X520 不能与当前固定 `25.78125 Gbit/s` GT image 建链。
   - **LED 判定规则**：先区分“光模块外壳上的指示灯”和“板卡 DS2/DS3”。光模块灯亮通常只说明模块已供电、发射器已启用或模块内部状态正常；它不等价于 FPGA 已完成 25G PCS/PMA block-lock，也不等价于主机网卡已经建立链路。模块的 `RX_LOS`/`TX_FAULT` 是独立的管理状态信号，必须结合 I2C/管理引脚和 MAC `rx_status` 一起判断。
   - 当前板卡约束中 `sfp_led[0]` 位于 `B12 (DS3)`、`sfp_led[1]` 位于 `C12 (DS2)`；RTL 在 `src/fpga_core.sv` 中将它们驱动为 `!sfp_rx_status[0/1]`。因此 DS3/DS2 亮灭反映的是 FPGA MAC 接收到的 RX 状态，且为反相显示；它们与模块自身灯是两套独立指示。
   - 本项目策略为：物理 SFP1/index 0 是 UDP transport，SFP2/index 1 保持 idle。SFP1 的 PASS 必须以 `sfp_rx_status[0]`、MAC block-lock、主机网卡 25G speed、ARP/UDP 收发和 ILA/计数器证据共同确认，单看任一盏灯都不作链路 PASS 依据。
3. 仅在**控制端用于 LC-LC 直连的物理 25G NIC**上设置与 FPGA endpoint 同网段的唯一地址，并告知 Codex Windows interface alias；不要只发送“网卡 1”之类不稳定名称。默认 FPGA UDP endpoint 为 `192.168.0.222/24`，`192.168.0.10/24` 只是示例源地址，`192.168.0.X/24` 中任一未占用地址均可使用，直连接口不配置默认网关。若控制端和 PCIe 目标端是同一台主机，物理 NIC 与 PCIe PF0 仍是两个独立接口；该 IPv4 只负责 SFP1 的 Ethernet/ARP/IPv4/UDP 路由，不改变 PF0 的 VID/DID/class/BAR，也不使 PF0 变成网卡。
4. 烧录后先执行 `test_as02_sfp1.ps1 -InterfaceAlias <alias>`。只有网卡 RX/TX 均为 25G、ARP 为 `02:00:00:00:00:de`、rawudp register probe 和 loopback 全部通过，工具才输出 `AS02_SFP1_NETWORK_TEST_PASS`；结果保存在 `.tmp_sfp1_test/`。
   默认压力项还包括 184 个 64-bit command 的标准 MTU 满载 loopback、100 轮 × 128 command 唯一序列连续校验、错误 UDP port 静默拒绝、非 8-byte 对齐 payload 静默拒绝，以及测试前后 NIC error/discard 计数增量为 0。缺失、重复、乱序或数据错误任一非零即失败。Python 报告的 `functional_payload_mbps` 只用于回归比较，不作为 25G MAC 线速证据。
5. **优先不要手工烧录**：由 SynthPilot `program_device` 同时装载匹配的 `fpga_debug.bit` 和 `fpga_debug.ltx`，避免 bit/ltx 串版。如果已经手工烧录，必须提供所用 bit/ltx 的完整路径和 SHA256。
6. Codex 用 SynthPilot `hw_ila_list/get_status/set_trigger/run/wait/read_data` 先 arm，再发送 ARP、UDP、BAR 或 DMA stimulus；不得先发包后截图。
7. 同时运行 `collect_as02_evidence.ps1 -InterfaceAlias <alias>`，收集 source/image hash、控制端物理 25G NIC 计数、ARP、WHEA/Kernel-PnP 日志，并在已安装 tshark/Npcap 时抓 `arp or udp port 28474` 的 pcapng。脚本默认从 tracked PCIe profile 派生 Windows PnP VID/DID/class；也可显式传入 expected identity，禁止硬编码旧画像。
8. 同一台主机无需人工上传日志，Codex 可直接读取 CSV/pcap/summary。若板卡在另一台主机，只需附加脚本生成的 `board_evidence_*.zip`，不要逐张发送 ILA 截图。

每轮实板证据至少包含：匹配的 bit/ltx SHA256、Git commit、两个 ILA CSV、SFP1 pcapng、PCIe 枚举记录、网卡前后计数和执行过的 host stimulus 命令。没有这些证据时不能把“link 亮”写成 UDP、BAR 或 DMA 功能通过。

Host stimulus 使用根目录 `as02_udp_smoke.py` 的 dependency-free `probe`/`loopback`；证据目录中的 ILA CSV、stimulus JSON、pcapng、bit/ltx/map SHA256 由 `collect_as02_evidence.ps1` 汇总到 `manifest.json`。这些工具只负责可复现刺激和归档，不能替代 RTL Gate。

实板结果按以下四层独立判定，禁止用后一层的前置条件代替该层 PASS：

| 层级 | PASS 条件 | 权威证据 |
|---|---|---|
| 25G 物理链路 | SFP1 RX/TX link speed 均不低于 24 Gbit/s，测试期间无 link-down | `test_as02_sfp1.ps1` summary、NIC 状态与事件日志 |
| UDP 协议功能 | ARP MAC、register probe、单次 loopback、184-word MTU burst、唯一序列压力、错误端口与非对齐包拒绝全部通过；缺失/重复/乱序/错误均为 0 | `AS02_SFP1_NETWORK_TEST_PASS`、`.tmp_sfp1_test/*.json`、pcapng |
| FPGA 内部数据面 | `udp_headers_accepted`、`udp_payload_words_accepted`、`asmcehnk_tx256_words`、`udp_tx_frames` 与刺激一致；`protocol_errors`、RX bad-frame/overflow 和 NIC error/discard 增量均为 0 | 两个只读 VIO 的测试前后快照、触发后的 ILA CSV、NIC counter delta |
| 25G 持续吞吐 | 高性能 packet generator 连续至少 60 s 发送标准 MTU 合法 command；目标应用净荷不低于 23.0 Gbit/s，目标理论上限 23.93 Gbit/s；全程 0 丢包/错误/overflow/link-down | generator 报告、NIC byte/error counters、FPGA payload-word/frame counter 的模 `2^32` 增量、pcap 抽样 |

25G 网卡只证明主机接口具备相应链路能力，不能单独证明 RTL 已经线速运行。当前 Python request/response 工具用于功能、顺序和稳定性验证，不作为线速发生器；线速项必须由支持 25GbE 持续发包的 DPDK/MoonGen/TRex、专业流量仪或等价工具执行，并用 FPGA 计数器交叉核对。

## 8. 验证门槛与顺序

### Gate A：工程与依赖

- Vivado Tcl 能从干净目录生成工程。
- top 为 `asmcehnk_as02mc04_top`，part 为 `xcku3p-ffvb676-2-e`。
- 无 `FC1003_RMII`、`pcie_7x_0`、A7 top 或 Corundum NIC/DMA 依赖。
- source roots 不含重复网络栈、重复 XDC 或未实例化 compatibility stub。

### Gate B：asmcehnk golden vectors

- `0x77` TLP/CFG/loopback/command 分类。
- magic/version/device/custom registers。
- command read/write、TX priority、loopback。
- activation lock 已删除且未改变其他分类语义。

### Gate C：25G UDP

- ARP reply、IPv4 checksum、UDP port filtering。
- RX/TX 64-bit word order 和 256->64 conversion。
- LeechCore `device_fpga.c` RawUDP golden vector、`0x77` byte position、status-first 32-byte response block和 DWORD byte order。
- 1024-byte response segmentation、短包 idle boundary。
- payload/descriptor 原子性。
- continuous frames、RX/TX backpressure、reset、partial/malformed rejection。
- SFP1/index 0 收发；SFP2/index 1 的 AXIS TX idle/RX drain，不承载 transport 帧。

### Gate D：PCIe enumeration 与 CFG

- 枚举、VID/DID/class/BAR/capability 与 XCI 一致。
- cfg_mgmt read/write、`rw[20]`、`rw[21]`、BDF/BAR status 映射。
- active raw-128 shadow 与 legacy shadow 不混用。
- 记录协商速率/宽度、cold/warm reboot。

### Gate E：CQ/CC BAR0

- BAR0 MWr、MRd、CplD、byte enable、multi-beat、backpressure。
- unsupported/malformed CQ drain 到 `tlast`，后续合法包不发生 head-of-line blocking。
- invalid/partial MWr 不产生任何 BAR/shadow 部分写；unsupported non-posted MRd 返回 UR Completion。
- CC descriptor、payload、`tkeep/tlast/tuser` 在任意 backpressure 下保持稳定。

### Gate F：RQ/RC

- MRd、MWr、RC Cpl/CplD。
- sequence credit：32-packet limit、双 acknowledgement、unknown/duplicate acknowledgement 和 backpressure。
- MRd tag：重复 tag 阻塞、MWr 不占 tag、split completion 最后一段释放、UR/CA 终止释放、unknown tag 报错。
- RC progress：length/byte count/lower address、multi-beat、malformed、背压，不提前释放 tag。
- completion 能经 UDP 返回 host。

### Gate G：实现与实板

- Vivado 2024.2 implementation 完成，记录 WNS/TNS、pulse-width、utilization、CDC、methodology。
- black box 0、locked IP 0。
- 记录 source hash、bitstream path、PCIe link、SFP link、host OS/tool command。
- 板上顺序：Taxi baseline -> SFP1 25G loopback -> UDP command -> PCIe enumeration -> CQ/CC -> RQ/RC -> rawudp probe/read/write -> throughput/stability。

允许为时序、资源或接口风险提前探索后续 Gate，但不得在前置 Gate 未通过时把后续 Gate 标记为 PASS，也不得据此宣称 board-ready。探索结果必须标成 experiment/WIP，并在相关功能修改后重新验证。

## 9. 当前状态（历史记录截至 2026-08-03；最新复核见 9.1）

已完成并有历史证据：

- AMDUSB4 风格 `src/ip/root-Tcl` 工程骨架、AS02 top/XDC、Vivado Tcl 入口。
- KU3P/FFVB676 device support 可用，工程 top/part 已由 Vivado 2024.2 核对。
- AMDUSB4 reusable FIFO/BRAM/DROM、BAR、raw-128 shadow 和 TLP helper 已纳入。
- `pcie_7x_0`、FC1003/RMII、STARTUPE2 compatibility、未使用 Taxi standard-latency PHY/PTP 路径已从 active source roots 清除。
- SFP1/index 0 transport 已进入 RTL；SFP2/index 1 保持 AXIS TX idle/RX drain，不承载 transport 帧。
- AMDUSB4 BAR、raw-TLP FIFO/mux、两类 shadow 和主数据面已经移植；AS02 CQ/CC、RQ/RC adapter 的有效 MRd/MWr/Cpl/CplD 路径已实现、可综合并通过 focused xsim。当前尚未关闭的是异常包鲁棒性、Root Complex 和实板端到端验收，不是 BAR/DMA 主体缺失。
- UltraScale+ PCIe 已增加项目自有 49-field profile：checked-in XCI、独立 fresh `create_ip` 路径、主工程导入路径和 generated synthesis wrapper 映射均已通过 Vivado 2024.2 回归；当前 tracked bring-up profile 为 `10EE:0666`、class `0C0340`、BAR0 4 KiB、MSI/DSN enabled、MSI-X/AER/ARI/RBAR/VC/SR-IOV disabled，并显式锁定 `PCIE_ID_IF=false`。
- activation lock/DNA reader 已从 AS02 副本删除；对应 clean synthesis 曾达到 0 error / 0 critical warning、black box 0、locked IP 0，setup WNS `+0.349 ns`。该结果早于当前 25G 数据面重构，不能替代本轮 clean validation。

### 8.1 2026-08-31 当前 HEAD 验证闭环

- 验证源码版本：`0baf31c`（`Validate AS02 RQ path with generated CDC FIFOs`）。
- Vivado 2024.2 fresh build 使用器件 `xcku3p-ffvb676-2-e`，顶层 `asmcehnk_as02mc04_top`；综合、布局布线和 bitstream/bin 生成均完成。
- post-route setup `WNS +0.011 ns / TNS 0.000 ns`，hold `WHS +0.011 ns / THS 0.000 ns`；无未约束内部端点、无未加时钟寄存器、无组合环，全部用户时序约束满足。
- route status：`50340/50340` routable nets fully routed，routing errors `0`；DRC 无 error/critical warning，仅保留两个器件布局 warning 和一个无可布线负载 warning。
- methodology 的 `TIMING-54` 来自 PCIe4 UltraScale+ 生成核内部 scoped clock-group constraint；完整 `report_cdc -details` 的其余 Critical 项位于 Taxi GT reset/watchdog 或本工程“同步复位组合后送入 XCI FIFO 内建 reset synchronizer”的受控复位路径。它们必须保留在报告中，不以 waiver 隐藏；实板 reset/link 抖动测试仍是验收项。
- 当前回归重新通过 PCIe focused xsim 12 项、UDP focused xsim 4 项和 AMDUSB4 framework compatibility；内部 TLP 仍为 raw-128，256-bit 仅位于 CQ/CC/RQ/RC 与 UDP packetizer 边界。
- 生成产物：`fpga.bit` SHA-256 `E19E18A745FC86D90642EDC4701C21144D60B6DFEE1D06FAE56AAF79A6EBA7C3`；`fpga.bin` SHA-256 `1C48D16C089EB726BCC7A51BDD8F360D2257323CFB2E741C3A39B0B30A6C3EB7`。
- 以上结果允许进入易失性 JTAG 实板 bring-up；正式验收仍需 PCIe cold-boot 枚举、BAR0、raw TLP/DMA、SFP1 ARP/UDP、reset/relink、背压/丢包和持续吞吐证据，并先闭环 SFP GPIO/I2C Bank VCCO 与 IOSTANDARD 冲突。
- CFG 默认 `rw[20]=1`、`rw[21]=0` 与 AMDUSB4 一致。

本轮已完成的结构改造：

- `asmcehnk_fifo` 和 UDP stack 移入 SFP1 TX/network 域。
- SFP1 RX frame 单次 CDC，移除 TX 整帧 CDC。
- Corundum 64-bit Ethernet/ARP/IPv4/UDP minimum stack 接入。
- TX 删除 FT601 `256->32` 路径，增加 256-bit packetizer、256->64 frame FIFO 和 length descriptor FIFO。
- TLP/CFG 恢复 system/network 与 PCIe 双时钟边界。
- 新 `asmcehnk_udp_tx_packetizer_256.v` 已通过 Erie strict gate：`errors=0`、`strict_warnings=0`。
- packetizer focused xsim 已通过：单字短包、32-word/1024-byte 满包、payload/descriptor 独立回压、原子 tail/descriptor handshake 和 reset flush。
- Corundum 最小依赖补齐 `lfsr.v`；三个旧 FT601 transport XCI 已从 source roots 和仓库删除。
- UDP RX focused xsim 已通过：正确 payload/字序、错误端口拒绝、IPv4 分片拒绝、非 8-byte 对齐拒绝、IPv4 checksum 错误拒绝和 reset。
- ARP/TX focused xsim 已通过：ARP reply、ARP resolution、UDP reply、IPv4/UDP header 和 256->64 payload 字序。
- 启动命令注入的 64-bit 自增计数器已缩成 5-bit 饱和计数器；xsim 已验证 5 个初始化字及 reset 后重放与原 64-bit 实现逐拍一致，避免在 402.8 MHz 域保留无意义的 64-bit 比较链。
- 独立 clean Vivado 2024.2 synthesis 已通过：0 error、0 critical warning、black box 0；当前复跑 setup 为 WNS `-0.919 ns`、TNS `-633.178 ns`，综合阶段结果仍未收敛且会随 seed/布局估计波动。
- SynthPilot MCP 已复核工程为 `asmcehnk_as02mc04_top` / `xcku3p-ffvb676-2-e`，并确认 PCIe 为 256-bit、250 MHz、DWORD-aligned、Gen3 x8；`pf0_aer_enabled=false`、`legacy_ext_pcie_cfg_space_enabled=false`、`ext_pcie_cfg_space_enabled=false` 已由 MCP 和 clean imported XCI 双重核对。
- PCIe XCI/Tcl 已同步关闭 AER 和两种 external config space，删除失效的顶层 `cfg_ext_*` tie-off；clean synthesis 为 0 error、0 critical warning、black box 0。
- PCIe `user_reset` 先在 250 MHz PCIe 域经过独立桥接寄存器隔离，再由两级 `taxi_sync_reset` 跨入并合并到 SFP1 TX/network 域；项目新增的 `user_reset -> net reset` CDC-11 critical 已从 clean synthesis CDC 报告中消失。
- reset CDC focused xsim 已通过：PCIe reset 异步断言、PCIe 域释放、network 域同步释放、MAC reset 同域合并和 reset 重入；最终边界 RTL 同时通过 Erie lint `0 error / 0 warning` 与 SynthPilot `check_syntax_file`。
- 当前 clean synthesis CDC 剩余 2 条 CDC-10 和 7 条 CDC-11：前者均为 Taxi 两个 SFP GT RX reset，后者均位于 `pcie4_uscale_plus_0` generated core 内部；不为消除 inherited 报告而修改 Taxi 或 generated IP。
- shadow mode controls 已在 PCIe 域同步；AMDUSB4 raw-TLP source helper 只做必要的 `rst_sys/rst_pcie` 拆分，未改其 packet/FIFO 语义。
- 25G staging 之前的 implementation baseline 已跑通 `place_design`、`phys_opt_design` 和 `route_design`，black box 0；当时 routed timing 为 WNS `-0.679 ns`、TNS `-840.029 ns`、WHS `+0.010 ns`，无 pulse-width failure。该结果仅保留为 QoR 对照，已被下述 staging + `AggressiveExplore` 结果取代。
- routed 最差 setup 路径来自 `tlp_dst_fifo_inst/i_fifo_134_134_clk2` BRAM 输出到原 `asmcehnk_mux` 的 `data_reg/ctx_reg` 写入路径。
- `fifo_134_134_clk2` embedded output register 实验把 clean synthesis WNS 改善到 `-0.639 ns`，但 FIFO 读延迟从 1 拍变为 2 拍；原 mux 明确要求所有输入 1 拍返回。两拍 mux/pipeline 的 backpressure stream comparison 未通过，因此该实验已回退，不能为了 timing 提交协议不等价改动。
- 已增加 AS02 专用 `asmcehnk_tlps128_dst_fifo_us` 两字 elastic staging；XCI 继续保持原 Standard FIFO/一拍语义，不打开 embedded output register，也不修改 AMDUSB4 `asmcehnk_mux`。staging 只预取最多两个 134-bit raw-TLP word，并把 mux 的一拍 request/return 契约保持在寄存器边界。
- 使用实际 Vivado FIFO Generator simulation netlist 的 focused xsim 已通过：277 个原实现输出 word 在 burst backpressure 下逐字、first/last 标记一致，且 staging occupancy、pending read 和 reserved slot 均未超过 2；Erie lint 为 `0 error / 0 warning`，SynthPilot syntax 通过。
- staging clean synthesis 为 0 error、0 critical warning、black box 0，WNS/TNS 从原一拍 FIFO版本的 `-0.919/-633.178 ns` 改善到 `-0.077/-8.520 ns`。完整 route 为 WNS `-0.127 ns`、TNS `-3.030 ns`、WHS `+0.010 ns`；协议等价且 QoR 明显改善，但 **timing 仍未关闭**。
- staging 默认 route 的最差路径已不再来自 BRAM 输出：首条为 Corundum `udp_checksum_gen_64` checksum 累加链 `-0.127 ns`，其次为 staging occupancy 到原 mux `-0.119 ns`。从同一 clean `phys_opt` checkpoint 使用 `route_design -directive AggressiveExplore` 后达到 WNS `+0.021 ns`、TNS `0.000 ns`、WHS `+0.008 ns`、pulse-width violation 0；因此该 router directive 已写入权威工程生成 Tcl，不关闭 UDP checksum，也不改 third-party Corundum 或 AMDUSB4 mux 语义。
- 该轮 `AggressiveExplore` routed CDC 为 2 条 CDC-10 与 11 条 CDC-11：4 条 CDC-11 来自 Taxi 两个 SFP GT TX reset，7 条来自 PCIe generated core；项目 `pcie_rst_bridge -> pcie_reset_to_net_sync_inst` 仅报告 CDC-9 info，新增 reset critical 仍未复现。methodology 唯一 critical 为 PCIe generated XDC 的 scoped clock-group `TIMING-54`，不是新增 RTL CDC。
- 已增加可选 `AS02_HW_DEBUG` 观测边界和独立调试构建入口；正常图像不带 ILA。调试 define 的 clean synthesis 为 0 error、0 critical warning，两个 ILA 的全部 probe 宽度/时钟域和本地 `save_constraints_as` 已在 Vivado 2024.2 验证。2026-07-31 已完成调试图像 full implementation、timing、bit/bin/LTX 生成；该项证明可烧录采集基础设施闭合，仍不等价于实板 UDP/PCIe 功能通过。
- commit `e30175e` 把 CQ/RC 汇合改为 packet-locked ready/valid 仲裁，并实现 32-entry RQ sequence credit、64-bit pending bitmap及 duplicate/unknown acknowledgement sticky error；对应 mux、CQ/RC merge 和第 33 个 RQ 阻塞/ack 后恢复 focused xsim 已通过。
- commit `d735dca` 把 CC `128 -> 256` packer 改为 12-DWORD elastic pack，修复缓存 5 至 7 个 DWORD 时无法继续接收也无法发出的死锁；focused xsim 已验证 CplD descriptor、DWORD 字序、跨 256-bit 尾拍和输出背压稳定。
- commit `b9c0821` 为 outbound MRd 增加 256-entry client-tag bitmap；重复 tag 背压，split RC 按 byte-count/length 判定 terminal completion 后释放，错误 completion 释放，unknown tag 置 sticky error，并接入 PCIe ILA。
- commit `aa308e2` 把 terminal RC 的 tag 释放点从 descriptor 首拍推迟到该 AXIS packet 的 `tlast` 握手；多拍 completion 尾部未接收完成时，重复 MRd tag 继续保持背压。
- 2026-07-29 10:28 使用 Vivado/xsim 2024.2 执行 `run_as02_pcie_tests.ps1`，commit `aa308e2` 的 CQ/RC merge、mux backpressure、RQ sequence credit、CC multi-beat 和 MRd tag lifecycle 五组 focused top 均出现显式 PASS marker；tag 用例包含两拍 terminal RC；日志位于 `.tmp_pcie_tests/`。
- commit `aa308e2` 的边界 RTL 和 testbench 已分别通过 Erie independent lint RTL/TB mode `0 error / 0 warning`，并由 SynthPilot `check_syntax_file` 复核通过。上述 focused test 均不是 Root Complex 枚举、BAR engine 端到端或 PCIe wire-level closure。
- 2026-07-29 10:41 使用 Vivado 2024.2 执行 `$env:AS02_DEBUG_SYNTH_ONLY='1'; vivado -mode batch -source vivado_build_debug_as02.tcl`，包含 commit `aa308e2` RTL 的 top synthesis 和 ILA insertion 为 0 error、0 critical warning；DCP 为 `.tmp_vivado_debug/fpga_debug_synth.dcp`，SHA256 `01CC596346C294822E6071B6A296CA9E71C1C05FBECF05A40AEC9FA2EE22A7D1`。该证据只到 synthesis，不含 implementation/timing。
- commit `37b3c88` 把正式 build 的 project/report/bit 输出统一到 `AS02_PROJECT_DIR`，implementation 固定跑到 `route_design`，setup/hold 任一负 slack 时禁止 bitgen；commit `2721a6e` 删除纯 RTL 工程不支持的 IPI/XSA 导出，使正式入口在 bitgen 后正常返回。
- 2026-07-29 10:50 在当前 RTL 上再次执行 `run_as02_pcie_tests.ps1`，五组 focused xsim 全部出现显式 PASS marker。
- 2026-07-29 11:36 对 commit `2721a6e` 执行隔离 clean build：`$env:AS02_PROJECT_DIR='.tmp_vivado_release_2721a6e'; vivado -mode batch -source vivado_build.tcl -notrace`，进程退出码 0；synthesis、route 和 bitgen 均为 0 error、0 critical warning，routed DRC error 为 0。
- 该轮 routed timing 为 WNS `+0.038 ns`、TNS `0.000 ns`、WHS `+0.012 ns`、THS `0.000 ns`、pulse-width slack `0.000 ns`，所有用户 timing constraint 和 bus-skew constraint 均满足。报告位于 `.tmp_vivado_release_2721a6e/fpga_timing_summary.rpt`。
- 正常图像为 `.tmp_vivado_release_2721a6e/fpga.runs/impl_1/fpga.bit`，SHA256 `21B02F26F61787F56DE84951311A2D06315A702F86D2295DE11CEBB1A60EAD46`；对应 raw bin SHA256 `3A845916952D3AC14CE91F6C1082943C1CC64CEB299672123CFDD00EA6C392CC`。该图像只证明 build/timing，不提升 PCIe/UDP 功能 Gate。
- 该轮 CDC 汇总为 2 条 CDC-10、11 条 CDC-11：Taxi SFP GT reset 与 PCIe generated core；methodology 唯一 critical 仍为 generated PCIe XDC `TIMING-54`。项目新增 PCIe/UDP 边界没有出现新的 CDC critical 类别。
- commit `a00a988` 将 UDP RX、ARP/UDP TX 和 256-bit packetizer 的历史 focused vector 正式迁入 `tests/`，并新增 `run_as02_udp_tests.ps1`；三个 testbench 均通过 Erie independent lint TB mode `0 error / 0 warning`，且不含 `function/task`。
- commit `c97c29d` 为 UDP/PCIe runner 增加逐 top transcript。2026-07-29 11:49 使用 Vivado/xsim 2024.2 重跑后，UDP 三项和 PCIe 五项共 8 个 top 全部出现显式 PASS marker；UDP 日志 SHA256 分别为 RX `8E4C4697BADAC3C27368FA59F8063E29F3B051D2B6972342F89344739E993391`、ARP/TX `AD1680CBE5F4D0F9D3F2350355B3D5EB1E307AEC80D6F213122129423990AA32`、packetizer `A94BCA79AA5496E3B4AF5D55D65459AB4B2BBF7837A251EA900F3A5621B43A56`；日志位于 `.tmp_udp_tests/`。
- 同轮 PCIe 日志 SHA256 为 mux backpressure `E2C943C7C9189ABE9B2D788A7F315B7B62E7E82EA2F3B4D6124CF0BD023E52AD`、CQ/RC merge `0A644EE476DE572C9132961B76D7E7E03D7C5BF2D46EBF5F589FED17230A2F31`、RQ credit `04FA00820CE6A03C87A7DECDE97D6BCB7900D5F34A00DD17ABA2A6367BF2F1AE`、CC multi-beat `6853F21923CF80E1E7A73A5554D0A23D083FF00007031D5DF6371719BC39D154`、tag lifecycle `C090300E5C6657452D679ADF7F4C7535043972FFF80DADDCD985D37CCE9266DC`；日志位于 `.tmp_pcie_tests/`。
- SynthPilot MCP 在同轮确认唯一连接实例为 Vivado 2024.2/port 9999，工程路径为 `as02_asmcehnk_25g`、top 为 `asmcehnk_as02mc04_top`、part 为 `xcku3p-ffvb676-2-e`，并确认 `asmcehnk_udp_tx_packetizer_256.v` syntax OK；未关闭用户 Vivado。
- 该 GUI 根工程的 SynthPilot `get_run_status` 仍包含历史/stale IP `synth_design ERROR` 和未启动的 top run，不能作为本轮 clean build 结论；本轮实现证据来自隔离 `.tmp_vivado_release_2721a6e` batch 工程、对应 reports 和 terminal build log。不得为了清除旧状态而重置或关闭用户当前 Vivado 会话。
- 自 `2721a6e` 之后截至该次状态记录，只新增/修改仿真 testbench、runner 和文档，implementation RTL、XCI、XDC 和工程生成 Tcl 当时未变化；该结论只说明历史图像的适用范围，不再代表提交 `977217a`。
- commit `d6a0148` 增加 `test_as02_sfp1.ps1`：先强制检查物理接口 Up、RX/TX 均为 25G、静态 `192.168.0.x/24`、FPGA ARP MAC `02:00:00:00:00:de`，再执行 register probe、loopback，并把结果写入 `.tmp_sfp1_test/*.json`；不满足 25G 的现有网卡会在发包前被正确拒绝。
- commit `0eb746d` 增加 `as02_udp_stress.py` 及 mock endpoint 单元测试：覆盖 184-command 标准 MTU burst、默认 `100 x 128` 唯一 loopback command、缺失/额外/损坏/乱序回复、错误 UDP port 和非 8-byte 对齐 payload 拒绝。2026-07-31 复跑 `python -m unittest -v tests.test_as02_udp_stress` 为 2/2 PASS，PowerShell 入口语法检查 PASS；`functional_payload_mbps` 明确只作功能回归比较，不作线速证据。
- commit `0eb746d` 的 `AS02_HW_DEBUG` 图像于 2026-07-31 使用 Vivado 2024.2 从独立 `.tmp_vivado_debug` 工程完成 full implementation。routed timing 为 WNS `+0.025 ns`、TNS `0.000 ns`、WHS `+0.010 ns`、THS `0.000 ns`、WPWS/TPWS `0.000 ns`；全部 76,993 条 routable net 已路由，routing error 0，routed DRC error/critical warning 0，bus-skew `VIOLATED` 0。DRC 的 5 条 warning 来自 debug hub/ILA 相关 LUT 和无 routable load，不提升为功能 PASS。
- 调试产物为 `as02_asmcehnk_25g/fpga_debug.bit` SHA256 `09F1751E2597EBEEEAF5AB48BD55C7C889216A484D694F1358D69F9F5B190B90`、`fpga_debug.bin` SHA256 `CB69358A1F6E75EA950D02C95F38C5FB10BC21B602F389D6150C72297A0270DE`、`fpga_debug.ltx` SHA256 `1772E780844559F7837EC91BEA77551FD92A7F117C1CFC3AF80AF9574E40A1B7`、`as02_debug_map.json` SHA256 `1847951D6B2AF3B4E1D70A8BBE1190804A0B07BB605DB7BD1A217FE0412D2FC6`。LTX 已核对包含且仅匹配当前 build 的 `as02_net_ila`、`as02_pcie_ila`、`as02_net_vio`、`as02_pcie_vio`。
- 2026-08-03 使用 Vivado/xsim 2024.2 在 commit `11015af` 重跑 `run_as02_pcie_tests.ps1`，CQ/RC packet-locked merge、mux backpressure、32-entry RQ sequence credit、CC multi-beat packetization 和 MRd tag lifecycle 五组 focused top 均出现显式 PASS marker，进程退出码 0。该结果确认当前 PCIe adapter 有效路径无回归，但仍不替代 Root Complex/实板端到端证据。
- 2026-08-03 新增 `tb_pcie_leechcore_128_256.sv`，直接以 AMDUSB4/LeechCore `IfAXIS128` golden vectors 驱动 AS02 的 256-bit CQ/CC/RQ/RC adapter；覆盖 CQ MRd32、两 DWORD MWr32、RQ MRd32/MRd64/MWr32/MWr64、RC CplD、CC CplD、multi-beat、DWORD byte order、`tkeep/tlast/tuser` 和输出 backpressure stability。测试未使用 `function/task`，Erie independent TB lint 为 `0 error / 0 warning`。
- 2026-08-03 22:59 使用 Vivado/xsim 2024.2 执行 `run_as02_pcie_tests.ps1 -VivadoBin D:\\Xilinx\\Vivado\\2024.2\\bin`，原五组 PCIe flow-control top 与新增 `PCIE_LEECHCORE_128_256_TEST_PASS` 共六组均出现显式 PASS marker，进程退出码 0。新增 transcript 为 `.tmp_pcie_tests/tb_pcie_leechcore_128_256_xsim.log`，SHA256 `B5F4F6CC2EA06F03438988ACD6495D04BB4AAD0198D4AFB16868D7306876546A`；testbench SHA256 `61068AF7D70D91FB3D29CB70B134AC11534303C9785DB174D84A6B8CFD5FECFB`。
- 本次兼容性取证只增加 testbench、runner top 和本文档，`src/asmcehnk_pcie_tlp_us.sv` 未修改，SHA256 仍为 `C74C4D65CC03180120A0C81F4C745C9B2C95AA9430A7F9C541D0ED01996BB037`。结果支持“256-bit PCIe IP 边界不改变 128-bit LeechCore raw-TLP contract”的 valid-path 结论；异常矩阵、Root Complex 与实板证据继续单独关闭。
- 进一步对照本地 upstream LeechCore commit `c7e6e94b2ae24de6bdb998b5405533ec1dbd28e3` 的 `device_fpga.c` 后，确认官方 RawUDP `WritePipe` 直接发送 C buffer，而 NeTV2 RX/TX在 transport 边界执行 byte ordering；此前 AS02 的通用 AXIS lane透传与配套自测工具互相补偿，旧自测可通过但不等于官方 LeechCore wire兼容。该差异已限制在 `asmcehnk_eth_axis_udp_25g.sv` 边界修正，AMDUSB4 FIFO/mux/CFG/BAR/TLP framework 未改。
- 修正后的 UDP RX xsim使用官方 `01 00 01 00 80 02 23 77` 和 `00 00 00 00 01 00 03 77` payload，分别得到内部 `64'h01000100_80022377`、`64'h00000000_01000377`；UDP TX xsim验证 mux 256-bit word以最高 byte/DWORD开始发送。UDP RX、ARP/TX、packetizer 三组均 PASS；host mock新增 RawUDP golden-vector测试后 3/3 PASS；Erie 对 transport RTL及两组 testbench均为 `0 error / 0 warning`。
- 同轮六组 PCIe focused xsim继续全部 PASS，证明 transport wire修正未改变 `IfAXIS128` 或 128/256 PCIe adapter。该轮 LeechCore PCIe transcript SHA256 为 `EB3597A8C1B4E5F869C777D12D508854305C3117B3CE309177256B57ED7B42EC`；UDP RX/ARP-TX/packetizer transcript SHA256依次为 `14366033F0CBA0F3224E213A73BE9AE2292DF30FCF9F34F7BFA0CCB69F129476`、`49C330B5163B20E6E84903B2D5159148AFD8598F6607E089BA8C6B27B0FAADED`、`7712F04E1182131B61B83EAC50475FDE3481E4BE3002C1EE5D2F0F61C041A980`。
- 2026-08-03 late-night clean Vivado 2024.2 build（elapsed `2181.5 s`）完成 synthesis、place、route 和 bitgen，0 error、0 critical warning、routing error 0；routed WNS/TNS 为 `+0.078 ns / 0.000 ns`，WHS/THS 为 `+0.011 ns / 0.000 ns`。bit SHA256 `70089FE3B3EF87E1C4AE93C90A78F29CFBBA83A0AF0C95F9FFBDDB5E983490ED`，bin SHA256 `924B5F506553583D78B9E16F15AFF98FF2696619DF2F20B86623B9BCB8D6C9D0`，位于 `.tmp_vivado_release_wire_20260803_2325/fpga.runs/impl_1/`。
- 2026-08-03 新增 `tb_asmcehnk_fifo_compat.sv` 与 `run_as02_framework_tests.ps1`，只验证原 AMDUSB4 `asmcehnk_fifo + asmcehnk_mux`，生产 RTL 未修改。向量覆盖默认控制位、错误 magic 拒绝、TLP/CFG/官方 `0x77` command 分类、activation-lock 删除后的直接 TLP 通行、loopback、普通 RO/RW command、shadow CFG read/write/byte-enable/response、复位阶段 DRP request/completion、CFG/TLP 同时输入时的 mux 优先级及 context/tag 布局。
- 首次命令响应超时已定位为测试模型把复位阶段的 PCIe DRP `rdy` 永久保持为 0，触发原框架 `WAIT_COMPLETE` 正常阻塞；补齐 DRP completion model 后 xsim 显式出现 `ASMCEHNK_FIFO_COMPAT_TEST_PASS`。测试 FIFO 深度和 Standard FIFO 一拍 valid 语义与 `fifo_34_34.xci`、`fifo_64_64_clk1_fifocmd.xci` 对齐；Erie independent TB lint 为 `0 error / 0 warning`，SynthPilot 单文件语法复核为 OK，且 testbench 不含 `function/task`。
- framework testbench SHA256 为 `B37849D641FA631F5CC1C828BCF1E47F19467D06ABC6F61ABCF58EE2D5289C2F`，runner SHA256 为 `7DFC8526D2C91FD88540A6D4EBA4A0A05E3B07CA5F6CD1052928EC37CF642D05`，xsim transcript `.tmp_framework_tests/tb_asmcehnk_fifo_compat_xsim.log` SHA256 为 `D4A7C06F23AB3A8F3276DBD4D63AA48EBC4172017BFC83A739AA644BC3E9C9F2`。
- 同轮自检继续通过 UDP focused xsim 3/3、PCIe focused xsim 6/6 和 host RawUDP/stress Python 3/3；四个 PowerShell 测试入口均通过 parser check。该结果把原 framework 基础路径的回归空白补齐，但仍不替代下述 Root Complex、malformed/error matrix、线速和实板闭环。

剩余验收与鲁棒性闭环；以下项目不得被误读为 AMDUSB4 BAR/DMA 框架尚未移植：

- UDP 连续线速、长时间 RX/TX backpressure，以及真实 LeechCore进程 + SFP1实板的最终 wire trace 对照。
- CQ byte-enable/malformed/unsupported、RC malformed/error、多种 split completion、Root Complex wire model 和 host rawudp 语义闭环。
- unsupported MRd 的 UR Completion、malformed/partial MWr 原子拒绝，以及 MRd tag 与 RC completion progress 的完整错误矩阵。
- 历史 debug bit/ltx 绑定 commit `0eb746d` 并满足当时的实现时序；它只证明调试基础设施可用，不代表提交 `977217a`。当前提交如需 ILA 取证，应另行生成匹配的 debug bit/LTX。
- 实板 25 Gbit/s 或 23.93 Gbit/s 应用净荷测量。

### 9.1 前一稳定基线（提交 `977217a`，2026-08-21）

提交 `977217ae1731f82f78059cbcbe4427b68c5392e9` 当时完成 clean focused regression、Vivado 2024.2 full implementation、timing gate、normal bit/bin 和 LeechCore host build，作为本轮 class-only 更新前的稳定基线。其状态标记为：`CURRENT_FULL_IMPLEMENTATION_PASS`、`CURRENT_BIT_BIN_PRESENT`、`CURRENT_FOCUSED_XSIM_PASS`、`BOARD_GATES_PENDING`；本轮权威结果以 9.2、9.3 为准。

验证总清单位于：

- `as02_asmcehnk_25g/validation/977217a/manifest.json`
- `as02_asmcehnk_25g/validation/977217a/verification.txt`
- `as02_asmcehnk_25g/validation/977217a/README.md`
- 稳定但不纳入 Git 的大文件：`as02_asmcehnk_25g/artifacts/977217a/`

#### 9.1.1 复用边界与最终数据路径

- AMDUSB4 的 header、mux、FIFO、BAR controller、raw-128 TLP、config-space shadow 和 command 语义继续作为内部唯一契约；未因 AS02 板卡迁移而重写 framework。
- AS02 只增加或修改板级 shell、25G UDP、CDC、UltraScale+ PCIe CFG/TLP adapter、XCI/XDC 和 Vivado 工程入口。A7/75T 专属 PCIe 7-series 生成核不进入 AS02 build。
- `asmcehnk_fifo.sv` 的 activation/DNA gate 已从 AS02 副本移除；`rw[20]=1` 的 master-abort auto-clear 和 `rw[21]=0` 的 command auto-set 语义保留。
- 物理 SFP1 对应 RTL/MAC index 0，是唯一 transport；物理 SFP2 对应 index 1，TX 保持无有效数据、RX drain，首版不承载备用或诊断流量。
- LeechCore/AMDUSB4 内部仍使用 128-bit raw TLP；256-bit 只存在于 UltraScale+ PCIe IP 的 CQ/CC/RQ/RC 边界。CQ/CC 与 RQ/RC 均已接入适配层，没有 tie-off。
- plain device string `fpga` 的 production host build 默认映射到 `192.168.0.222:28474`；显式 `fpga://ip=HOST` 保留用于诊断。

#### 9.1.2 Erie/verilog-generator、xsim 与 host 证据

| 检查 | 结果 | 范围 |
|---|---|---|
| Erie `asmcehnk_pcie_cfg_us.sv` | 0 error / 0 warning | AS02 CFG adapter |
| Erie `asmcehnk_pcie_tlp_us.sv` | 0 error / 0 warning | AS02 PCIe TLP adapter |
| Erie `tb_pcie_drp_bar_info.sv` | 0 error / 0 warning | DRP/BAR testbench |
| Erie packetizer strict gate | delivery ready，0 error，0 strict warning | `asmcehnk_udp_tx_packetizer_256.v` |
| PCIe xsim | 7/7 PASS | mux/backpressure、CQ/RC merge、RQ credit、CC multi-beat、tag lifecycle、LeechCore 128/256、DRP/BAR |
| UDP xsim | 4/4 PASS | RX、ARP/TX、packetizer、FIFO end-to-end |
| AMDUSB4 FIFO compatibility | PASS | classification、command、loopback、CFG/TLP mux、100 MHz tick |
| PCIe profile | PASS | 49 个 XCI/profile 属性 |
| LeechCore controlled loopback | PASS | plain `fpga` 与显式 URI 的 32-byte golden probe；测试 build 默认 `127.0.0.1` |
| LeechCore API mock | PASS | 40 probes；MRd=2、MWr=2、CplD=2、malformed=0、DRP size `0x100` |

DRP focused test 已覆盖 words `0..127` 的默认值扫描、128 个 word 全窗口写入/读回、BAR0 mask words 7/8、word 127，以及 window 外 word 128 返回零；marker 为 `PCIE_DRP_BAR_INFO_TEST_PASS`。

production LeechCore x64 Release DLL：

- `as02_asmcehnk_25g/host/leechcore/out/leechcore.dll`
- SHA256 `1E9658A36AEF8C77304CB597B042125D729D9F9E930200CEFD1588A7180B93BF`
- 同次 manifest SHA256 `30A5DA61E27CF29B0FAC6013AF129C7A91CD3DD38ED946BE0DA7AC3C37EECF2B`
- manifest 绑定 project commit `977217a`、upstream LeechCore commit `709dce874df14e289e1c26fc18ab0b0856ae4151`、default IP `192.168.0.222` 和 UDP port `28474`。

controlled loopback/API mock 使用相同 source/patch、但把测试默认地址设为 `127.0.0.1`；它证明 host adapter、plain alias 和 raw-128 TLP API 契约。真实板卡上的 plain `fpga` 会话仍由实板 Gate 单独验收。

#### 9.1.3 Vivado 2024.2 clean full build

- clean 工程：`<build-root>\fpga`
- top：`asmcehnk_as02mc04_top`
- part：`xcku3p-ffvb676-2-e`
- `synth_1` complete，`impl_1` route complete；SynthPilot MCP 复核 21/21 IP 为 Up-to-date。
- timing：WNS `+0.006 ns`、TNS `0`、WHS `+0.010 ns`、THS `0`；setup/hold total endpoints 为 `73,566 / 73,440`，所有用户 timing constraints 满足。
- route：`44,563` 条 routable net 全部完成，routing errors `0`。
- DRC：errors `0`；保留 1 条 FIFO-generator 内部 unused/reset net 的 `RTSTAT-10` warning。
- 71/71 个 top-level port 具有 LOC；normal BIT/BIN 已生成。

| 产物/报告 | SHA256 |
|---|---|
| `fpga.bit` | `434436DD31350B4C2485A2FE2F7E5AA7C5E2C4C2BA3DEA90535144FEEB793F50` |
| `fpga.bin` | `46186625A011C611B260751ECA6756A71D345369267FB45F0A14BC2298D9CD36` |
| timing | `ED2EE1C6E358AA247038CC711C9B9B246AE92679E5945183A8EFFA0FBA59B897` |
| CDC | `FBB95DBB80C2C42E63D19127A0FB0F502E22E8792F2A0CE407020C5ADB1CFEB0` |
| methodology | `524334B6F6B6A15DEB4F0FD96C03ACD31B859895D51DCFACA6712FD10AB544F1` |
| DRC | `E4D82CF32DE4C77B12716CCADA80D5979F201CDBF421154658C6FBE51CDCA934` |
| route status | `79A5649E6A2D295EA03B2A6715C18DDEA2CB8E64DD05F081282537A9EFEBB56D` |

CDC 报告仍包含 CDC-10 Critical 2、CDC-11 Critical 11、CDC-15 Warning 299、CDC-6 Warning 1。Critical 项位于 Taxi GT reset 和 generated PCIe structures；warning 中包含已知异步 FIFO 结构。methodology 保留 generated-XDC `TIMING-54` Critical Warning 1 和 `TIMING-9` Warning 1，同时还有报告内列出的其他 non-critical warning 类别。以上 finding 保留为实现审计项，不通过重写 AMDUSB4 framework 或 generated IP 消除。

BIT 本地时间为 `2026-08-21 03:09:05 +08:00`，对应 UTC `2026-08-20 19:09:05Z`；因此本地文件名/日志进入 8 月 21 日，而 UTC evidence timestamp 仍可能是 8 月 20 日。

#### 9.1.4 当前可上板范围与仍待实测的 Gate

normal `fpga.bit` 已具备开始受控上板 smoke test 的条件；当前 PASS 表示 RTL focused regression、host mock、综合、布局布线和时序闭合完成，不代表下表实物链路已经观测通过。

| Gate | 状态 | 实板证据 |
|---|---|---|
| SFP1 25G link / ARP / UDP | PENDING | NIC 25G link、ARP、RawUDP probe/loopback、pcap、NIC counters、ILA |
| PCIe enumeration | PENDING | BDF、VID/DID/class/BAR/capability、链路宽度与速率 |
| BAR0 CQ/CC | PENDING | 真实 MRd/MWr/CplD 与 CQ/CC ILA |
| RQ/RC DMA | PENDING | host memory transaction、tag/sequence/completion 与 RQ/RC ILA |
| real plain `fpga` LeechCore | PENDING | production DLL 对真实板卡建立会话并完成 probe/read/write |
| 60 s 持续吞吐与稳定性 | PENDING | 发生器、FPGA/NIC counters、pcap，0 丢包/错误/link-down |
| 当前提交 debug bit/LTX | PENDING | 需要 ILA 取证时从 `977217a` 对应 RTL 另行生成 |

### 9.2 2026-08-24 transport/identity/reuse 复核

- 复核报告：`as02_asmcehnk_25g/validation/transport_identity_reaudit_20260824.md`。
- 上游 `pcileech-fpga` commit `c538c4170678c13f723dc921905fb81ff3c71d8e` 的多套历史 `pcie_7x_0.xci` 采用 `10EE:0666`、class `020000`、4 KiB 32-bit BAR0、MSI-on/MSI-X-off；AS02 当前保留其中 VID/DID、BAR 和 MSI envelope，并将 class-only 修正为 `0C0340`。PCIe class 元数据和 SFP1 transport NIC 仍是两条独立路径。
- `192.168.0.10/24` 仅是控制端物理 25G NIC 的可选示例源地址，不是 FPGA PCIe PF0 的地址，也不是 LeechCore 的设备身份。控制端 NIC 可以位于另一台主机；尚未安装 NIC 时，PCIe 枚举阶段不配置 IPv4。实际部署只需为连接 SFP1 的物理 NIC 选择一个未占用、可路由的地址，并把 PF0 与该 NIC 分开记录。
- PF0 当前 `CLASS_CODE=0C0340`，因此不再声明为 Ethernet controller 类别；该字段仍只是配置空间元数据，不创建 PF0 网卡数据面，也不把 PF0 和 SFP1 物理 NIC 合并。SFP1 UDP transport 仍由独立物理 25G NIC 承载。
- 复用审计脚本 `tests/test_transport_identity_reuse.ps1` 在 PowerShell 5.1/7 均输出 `AS02_TRANSPORT_IDENTITY_REUSE_AUDIT_PASS`；metadata 回归、framework、PCIe 7/7、UDP 4/4 和 PCIe profile 复跑通过。
- active shadow 仍为 `asmcehnk_tlps128_cfgspace_shadow.sv`，旧 `asmcehnk_pcie_cfgspace_shadow.sv` 保持参考文件，不加入 active source roots。`asmcehnk_pcie_tlp_a7.sv` 也只保留作迁移参考；A7 wrapper 不进入 AS02 active build。
- A7 wrapper 中原本随 wrapper 定义的三个芯片无关 helper 已按原实现拆出为独立 active source：`asmcehnk_tlps128_filter.sv`、`asmcehnk_tlps128_src_fifo.sv`、`asmcehnk_tlps128_sink_mux1.sv`。这是 source-root 完整性修复，不是对 AMDUSB4 framework 的算法重写；AS02 active 边界执行 Erie/verilog-generator targeted lint，复用 framework 由 byte/hash 审计和 Vivado 回归保护。
- SynthPilot 已连接到 Vivado 2024.2、part `xcku3p-ffvb676-2-e`、top `asmcehnk_as02mc04_top`，并返回 syntax `OK`、black-box `0`；当前树的 clean flow 结果在 9.3 记录。

### 9.3 2026-08-24 current-tree clean flow

- 详细记录：`as02_asmcehnk_25g/validation/current_tree_clean_flow_20260824.md`。
- 本轮 clean flow 使用 `xcku3p-ffvb676-2-e`、top `asmcehnk_as02mc04_top`，证据工程为 `.tmp_clean_class_20260824_a/project`。flow 从提交 `7c88bac` 启动；之后的 `64a29b3`、`c81a8cb` 只修改验证记录和 LeechCore fixture，未修改 FPGA build input。稳定打包目录为 `as02_asmcehnk_25g/artifacts/c81a8cb/`，bit/bin 以记录的 16 个 active-source SHA256 为权威绑定。
- 字面标记为 `synth_design Complete!`、`route_design Complete!`、synthesis/implementation black-box `0`、setup/hold fail `0`；top `synth_1` 与 19 个 OOC synthesis run 完成，21/21 IP 对象为 Up-to-date。
- routed timing 为 WNS `+0.007 ns`、TNS `0`、WHS `+0.012 ns`、THS `0`；route `44,564/44,564`，routing error `0`；DRC error `0`，保留一条 generated FIFO/reset no-routable-load 的 `RTSTAT-10` warning。
- 当前 normal 产物为 `fpga.bit` SHA256 `F505B9D341F76CFDA46F259E63EF9CD6E4A2F5A038067B764A55CF00998E2EB5`、`fpga.bin` SHA256 `F8D0EA792A5535F68AF103E1F7FB430F46D874F15FB7420BC76803ADF827CD5F`；完整报告、`clean_flow.log`、manifest 和 `sha256.txt` 位于 `artifacts/c81a8cb/build/`。
- SynthPilot MCP 已对该 routed project 独立读取 project/part/top、run status、route、DRC、timing、CDC 和 methodology；专用 MCP Vivado 会话取证后已关闭，没有终止其他 Vivado 实例。
- 配置空间按四层记录，禁止混用：live hard-IP/`cfg_mgmt` 为 OS 枚举和 `LC_CMD_FPGA_PCIECFGSPACE` 的 `10EE:0666 / rev02 / class 0C0340`；active `asmcehnk_tlps128_cfgspace_shadow` 的 COE 为 `18C9:18B4 / rev01 / class 0C0340` 及 64-bit BAR image，在 `CFG_EXT_IF=false` 时不决定 PF0 枚举；`CFGREGDRP` 是本地 128×16 mirror，words 7/8 组成 `FFFFF000` 且不承载身份；`asmcehnk_fifo` 的 `10EE:0666/rev02` 是 `NOT IMPLEMENTED` legacy metadata，实际消费的是后续控制位。`rw[20]=1`、`rw[21]=0` 保持 AMDUSB4 默认语义。
- routed CDC 为 CDC-10 Critical `2`、CDC-11 Critical `11`：6 项落在 Taxi 两路 GT reset 链，7 项由 PCIe generated `user_reset_reg` 发往 AS02 实例化的 FIFO Generator reset synchronizer；项目自写 `pcie_rst_bridge -> pcie_reset_to_net_sync_inst` 是 CDC-9 Info，不在 Critical 内。methodology 的 `TIMING-9` 是这些详细 CDC finding 的汇总提示，不作为额外第 14 条 crossing。
- methodology 仍有 generated PCIe late-XDC 的 `TIMING-54` Critical Warning `1`：vendor waiver tag `1127439` 查找 `sys_clk`，板级时钟对象名为 `pcie_mgt_refclk`，因此 waiver 未绑定。当前不加 blanket waiver、不为清报告重写 Taxi/AMDUSB4；后续只允许对象级约束修正并做 fresh/multi-seed 复验。
- 该 bit 的发布结论为 `PASS_FOR_CONTROLLED_JTAG_SMOKE / HOLD_FOR_PERSISTENT_RELEASE`：可做可回退的 volatile JTAG smoke；非易失烧录、长期压力和 release 仍等待 CDC 分类、时序裕量复现以及全部实板 gate。原始 Vivado/xsim header 显示未来日期 `2026-08-25`，按 host-clock skew 处理；本记录权威日期为 `2026-08-24`。

## 10. 当前执行清单

1. 使用 normal `fpga.bit` 完成 PCIe 冷启动枚举；记录 BDF、VID/DID/class/BAR、Gen3 x8 协商状态。
2. 连接控制端物理 25G NIC 到物理 SFP1；SFP2 保持空闲。只在该 transport NIC 上配置同网段地址，依次验证 link、ARP、UDP probe 和 command loopback；不要把此 IPv4 配置与 FPGA PCIe PF0 identity 混为一体。
3. 运行 production LeechCore DLL，host 继续传入 plain `fpga`；采集真实 RawUDP probe/read/write、pcap 和 NIC counters。
4. 依次验证 BAR0 CQ/CC 和 RQ/RC DMA；如需定位，在同一 RTL/source hash 上生成 debug bit/LTX，并由 SynthPilot arm ILA 后再发送 stimulus。
5. 完成 60 秒持续吞吐与 reset/link-retrain 稳定性测试，将 ILA CSV、pcapng、主机日志、设备枚举和 counters 归档到新的 board evidence manifest。
6. 每次后续 AS02 边界 RTL/XCI/XDC/Tcl 改动均先运行 Erie/verilog-generator，再运行 focused xsim 和 clean Vivado flow；AMDUSB4 原 framework 与 generated IP 保持原样。

最终原则：**AMDUSB4 核心少改，AS02 边界薄改；物理 SFP1/index 0 是唯一 25G transport，SFP2/index 1 保持空闲；内部 raw TLP 始终为 128-bit。**

## 11. 2026-08-31 复核补充：SFP1 物理映射与版本一致性

- Vivado 板卡库 `<Vivado-2024.2>\data\boards\board_files\as02mc04\1.0\part0_pins.xml` 将 SFP1 映射到 RX `A4/A3`、TX `B7/B6`，将 SFP2 映射到 RX `B2/B1`、TX `D7/D6`；与工程 `src/asmcehnk_as02mc04.xdc` 的 `sfp_*[0]`、`sfp_*[1]` 一致。
- 因此本工程固定：**物理 SFP1 = RTL/MAC index 0 = 唯一 UDP/asmcehnk transport；物理 SFP2 = RTL/MAC index 1 = TX idle、RX drain**。后续板上测试必须把光纤和 25G NIC 接到 SFP1，不使用 SFP2 作为数据口。
- 已复核 `asmcehnk_as02_core.sv`、`fpga_core.sv`、`asmcehnk_as02mc04_top.sv`、XDC 及 Taxi 原始 AS02 约束；未发现 index 0/1 交换或 SFP2 非零 `tvalid` 路径。
- 修正新增 wrapper 的默认 `PARAM_VERSION_NUMBER_MINOR` 为 `8'd13`，与顶层/FIFO 暴露值一致；AMDUSB4 原始协议模块保持未改动。

### 9.4 2026-08-31 两项端到端仿真闭环与独立复核

- commit `cabddbc` 新增完整 PCIe TLP integration test：使用实际 BRAM/FIFO XCI simulation netlist，覆盖 CQ BAR0 MRd/MWr、CC response、RQ MRd/MWr、RC completion、shadow-config、backpressure 和双时钟 reset stale-data 检查；`PCIE_TLP_US_INTEGRATION_TEST_PASS`，runner 退出码 0。
- `run_as02_pcie_tests.ps1` 完整回归通过：12 个 focused PCIe top、生成 XCI FIFO 重复测试和 integration top 均有 PASS marker。
- `run_as02_udp_tests.ps1` 完整回归通过：RX、ARP/TX、256-bit packetizer、UDP FIFO E2E、SFP1 CDC E2E 五个 top 均有 PASS marker；SFP1 是唯一 transport，SFP2 仍为 TX idle/RX drain。
- supporting regression 同轮通过：AMDUSB4 FIFO compatibility、PCIe profile/XCI、transport identity/reuse audit、LeechCore/RawUDP host 3/3。
- 独立只读复核记录于 `as02_asmcehnk_25g/validation/final_independent_review_20260831.md`：新增 AS02 边界 RTL 与 integration TB Erie lint 均为 0 error/0 warning；仅保留两个未改动的 AMDUSB4 reference helper 的 legacy-style lint exception。
- 当前结论：两项仿真闭环与源码复核 PASS；正式上板仍需 cold-boot PCIe enumeration、BAR0、RQ/RC、SFP1 25G packet capture、plain `fpga` LeechCore 和持续吞吐证据，不能把仿真 PASS 等同于实板 PASS。

### 9.5 2026-09-04 重启后最终复跑与 CDC 分类

- 当前验证提交为 `8250d88`。重启后重新执行 PCIe、UDP/SFP1 CDC、AMDUSB4 framework、PCIe profile、transport/reuse 和 host RawUDP stress 六组门禁，退出码全部为 `0`；关键标记仍为 `PCIE_TLP_US_INTEGRATION_TEST_PASS`、`UDP_SFP1_CDC_E2E_TEST_PASS`、`ASMCEHNK_FIFO_COMPAT_TEST_PASS` 和 `AS02_PCIE_PROFILE_TEST_PASS`。
- Windows PowerShell 5.1 环境未导出 `Get-FileHash` 时，reuse audit 现直接使用 .NET SHA-256 API；PowerShell 5.1 与 PowerShell 7.6.5 均实测退出码 `0`。该变更只影响验证脚本，不改变 FPGA RTL、XCI、XDC、Vivado Tcl 或 host transport。
- `e9ee8e6..8250d88` 在 `src/`、`ip/`、`vivado_generate_project_as02.tcl` 和 `vivado_build_as02.tcl` 上无差异，因此 routed `fpga.bit` 仍覆盖当前全部生产 FPGA 输入。BIT SHA256 为 `836AD57DF808C4FECF092D7E7219845ABB777983779C3724C80A01B6A7E5A99F`，BIN SHA256 为 `12CFD4E5E4D6CECA260D1D868548CAB08EAA1713CAF66143EF46BC7825A42F48`。
- Vivado 2024.2 routed 结果：part `xcku3p-ffvb676-2-e`，WNS `+0.018 ns`、TNS `0`、WHS `+0.010 ns`、THS `0`，`check_timing` 各项为 `0`，route error `0`，DRC error `0`；保留 `PDRC-144` 和 `RTSTAT-10` 各一条 warning。
- CDC-10 的 2 项均位于 Taxi 两个 25G GT channel 的 RX reset 链。CDC-11 的 11 项中，4 项位于 Taxi 两个 GT channel 的 TX reset/buffer-bypass 链；其余 7 项由 AS02 的 PCIe 域 `reg_pcie_path_rst_pcie` 驱动 7 个 FIFO Generator 实例的内部 reset synchronizer。后者展开为 28 个内部 `arststages_ff` PRE 端点，报告均标为 `False Path`；它们是 vendor FIFO 双时钟 reset contract，不是未同步的 payload/control data crossing。未为清除报告而改写 AMDUSB4 framework、Taxi GT reset 或 generated FIFO。
- methodology 的 `TIMING-54` 来自 generated `pcie4_uscale_plus_0_late.xdc`，同一 vendor XDC 带 `SAFELYcanIGNORE` waiver，报告的 related violations 为 none；继续作为 generated-IP 审计项记录，不向板级 XDC 添加 blanket waiver。
- Erie/verilog-generator 对 7 个新增/改写 AS02 边界 RTL 和 3 个重点 testbench 为 `0 error / 0 warning`。两个从 AMDUSB4 A7 wrapper 原样拆出的 helper（`asmcehnk_tlps128_src_fifo.sv`、`asmcehnk_tlps128_sink_mux1.sv`）保留 legacy-style lint exception，以 byte/reuse 审计和 XSim 行为回归约束，不做无功能收益的格式重写。
- 最终证据目录为 `as02_asmcehnk_25g/validation/final_recheck_20260904/`，包含原始 runner 日志、CDC endpoint 展开、Vivado 摘要与报告 hash、命令、退出码、patch、verification record 和已实测的 rollback dry-run。

当前发布边界保持不变：**仿真、host mock、routed implementation 和受控 JTAG smoke readiness 已闭环；PCIe 冷启动枚举、真实 BAR0 CQ/CC、RQ/RC DMA、真实 SFP1 25G 抓包、production plain `fpga` LeechCore 会话及持续吞吐仍由实板证据关闭。**
