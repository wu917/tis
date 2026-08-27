#!/usr/bin/env bash
# =============================================================================
# init-local-dev.sh — TIS chatbi-only 本地开发环境初始化
#
# 作用：
#   1. 在仓库根目录创建 runtime/ 运行时目录（Jetty 多 context 约定布局）
#   2. 组装 tis-console 主 context（jar+conf+webapp+lib，对应 assembly.xml 结构）
#   3. 生成 Derby 版 config.properties（零外部数据库依赖；--with-mysql 可切换）
#   4. 输出 IDE 启动参数 / 命令行启动命令
#
# 用法：
#   ./init-local-dev.sh                 # Derby 模式（推荐，开箱即跑）
#   ./init-local-dev.sh --with-mysql    # MySQL 模式（交互输入连接信息）
#
# 幂等：可重复执行；删除 runtime/ 目录即完全重置。
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${REPO_DIR}/runtime"
PORT="${TIS_PORT:-8080}"
WITH_MYSQL=false
[[ "${1:-}" == "--with-mysql" ]] && WITH_MYSQL=true

log()  { printf '\033[1;32m[init]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2; }

# -----------------------------------------------------------------------------
# 0. 前置校验：JDK 17 与构建产物
# -----------------------------------------------------------------------------
JAVA17_HOME=""
# 候选：环境变量 > brew openjdk@17 > java_home（校验版本确为17，防回落到11）
for h in "${JAVA_HOME:-}" \
         /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
         "$(/usr/libexec/java_home -v 17 2>/dev/null || true)"; do
  if [[ -n "$h" && -x "$h/bin/java" ]] && "$h/bin/java" -version 2>&1 | grep -q 'version "17'; then
    JAVA17_HOME="$h"; break
  fi
done
if [[ -z "$JAVA17_HOME" ]]; then
  err "未找到 JDK 17。请先: brew install openjdk@17"
  exit 1
fi
log "JDK17: ${JAVA17_HOME}"

WEB_START_JAR="$(ls "${REPO_DIR}"/tis-web-start/target/web-start-*.jar 2>/dev/null | grep -v sources | head -1 || true)"
[[ -z "$WEB_START_JAR" ]] && WEB_START_JAR="${REPO_DIR}/tis-web-start/target/classes"

CONSOLE_JAR="${REPO_DIR}/tis-console/target/tis.jar"
for artifact in "${CONSOLE_JAR}" \
  "${REPO_DIR}/tis-web-start/target/classes/com/qlangtech/tis/web/start/TisApp.class" ; do
  if [[ ! -e "$artifact" ]]; then
    err "缺少构建产物: $artifact"
    err "请先执行: mvn clean install -Dmaven.test.skip=true"
    exit 1
  fi
done
log "构建产物校验通过"

# -----------------------------------------------------------------------------
# 1. 运行时目录（web.root.dir 根下每个子目录 = 一个 Jetty context）
#    <context>/lib   = classpath jar
#    <context>/conf  = 配置目录（manifest Class-Path 引用 conf/）
#    <context>/webapp= 静态资源 + WEB-INF/web.xml
# -----------------------------------------------------------------------------
CTX="${RUNTIME_DIR}/webapps/tis"
mkdir -p "${CTX}/webapp" "${CTX}/conf" "${CTX}/lib" \
         "${RUNTIME_DIR}/data/libs/plugins" \
         "${RUNTIME_DIR}/logs"

# -----------------------------------------------------------------------------
# 2. 组装 tis console context
# -----------------------------------------------------------------------------
log "组装 console jar → ${CTX}/lib/"
cp "${CONSOLE_JAR}" "${CTX}/lib/"

log "复制运行期依赖(runtime scope) → ${CTX}/lib/"
# maven-dependency-plugin 首次需联网解析；已有缓存则 -o 离线
CP_FILE=/tmp/tis-cp.txt
( cd "${REPO_DIR}/tis-console" && \
  if [[ -s "${CP_FILE}" ]]; then OFFLINE="-o"; else OFFLINE=""; export http_proxy="${http_proxy:-http://127.0.0.1:7890}" https_proxy="${https_proxy:-http://127.0.0.1:7890}"; fi
  "/Applications/IntelliJ IDEA CE.app/Contents/plugins/maven/lib/maven3/bin/mvn" -q \
    dependency:build-classpath -Dmdep.outputFile=${CP_FILE} \
    -Dmdep.includeScope=runtime $OFFLINE > /dev/null )
TRASH_EXCLUDE='log4j|jetty|logback|slf4j|servlet'
copied=0; skipped=0
CP_CLASSPATH="$(cat "${CP_FILE}")"
for e in ${CP_CLASSPATH//:/ }; do
  base="$(basename "$e")"
  if echo "$base" | grep -qE "$TRASH_EXCLUDE"; then skipped=$((skipped+1)); continue; fi
  cp -f "$e" "${CTX}/lib/" && copied=$((copied+1))
done
log "依赖 jar 复制 ${copied} 个（跳过容器冲突类 ${skipped} 个）"

log "同步 resources(conf) 与 webapp/ "
rsync -a --delete "${REPO_DIR}/tis-console/target/classes/" "${CTX}/conf/" \
  --include="*.yml" --include="*/" --include="*.xml" --include="*.properties" --exclude="*"
rsync -a --delete "${REPO_DIR}/tis-console/webapp/" "${CTX}/webapp/" \
  --exclude="WEB-INF/classes/**"

# manifest 需要 classpath 前缀为 lib/ 且 jar 内引用 conf/ —— jar 放到 lib/ 已满足；
# struts/spring 等 XML 中的相对路径按 ${ctx}/ 为基准，与生产 tar 结构一致。

# -----------------------------------------------------------------------------
# 3. config.properties
#    Config 加载顺序: classpath tis-web-config/config.properties
#      → 本地开发同时放 conf/ 与 WEB-INF/classes/tis-web-config/
# -----------------------------------------------------------------------------
mkdir -p "${CTX}/webapp/WEB-INF/classes/tis-web-config" "${RUNTIME_DIR}/tis-web-config"

if $WITH_MYSQL; then
  read -rp "MySQL host: " MYSQL_HOST
  read -rp "MySQL port [3306]: " MYSQL_PORT; MYSQL_PORT=${MYSQL_PORT:-3306}
  read -rp "MySQL user [root]: " MYSQL_USER; MYSQL_USER=${MYSQL_USER:-root}
  read -rsp "MySQL password: " MYSQL_PASS; echo
  DS_BLOCK="tis.datasource.type=mysql
tis.datasource.url=${MYSQL_HOST}
tis.datasource.port=${MYSQL_PORT}
tis.datasource.username=${MYSQL_USER}
tis.datasource.password=${MYSQL_PASS}
tis.datasource.dbname=tis_console"
  warn "MySQL 模式需提前建库: CREATE DATABASE tis_console;"
else
  DS_BLOCK="tis.datasource.type=derby
tis.datasource.dbname=tis_console_db"
fi

cat > "${RUNTIME_DIR}/tis-web-config/config.properties" <<EOF
##
# TIS 本地开发配置（由 init-local-dev.sh 生成）
project.name=TIS
runtime=daily

${DS_BLOCK}

# 数据目录（tpi 插件安装于 <data.dir>/libs/plugins）
data.dir=${RUNTIME_DIR}/data

tis.host=127.0.0.1
assemble.host=127.0.0.1
EOF

for d in "${CTX}/conf/tis-web-config" \
         "${CTX}/webapp/WEB-INF/classes/tis-web-config"; do
  mkdir -p "$d"
  cp "${RUNTIME_DIR}/tis-web-config/config.properties" "$d/config.properties"
done
log "config.properties(Derby=$([[ $WITH_MYSQL == false ]] && echo true || echo false)) 就位"

# -----------------------------------------------------------------------------
# 4. 插件提示 & 输出启动方式
# -----------------------------------------------------------------------------
log "插件目录: ${RUNTIME_DIR}/data/libs/plugins/"
warn "ChatBI 三件套需另行安装(tpi): JDBC 数据源 / LLM Provider(API Key) / tis-ontology-plugin"
warn "tis-ontology-plugin 含 DefaultChatBIService 与 Neo4j 同步实现，本仓库仅有接口"

cat <<EOF

==================== 初始化完成 ====================
① IDE 启动（推荐）— main 类 com.qlangtech.tis.web.start.TisApp
     VM options:
       -Djava.awt.headless=true
       -Dweb.root.dir=${RUNTIME_DIR}/webapps
       -Ddata.dir=${RUNTIME_DIR}/data
     Working directory: ${RUNTIME_DIR}
     module classpath: tis-web-start

② 命令行启动:
     cd '${RUNTIME_DIR}' && \\
     '${JAVA17_HOME}/bin/java' \\
       -cp 'tis/lib/*:${WEB_START_JAR}:${REPO_DIR}/tis-web-start/target/classes' \\
       -Dweb.root.dir='${RUNTIME_DIR}/webapps' \\
       -Ddata.dir='${RUNTIME_DIR}/data' \\
       com.qlangtech.tis.web.start.TisApp

③ 验证: curl http://127.0.0.1:${PORT}/check_health
   首次访问会进入 SysInitializeAction 初始化向导(Derby 自动建表)
====================================================
EOF
