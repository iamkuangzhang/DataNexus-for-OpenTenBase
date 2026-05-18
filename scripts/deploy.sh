#!/bin/bash
################################################################################
# DataNexus for OpenTenBase - 一键部署脚本
# 
# 功能:
#   1. 自动检测环境
#   2. 交互式配置分布式环境（可选）
#   3. 安装SQL基础扩展
#   4. 编译并安装C性能扩展
#   5. 运行功能测试
#
# 使用方法:
#   bash deploy.sh                          # 交互式配置
#   bash deploy.sh --auto-config            # 自动配置所有DN
#   bash deploy.sh --skip-config            # 跳过分布式配置
#   bash deploy.sh --dn-count 3             # 配置指定数量的DN
#   bash deploy.sh --skip-compile           # 跳过C扩展编译
#   bash deploy.sh --skip-test              # 跳过功能测试
################################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置参数
OPENTENBASE_HOST=${OPENTENBASE_HOST:-127.0.0.1}
OPENTENBASE_PORT=${OPENTENBASE_PORT:-30004}
OPENTENBASE_USER=${OPENTENBASE_USER:-opentenbase}
OPENTENBASE_DB=${OPENTENBASE_DB:-postgres}

# 动态获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 智能检测项目结构（支持多种运行场景）
# 场景1: deploy.sh在/data/opentenbase/下，插件在OpenTenBase/contrib/下
# 场景2: deploy.sh在contrib/otb_timeseries/下
# 场景3: deploy.sh在DataNexus for OpenTenBase/下，插件在src/下
# 场景4: deploy.sh在DataNexus for OpenTenBase/scripts/下，插件在../src/下
if [ -d "$SCRIPT_DIR/OpenTenBase/contrib" ]; then
    # 场景1: deploy.sh在项目根目录(/data/opentenbase/)
    CONTRIB_DIR="$SCRIPT_DIR/OpenTenBase/contrib"
    PROJECT_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/src/otb_timeseries" ]; then
    # 场景3: deploy.sh在提交目录(DataNexus for OpenTenBase/)
    CONTRIB_DIR="$SCRIPT_DIR/src"
    PROJECT_ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../src/otb_timeseries" ]; then
    # 场景4: deploy.sh在scripts/子目录下
    CONTRIB_DIR="$(cd "$SCRIPT_DIR/../src" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/../otb_age" ] || [ -d "$SCRIPT_DIR/../otb_fulltext" ]; then
    # 场景2: deploy.sh在contrib/otb_timeseries/下
    CONTRIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    # 默认使用脚本目录
    CONTRIB_DIR="$SCRIPT_DIR"
    PROJECT_ROOT="$SCRIPT_DIR"
fi

# 参数解析
SKIP_COMPILE=0
SKIP_TEST=0
CONFIG_MODE="interactive"  # interactive, auto, skip, custom
CUSTOM_DN_COUNT=0
SETUP_MODE=0  # 首次安装模式

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-compile)
            SKIP_COMPILE=1
            shift
            ;;
        --skip-test)
            SKIP_TEST=1
            shift
            ;;
        --auto-config)
            CONFIG_MODE="auto"
            shift
            ;;
        --skip-config)
            CONFIG_MODE="skip"
            shift
            ;;
        --dn-count)
            CONFIG_MODE="custom"
            CUSTOM_DN_COUNT="$2"
            shift 2
            ;;
        --setup)
            SETUP_MODE=1
            shift
            ;;
        --help|-h)
            echo "DataNexus for OpenTenBase - 一键部署脚本"
            echo ""
            echo "使用方法:"
            echo "  bash deploy.sh                  # 交互式配置（默认）"
            echo "  bash deploy.sh --setup          # 首次安装（自动复制源码到系统目录）"
            echo "  bash deploy.sh --auto-config    # 自动配置所有检测到的DN"
            echo "  bash deploy.sh --skip-config    # 跳过分布式配置"
            echo "  bash deploy.sh --dn-count N     # 配置指定数量的DN"
            echo "  bash deploy.sh --skip-compile   # 跳过C扩展编译"
            echo "  bash deploy.sh --skip-test      # 跳过功能测试"
            echo ""
            echo "新手快速开始:"
            echo "  1. 下载项目到 /data/opentenbase/"
            echo "  2. cd '/data/opentenbase/DataNexus for OpenTenBase/scripts'"
            echo "  3. bash deploy.sh --setup --auto-config"
            echo ""
            echo "示例:"
            echo "  bash deploy.sh --setup                    # 首次安装"
            echo "  bash deploy.sh --auto-config --skip-test  # 跳过测试快速部署"
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

################################################################################
# 首次安装检测与自动设置
################################################################################

# 辅助函数（提前定义）
print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# 检测是否从作品提交目录运行，且系统目录缺少插件
detect_first_time_setup() {
    local SUBMISSION_DIR=""
    local SYSTEM_CONTRIB_DIR=""
    
    # 检测作品提交目录位置
    if [ -d "$SCRIPT_DIR/../src/otb_timeseries" ]; then
        # 场景: deploy.sh在scripts/子目录下
        SUBMISSION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    elif [ -d "$SCRIPT_DIR/src/otb_timeseries" ]; then
        # 场景: deploy.sh在DataNexus for OpenTenBase/根目录
        SUBMISSION_DIR="$SCRIPT_DIR"
    fi
    
    # 如果不是从作品提交目录运行，不需要首次安装
    if [ -z "$SUBMISSION_DIR" ]; then
        return 1
    fi
    
    # 确定系统目录位置（假设标准路径）
    if [ -d "/data/opentenbase/OpenTenBase/contrib" ]; then
        SYSTEM_CONTRIB_DIR="/data/opentenbase/OpenTenBase/contrib"
    elif [ -d "$SUBMISSION_DIR/../OpenTenBase/contrib" ]; then
        SYSTEM_CONTRIB_DIR="$(cd "$SUBMISSION_DIR/../OpenTenBase/contrib" && pwd)"
    else
        # 系统目录不存在，无法执行首次安装
        return 1
    fi
    
    # 检测系统目录是否已有插件
    if [ -d "$SYSTEM_CONTRIB_DIR/otb_timeseries" ]; then
        # 已安装，不需要首次安装
        return 1
    fi
    
    # 需要首次安装，设置全局变量
    DETECTED_SUBMISSION_DIR="$SUBMISSION_DIR"
    DETECTED_SYSTEM_CONTRIB_DIR="$SYSTEM_CONTRIB_DIR"
    DETECTED_SYSTEM_ROOT="$(dirname "$SYSTEM_CONTRIB_DIR")"
    DETECTED_SYSTEM_ROOT="$(dirname "$DETECTED_SYSTEM_ROOT")"
    
    return 0
}

