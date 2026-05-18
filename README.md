# DataNexus for OpenTenBase

## OpenTenBase 多模态融合枢纽

<p align="center">
  <img src="https://www.opentenbase.org/images/logo.png" alt="OpenTenBase Logo" width="180"/>
</p>



<p align="center">
  <strong>「数据融合枢纽，模态无限可能」</strong>
</p>



<p align="center">
  <a href="#-快速开始">快速开始</a> •
  <a href="#-基本使用">基本使用</a> •
  <a href="#-插件一览">插件一览</a> •
  <a href="#-性能指标">性能指标</a> •
  <a href="#-常见问题">常见问题</a>
</p>



---

## 📖 项目简介

本项目是 **OpenTenBase 开源创新大赛（赛题二：多模态插件增强）** 的参赛作品。

我们将 PostgreSQL 生态中的多个优秀插件适配到 OpenTenBase 分布式架构，并开发了 3 个完全原创的插件，实现了 **9 种数据模态**的统一 SQL 融合分析能力。

### 核心成果

| 指标     | 数值             | 说明                                           |
| -------- | ---------------- | ---------------------------------------------- |
| 适配插件 | **5 个**         | TimescaleDB、AGE、Fulltext、Routing、Scheduler |
| 原创插件 | **3 个**         | otb_analytics、otb_health、otb_snapshot        |
| 功能对象 | **292 个**       | 函数213 + 聚合29 + 视图20 + 类型3 + 表27       |
| 数据模态 | **9 种**         | 关系/时序/图/地理/向量/全文/路网/JSON/调度     |
| 测试用例 | **160 项**       | 功能测试 110 项 + 性能测试 50 项               |
| 性能提升 | **最高 1284 倍** | GIN 索引全文搜索：1926ms → 1.5ms               |

### 系统架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              用户/应用层                                     │
│                          (SQL 查询 / API 调用)                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TimescaleDB 兼容层                                   │
│              (timescaledb_compat.sql - 提供标准 TimescaleDB API)            │
│                                                                             │
│   time_bucket() | create_hypertable() | first()/last() | add_retention()   │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       DataNexus 多模态插件层                                 │
├─────────────┬─────────────┬─────────────┬─────────────┬─────────────────────┤
│ otb_ts      │ otb_age     │ otb_fulltext│ otb_routing │ otb_scheduler       │
│ 时序数据    │ 图数据库    │ 全文检索    │ 路网分析    │ 调度管理            │
│ (81函数)    │ (28函数)    │ (34函数)    │ (10函数)    │ (28函数)            │
├─────────────┴─────────────┴─────────────┴─────────────┴─────────────────────┤
│ otb_analytics ⭐原创      │ otb_health ⭐原创       │ otb_snapshot ⭐原创   │
│ 时序分析算法 (31函数)     │ 数据健康诊断 (9函数)    │ 数据快照 (5函数)      │
│ SMA/EMA/WMA/DEMA/TEMA     │ 空值/间隙/重复检测      │ 创建/回滚/删除        │
│ Z-score/IQR异常检测       │ 自动调优建议            │ 版本管理              │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            deploy.sh 部署脚本                                │
│                                                                             │
│   • 自动检测源码目录        • 智能配置分布式环境                            │
│   • 编译安装 C 扩展         • 安装 8 个插件 SQL                             │
│   • 运行功能测试            • 验证安装结果                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        OpenTenBase 分布式集群                                │
│                                                                             │
│    ┌──────────────┐              ┌──────────────┐                          │
│    │     CN       │              │     GTM      │                          │
│    │ Coordinator  │◀────────────▶│  全局事务    │                          │
│    └──────────────┘              └──────────────┘                          │
│           │                                                                 │
│     ┌─────┴─────┬─────────────┐                                            │
│     ▼           ▼             ▼                                            │
│  ┌──────┐   ┌──────┐     ┌──────┐                                          │
│  │ DN1  │   │ DN2  │     │ DN3  │                                          │
│  │数据节点│   │数据节点│     │数据节点│                                          │
│  └──────┘   └──────┘     └──────┘                                          │
│                                                                             │
│              DISTRIBUTE BY REPLICATION                                      │
│               (数据全量复制到所有DN)                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 快速开始

### 前置要求

**1. OpenTenBase 数据库**

本项目是 OpenTenBase 的扩展插件，需要先安装 OpenTenBase 数据库。

如果你还没有安装OpenTenBase，请先按照官方文档部署：

