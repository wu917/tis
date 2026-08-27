# ChatBI 插件开发与打包指引

> 本分支（feature/chatbi-only）内核只含 **接口契约**，ChatBI 的具体实现、知识图谱（Neo4j）同步均由 [qlangtech/plugins](https://github.com/qlangtech/plugins) 仓库的子工程以 tpi 插件形式提供——**初始项目零外部依赖即可启动**，插件按需装配。

## 必装插件（ChatBI 完整链路）

| tpi 包 | plugins 仓库子目录 | 提供 |
|---|---|---|
| tis-ontology-plugin | `tis-ontology-plugin/` | `DefaultChatBIService`(NL2SQL 主流程)、`DefaultGraphRAGService` 检索、`OntologyNeo4jSyncService` 图谱同步、SQL 校验链(AstValidator/ExplainValidator/KeywordWhitelistValidator)、PromptBuilder |
| MySQL/JDBC 数据源 Reader | `tis-datax-mysql-plugin/` 等 | 本体 ObjectType 绑定物理表 + Doris 数仓连接 |
| LLM Provider（四选一） | `tis-llm-deepseek-plugin/` `tis-llm-qwen/` 等 | NL2SQL 的模型调用（需 API Key）|

## 打包步骤

```bash
# 1. 克隆插件仓库（与本仓库平级放置）
git clone https://github.com/qlangtech/plugins.git ../plugins

# 2. 单独打 tpi 包（maven-tpi-plugin 已在父 POM 配置）
cd ../plugins/tis-ontology-plugin
mvn clean package -Dmaven.test.skip=true
# 产物: target/*.tpi

# 3. 装入运行时插件目录（放入即被 PluginManager 发现，重启生效）
cp target/*.tpi <repo>/runtime/data/libs/plugins/
```

## 缺失插件时的行为（设计保证）

- 内核启动：**不受影响**，正常拉起 Web/MCP 服务
- 访问 ChatBI：两个入口都会**快速失败**并给出明确指引：
  - MCP `ChatBITool.getChatBIService()` → `"domain 'xxx' does not have ChatBI enabled"`
  - Web `OntologyAction` → `"instance of ChatBIService can not be null"`
  这是有意为之的错误暴露（见 AGENTS.md「禁止错误静默兜底」），不是缺陷。

## 外部服务依赖策略

| 服务 | 定位 | 缺失时 |
|---|---|---|
| Derby(内嵌) / MySQL | 强依赖（元数据存储）| 内核自带 Derby，启动即用；MySQL 为扩容选项 |
| Neo4j | 扩容项（图谱持久化）| 不装则本体功能可用但无图谱统计，接口显式返回 empty(`Ontology.java`) |
| LLM API | 运行时配置 | 未配 Key 时 verify 环节失败并回传错误 |
| Doris/数仓 | 扩容项（查询引擎）| 问数执行阶段才依赖，连接失败错误原样上抛 |
