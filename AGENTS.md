# AGENTS.md — TIS 项目开发规范

> 本文件由全局开发偏好（`~/.reasonix/global-workspace/.mcp/AGENTS.global.md`）针对本项目适配而来，作用于 TIS 仓库全局。项目背景详见 [CLAUDE.md](./CLAUDE.md)。

## 沟通

- 始终用简体中文回复，代码/标识符/命令保持原文。
- 回答要直接给结论，再给依据；不要长篇铺垫。

## 编码

- 改动前先看相关代码与现有风格，保持一致性；优先参考同模块内既有实现。
- **项目记忆沉淀**：凡涉及模块结构、依赖关系、技术栈、AI 扩展点、DAO 结构或构建部署流程的变更，完成后必须同步更新 [CLAUDE.md](./CLAUDE.md) 对应章节（变更沉淀机制见该文件头部）。
- **禁止错误静默兜底**：
  - 禁止 `catch` 后返回常量/null/空集合/固定状态码且不打日志——这会制造"假成功"，问题被无限期掩盖。
  - 被裁剪能力（chatbi-only 已删的 Solr/DAG/Flink 编译链路）被调用时必须**快速失败**：抛 `UnsupportedOperationException` 并写明裁剪背景与替代方案，或校验结果置 fail + 明确文案，绝不返回假成功。
  - 必须容错跳过的场景（如批量枚举中单条失败），至少 `log.warn/error` 带实体标识与异常栈；能向调用方传递错误的应回传 error 字段/消息。
  - 可选依赖未装配属于设计内合法状态的可显式降级（如 Neo4j 未启动返回 empty），但须在 Javadoc 写明降级语义。
  - 禁用 `e.printStackTrace()` 与空 catch 块。
- 写测试：修复 bug 时先加复现测试；新功能尽量带测试。
  - 测试类命名 `FooTest.java`，放在对应模块 `src/test/java` 下，包路径与被测类一致。
  - 测试框架跟随项目：JUnit + Mockito（3.4.x），Scala 模块可用 mockito-scala。
- 提交用 Conventional Commits：`<type>(<scope>): <摘要>`。type 取 feat/fix/docs/refactor/test/chore/perf/style；摘要可中文（跟随仓库现状，如 `fix(dag): DAG 节点执行 Derby 兼容问题`）。
- 不留下调试代码（System.out.println、printStackTrace、注释掉的代码块、TODO 未清理）。
- 密钥、token 绝不写进代码或提交（注意 `docker-compose/`、`deploy*.sh` 中常出现 OSS/host 配置），敏感值走环境变量。

## 命名规范

- **分支**：`feature/<简述>`、`fix/<简述>`、`chore/<简述>`、`docs/<简述>`；连字符分隔（如 `feature/oracle-cdc`）。
- **提交**：见「编码」一节；摘要祈使句风格，一行 ≤72 字符为宜。
- **Maven 模块**：新模块命名 `tis-<功能域>`（如 `tis-dag`、`tis-k8s`）；groupId 继承 `com.qlangtech.tis`。
- **Java 标识符**：
  - 类/接口/枚举：`PascalCase`；抽象基类前缀 `Abstract`、接口实现后缀按语义（如 `Impl`、`<Source>Reader`、`<Target>Writer`）。
  - 方法/变量：`camelCase`；常量：`UPPER_SNAKE_CASE`。
  - 包名：全小写，`com.qlangtech.tis.<域>`。
- **SPI 插件**：Reader/Writer、数据源插件遵循 `tis-plugin` 既有命名与目录结构，通过 `maven-tpi-plugin` 打包。
- **SQL/XML 配置**：资源文件跟随所在模块惯例（SQLMap、solrconfig 等），不随意重排属性顺序，减少 diff。

## 技术选型

- **首要原则**：跟随项目现有技术栈与依赖版本，不引入新框架/新依赖除非必要。
- **插件优先（chatbi-only 演进纪律）**：新增能力优先通过 SPI 扩展点 + tpi 插件包实现，不改内核；禁止往保留模块回引已裁剪能力（Solr 索引管理、DataX/Flink 管道编排、DAG 调度、脚本动态编译）；新第三方 jar 入依赖前先确认能否复用已有传递依赖。
- **关键版本**（以根 `pom.xml` 为准，勿擅自升级）：Java 17、`${revision}` 统一管理版本号（当前 5.1.0）、Spring 6.2.x、Flink tis-1.20.1、Solr 8.7.0。
- 多模块间依赖通过父 POM `tis-parent` 继承管理；新增模块必须加入根 `<modules>` 并沿用 `${revision}`。
- 构建/CI：Maven；常见命令见 CLAUDE.md，本地快速验证用：
  ```bash
  mvn clean install -Dmaven.test.skip=true -Dappname=all -o   # 完整安装
  mvn test -pl <module> -am                                   # 单模块测试
  ```
- 前端在本仓库之外（独立仓库 ng-tis），本仓库内不要引入前端构建产物。

## 环境

- Python 脚本用 `/usr/local/bin/python3.11`（系统默认 `python3` 已损坏，勿用）。
- 本机访问 GitHub 需代理：`git -c http.proxy=http://127.0.0.1:7890 ...`（clone/pull 时加 `-c` 参数即可，不改全局配置）。
- 构建离线模式 `-o` 依赖本地仓库已缓存的产物；依赖拉取失败时先去掉 `-o` 排查。

## 团队协作（多 Agent）

- 团队角色 Profiles：`architect`（拆解/设计）、`backend-engineer`（Java/Maven 实现）、`devops-engineer`（打包/部署/k8s）、`test-writer`（实现）、`code-reviewer`（评审）、`debugger`（疑难问题）。
- 多模块任务：architect 拆解定接口 → 各 agent 按模块隔离并行实现 → code-reviewer 评审 → `mvn install` 集成验证。
- 大任务默认按团队分工；小改动（<5 文件）直接单 agent 做。

## 安全

- 涉及不可逆操作（删除、`git push --force`、部署脚本 `deploy.sh`/`package.sh` 影响远端产物）前先确认。
- 不把无关文件加入提交；提交前审查 diff。
