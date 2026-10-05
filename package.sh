#!/usr/bin/env bash
#
#  package.sh
#  Me2Tune 一键打包脚本
#
#  用法:
#    ./package.sh [选项]
#
#  选项:
#    --dmg-only          仅生成 DMG 安装包
#    --zip-only          仅生成 ZIP 压缩包
#    --app-only          仅生成 .app 应用程序包
#    --clean             打包前先清理构建缓存
#    --config <Debug|Release>  指定构建配置 (默认: Release)
#    -h, --help          查看帮助说明
#

set -euo pipefail

# MARK: - 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# MARK: - 脚本所在目录定位
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

PROJECT_NAME="Me2Tune"
SCHEME_NAME="Me2Tune"
CONFIGURATION="Release"
DESTINATION="generic/platform=macOS"
OUTPUT_DIR="${SCRIPT_DIR}/dist"
BUILD_DIR="${SCRIPT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"

BUILD_DMG=true
BUILD_ZIP=true
CLEAN_BUILD=false

# MARK: - 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg-only)
            BUILD_DMG=true
            BUILD_ZIP=false
            shift
            ;;
        --zip-only)
            BUILD_DMG=false
            BUILD_ZIP=true
            shift
            ;;
        --app-only)
            BUILD_DMG=false
            BUILD_ZIP=false
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --config)
            CONFIGURATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Me2Tune 一键打包脚本"
            echo ""
            echo "用法: ./package.sh [选项]"
            echo ""
            echo "选项:"
            echo "  --dmg-only          仅生成 DMG 安装包"
            echo "  --zip-only          仅生成 ZIP 压缩包"
            echo "  --app-only          仅生成 .app 应用程序包"
            echo "  --clean             打包前先清理构建缓存"
            echo "  --config <Config>   构建配置 (默认: Release)"
            echo "  -h, --help          显示此帮助"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ 未知参数: $1${NC}"
            echo "运行 ./package.sh --help 查看使用说明。"
            exit 1
            ;;
    esac
done

START_TIME=$(date +%s)

echo -e "${BOLD}${CYAN}=================================================${NC}"
echo -e "${BOLD}${CYAN}          🎵 Me2Tune 一键打包脚本               ${NC}"
echo -e "${BOLD}${CYAN}=================================================${NC}"

# MARK: - 环境检查
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo -e "${RED}❌ 错误: 未检测到 xcodebuild 命令，请确认已安装 Xcode 命令行工具。${NC}"
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version | head -n 1)
echo -e "${BLUE}ℹ️  Xcode 环境: ${XCODE_VERSION}${NC}"
echo -e "${BLUE}ℹ️  构建配置:   ${CONFIGURATION}${NC}"
echo -e "${BLUE}ℹ️  输出目录:   ${OUTPUT_DIR}${NC}"
echo ""

# MARK: - 清理旧产物
if [ "${CLEAN_BUILD}" = true ]; then
    echo -e "${YELLOW}🧹 正在执行深层清理 (--clean)...${NC}"
    rm -rf "${BUILD_DIR}"
    xcodebuild clean -scheme "${SCHEME_NAME}" -configuration "${CONFIGURATION}" -quiet || true
fi

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${BUILD_DIR}"

# MARK: - 执行构建与归档
echo -e "${CYAN}🔨 [1/4] 正在归档 (xcodebuild archive)...${NC}"

xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination "${DESTINATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE="Manual" \
    -quiet

if [ ! -d "${ARCHIVE_PATH}" ]; then
    echo -e "${RED}❌ 归档失败: 未找到 ${ARCHIVE_PATH}${NC}"
    exit 1
fi

SOURCE_APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PROJECT_NAME}.app"
if [ ! -d "${SOURCE_APP_PATH}" ]; then
    echo -e "${RED}❌ 错误: 归档产物中未找到 ${PROJECT_NAME}.app${NC}"
    exit 1
fi

# MARK: - 获取版本信息
INFO_PLIST="${SOURCE_APP_PATH}/Contents/Info.plist"
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${INFO_PLIST}" 2>/dev/null || echo "1.0.0")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${INFO_PLIST}" 2>/dev/null || echo "1")

echo -e "${GREEN}✅ 归档成功! 版本号: v${APP_VERSION} (Build ${APP_BUILD})${NC}"