**官方部署文档：**

- OpenTenBase官网：https://www.opentenbase.org/
- GitHub仓库：https://github.com/OpenTenBase/OpenTenBase

**社区部署指南：（由本社区团队贡献）**

- [OpenTenBase 5.0 编译与使用指南](https://www.yuque.com/u53300690/rlbl35/suz5n96cwfgiabz4?singleDoc=)
- [OpenTenBase 社区实践](https://mp.weixin.qq.com/s?__biz=MzE5ODYxMTM3Nw==&mid=2247483735&idx=1&sn=011cb07b7bf010784b45115f8ad78da9&chksm=9719c19cc14813d40539c818a076f0c87d5fe9f213f149668200b0144f9257664f67a07b7438&mpshare=1&scene=23&srcid=091970dVAXo2O73aX6kUUGfw&sharer_shareinfo=3be1e5bb46ca15f3222b9444c50c0dee&sharer_shareinfo_first=3be1e5bb46ca15f3222b9444c50c0dee#rd)

**推荐配置：**

- 操作系统：CentOS 7+
- OpenTenBase 版本：v5.21+
- 集群配置：1 Coordinator + 3 DataNode + 1 GTM（推荐）
- 最小配置：1 Coordinator + 1 DataNode + 1 GTM

**2. 环境检查**

确认 OpenTenBase 已安装并启动：

```bash
# 如果 OpenTenBase 未启动，先启动
su - opentenbase
cd /data/opentenbase
pgxc_ctl
start all
quit

# 测试连接
psql -h 127.0.0.1 -p 30004 -d postgres -U opentenbase -c "SELECT version();"
```

**预期输出：**

```
                                  version
---------------------------------------------------------------------------
 PostgreSQL 11.0 @ OpenTenBase_v5.21.8 ...
(1 row)
```

**3. 编译工具**

```bash
# 确认以下工具已安装
gcc --version    # GCC 4.8+
make --version   # GNU Make
pg_config        # PostgreSQL 开发头文件
```

---

### 获取源代码

```bash
# 方式一：克隆到任意目录
cd /data/opentenbase
git clone <repository_url> "DataNexus for OpenTenBase"

# 方式二：解压压缩包
unzip datanexus-opentenbase.zip -d /data/opentenbase
```

---

### 🌟 新手一键安装（推荐）

如果你刚下载了项目，只需 **2 步** 即可完成安装：

```bash
# 步骤1：进入脚本目录
su - opentenbase
cd "/data/opentenbase/DataNexus for OpenTenBase/scripts"

# 步骤2：运行首次安装
bash deploy.sh --setup --auto-config
```

**首次安装会自动完成：**
- ✅ 复制插件源码到系统目录 (`OpenTenBase/contrib/`)
- ✅ 复制部署脚本到 `/data/opentenbase/deploy.sh`
- ✅ 清理不需要的文件（tests、examples、PDF、视频等）
- ✅ 保留文档供参考（README、docs/）
- ✅ 编译安装所有插件
- ✅ 配置分布式环境

---

### 常规部署（已有插件源码）

如果系统目录已有插件源码，使用以下方式：

#### 步骤 1：进入项目目录

```bash
su - opentenbase
cd /data/opentenbase
```

#### 步骤 2：运行部署脚本

```bash
bash deploy.sh
```

> **注意**：`deploy.sh` 放在 `/data/opentenbase/` 目录下，会自动检测 `OpenTenBase/contrib/` 中的插件源码。

**部署过程示例：**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ 步骤1: 环境检查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

检查必需的命令...
✓ psql 已安装
✓ gcc 已安装
✓ make 已安装
✓ pg_config 已安装

检查OpenTenBase连接...
✓ OpenTenBase连接成功
    版本: PostgreSQL 11.0 @ OpenTenBase_v5.21.8 ...

检查DataNode数量...
✓ 检测到 3 个DataNode

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ 步骤2: 安装SQL基础扩展
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ 找到 SQL 目录: /data/opentenbase/OpenTenBase/contrib/otb_timeseries/core/sql
✓ otb_timeseries 核心扩展安装成功
✓ TimescaleDB 兼容层安装成功
✓ otb_age 图数据库扩展安装成功
✓ otb_fulltext 全文检索扩展安装成功
✓ otb_scheduler 调度管理扩展安装成功
✓ otb_routing 路网分析扩展安装成功
✓ otb_analytics 时序分析扩展安装成功
✓ otb_snapshot 数据快照扩展安装成功
✓ otb_health 数据健康诊断扩展安装成功

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ 步骤3: 编译并安装C扩展（性能增强）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ 编译成功
✓ 安装成功
✓ otb_timeseries_c C扩展创建成功
✓ otb_analytics 扩展创建成功

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ 步骤4: 运行功能测试
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ 基础功能测试通过
✓ C扩展功能测试通过
✓ Analytics功能测试通过
✓ otb_age图数据库功能测试通过
✓ otb_fulltext全文检索功能测试通过

╔══════════════════════════════════════════════════════════════════╗
║   ✓ DataNexus for OpenTenBase 部署成功！                        ║
║     OpenTenBase 多模态融合枢纽                                  ║
╠══════════════════════════════════════════════════════════════════╣
║  已安装模块（8个插件）：                                         ║
║    • otb_timeseries  - 时序数据（TimescaleDB兼容）              ║
║    • otb_age         - 图数据（Apache AGE兼容）                 ║
║    • otb_fulltext    - 全文检索（zhparser+RUM兼容）             ║
║    • otb_scheduler   - 调度管理（pg_cron+pg_partman兼容）       ║
║    • otb_routing     - 路网分析（pgRouting兼容）                ║
║    • otb_analytics   - 时序分析算法库                           ║
║    • otb_snapshot    - 数据快照与回滚系统                       ║
║    • otb_health      - 数据健康诊断                             ║
╚══════════════════════════════════════════════════════════════════╝

✓ 部署完成！共安装 8 个插件
```

#### 步骤 3：验证安装

```bash
psql -h 127.0.0.1 -p 30004 -d postgres -U opentenbase
-- 检查所有插件版本
SELECT 'otb_timeseries' AS plugin, otb_ts.version() AS version
UNION ALL SELECT 'otb_age', otb_age.version()
UNION ALL SELECT 'otb_fulltext', otb_fulltext.version()
UNION ALL SELECT 'otb_routing', otb_routing.version()
UNION ALL SELECT 'otb_scheduler', otb_scheduler.version()
UNION ALL SELECT 'otb_analytics', otb_analytics.version()
UNION ALL SELECT 'otb_health', otb_health.version()
UNION ALL SELECT 'otb_snapshot', otb_snapshot.version();
```

**预期输出：**

```
     plugin     |                          version
----------------+------------------------------------------------------------
 otb_timeseries | 1.0.0
 otb_age        | otb_age 1.0.0 (Apache AGE compatible)
 otb_fulltext   | otb_fulltext 1.0.0 (zhparser + RUM compatible)
 otb_routing    | 1.0.0 - OpenTenBase Routing (pgRouting compatible)
 otb_scheduler  | 1.0.0 - OpenTenBase Scheduler (pg_cron + pg_partman compatible)
 otb_analytics  | 1.0.0 - OpenTenBase Analytics (Moving Average + Anomaly Detection)
 otb_health     | 1.0.0 - OpenTenBase Health (Data Quality Check + Smart Diagnostics)
 otb_snapshot   | 1.0.0 - OpenTenBase Snapshot (Data Snapshot & Rollback System)
(8 rows)
```

---

## 📚 基本使用

### 1. 时序数据（otb_timeseries）

```sql
-- 创建普通表
CREATE TABLE sensor_data (
    time        TIMESTAMPTZ NOT NULL,
    sensor_id   INTEGER,
    temperature DOUBLE PRECISION,
    humidity    DOUBLE PRECISION
) DISTRIBUTE BY REPLICATION;  -- 多DN环境必须使用REPLICATION

-- 转换为Hypertable（自动分区）
SELECT otb_ts.create_hypertable('sensor_data', 'time', '1 day'::INTERVAL);

-- 时间分桶聚合
SELECT 
    time_bucket('1 hour', time) AS hour,
    AVG(temperature)::NUMERIC(5,2) AS avg_temp
FROM sensor_data
GROUP BY hour ORDER BY hour;

-- first/last 聚合
SELECT 
    sensor_id,
    otb_ts.first(temperature::numeric, time) AS first_temp,
    otb_ts.last(temperature::numeric, time) AS last_temp
FROM sensor_data
GROUP BY sensor_id;
```

### 2. 图数据（otb_age）

```sql
-- 创建图
SELECT otb_age.create_graph('social_network');

-- 添加顶点和边
SELECT otb_age.add_vertex('social_network', 'Person', '{"name": "Alice"}');
SELECT otb_age.add_edge('social_network', 1, 2, 'KNOWS', '{"since": 2020}');

-- Cypher 查询
SELECT * FROM otb_age.cypher('social_network', 'MATCH (n:Person) RETURN n.name');
```

### 3. 时序分析（otb_analytics）⭐原创

```sql
-- 5种移动平均
SELECT otb_analytics.sma(temperature, 10) FROM sensor_data;   -- 简单
SELECT otb_analytics.ema(temperature, 0.3) FROM sensor_data;  -- 指数
SELECT otb_analytics.wma(temperature, 10) FROM sensor_data;   -- 加权
SELECT otb_analytics.dema(temperature, 0.3) FROM sensor_data; -- 双指数
SELECT otb_analytics.tema(temperature, 0.3) FROM sensor_data; -- 三指数

-- 异常检测
SELECT otb_analytics.detect_anomalies_zscore(temperature, 3.0) FROM sensor_data;
SELECT otb_analytics.detect_anomalies_iqr(temperature, 1.5) FROM sensor_data;
```

### 4. 数据健康诊断（otb_health）⭐原创

```sql
-- 综合健康检查
SELECT * FROM otb_health.health_check('sensor_data'::regclass, 'time');

-- 自动调优建议（生成可执行SQL）
SELECT * FROM otb_health.auto_tune_advisor('sensor_data'::regclass);
```

---

## 🔌 插件一览

### 适配插件（5 个）

| 插件               | 兼容目标     | 函数数 | 核心功能                                  |
| ------------------ | ------------ | ------ | ----------------------------------------- |
| **otb_timeseries** | TimescaleDB  | 81     | Hypertable、time_bucket、first/last、压缩 |
| **otb_age**        | Apache AGE   | 28     | 图创建、Cypher查询、最短路径              |
| **otb_fulltext**   | zhparser+RUM | 34     | 中文分词、全文搜索、高亮                  |
| **otb_routing**    | pgRouting    | 10     | Dijkstra、距离计算、最近节点              |
| **otb_scheduler**  | pg_cron      | 28     | Cron调度、分区管理                        |

### 原创插件（3 个）⭐

| 插件              | 函数数 | 核心功能                                            |
| ----------------- | ------ | --------------------------------------------------- |
| **otb_analytics** | 31     | 5种移动平均、Z-score/IQR异常检测、delta/cumsum/rate |
| **otb_health**    | 9      | 空值/间隙/重复检测、健康检查、自动调优建议          |
| **otb_snapshot**  | 5      | 创建/列表/回滚/删除快照                             |

---

## 📊 性能指标

### 测试环境

- **集群配置**：1 Coordinator + 3 DataNode
- **数据规模**：时序 100 万条、图 1000 顶点 + 2000 边、文档 1000 条

### 核心性能对比

| 测试项           | 传统方式        | 优化后      | 提升        | 说明         |
| ---------------- | --------------- | ----------- | ----------- | ------------ |
| time_bucket 聚合 | 147ms (SQL)     | 105ms (C)   | **28%**     | C语言实现    |
| first/last 聚合  | 263ms (子查询)  | 161ms (C)   | **39%**     | C语言实现    |
| 全文搜索         | 1926ms (无索引) | 1.5ms (GIN) | **1284 倍** | GIN索引加速  |
| Gorilla 压缩     | 45.3ms (Delta)  | 6.6ms       | **7 倍**    | 优化压缩算法 |

> **注**：1284倍提升来自实测数据（match()无索引 1925.5ms vs tsquery有GIN索引 1.5ms）

### 响应时间

| 操作         | 数据量 | 响应时间 |
| ------------ | ------ | -------- |
| 时间桶聚合   | 100 万 | 105ms    |
| 移动平均计算 | 100 万 | ~100ms   |
| 健康检查     | 100 万 | 1.2 秒   |
| 图顶点查询   | 1000   | 1.9ms    |

---

## 🧪 运行测试

```bash
# 功能测试（110 项）
psql -h 127.0.0.1 -p 30004 -d postgres -U opentenbase \
     -f tests/functional/complete_feature_test.sql

# 性能测试（50 项）
psql -h 127.0.0.1 -p 30004 -d postgres -U opentenbase \
     -f tests/performance/performance_test.sql
```

---

## ❓ 常见问题

### Q1：为什么要使用 DISTRIBUTE BY REPLICATION？

在多 DN 环境中，Hypertable 的自动分区机制创建的继承表需要数据一致性。使用 `DISTRIBUTE BY REPLICATION` 确保所有 DN 的数据完全同步。

### Q2：deploy.sh 应该放在哪里？

支持多种运行位置：

1. **推荐**：`/data/opentenbase/deploy.sh` - 自动检测 `OpenTenBase/contrib/` 中的插件
2. **提交目录**：`/data/opentenbase/DataNexus for OpenTenBase/deploy.sh` - 自动检测 `src/` 中的插件副本

脚本会智能识别目录结构，直接运行 `bash deploy.sh` 即可。

### Q3：遇到"找不到 SQL 文件"怎么办？

确认源码目录结构正确：

```
/data/opentenbase/
├── deploy.sh                              # 部署脚本
└── OpenTenBase/contrib/                   # 插件源码
    ├── otb_timeseries/
    ├── otb_age/
    ├── otb_fulltext/
    └── ...
```

---

## 📁 目录结构

### 作品提交目录

```
DataNexus for OpenTenBase/                 # 作品提交根目录
├── README.md                              # 项目说明（本文件）
├── 技术报告.md                            # 技术报告（简版）
├── deploy.sh                              # 一键部署脚本
├── DataNexus for OpenTenBase - *.pptx     # 演示PPT
├── 演示视频.mp4                           # 演示视频
│
├── docs/                                  # 文档目录
│   ├── 技术详析.md                        # 详细技术报告（10000字）
│   ├── 功能函数表.md                      # 完整功能清单（292个对象）
│   └── 商业价值分析.md                    # 商业价值分析
│
├── src/                                   # 源码目录
│   ├── otb_timeseries/                    # 时序数据插件
│   │   ├── core/sql/                      # SQL 定义
│   │   └── c_extension/                   # C 扩展
│   ├── otb_age/sql/                       # 图数据库插件
│   ├── otb_fulltext/sql/                  # 全文检索插件
│   ├── otb_routing/sql/                   # 路网分析插件
│   ├── otb_scheduler/sql/                 # 调度管理插件
│   ├── otb_analytics/sql/                 # 时序分析插件（原创）
│   ├── otb_health/sql/                    # 健康诊断插件（原创）
│   └── otb_snapshot/sql/                  # 数据快照插件（原创）
│
├── tests/                                 # 测试目录
│   ├── functional/                        # 功能测试（110项）
│   └── performance/                       # 性能测试（55项）
│
├── examples/                              # 示例目录
│   └── demo_multimodal.sql                # 多模态演示脚本
│
└── scripts/                               # 脚本目录
    └── deploy.sh                          # 部署脚本
```

### 系统安装目录

部署后，插件源码会被复制到 OpenTenBase 的 contrib 目录：

```
/data/opentenbase/                         # OpenTenBase 安装根目录
├── deploy.sh                              # 部署脚本（从作品目录复制）
│
└── OpenTenBase/                           # OpenTenBase 源码目录
    └── contrib/                           # 插件安装目录
        ├── otb_timeseries/                # 时序数据插件
        │   ├── core/sql/                  # SQL 定义
        │   └── c_extension/               # C 扩展（编译安装）
        ├── otb_age/sql/                   # 图数据库插件
        ├── otb_fulltext/sql/              # 全文检索插件
        ├── otb_routing/sql/               # 路网分析插件
        ├── otb_scheduler/sql/             # 调度管理插件
        ├── otb_analytics/sql/             # 时序分析插件
        ├── otb_health/sql/                # 健康诊断插件
        └── otb_snapshot/sql/              # 数据快照插件
```

---

## 📚 相关文档

| 文档                                           | 说明                      |
| ---------------------------------------------- | ------------------------- |
| [技术报告.md](./技术报告.pdf)                  | 技术报告                  |
| [docs/技术详析.md](./docs/技术详析.md)         | 详细技术实现              |
| [docs/功能函数表.md](./docs/功能函数表.md)     | 完整功能对象清单（292个） |
| [docs/商业价值分析.md](./docs/商业价值分析.md) | 商业价值分析              |

---

## 📜 许可证

Apache License 2.0

---

## 🙏 致谢

- [OpenTenBase](https://www.opentenbase.org/) - 分布式数据库内核

---

<p align="center">
  <strong>DataNexus for OpenTenBase</strong><br>
  <strong>OpenTenBase 多模态融合枢纽</strong><br>
  <br>
  「数据融合枢纽，模态无限可能」
</p>

