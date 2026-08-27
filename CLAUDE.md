# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> 项目记忆：由仓库全局梳理而来，描述 TIS 当前（v5.1.0）真实架构。开发规范见 [AGENTS.md](./AGENTS.md)。
>
> **变更沉淀机制（必须遵守）**：凡涉及以下任一情况的迭代，完成后必须在对应章节同步更新本文件，作为项目记忆的一部分：
> 1. 新增/删除/更名 Maven 模块，或调整模块间依赖 → 更新「核心架构」「模块清单」
> 2. 引入新技术、升级关键版本、移除组件 → 更新「技术与场景图谱」（含可拆卸性状态）
> 3. AI 能力、扩展点、SPI 接口变化 → 更新「AI 能力体系」
> 4. DAO/表结构/SQLMap 变化 → 更新「DAO/配置文件位置」
> 5. 构建/部署/脚本流程变化 → 更新「常用命令」「部署形态」
> 6. 发现新的架构耦合点或坑 → 补充到「可拆卸性评估」表格

## 项目概述

TIS 是新一代 **AI 原生数据集成平台**：底层为经过生产验证的批流一体引擎（DataX 批量 / Flink-CDC、Chunjun 实时），上层融合 LLM 能力——Pipeline AI Agent（自然语言建管道）、Ontology 知识图谱 + ChatBI（GraphRAG 检索）。设计思想继承 Jenkins（SPI 插件体系 + 微前端自动渲染），前端为独立仓库 [ng-tis](https://github.com/qlangtech/ng-tis)，不在本仓库。

- 当前版本：`5.1.0`（根 POM `${revision}` 统一管理）
- 组织坐标：`com.qlangtech.tis`，父 POM 为外部 `tis-parent:2.2.0`
- License：Apache 2.0；文档站 https://tis.pub

## 核心架构（分层依赖自上而下）

```
应用层    tis-console        Struts2 控制台业务（war，finalName=tis）
容器层    tis-web-start      Jetty 12 (EE11) 嵌入式启动器
          tis-web-start-api  启动契约 jar（打破循环依赖）
执行层    tis-dag            DAG 运行时模型   tis-assemble 全量构建节点
          tis-k8s(纯yaml)     tis-hadoop-rpc(gRPC)
插件层    tis-plugin-sezpoz  SPI 注解协议(APT)
          tis-plugin         Jenkins 式扩展点框架 + 全部扩展点定义
基础层    tis-common · tis-common-dao · tis-manage-pojo · tis-builder-api
          tis-sql-parser · tis-solrconfig-parser · xmodifier · tis-scala-compiler
          datax-config(DataX 共享基类) · tis-base-test(测试基建)
打包工具  maven-tpi-plugin   tpi 插件包格式（Jenkins hpi 改造）
```

依赖方向单向流动；tis-web-start-api 被重型模块以 provided 引用，避免循环。

### 运行形态

单进程多 context：`TisApp.main`（tis-web-start）→ `JettyTISRunner` 拉起主 context 即 tis-console 的 war（约定结构 `<dir>/webapp|lib|conf`，每 context 独立 `TISAppClassLoader`），可选挂载 tis-assemble 等子应用。Connector 为 HTTP1.1+HTTP2C；`/check_health` 经 JDK ServiceLoader 加载 `IStatusChecker`；`TriggerStop` 支持 STOP.PORT 平滑停机。

## 模块清单（feature/chatbi-only 后：根 POM 13 个 module）

> **分支背景**：`feature/chatbi-only` = Scope A「纯问答」裁剪——数据仓库由外部系统建好，本仓只保留 本体建模 + GraphRAG + NL2SQL 所需能力。已移出构建并删除目录的 8 个模块：xmodifier、tis-hadoop-rpc、tis-solrconfig-parser、tis-assemble、tis-dag、tis-sql-parser、tis-scala-compiler、tis-k8s、tis-collection-info-collect；其已发布的 5.1.0 构件仍在 rdc-releases 远程仓库，console 等遗留 Solr/DataX 管理 Action 经 Maven 依赖引用这些远程 jar，编译/运行不受影响。

| 模块 | 职责 | 关键点 |
|---|---|---|
| tis-console | Web 控制台业务核心（Struts2 7.0.0 + iBATIS 2.3.4.726/tis-ibatis + 内嵌 Derby + Quartz 2.3.2 + MCP SDK 1.1.0） | 入口 `ConsoleInitilizeListener`(ServletContextListener)；manifest mainClass=`SysInitializeAction`；包：`aiagent.core/plan/execute`（Plan-and-Execute Agent）、`runtime.module`（Action/control/screen）、`manage.biz.dal`、`offline.module`、`workflow.*`（websocket 日志推送）、`mcp.tools`（ChatBITool 等 MCP 工具）、`openapi/alert/db.parser` |
| tis-web-start | Jetty12 嵌入容器 + 健康检查 + 日志采集 + ng-tis 路由 Filter(AngluarFilter) | main 类 `com.qlangtech.tis.web.start.TisApp` |
| tis-web-start-api | 启动契约：`TisAppLaunch`/`TisSubModule`/`TisRunMode`、`datax.job.SSERunnable`、`trigger.feedback.IJobFeedback` | 近零依赖 |
| tis-plugin | SPI 核心（仿 Jenkins）：`Descriptor`/`Describable`/`PluginManager`/`PluginWrapper`/`ExtensionList`/`UberClassLoader`/`KeyedPluginStore`（插件实例 JSON 存储）/`IPluginContext` | 扩展点子包：`plugin.ds`(数据源)、`plugin.datax`(reader/writer/transformer)、`plugin.llm`、**`plugin.ontology`**(本体+chatbi)、`plugin.alert/k8s/credentials`、`plugins.incr.flink.cdc.pipeline`；akka 集群支持类在此（`DataXJobSubmitAkkaClusterSupport`）。chatbi-only 已删 `plugin.solr.schema` 包并去除 xmodifier 依赖 |
| tis-plugin-sezpoz | 仅 4 个类：`@TISExtension`/`@TISExtensible` 注解协议，sezpoz 编译期索引（运行期零反射扫描） | 全项目 SPI 注册标准方式 |
| tis-dag | DAG 运行时模型与调度入口（参考 PowerJob 设计，9 个类） | `powerjob.algorithm.WorkflowDAG`+拓扑算法；注意 akka 不在本模块（在 tis-plugin/tis-assemble/console）；`TemplateContext` 已整体注释废弃 |
| tis-assemble | 全量索引流水线构建节点 | 启动类 `IndexSwapTaskflowLauncher`；打 tar.gz 输出到仓库根目录；profile daily/pre/publish |
| tis-hadoop-rpc | 组件间 gRPC/Protobuf 通信：增量状态上报 `IncrStatusGrpc`、日志流、DataX 预览服务 | — |
| tis-sql-parser | SQL AST 解析/改写（Presto fork），驱动流式代码生成与表血缘 | `SqlTaskNode`/`SqlRewriter`/`TableDependencyVisitor` |
| tis-solrconfig-parser | 解析 Solr schema/config（StAX） | `SolrFieldsParser`、`IIndexBuildLifeCycleHook` |
| xmodifier | 类 XPath 语法的 XML 补丁工具 | 用于 solrconfig/schema 动态修改 |
| tis-scala-compiler | 运行时动态编译（Java Compiler API）生成 DAO 与增量脚本 | `GenerateDAOAndIncrScript` |
| tis-manage-pojo | 最大公共 POJO 库：表元数据(`ISelectedTab`/`CMeta`)、solr schema、fullbuild、realtime.yarn.rpc、powerjob.model | 最小 LLM 面：`aiagent.llm.ITISJsonSchema` |
| tis-common-dao | iBATIS DAO 层：manage(应用)、trigger(Job/Task/日志)、workflow(`IDAGNodeExecutionDAO`) 三域 | dbcp 数据源 |
| tis-common | 轻量基础库：ConfigFileReader(本地/HTTP)、GitUtils(JGit)、ZkPathUtils | — |
| tis-builder-api | 构建期 API：taskflow 编排(hudson reactor)、增量 dump、**tis-plugin-sezpoz 注解处理核心所在**、tpi 打包模型 | — |
| tis-base-test | 测试基建：`TISTestCase` 自动 mock HTTP/ZK；JUnit4+Mockito 3.4.x(+EasyMock) | compile scope 发布供 test 复用 |
| maven-tpi-plugin | `tpi` Mojo（Jenkins hpi 改造）：生成 Jenkins 风格 MANIFEST(`Plugin-Class` 等)，先出普通 jar 再把 webapp 依赖打成 `.tpi` fat-jar 设为主构件 | 另有 `ValidateMojo`/`HplMojo` |
| tis-k8s | 无 Java 代码，packaging=pom：两份可 `kubectl apply` 的清单（tis-console.yaml Deployment/PV/ConfigMap、tis-test-mysql.yaml），资源变量替换 `${project.version}` | K8S 客户端实际在插件仓库，用 kubernetes-client/java（`K8sImage.createApiClient()`），无 fabric8/CRD |
| docker-compose | pom 型：docker-compose.yaml 起 flink(tis/flink:5.1.0,:8081) + tis-console(:8080 + gRPC 56432)；含自建 powerjob-server:4.3.6 镜像目录 | 挂载 config.properties → `/opt/app/tis-uber/web-start/conf/tis-web-config/config.properties` |
| datax-config | 普通 jar：DataX 侧共享基类（Column/Record、DataXException、非结构化 Reader/Writer SPI），供 DataX 插件复用 | 不是配置目录 |

### 根构建之外的特殊目录

- **tis-web-config**：非 Maven 模块，仅 `config.properties` 模板（runtime=daily、MySQL 连接、assemble.host 等），对应 docker-compose/K8S 的 ConfigMap 挂载内容。
- **tis-openclaw-plugin**：完全独立版本（无 parent，1.0.0），把 TIS 能力封装成 OpenClaw 插件（MCP 协议 + SKILL.md），默认 endpoint `http://localhost:8080/tjs/mcp`。
- ~~tis-collection-info-collect~~：chatbi-only 分支已删除。

## AI 能力体系（v5.1 核心）

三层分布：

1. **tis-manage-pojo**：`ITISJsonSchema` 最小接口下沉公共层。
2. **tis-plugin**（插件抽象层 ~75 文件）：
   - `aiagent.llm.LLMProvider`（LLM 厂商 SPI）→ `plugin.llm.DeepSeekProvider/QWenLLMProvider/AnthropicLLMProvider/ZhipuLLMProvider`
   - `plugin.ontology.Ontology/OntologyDomain/OntologyObjectType/OntologyLinker/OntologyGlossary`（本体建模，neo4j 存储在 Ontology.java 引用）
   - `plugin.ontology.chatbi.ChatBIService/QueryResult/TraceStep`（ChatBI，GraphRAG 四路并行检索）
3. **tis-console**（编排层 ~64 文件）：
   - `aiagent.core.TISPlanAndExecuteAgent`（Plan-and-Execute 主循环）、`PendingClarificationException`（澄清追问）
   - `aiagent.plan.PlanGenerator/TaskPlan/TaskStep`；`aiagent.execute.impl.PluginInstanceCreateExecutor/PipelineBatchExecutor/PipelineIncrExecutor/PluginDownloadAndInstallExecutor`
   - Prompt 模板为 resources 下 `aiagent/execute/impl/*.md` 文件
   - `mcp.tools.ChatBITool` 及 pipeline 工具（MCP Server 形态对外暴露）

## DAO/配置文件位置（tis-console 内两套 iBatis 并存）

- 总配置：`src/main/resources/conf/*-sqlmap-config.xml` + 对应 `*-dao-context.xml`、`tis.application.context.xml`、`struts.xml`
- 映射文件：
  - `com/qlangtech/tis/manage/biz/dal/dao/sqlmap/*.xml`（~27 个）
  - `com/qlangtech/tis/workflow/dao/sqlmap/*.xml`（work_flow、dag_node_execution 等）
  - `com/qlangtech/tis/dataplatform/dao/sqlmap/`（ds_datasource、ds_table）

改表字段需同步 POJO → DAO 接口 → Criteria → SQLMap 四处；SQLMap 注意 Derby 兼容性（历史 fix 见 git log）。

## 技术与场景图谱（v5.1 实测梳理）

### 一、技术清单与应用场景

| 技术栈 | 版本 | 应用场景 | 落点 |
|---|---|---|---|
| Java / Maven `${revision}` | 17 / 5.1.0 | 全仓构建体系，父 POM 外置 tis-parent | 根 pom.xml |
| Jetty EE11 + HTTP2C + WebSocket | 12.1.7 | 嵌入式容器，多 context 类加载，日志实时推送 | tis-web-start |
| Struts2 + Velocity | 7.0.0 | 控制台 Action/Screen 渲染 | tis-console |
| Spring | 6.2.1 | DAO/AOP 装配（操作日志切面等） | tis-console resources |
| iBATIS (tis-ibatis) + Derby + MySQL | 2.3.4 | 平台自身元数据存储（应用/工作流/DAG 执行记录） | tis-console、tis-common-dao |
| Quartz | 2.3.2 | 工作流定时调度 | tis-console |
| Sezpoz APT | — | 编译期 SPI 索引（`@TISExtension`），Jenkins 式插件框架核心 | tis-plugin-sezpoz + tis-builder-api APT 配置 |
| akka cluster | — | DataX 分布式提交通道之一、DAG 取消/状态查询 | tis-plugin(`DataXJobSubmitAkkaClusterSupport`)、tis-assemble(`DAGWorkflowServlet`) |
| gRPC/Protobuf | — | 增量状态上报、日志流、DataX 预览 | tis-hadoop-rpc |
| ZooKeeper | — | assemble 触发器路径（仅 2 处直接 import） | tis-assemble `TriggerJobManage` 等 |
| Solr SolrJ | 8.7.0 | 索引 core 管理、schema 解析、在线查询 | tis-console servlet、tis-solrconfig-parser |
| Presto SQL parser fork | — | SQL 改写、表血缘、Flink 流式代码生成 | tis-sql-parser |
| Java Compiler API (+Scala) | — | 运行时动态编译 DAO 与增量脚本 | tis-scala-compiler |
| JGit | — | 配置仓库（cfg_repo）版本管理 | tis-common `GitUtils` |
| Flink CDC (fork) / DataX (fork) / Chunjun | tis-1.20.1 | 批流一体同步引擎；本仓库仅 1 文件直接 import flink（`TISRateLimiter`），管道实现走扩展点+外部插件仓 | tis-plugin 扩展点 |
| kubernetes-client/java | — | K8S DataX Worker、Flink Cluster 管理（实现在插件仓）；本模块纯 YAML 清单 | tis-k8s、tis-plugin `K8sImage` |
| PowerJob | 4.3.6 | 全量构建调度后端之一（`PEWorkflowDAG` 模型对接） | docker-compose/powerjob、tis-manage-pojo |
| LLM SDK（DeepSeek/QWen/Anthropic/Zhipu） | — | Pipeline AI Agent、参数生成、ChatBI SQL 生成 | tis-plugin `plugin.llm`（SPI 插件化） |
| Neo4j + GraphRAG | — | Ontology 图谱存储与检索；**本仓库零依赖**，由外部 tis-ontology-plugin 运行时注册 | `plugin.ontology.Ontology.java:189`（未启动返回 empty） |
| MCP SDK | 1.1.0 | console 的 MCP Server（mcp.tools.* 10+ 工具）对外暴露 TIS 能力 | tis-console `mcp.tools` |

### 二、可拆卸性评估

**A. 核心骨架，不可拆**：Sezpoz SPI 框架、Jetty 启动器、Struts2/Spring/iBATIS(Derby)、tis-plugin Descriptor 体系——移除任何一项平台无法启动。

**B. 已是插件化设计，天然可拆卸 ✅**（不装对应插件即自动降级）：
- AI 全家桶（LLM/Ontology/ChatBI/MCP）：LLM 是 `LLMProvider` SPI；Neo4j 由外部 plugin 注册、未启动返回 empty；ChatBI/MCP 工具是独立扩展点
- 数据同步引擎：Reader/Writer 全在 tpi 包；DataX 提交通道是 SPI 三选一（`DataXJobSubmit.InstanceType`: EMBEDDED/LOCAL/AKKA）
- 各数据源：MySQL→ES/Hive/StarRocks 等全部按需安装 tpi

**C. 架构留了位，可拆但有残留耦合 ⚠️**：

| 组件 | 拆卸方式 | 当前耦合点 |
|---|---|---|
| akka 集群 | 选 LOCAL/EMBEDDED 通道即可不用 | `DAGWorkflowServlet` 硬引用 akkaClusterSupport；console `TISActorSystemHolder` 已注释=作者在弱化它，彻底移除只需清理 assemble 一处调用链 |
| Solr 索引管理 | 只做数据同步时可弃 | 历史包袱重（console core 构建/solrconfig-parser/xmodifier 都为它服务），TIS 出身即 tis-solr，拆除等于裁掉半个控制台 |
| PowerJob | 不选该调度后端即可 | PEWorkflowDAG POJO 在 manage-pojo 公共层，仅模型依赖非硬绑定 |
| DolphinScheduler | 枚举值已注释禁用 | `InstanceType.DS` 整段注释，官方已搁置项 |
| ZooKeeper | 单机模式不触发即无感 | assemble 触发器 2 个类直接 import，非中心化依赖 |
| gRPC (tis-hadoop-rpc) | 单机不用分布式增量时可弃 | 增量状态上报强绑定 Flink-CDC 链路 |
| tis-collection-info-collect | 直接不打包 | 本就游离于根构建外 |

> 结论：动不得的是「Jenkins 式内核 + Web 容器 + 元数据库」三件套；AI 栈和同步引擎活在插件体系里拆卸零成本；akka/Solr 索引管理/DS/ZK 是历史旁路，属"架构允许拆、需清调用残留"。

### 三、chatbi-only 分支的实际裁剪结果（2026-08-27）

**第一轮**：根 POM 移除并删除 9 个模块目录（xmodifier、tis-hadoop-rpc、tis-solrconfig-parser、tis-assemble、tis-dag、tis-sql-parser、tis-scala-compiler、tis-k8s、tis-collection-info-collect）；tis-plugin 删 `plugin.solr.schema` 包。

**第二轮（外部依赖清零）**：保留模块 POM 已零引用已删模块，main+test 编译完全基于仓内源码：
- console：删 `CoreAction`（compiler/sql-parser 双重硬耦合）、`CollectionAction`（hadoop-rpc）、`PipelineIncrExecutor` 及 TaskStep.EXECUTE_INCR 步骤、Solr 向导端点（doCreateCollection/doAdvanceAddApp/doGetTplFields/mergeWfColsWithTplCollection/ExtendApp.createAppSource）、死测试若干
- 迁移：`WorkflowDAGFileManager`→ tis-plugin（builder-api 依赖方向不符）；`SchemaResult`/`CoreRequest.createIps` 就地内联；`StreamContextConstant.getStreamScriptRootDir` 路径工具本地化进 DataxAction
- stub 化：OfflineManager 的 SqlTaskNodeMeta 触点；DataxAction 增量状态探测退化为 NONE；BasicModule.getServerGroup0 内联并摘除 IERRulesGetter 实现
- 零依赖原则落地：`javax.annotation.Nullable` → `org.springframework.lang.Nullable`（复用 spring-core，不新增 jar）
- 根 POM dependencyManagement 清理已删模块条目；新增 rdc-releases 私仓（https，Maven 3.8+ 屏蔽 http）解析 tis-ibatis/tisasm 等不可替代的外部自研构件

## 常用命令

```bash
# 完整安装（离线模式，依赖本地仓库缓存）
mvn clean install -Dmaven.test.skip=true -Dappname=all -o

# 打包（同 package.sh）
mvn clean package -Dmaven.test.skip=true -Dappname=all -o

# 单模块测试（JUnit4，测试类 FooTest.java 放 src/test/java 包路径对齐）
mvn test -pl <module> -am

# 发布核心模块到远程 Maven 仓（deploy.sh 内容）
mvn clean deploy -Dmaven.test.skip=true -Dautoconfig.skip \
  -pl tis-plugin,maven-tpi-plugin,tis-sql-parser,tis-web-start -am -Ptis-repo

# 批量改版本号
./setversion.sh
```

脚本速查：`package.sh` 全量打包；`deploy.sh` 发 Maven 仓；`deploy-assemble-local.sh` 用外部 tisasm-maven-plugin 把各节点 tar.gz put 到 OSS；`create-ln.sh` 服务端软链装载 *.tpi 插件；`copy-2-remote-node.sh`/`sync-data-cfg.sh` rsync 同步到固定内网测试机（192.168.28.x，慎用）。

## 部署形态

单机 tar 解压启动 / Docker / Docker Compose（flink+tis-console 双服务）/ Kubernetes（tis-k8s 清单直 apply）。运行时配置统一走 `tis-web-config` 的 config.properties 模板。

## 外部配套仓库

前端 ng-tis · 插件 [plugins](https://github.com/qlangtech/plugins)（大部分 Reader/Writer 实现不在本仓库！本仓库是 Core 内核，管插件生命周期）· 商业插件 tis-plugins-commercial · 数据源专项 tis-sqlserver/tis-paimon/tis-dameng-plugin · 插件脚手架 tis-archetype-plugin · 元数据生成 update-center2 · fork 版 DataX/Flink/Chunjun/Debezium/Flink-CDC/Dolphinscheduler

> ⚠️ 常见误区：新增数据源插件通常应在新仓库基于 tis-archetype-plugin 开发并通过 maven-tpi-plugin 打 tpi 包发布到 update-center，而非直接改本仓库。