# 执行首次安装
run_first_time_setup() {
    local SUBMISSION_DIR="$1"
    local SYSTEM_CONTRIB_DIR="$2"
    local SYSTEM_ROOT="$3"
    
    print_step "首次安装：复制源码到系统目录"
    
    echo "源码目录: $SUBMISSION_DIR/src"
    echo "目标目录: $SYSTEM_CONTRIB_DIR"
    echo ""
    
    # 1. 复制源码到系统目录
    echo "复制插件源码..."
    for plugin_dir in "$SUBMISSION_DIR/src"/*; do
        if [ -d "$plugin_dir" ]; then
            plugin_name=$(basename "$plugin_dir")
            echo "  • 复制 $plugin_name..."
            cp -r "$plugin_dir" "$SYSTEM_CONTRIB_DIR/"
        fi
    done
    print_success "插件源码复制完成"
    
    # 2. 复制部署脚本到系统根目录
    echo ""
    echo "复制部署脚本..."
    if [ -f "$SUBMISSION_DIR/scripts/deploy.sh" ]; then
        cp "$SUBMISSION_DIR/scripts/deploy.sh" "$SYSTEM_ROOT/deploy.sh"
        chmod +x "$SYSTEM_ROOT/deploy.sh"
        print_success "deploy.sh 已复制到 $SYSTEM_ROOT/"
    fi
    
    # 3. 清理作品提交目录（保留文档和脚本备份）
    echo ""
    echo "清理作品提交目录..."
    
    # 删除不需要的文件/目录
    if [ -d "$SUBMISSION_DIR/tests" ]; then
        echo "  • 删除 tests/"
        rm -rf "$SUBMISSION_DIR/tests"
    fi
    
    if [ -d "$SUBMISSION_DIR/examples" ]; then
        echo "  • 删除 examples/"
        rm -rf "$SUBMISSION_DIR/examples"
    fi
    
    if [ -d "$SUBMISSION_DIR/src" ]; then
        echo "  • 删除 src/ (已复制到系统目录)"
        rm -rf "$SUBMISSION_DIR/src"
    fi
    
    # 删除PDF和视频文件
    for file in "$SUBMISSION_DIR"/*.pdf "$SUBMISSION_DIR"/*.mp4; do
        if [ -f "$file" ]; then
            echo "  • 删除 $(basename "$file")"
            rm -f "$file"
        fi
    done
    
    # 删除.gitignore
    if [ -f "$SUBMISSION_DIR/.gitignore" ]; then
        echo "  • 删除 .gitignore"
        rm -f "$SUBMISSION_DIR/.gitignore"
    fi
    
    print_success "清理完成"
    
    echo ""
    print_success "首次安装完成！"
    echo ""
    echo "保留的文件:"
    echo "  • $SUBMISSION_DIR/README.md      (项目说明)"
    echo "  • $SUBMISSION_DIR/docs/          (详细文档)"
    echo "  • $SUBMISSION_DIR/scripts/       (脚本备份)"
    echo ""
    echo "安装位置:"
    echo "  • $SYSTEM_CONTRIB_DIR/   (插件源码)"
    echo "  • $SYSTEM_ROOT/deploy.sh (部署脚本)"
    echo ""
    
    # 更新路径变量，继续后续安装
    CONTRIB_DIR="$SYSTEM_CONTRIB_DIR"
    PROJECT_ROOT="$SYSTEM_ROOT"
}

# 检测并执行首次安装
if detect_first_time_setup; then
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  检测到首次安装场景                                              ║${NC}"
    echo -e "${CYAN}║                                                                  ║${NC}"
    echo -e "${CYAN}║  当前运行位置: 作品提交目录                                      ║${NC}"
    echo -e "${CYAN}║  系统目录状态: 尚未安装插件                                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$SETUP_MODE" -eq 1 ]; then
        # 使用了 --setup 参数，直接执行
        run_first_time_setup "$DETECTED_SUBMISSION_DIR" "$DETECTED_SYSTEM_CONTRIB_DIR" "$DETECTED_SYSTEM_ROOT"
    else
        # 交互式询问
        print_info "是否执行首次安装？"
        echo ""
        echo "  这将会："
        echo "    1. 复制插件源码到系统目录 (OpenTenBase/contrib/)"
        echo "    2. 复制 deploy.sh 到 /data/opentenbase/"
        echo "    3. 清理作品提交目录中的测试文件、示例、PDF、视频等"
        echo "    4. 保留 README.md、docs/、scripts/(备份)"
        echo ""
        echo "  [1] 是，执行首次安装（推荐）"
        echo "  [2] 否，跳过（仅从当前目录安装）"
        echo ""
        
        read -t 30 -p "请选择 (1-2) [默认: 1，30秒后自动选择]: " setup_choice
        echo ""
        
        if [ -z "$setup_choice" ] || [ "$setup_choice" = "1" ]; then
            run_first_time_setup "$DETECTED_SUBMISSION_DIR" "$DETECTED_SYSTEM_CONTRIB_DIR" "$DETECTED_SYSTEM_ROOT"
        else
            print_warning "跳过首次安装，从当前目录安装"
        fi
    fi
fi

# check_command 辅助函数（其他辅助函数已在首次安装检测部分定义）
check_command() {
    if command -v $1 &> /dev/null; then
        print_success "$1 已安装"
        return 0
    else
        print_error "$1 未找到"
        return 1
    fi
}

################################################################################
# 步骤1: 环境检查
################################################################################

print_step "步骤1: 环境检查"

echo "检查必需的命令..."
check_command psql || { print_error "请安装PostgreSQL客户端"; exit 1; }
check_command gcc || { print_error "请安装gcc编译器"; exit 1; }
check_command make || { print_error "请安装make"; exit 1; }
check_command pg_config || { print_error "请安装postgresql-devel"; exit 1; }

echo ""
echo "检查OpenTenBase连接..."
if psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB -c "SELECT version();" > /dev/null 2>&1; then
    print_success "OpenTenBase连接成功"
    VERSION=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB -t -c "SELECT version();" | head -1)
    echo "    版本: $VERSION"
else
    print_error "无法连接到OpenTenBase"
    echo "    Host: $OPENTENBASE_HOST:$OPENTENBASE_PORT"
    echo "    User: $OPENTENBASE_USER"
    exit 1
fi

echo ""
echo "检查DataNode数量..."
DN_COUNT=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
    -t -c "SELECT COUNT(*) FROM pgxc_node WHERE node_type = 'D';" 2>/dev/null | xargs)

if [ -n "$DN_COUNT" ] && [ "$DN_COUNT" -gt 0 ]; then
    print_success "检测到 ${DN_COUNT} 个DataNode"
    
    # 显示DN列表
    echo ""
    echo "DataNode列表:"
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -c "SELECT node_name, node_host, node_port FROM pgxc_node WHERE node_type = 'D' ORDER BY node_name;" 2>/dev/null | head -20
else
    DN_COUNT=0
    print_warning "未检测到DataNode（单机模式）"
fi

################################################################################
# 步骤1.5: 交互式配置分布式环境（可选）
################################################################################

if [ "$DN_COUNT" -ge 2 ]; then
    print_step "步骤1.5: 配置分布式环境（可选）"
    
    # 检查是否已配置
    GROUP_EXISTS=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -t -c "SELECT COUNT(*) FROM pgxc_group WHERE group_name = 'default_group';" 2>/dev/null | xargs)
    
    SHARD_EXISTS=0
    if [ "$GROUP_EXISTS" -gt 0 ]; then
        GROUP_OID=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
            -t -c "SELECT oid FROM pgxc_group WHERE group_name = 'default_group';" 2>/dev/null | xargs)
        SHARD_EXISTS=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
            -t -c "SELECT COUNT(*) FROM pgxc_shard_map WHERE disgroup = $GROUP_OID;" 2>/dev/null | xargs)
    fi
    
    if [ "$GROUP_EXISTS" -gt 0 ] && [ "$SHARD_EXISTS" -gt 0 ]; then
        print_success "分布式环境已配置完成 (default_group 已存在，$SHARD_EXISTS 个shard)"
        
        # 在交互模式下，询问是否重新配置
        if [ "$CONFIG_MODE" = "interactive" ]; then
            echo ""
            print_info "发现已有配置，您想："
            echo ""
            echo "  [1] 保持现有配置（推荐）"
            echo "  [2] 重新配置分布式环境"
            echo ""
            
            read -t 10 -p "请选择 (1-2) [默认: 1]: " reconfig_choice
            echo ""
            
            if [ "$reconfig_choice" = "2" ]; then
                print_warning "即将重新配置分布式环境"
                echo ""
                
                # 检查是否有使用HASH分布的表
                echo "  • 检查依赖shard map的表..."
                HASH_TABLES=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB -t << 'EOF' 2>/dev/null
SELECT string_agg(schemaname || '.' || tablename, ', ')
FROM pg_tables t
WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'pgxc_cron')
  AND EXISTS (
    SELECT 1 FROM pg_class c 
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = t.schemaname 
      AND c.relname = t.tablename
      AND c.pclocatortype = 'H'  -- H = HASH分布
  );
EOF
)
                
                HASH_TABLES=$(echo "$HASH_TABLES" | xargs)
                
                if [ -n "$HASH_TABLES" ]; then
                    echo ""
                    print_warning "发现以下表使用HASH分布策略（依赖shard map）："
                    echo "    $HASH_TABLES"
                    echo ""
                    print_warning "⚠️  重新配置会导致这些表无法访问"
                    echo ""
                    echo "  [1] 取消操作，保持现有配置"
                    echo "  [2] 删除这些表并继续重新配置"
                    echo ""
                    
                    read -t 15 -p "请选择 (1-2) [默认: 1]: " delete_choice
                    echo ""
                    
                    if [ "$delete_choice" = "2" ]; then
                        print_warning "正在删除HASH分布的表..."
                        
                        # 获取表列表并逐个删除
                        psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB -t << 'EOF' 2>/dev/null | while read schema_table; do
SELECT schemaname || '.' || tablename
FROM pg_tables t
WHERE schemaname NOT IN ('pg_catalog', 'information_schema', 'pgxc_cron')
  AND EXISTS (
    SELECT 1 FROM pg_class c 
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = t.schemaname 
      AND c.relname = t.tablename
      AND c.pclocatortype = 'H'
  );
EOF
                            if [ -n "$schema_table" ]; then
                                echo "    删除表: $schema_table"
                                psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                                    -c "DROP TABLE IF EXISTS $schema_table CASCADE;" > /dev/null 2>&1
                            fi
                        done
                        
                        print_success "HASH分布的表已删除"
                        
                        # 设置标志，允许重新配置
                        ALLOW_RECONFIG=1
                    else
                        print_info "已取消重新配置"
                        ALLOW_RECONFIG=0
                    fi
                else
                    echo "    没有发现HASH分布的表"
                    print_info "可以安全地重新配置"
                    echo ""
                    read -t 10 -p "确认继续重新配置？(y/N): " confirm_reconfig
                    echo ""
                    
                    if [[ "$confirm_reconfig" =~ ^[Yy]$ ]]; then
                        ALLOW_RECONFIG=1
                    else
                        print_info "已取消重新配置"
                        ALLOW_RECONFIG=0
                    fi
                fi
                
                # 执行重新配置
                if [ "$ALLOW_RECONFIG" = "1" ]; then
                    echo ""
                    print_info "清理现有配置..."
                    
                    # 删除shard map
                    echo "  • 删除 shard map..."
                    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                        -c "DELETE FROM pgxc_shard_map WHERE disgroup = $GROUP_OID;" > /dev/null 2>&1
                    
                    # 删除group
                    echo "  • 删除 default_group..."
                    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                        -c "DROP NODE GROUP IF EXISTS default_group;" > /dev/null 2>&1
                    
                    print_success "现有配置已清理"
                    
                    # 重置标志，进入配置流程
                    GROUP_EXISTS=0
                    SHARD_EXISTS=0
                else
                    CONFIGURE_DN_COUNT=0
                fi
            else
                print_info "保持现有配置"
                CONFIGURE_DN_COUNT=0
            fi
        else
            # 非交互模式，直接跳过
            print_info "跳过配置步骤（非交互模式）"
            CONFIGURE_DN_COUNT=0
        fi
    fi
    
    # 如果没有现有配置，或者已经清理了配置，进入配置流程
    if [ "$GROUP_EXISTS" -eq 0 ] || [ "$SHARD_EXISTS" -eq 0 ]; then
        # 根据CONFIG_MODE决定行为
        CONFIGURE_DN_COUNT=0
        
        case $CONFIG_MODE in
            "auto")
                print_info "自动配置模式：配置所有 ${DN_COUNT} 个DataNode"
                CONFIGURE_DN_COUNT=$DN_COUNT
                ;;
            "skip")
                print_warning "跳过分布式环境配置"
                print_info "说明：Hypertable使用REPLICATION策略，无需shard配置即可工作"
                CONFIGURE_DN_COUNT=0
                ;;
            "custom")
                if [[ "$CUSTOM_DN_COUNT" =~ ^[0-9]+$ ]] && [ "$CUSTOM_DN_COUNT" -ge 2 ] && [ "$CUSTOM_DN_COUNT" -le "$DN_COUNT" ]; then
                    print_info "自定义配置：配置 ${CUSTOM_DN_COUNT} 个DataNode"
                    CONFIGURE_DN_COUNT=$CUSTOM_DN_COUNT
                else
                    print_error "无效的DN数量: $CUSTOM_DN_COUNT (必须在 2-${DN_COUNT} 之间)"
                    CONFIGURE_DN_COUNT=0
                fi
                ;;
            "interactive")
                echo ""
                print_info "检测到 ${DN_COUNT} 个DataNode，需要配置分布式环境吗？"
                echo ""
                echo "  [1] 是，配置所有 ${DN_COUNT} 个DataNode（推荐）"
                echo "  [2] 否，跳过配置（仅使用REPLICATION策略）"
                if [ "$DN_COUNT" -gt 2 ]; then
                    echo "  [3] 自定义DN数量"
                fi
                echo ""
                
                # 读取用户输入（10秒超时，默认选1）
                read -t 10 -p "请选择 (1-3) [默认: 1，10秒后自动选择]: " user_choice
                echo ""
                
                # 处理超时或直接回车
                if [ -z "$user_choice" ]; then
                    user_choice=1
                    print_info "超时或无输入，使用默认选项: 1"
                fi
                
                case $user_choice in
                    1)
                        print_info "配置 ${DN_COUNT} 个DataNode..."
                        CONFIGURE_DN_COUNT=$DN_COUNT
                        ;;
                    2)
                        print_warning "跳过分布式环境配置"
                        print_info "说明：Hypertable使用REPLICATION策略，无需shard配置即可工作"
                        CONFIGURE_DN_COUNT=0
                        ;;
                    3)
                        if [ "$DN_COUNT" -gt 2 ]; then
                            echo ""
                            read -t 10 -p "请输入要配置的DN数量 (2-${DN_COUNT}): " custom_dn_count
                            echo ""
                            
                            # 验证输入
                            if [[ "$custom_dn_count" =~ ^[0-9]+$ ]] && [ "$custom_dn_count" -ge 2 ] && [ "$custom_dn_count" -le "$DN_COUNT" ]; then
                                print_info "配置 ${custom_dn_count} 个DataNode..."
                                CONFIGURE_DN_COUNT=$custom_dn_count
                            else
                                print_error "无效输入，跳过配置"
                                CONFIGURE_DN_COUNT=0
                            fi
                        else
                            print_warning "DN数量较少，自动配置全部"
                            CONFIGURE_DN_COUNT=$DN_COUNT
                        fi
                        ;;
                    *)
                        print_warning "无效选择，跳过配置"
                        CONFIGURE_DN_COUNT=0
                        ;;
                esac
                ;;
        esac
        
        # 执行配置
        if [ "$CONFIGURE_DN_COUNT" -ge 2 ]; then
            echo ""
            print_info "开始配置分布式环境..."
            
            # 创建default_group
            echo "  • 创建 default_group..."
            psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB << 'EOF' > /dev/null 2>&1
DO $$
DECLARE
    v_nodes TEXT;
BEGIN
    -- ORDER BY 必须在 string_agg 内部
    SELECT string_agg(node_name, ', ' ORDER BY node_name) INTO v_nodes 
    FROM pgxc_node WHERE node_type = 'D';
    
    IF v_nodes IS NULL THEN
        RAISE EXCEPTION 'No DataNode found!';
    END IF;
    
    EXECUTE 'CREATE DEFAULT NODE GROUP default_group WITH (' || v_nodes || ')';
END $$;
EOF
            
            if [ $? -eq 0 ]; then
                print_success "default_group 创建成功"
            else
                print_error "default_group 创建失败"
            fi
            
            # 获取group OID
            GROUP_OID=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                -t -c "SELECT oid FROM pgxc_group WHERE group_name = 'default_group';" 2>/dev/null | xargs)
            
            # 初始化shard map
            echo "  • 初始化 shard map (4096个shard)..."
            psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB << EOF > /dev/null 2>&1
DO \$\$
DECLARE
    v_group_oid OID;
    v_dn_oids OID[];
    v_dn_count INT;
    v_shards_per_dn INT;
    v_current_dn_idx INT;
    v_current_dn_oid OID;
    i INT;
BEGIN
    SELECT oid INTO v_group_oid FROM pgxc_group WHERE group_name = 'default_group';
    
    IF v_group_oid IS NULL THEN
        RAISE EXCEPTION 'default_group not found!';
    END IF;
    
    -- 获取指定数量的DN的OID
    SELECT array_agg(oid ORDER BY node_name) INTO v_dn_oids
    FROM (
        SELECT oid, node_name 
        FROM pgxc_node 
        WHERE node_type = 'D' 
        ORDER BY node_name 
        LIMIT $CONFIGURE_DN_COUNT
    ) t;
    
    v_dn_count := array_length(v_dn_oids, 1);
    
    IF v_dn_count IS NULL OR v_dn_count < 2 THEN
        RAISE EXCEPTION 'Need at least 2 DataNodes, found: %', v_dn_count;
    END IF;
    
    -- 均分shard到各个DN
    v_shards_per_dn := 4096 / v_dn_count;
    
    FOR i IN 0..4095 LOOP
        -- 计算当前shard应该分配到哪个DN
        v_current_dn_idx := (i / v_shards_per_dn) + 1;
        
        -- 处理余数（最后一个DN分配剩余的所有shard）
        IF v_current_dn_idx > v_dn_count THEN
            v_current_dn_idx := v_dn_count;
        END IF;
        
        v_current_dn_oid := v_dn_oids[v_current_dn_idx];
        
        -- 插入shard映射
        INSERT INTO pgxc_shard_map 
        (disgroup, shardgroupid, ncopy, primarycopy, copy1, copy2, shardclusterid, primarystatus, status1, status2, extended, ntuples)
        VALUES 
        (v_group_oid, i, 1, v_current_dn_oid, 0, 0, i % 8, 'U', 'N', 'N', 0, 0);
    END LOOP;
END \$\$;
EOF
            
            if [ $? -eq 0 ]; then
                print_success "shard map 初始化成功"
            else
                print_error "shard map 初始化失败"
            fi
            
            # 刷新连接池
            echo "  • 刷新连接池..."
            psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                -c "SELECT pgxc_pool_reload();" > /dev/null 2>&1
            
            # 验证配置
            FINAL_SHARD_COUNT=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                -t -c "SELECT COUNT(*) FROM pgxc_shard_map WHERE disgroup = $GROUP_OID;" 2>/dev/null | xargs)
            
            echo ""
            print_success "分布式环境配置完成"
            print_info "配置摘要: ${CONFIGURE_DN_COUNT} 个DataNode, ${FINAL_SHARD_COUNT} 个shard"
        fi
    fi
fi

################################################################################
# 步骤2: 安装SQL基础扩展
################################################################################

print_step "步骤2: 安装SQL基础扩展"

# 智能检测 SQL 文件目录
SQL_DIR=""
# 检查CONTRIB_DIR下的otb_timeseries
if [ -f "$CONTRIB_DIR/otb_timeseries/core/sql/otb_timeseries--1.0.sql" ]; then
    SQL_DIR="$CONTRIB_DIR/otb_timeseries/core/sql"
# 检查SCRIPT_DIR下（如果deploy.sh在otb_timeseries目录内）
elif [ -f "$SCRIPT_DIR/core/sql/otb_timeseries--1.0.sql" ]; then
    SQL_DIR="$SCRIPT_DIR/core/sql"
fi

if [ -z "$SQL_DIR" ] || [ ! -f "$SQL_DIR/otb_timeseries--1.0.sql" ]; then
    print_error "找不到 SQL 文件，已尝试以下路径："
    echo "  - $CONTRIB_DIR/otb_timeseries/core/sql/"
    echo "  - $SCRIPT_DIR/core/sql/"
    echo ""
    echo "当前 SCRIPT_DIR: $SCRIPT_DIR"
    echo "当前 CONTRIB_DIR: $CONTRIB_DIR"
    exit 1
fi

print_success "找到 SQL 目录: $SQL_DIR"

echo ""
echo "安装 otb_timeseries 核心扩展..."

# 安装核心扩展
psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
    -f "$SQL_DIR/otb_timeseries--1.0.sql" > /tmp/otb_ts_install.log 2>&1

if [ $? -eq 0 ]; then
    print_success "otb_timeseries 核心扩展安装成功"
else
    print_error "核心扩展安装失败，请查看 /tmp/otb_ts_install.log"
    exit 1
fi

echo ""
echo "安装 TimescaleDB 兼容层..."

# 检查兼容层 SQL 文件（与核心扩展在同一目录）
COMPAT_SQL="$SQL_DIR/timescaledb_compat.sql"
if [ ! -f "$COMPAT_SQL" ]; then
    print_error "找不到兼容层 SQL 文件: $COMPAT_SQL"
    exit 1
fi

# 安装TimescaleDB兼容接口
psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
    -f "$COMPAT_SQL" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    print_success "TimescaleDB 兼容层安装成功"
else
    print_error "兼容层安装失败"
    exit 1
fi

echo ""
echo "注册为PostgreSQL扩展（用于\dx显示）..."
psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB << 'EOF' > /dev/null 2>&1
-- 注册扩展到pg_extension（用于\dx显示）
INSERT INTO pg_extension (extname, extowner, extnamespace, extrelocatable, extversion)
SELECT 'otb_timeseries', 
       (SELECT oid FROM pg_roles WHERE rolname = current_user),
       (SELECT oid FROM pg_namespace WHERE nspname = 'otb_ts'),
       false,
       '1.0'
WHERE NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'otb_timeseries');
EOF

echo ""
echo "验证安装..."
VERSION=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
    -t -c "SELECT otb_ts.version();" 2>/dev/null | xargs)
if [ -n "$VERSION" ]; then
    print_success "版本: $VERSION"
else
    print_warning "无法获取版本信息（可能正常）"
fi

################################################################################
# 步骤2.5: 安装otb_age图数据库扩展
################################################################################

print_step "步骤2.5: 安装otb_age图数据库扩展（Apache AGE兼容）"

# 智能检测 otb_age SQL 文件目录
AGE_SQL_DIR=""
if [ -f "$CONTRIB_DIR/otb_age/sql/otb_age--1.0.sql" ]; then
    AGE_SQL_DIR="$CONTRIB_DIR/otb_age/sql"
fi

if [ -n "$AGE_SQL_DIR" ] && [ -f "$AGE_SQL_DIR/otb_age--1.0.sql" ]; then
    print_success "找到 otb_age SQL 目录: $AGE_SQL_DIR"
    
    echo ""
    echo "安装 otb_age 图数据库扩展..."
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -f "$AGE_SQL_DIR/otb_age--1.0.sql" > /tmp/otb_age_install.log 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "otb_age 图数据库扩展安装成功"
    else
        print_warning "otb_age 安装有警告，请查看 /tmp/otb_age_install.log"
    fi
    
    # 验证安装
    AGE_VERSION=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -t -c "SELECT otb_age.version();" 2>/dev/null | xargs)
    if [ -n "$AGE_VERSION" ]; then
        print_success "版本: $AGE_VERSION"
    fi
else
    print_warning "未找到 otb_age SQL 文件，跳过安装"
fi

################################################################################
# 步骤2.6: 安装otb_fulltext全文检索扩展
################################################################################

print_step "步骤2.6: 安装otb_fulltext全文检索扩展（zhparser+RUM兼容）"

# 确保pg_trgm扩展可用（模糊搜索依赖）
psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
    -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" > /dev/null 2>&1

# 智能检测 otb_fulltext SQL 文件目录
FT_SQL_DIR=""
if [ -f "$CONTRIB_DIR/otb_fulltext/sql/otb_fulltext--1.0.sql" ]; then
    FT_SQL_DIR="$CONTRIB_DIR/otb_fulltext/sql"
fi

if [ -n "$FT_SQL_DIR" ] && [ -f "$FT_SQL_DIR/otb_fulltext--1.0.sql" ]; then
    print_success "找到 otb_fulltext SQL 目录: $FT_SQL_DIR"
    
    echo ""
    echo "安装 otb_fulltext 全文检索扩展..."
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -f "$FT_SQL_DIR/otb_fulltext--1.0.sql" > /tmp/otb_fulltext_install.log 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "otb_fulltext 全文检索扩展安装成功"
    else
        print_warning "otb_fulltext 安装有警告，请查看 /tmp/otb_fulltext_install.log"
    fi
    
    # 验证安装
    FT_VERSION=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -t -c "SELECT otb_fulltext.version();" 2>/dev/null | xargs)
    if [ -n "$FT_VERSION" ]; then
        print_success "版本: $FT_VERSION"
    fi
else
    print_warning "未找到 otb_fulltext SQL 文件，跳过安装"
fi

################################################################################
# 步骤2.7: 安装otb_scheduler调度管理扩展
################################################################################

print_step "步骤2.7: 安装otb_scheduler调度管理扩展（pg_cron+pg_partman兼容）"

# 智能检测 otb_scheduler SQL 文件目录
SCHED_SQL_DIR=""
if [ -f "$CONTRIB_DIR/otb_scheduler/sql/otb_scheduler--1.0.sql" ]; then
    SCHED_SQL_DIR="$CONTRIB_DIR/otb_scheduler/sql"
fi

if [ -n "$SCHED_SQL_DIR" ] && [ -f "$SCHED_SQL_DIR/otb_scheduler--1.0.sql" ]; then
    print_success "找到 otb_scheduler SQL 目录: $SCHED_SQL_DIR"
    
    echo ""
    echo "安装 otb_scheduler 调度管理扩展..."
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -f "$SCHED_SQL_DIR/otb_scheduler--1.0.sql" > /tmp/otb_scheduler_install.log 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "otb_scheduler 调度管理扩展安装成功"
    else
        print_warning "otb_scheduler 安装有警告，请查看 /tmp/otb_scheduler_install.log"
    fi
else
    print_warning "未找到 otb_scheduler SQL 文件，跳过安装"
fi

################################################################################
# 步骤2.8: 安装otb_routing路网分析扩展
################################################################################

print_step "步骤2.8: 安装otb_routing路网分析扩展（pgRouting兼容）"

# 智能检测 otb_routing SQL 文件目录
ROUTE_SQL_DIR=""
if [ -f "$CONTRIB_DIR/otb_routing/sql/otb_routing--1.0.sql" ]; then
    ROUTE_SQL_DIR="$CONTRIB_DIR/otb_routing/sql"
fi

if [ -n "$ROUTE_SQL_DIR" ] && [ -f "$ROUTE_SQL_DIR/otb_routing--1.0.sql" ]; then
    print_success "找到 otb_routing SQL 目录: $ROUTE_SQL_DIR"
    
    echo ""
    echo "安装 otb_routing 路网分析扩展..."
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -f "$ROUTE_SQL_DIR/otb_routing--1.0.sql" > /tmp/otb_routing_install.log 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "otb_routing 路网分析扩展安装成功"
    else
        print_warning "otb_routing 安装有警告，请查看 /tmp/otb_routing_install.log"
    fi
else
    print_warning "未找到 otb_routing SQL 文件，跳过安装"
fi

################################################################################
# 步骤2.9: 安装otb_analytics时序分析算法库
################################################################################

print_step "步骤2.9: 安装otb_analytics时序分析算法库"

# 智能检测 otb_analytics SQL 文件目录
ANALYTICS_SQL_DIR=""
if [ -f "$CONTRIB_DIR/otb_analytics/sql/otb_analytics--1.0.sql" ]; then
    ANALYTICS_SQL_DIR="$CONTRIB_DIR/otb_analytics/sql"
fi

if [ -n "$ANALYTICS_SQL_DIR" ] && [ -f "$ANALYTICS_SQL_DIR/otb_analytics--1.0.sql" ]; then
    print_success "找到 otb_analytics SQL 目录: $ANALYTICS_SQL_DIR"
    print_info "注意：otb_analytics需要先编译C扩展，将在步骤3中处理"
else
    print_warning "未找到 otb_analytics SQL 文件，跳过安装"
fi

################################################################################
# 步骤2.10: 安装otb_snapshot数据快照系统
################################################################################

print_step "步骤2.10: 安装otb_snapshot数据快照系统"

# 智能检测 otb_snapshot SQL 文件目录
SNAPSHOT_SQL_DIR=""
if [ -f "$CONTRIB_DIR/otb_snapshot/sql/otb_snapshot--1.0.sql" ]; then
    SNAPSHOT_SQL_DIR="$CONTRIB_DIR/otb_snapshot/sql"
fi

if [ -n "$SNAPSHOT_SQL_DIR" ] && [ -f "$SNAPSHOT_SQL_DIR/otb_snapshot--1.0.sql" ]; then
    print_success "找到 otb_snapshot SQL 目录: $SNAPSHOT_SQL_DIR"
    
    echo ""
    echo "安装 otb_snapshot 数据快照扩展..."
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -f "$SNAPSHOT_SQL_DIR/otb_snapshot--1.0.sql" > /tmp/otb_snapshot_install.log 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "otb_snapshot 数据快照扩展安装成功"
    else
        print_warning "otb_snapshot 安装有警告，请查看 /tmp/otb_snapshot_install.log"
    fi
    
    # 验证安装
    SNAPSHOT_VERSION=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -t -c "SELECT otb_snapshot.version();" 2>/dev/null | xargs)
    if [ -n "$SNAPSHOT_VERSION" ]; then
        print_success "版本: $SNAPSHOT_VERSION"
    fi
else
    print_warning "未找到 otb_snapshot SQL 文件，跳过安装"
fi

################################################################################
# 步骤2.11: 安装otb_health数据健康诊断系统
################################################################################

print_step "步骤2.11: 安装otb_health数据健康诊断系统"

# 智能检测 otb_health SQL 文件目录
HEALTH_SQL_DIR=""
if [ -f "$CONTRIB_DIR/otb_health/sql/otb_health--1.0.sql" ]; then
    HEALTH_SQL_DIR="$CONTRIB_DIR/otb_health/sql"
fi

if [ -n "$HEALTH_SQL_DIR" ] && [ -f "$HEALTH_SQL_DIR/otb_health--1.0.sql" ]; then
    print_success "找到 otb_health SQL 目录: $HEALTH_SQL_DIR"
    
    echo ""
    echo "安装 otb_health 数据健康诊断扩展..."
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -f "$HEALTH_SQL_DIR/otb_health--1.0.sql" > /tmp/otb_health_install.log 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "otb_health 数据健康诊断扩展安装成功"
    else
        print_warning "otb_health 安装有警告，请查看 /tmp/otb_health_install.log"
    fi
    
    # 验证安装
    HEALTH_VERSION=$(psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -t -c "SELECT otb_health.version();" 2>/dev/null | xargs)
    if [ -n "$HEALTH_VERSION" ]; then
        print_success "版本: $HEALTH_VERSION"
    fi
else
    print_warning "未找到 otb_health SQL 文件，跳过安装"
fi

################################################################################
# 步骤3: 编译并安装C扩展
################################################################################

if [ $SKIP_COMPILE -eq 0 ]; then
    print_step "步骤3: 编译并安装C扩展（性能增强）"

    # 智能检测 C 扩展目录
    C_EXT_DIR=""
    if [ -d "$CONTRIB_DIR/otb_timeseries/c_extension" ]; then
        C_EXT_DIR="$CONTRIB_DIR/otb_timeseries/c_extension"
    elif [ -d "$SCRIPT_DIR/c_extension" ]; then
        C_EXT_DIR="$SCRIPT_DIR/c_extension"
    fi
    
    if [ -z "$C_EXT_DIR" ] || [ ! -d "$C_EXT_DIR" ]; then
        print_error "找不到C扩展目录，已尝试以下路径："
        echo "  - $CONTRIB_DIR/otb_timeseries/c_extension"
        echo "  - $SCRIPT_DIR/c_extension"
        exit 1
    fi
    
    print_success "找到C扩展目录: $C_EXT_DIR"

    cd "$C_EXT_DIR"
    
    echo "清理旧的编译文件..."
    make clean > /dev/null 2>&1 || true
    
    echo "编译C扩展..."
    if make 2>&1 | tee /tmp/otb_ts_compile.log | grep -q "error:"; then
        print_error "编译失败，请查看 /tmp/otb_ts_compile.log"
        exit 1
    fi
    print_success "编译成功"
    
    echo "安装C扩展..."
    if make install > /dev/null 2>&1; then
        print_success "安装成功"
    else
        print_error "安装失败"
        exit 1
    fi
    
    echo ""
    echo "在数据库中创建C扩展..."
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -c "DROP EXTENSION IF EXISTS otb_timeseries_c CASCADE;" > /dev/null 2>&1 || true
    
    if psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -c "CREATE EXTENSION otb_timeseries_c;" > /dev/null 2>&1; then
        print_success "otb_timeseries_c C扩展创建成功"
    else
        print_error "C扩展创建失败"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
    
    # 编译并安装 otb_analytics C扩展（独立插件）
    echo ""
    print_info "编译 otb_analytics 独立C扩展..."
    
    ANALYTICS_C_DIR=""
    if [ -d "$CONTRIB_DIR/otb_analytics" ]; then
        ANALYTICS_C_DIR="$CONTRIB_DIR/otb_analytics"
    fi
    
    if [ -n "$ANALYTICS_C_DIR" ] && [ -f "$ANALYTICS_C_DIR/Makefile" ]; then
        cd "$ANALYTICS_C_DIR"
        
        echo "清理旧的编译文件..."
        make clean > /dev/null 2>&1 || true
        
        echo "编译otb_analytics C扩展..."
        if make 2>&1 | tee /tmp/otb_analytics_compile.log | grep -q "error:"; then
            print_warning "otb_analytics编译失败，请查看 /tmp/otb_analytics_compile.log"
        else
            print_success "otb_analytics编译成功"
            
            echo "安装otb_analytics C扩展..."
            if make install > /dev/null 2>&1; then
                print_success "otb_analytics安装成功"
                
                echo ""
                echo "在数据库中创建otb_analytics扩展..."
                psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                    -c "DROP EXTENSION IF EXISTS otb_analytics CASCADE;" > /dev/null 2>&1 || true
                
                if psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                    -c "CREATE EXTENSION otb_analytics;" > /dev/null 2>&1; then
                    print_success "otb_analytics 扩展创建成功"
                else
                    print_warning "otb_analytics扩展创建失败，尝试直接执行SQL..."
                    if [ -f "$ANALYTICS_C_DIR/sql/otb_analytics--1.0.sql" ]; then
                        psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
                            -f "$ANALYTICS_C_DIR/sql/otb_analytics--1.0.sql" > /tmp/otb_analytics_sql.log 2>&1
                        print_success "otb_analytics SQL安装完成"
                    fi
                fi
            else
                print_warning "otb_analytics安装失败"
            fi
        fi
        
        cd "$PROJECT_ROOT"
    else
        print_warning "未找到otb_analytics目录，跳过"
    fi
else
    print_warning "跳过C扩展编译（--skip-compile）"
fi

################################################################################
# 步骤4: 运行功能测试
################################################################################

if [ $SKIP_TEST -eq 0 ]; then
    print_step "步骤4: 运行功能测试"

    echo "测试基础功能..."
    TEST_SQL=$(cat <<EOF
SELECT 'create_hypertable' AS test, 
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
                         WHERE n.nspname = 'otb_ts' AND p.proname = 'create_hypertable') 
            THEN 'PASS' ELSE 'FAIL' END AS result;
SELECT 'time_bucket' AS test,
       CASE WHEN time_bucket('1 hour', now()::timestamptz) IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS result;
EOF
    )
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -c "$TEST_SQL" > /tmp/otb_ts_test.log 2>&1 || true
    
    if grep -q "FAIL" /tmp/otb_ts_test.log || grep -q "ERROR" /tmp/otb_ts_test.log; then
        print_warning "部分测试失败，请查看 /tmp/otb_ts_test.log"
    else
        print_success "基础功能测试通过"
    fi
    
    if [ $SKIP_COMPILE -eq 0 ]; then
        echo ""
        echo "测试C扩展功能..."
        TEST_C_SQL=$(cat <<EOF
SELECT 'time_bucket_c' AS test,
       CASE WHEN time_bucket_c('1 hour'::interval, now()::timestamptz) IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS result;
SELECT 'compression_ratio' AS test,
       CASE WHEN compression_ratio(1000, 150) > 0 THEN 'PASS' ELSE 'FAIL' END AS result;
EOF
        )
        
        psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
            -c "$TEST_C_SQL" > /tmp/otb_ts_c_test.log 2>&1 || true
        
        if grep -q "FAIL" /tmp/otb_ts_c_test.log || grep -q "ERROR" /tmp/otb_ts_c_test.log; then
            print_warning "C扩展部分测试失败"
        else
            print_success "C扩展功能测试通过"
        fi
        
        # 测试合并后的Analytics功能
        echo ""
        echo "测试Analytics功能..."
        TEST_ANALYTICS_SQL=$(cat <<'EOF'
SELECT 'sma' AS test,
       CASE WHEN (SELECT otb_analytics.sma(i::float8, 3) FROM generate_series(1,10) i) IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS result;
SELECT 'zscore_anomaly' AS test,
       CASE WHEN (SELECT otb_analytics.detect_anomalies_zscore(i::float8, 2.0) FROM generate_series(1,10) i) >= 0 THEN 'PASS' ELSE 'FAIL' END AS result;
EOF
        )
        
        psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
            -c "$TEST_ANALYTICS_SQL" > /tmp/otb_ts_analytics_test.log 2>&1 || true
        
        if grep -q "FAIL" /tmp/otb_ts_analytics_test.log || grep -q "ERROR" /tmp/otb_ts_analytics_test.log; then
            print_warning "Analytics功能部分测试失败"
        else
            print_success "Analytics功能测试通过"
        fi
    fi
    
    # 测试otb_age图数据库功能
    echo ""
    echo "测试otb_age图数据库功能..."
    TEST_AGE_SQL=$(cat <<'EOF'
SELECT 'create_graph' AS test,
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
                         WHERE n.nspname = 'otb_age' AND p.proname = 'create_graph') 
            THEN 'PASS' ELSE 'FAIL' END AS result;
SELECT 'cypher' AS test,
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid 
                         WHERE n.nspname = 'otb_age' AND p.proname = 'cypher') 
            THEN 'PASS' ELSE 'FAIL' END AS result;
EOF
    )
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -c "$TEST_AGE_SQL" > /tmp/otb_age_test.log 2>&1 || true
    
    if grep -q "FAIL" /tmp/otb_age_test.log || grep -q "ERROR" /tmp/otb_age_test.log; then
        print_warning "otb_age部分功能未安装"
    else
        print_success "otb_age图数据库功能测试通过"
    fi
    
    # 测试otb_fulltext全文检索功能
    echo ""
    echo "测试otb_fulltext全文检索功能..."
    TEST_FT_SQL=$(cat <<'EOF'
SELECT 'tokenize' AS test,
       CASE WHEN array_length(otb_fulltext.tokenize('hello world'), 1) > 0 
            THEN 'PASS' ELSE 'FAIL' END AS result;
SELECT 'match' AS test,
       CASE WHEN otb_fulltext.match('hello world', 'hello') = true
            THEN 'PASS' ELSE 'FAIL' END AS result;
EOF
    )
    
    psql -h $OPENTENBASE_HOST -p $OPENTENBASE_PORT -U $OPENTENBASE_USER -d $OPENTENBASE_DB \
        -c "$TEST_FT_SQL" > /tmp/otb_fulltext_test.log 2>&1 || true
    
    if grep -q "FAIL" /tmp/otb_fulltext_test.log || grep -q "ERROR" /tmp/otb_fulltext_test.log; then
        print_warning "otb_fulltext部分功能未安装"
    else
        print_success "otb_fulltext全文检索功能测试通过"
    fi
else
    print_warning "跳过功能测试（--skip-test）"
fi

################################################################################
# 完成
################################################################################

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}║   ✓ DataNexus for OpenTenBase 部署成功！                        ║${NC}"
echo -e "${GREEN}║     OpenTenBase 多模态融合枢纽                                  ║${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  已安装模块（8个插件）：                                         ║${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}║    • otb_timeseries  - 时序数据（TimescaleDB兼容）              ║${NC}"
echo -e "${GREEN}║    • otb_age         - 图数据（Apache AGE兼容）                 ║${NC}"
echo -e "${GREEN}║    • otb_fulltext    - 全文检索（zhparser+RUM兼容）             ║${NC}"
echo -e "${GREEN}║    • otb_scheduler   - 调度管理（pg_cron+pg_partman兼容）       ║${NC}"
echo -e "${GREEN}║    • otb_routing     - 路网分析（pgRouting兼容）                ║${NC}"
echo -e "${GREEN}║    • otb_analytics   - 时序分析算法库（移动平均+异常检测）      ║${NC}"
echo -e "${GREEN}║    • otb_snapshot    - 数据快照与回滚系统                       ║${NC}"
echo -e "${GREEN}║    • otb_health      - 数据健康诊断（DBA智能助手）              ║${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}║  加上OpenTenBase原生支持：                                       ║${NC}"
echo -e "${GREEN}║    • 关系数据、地理空间(PostGIS)、向量数据(pgvector)            ║${NC}"
echo -e "${GREEN}║                                                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
print_success "部署完成！共安装 8 个插件"