# MARK: - 复制并签名 App
echo -e "${CYAN}📦 [2/4] 导出与验证 .app 包...${NC}"

TARGET_APP_PATH="${OUTPUT_DIR}/${PROJECT_NAME}.app"
cp -R "${SOURCE_APP_PATH}" "${TARGET_APP_PATH}"

# 对导出目录下的 app 重新应用本地签名（Ad-Hoc），确保完整性
codesign --force --deep --sign - "${TARGET_APP_PATH}" >/dev/null 2>&1 || true

echo -e "${GREEN}✅ 应用程序包已生成: ${TARGET_APP_PATH}${NC}"

# MARK: - 生成 DMG 安装镜像
DMG_NAME="${PROJECT_NAME}-v${APP_VERSION}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"

if [ "${BUILD_DMG}" = true ]; then
    echo -e "${CYAN}💿 [3/4] 正在制作 DMG 镜像 (${DMG_NAME})...${NC}"
    
    DMG_STAGING_DIR="$(mktemp -d -t me2tune-dmg-staging-XXXXXX)"
    
    # 拷贝 app 并创建 Applications 快捷方式
    cp -R "${TARGET_APP_PATH}" "${DMG_STAGING_DIR}/"
    ln -s /Applications "${DMG_STAGING_DIR}/Applications"
    
    # 生成压缩只读 DMG
    hdiutil create \
        -volname "${PROJECT_NAME}" \
        -srcfolder "${DMG_STAGING_DIR}" \
        -ov \
        -format UDZO \
        "${DMG_PATH}" >/dev/null 2>&1
        
    rm -rf "${DMG_STAGING_DIR}"
    
    echo -e "${GREEN}✅ DMG 镜像生成完成!${NC}"
else
    echo -e "${YELLOW}⏭️  跳过 DMG 生成${NC}"
fi

# MARK: - 生成 ZIP 压缩包
ZIP_NAME="${PROJECT_NAME}-v${APP_VERSION}.zip"
ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

if [ "${BUILD_ZIP}" = true ]; then
    echo -e "${CYAN}🗜️  [4/4] 正在制作 ZIP 压缩包 (${ZIP_NAME})...${NC}"
    
    cd "${OUTPUT_DIR}"
    ditto -c -k --sequesterRsrc --keepParent "${PROJECT_NAME}.app" "${ZIP_PATH}"
    cd "${SCRIPT_DIR}"
    
    echo -e "${GREEN}✅ ZIP 压缩包生成完成!${NC}"
else
    echo -e "${YELLOW}⏭️  跳过 ZIP 生成${NC}"
fi

# MARK: - 清理临时构建文件
rm -rf "${BUILD_DIR}"

# MARK: - 完成报告
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${BOLD}${GREEN}=================================================${NC}"
echo -e "${BOLD}${GREEN}              🎉 打包成功! (耗时: ${DURATION}s)              ${NC}"
echo -e "${BOLD}${GREEN}=================================================${NC}"
echo -e "${BOLD}产物清单:${NC}"

if [ -d "${TARGET_APP_PATH}" ]; then
    APP_SIZE=$(du -sh "${TARGET_APP_PATH}" | awk '{print $1}')
    echo -e "  📁 应用程序: ${BOLD}${TARGET_APP_PATH}${NC} (${APP_SIZE})"
fi

if [ -f "${DMG_PATH}" ]; then
    DMG_SIZE=$(du -sh "${DMG_PATH}" | awk '{print $1}')
    DMG_SHA=$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')
    echo -e "  💿 DMG 安装包: ${BOLD}${DMG_PATH}${NC} (${DMG_SIZE})"
    echo -e "     SHA256: ${CYAN}${DMG_SHA}${NC}"
fi

if [ -f "${ZIP_PATH}" ]; then
    ZIP_SIZE=$(du -sh "${ZIP_PATH}" | awk '{print $1}')
    ZIP_SHA=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')
    echo -e "  🗜️  ZIP 归档:   ${BOLD}${ZIP_PATH}${NC} (${ZIP_SIZE})"
    echo -e "     SHA256: ${CYAN}${ZIP_SHA}${NC}"
fi

echo ""
echo -e "${BOLD}${CYAN}可直接在 Finder 中查看产物: open dist${NC}"
