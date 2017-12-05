
export BUILDTYPE ?= Debug
export WITH_CXX11ABI ?= $(shell scripts/check-cxx11abi.sh)

ifeq ($(BUILDTYPE), Release)
else ifeq ($(BUILDTYPE), RelWithDebInfo)
else ifeq ($(BUILDTYPE), Sanitize)
else ifeq ($(BUILDTYPE), Debug)
else
  $(error BUILDTYPE must be Debug, Sanitize, Release or RelWithDebInfo)
endif

buildtype := $(shell echo "$(BUILDTYPE)" | tr "[A-Z]" "[a-z]")

ifeq ($(shell uname -s), Darwin)
  HOST_PLATFORM = macos
  HOST_PLATFORM_VERSION = $(shell uname -m)
  export NINJA = platform/macos/ninja
  export JOBS ?= $(shell sysctl -n hw.ncpu)
else ifeq ($(shell uname -s), Linux)
  HOST_PLATFORM = linux
  HOST_PLATFORM_VERSION = $(shell uname -m)
  export NINJA = platform/linux/ninja
  export JOBS ?= $(shell grep --count processor /proc/cpuinfo)
else
  $(error Cannot determine host platform)
endif

ifeq ($(MASON_PLATFORM),)
  BUILD_PLATFORM = $(HOST_PLATFORM)
else
  BUILD_PLATFORM = $(MASON_PLATFORM)
endif

ifeq ($(MASON_PLATFORM_VERSION),)
  BUILD_PLATFORM_VERSION = $(HOST_PLATFORM_VERSION)
else
  BUILD_PLATFORM_VERSION = $(MASON_PLATFORM_VERSION)
endif

ifeq ($(MASON_PLATFORM),macos)
	MASON_PLATFORM=osx
endif

ifeq ($(V), 1)
  export XCPRETTY
  NINJA_ARGS ?= -v
else
  export XCPRETTY ?= | xcpretty
  NINJA_ARGS ?=
endif

.PHONY: default
default: test

BUILD_DEPS += Makefile
BUILD_DEPS += CMakeLists.txt

#### macOS targets ##############################################################

ifeq ($(HOST_PLATFORM), macos)

export PATH := $(shell pwd)/platform/macos:$(PATH)

MACOS_OUTPUT_PATH = build/macos
MACOS_PROJ_PATH = $(MACOS_OUTPUT_PATH)/mbgl.xcodeproj
MACOS_WORK_PATH = platform/macos/macos.xcworkspace
MACOS_USER_DATA_PATH = $(MACOS_WORK_PATH)/xcuserdata/$(USER).xcuserdatad
MACOS_COMPDB_PATH = $(MACOS_OUTPUT_PATH)/compdb/$(BUILDTYPE)

MACOS_XCODEBUILD = xcodebuild \
	  -derivedDataPath $(MACOS_OUTPUT_PATH) \
	  -configuration $(BUILDTYPE) \
	  -workspace $(MACOS_WORK_PATH)

$(MACOS_PROJ_PATH): $(BUILD_DEPS) $(MACOS_USER_DATA_PATH)/WorkspaceSettings.xcsettings
	mkdir -p $(MACOS_OUTPUT_PATH)
	(cd $(MACOS_OUTPUT_PATH) && cmake -G Xcode ../..)

$(MACOS_USER_DATA_PATH)/WorkspaceSettings.xcsettings: platform/macos/WorkspaceSettings.xcsettings
	mkdir -p "$(MACOS_USER_DATA_PATH)"
	cp platform/macos/WorkspaceSettings.xcsettings "$@"

.PHONY: macos
macos: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'CI' build $(XCPRETTY)

.PHONY: xproj
xproj: $(MACOS_PROJ_PATH)
	open $(MACOS_WORK_PATH)

.PHONY: test
test: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'mbgl-test' build $(XCPRETTY)

.PHONY: benchmark
benchmark: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'mbgl-benchmark' build $(XCPRETTY)

.PHONY: run-test
run-test: run-test-*

run-test-%: test
	ulimit -c unlimited && ($(MACOS_OUTPUT_PATH)/$(BUILDTYPE)/mbgl-test --gtest_catch_exceptions=0 --gtest_filter=$* & pid=$$! && wait $$pid \
	  || (lldb -c /cores/core.$$pid --batch --one-line 'thread backtrace all' --one-line 'quit' && exit 1))
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'CI' test $(XCPRETTY)

.PHONY: run-benchmark
run-benchmark: run-benchmark-.

run-benchmark-%: benchmark
	$(MACOS_OUTPUT_PATH)/$(BUILDTYPE)/mbgl-benchmark --benchmark_filter=$* ${BENCHMARK_ARGS}

.PHONY: node-benchmark
node-benchmark: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'node-benchmark' build $(XCPRETTY)

.PHONY: run-node-benchmark
run-node-benchmark: node-benchmark
	node platform/node/test/benchmark.js

.PHONY: glfw-app
glfw-app: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'mbgl-glfw' build $(XCPRETTY)

.PHONY: run-glfw-app
run-glfw-app: glfw-app
	"$(MACOS_OUTPUT_PATH)/$(BUILDTYPE)/mbgl-glfw"

.PHONY: render
render: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'mbgl-render' build $(XCPRETTY)

.PHONY: offline
offline: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'mbgl-offline' build $(XCPRETTY)

.PHONY: node
node: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'mbgl-node' build $(XCPRETTY)

.PHONY: macos-test
macos-test: $(MACOS_PROJ_PATH)
	set -o pipefail && $(MACOS_XCODEBUILD) -scheme 'CI' test $(XCPRETTY)

.PHONY: macos-lint
macos-lint:
	find platform/macos -type f -name '*.plist' | xargs plutil -lint

.PHONY: xpackage
xpackage: $(MACOS_PROJ_PATH)
	SYMBOLS=$(SYMBOLS) ./platform/macos/scripts/package.sh

.PHONY: xdeploy
xdeploy:
	caffeinate -i ./platform/macos/scripts/deploy-packages.sh

.PHONY: xdocument
xdocument:
	OUTPUT=$(OUTPUT) ./platform/macos/scripts/document.sh

.PHONY: genstrings
genstrings:
	genstrings -u -o platform/macos/sdk/Base.lproj platform/darwin/src/*.{m,mm}
	genstrings -u -o platform/macos/sdk/Base.lproj platform/macos/src/*.{m,mm}
	genstrings -u -o platform/ios/resources/Base.lproj platform/ios/src/*.{m,mm}
	-find platform/ios/resources platform/macos/sdk -path '*/Base.lproj/*.strings' -exec \
		textutil -convert txt -extension strings -inputencoding UTF-16 -encoding UTF-8 {} \;
	mv platform/macos/sdk/Base.lproj/Foundation.strings platform/darwin/resources/Base.lproj/

$(MACOS_COMPDB_PATH)/Makefile:
	mkdir -p $(MACOS_COMPDB_PATH)
	(cd $(MACOS_COMPDB_PATH) && cmake ../../../.. \
		-DCMAKE_BUILD_TYPE=$(BUILDTYPE) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON)

.PHONY:
compdb: $(BUILD_DEPS) $(TEST_DEPS) $(MACOS_COMPDB_PATH)/Makefile
	@$(MAKE) -C $(MACOS_COMPDB_PATH) cmake_check_build_system

.PHONY: tidy
tidy: compdb
	scripts/clang-tools.sh $(MACOS_COMPDB_PATH)

.PHONY: check
check: compdb
	scripts/clang-tools.sh $(MACOS_COMPDB_PATH) --diff

endif

#### iOS targets ##############################################################

ifeq ($(HOST_PLATFORM), macos)

IOS_OUTPUT_PATH = build/ios
IOS_PROJ_PATH = $(IOS_OUTPUT_PATH)/mbgl.xcodeproj
IOS_WORK_PATH = platform/ios/ios.xcworkspace
IOS_USER_DATA_PATH = $(IOS_WORK_PATH)/xcuserdata/$(USER).xcuserdatad

IOS_XCODEBUILD_SIM = xcodebuild \
	  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES \
	  -derivedDataPath $(IOS_OUTPUT_PATH) \
	  -configuration $(BUILDTYPE) -sdk iphonesimulator \
	  -destination 'platform=iOS Simulator,name=iPhone 6,OS=latest' \
	  -workspace $(IOS_WORK_PATH)

$(IOS_PROJ_PATH): $(IOS_USER_DATA_PATH)/WorkspaceSettings.xcsettings $(BUILD_DEPS)
	mkdir -p $(IOS_OUTPUT_PATH)
	(cd $(IOS_OUTPUT_PATH) && cmake -G Xcode ../.. \
		-DCMAKE_TOOLCHAIN_FILE=../../platform/ios/toolchain.cmake \
		-DMBGL_PLATFORM=ios \
		-DMASON_PLATFORM=ios)

$(IOS_USER_DATA_PATH)/WorkspaceSettings.xcsettings: platform/ios/WorkspaceSettings.xcsettings
	mkdir -p "$(IOS_USER_DATA_PATH)"
	cp platform/ios/WorkspaceSettings.xcsettings "$@"

.PHONY: ios
ios: $(IOS_PROJ_PATH)
	set -o pipefail && $(IOS_XCODEBUILD_SIM) -scheme 'CI' build $(XCPRETTY)

.PHONY: iproj
iproj: $(IOS_PROJ_PATH)
	open $(IOS_WORK_PATH)

.PHONY: ios-lint
ios-lint:
	find platform/ios/framework -type f -name '*.plist' | xargs plutil -lint
	find platform/ios/app -type f -name '*.plist' | xargs plutil -lint

.PHONY: ios-test
ios-test: $(IOS_PROJ_PATH)
	set -o pipefail && $(IOS_XCODEBUILD_SIM) -scheme 'CI' test $(XCPRETTY)

.PHONY: ios-sanitize-address
ios-sanitize-address: $(IOS_PROJ_PATH)
	set -o pipefail && $(IOS_XCODEBUILD_SIM) -scheme 'CI' -enableAddressSanitizer YES test $(XCPRETTY)

.PHONY: ios-sanitize-thread
ios-sanitize-thread: $(IOS_PROJ_PATH)
	set -o pipefail && $(IOS_XCODEBUILD_SIM) -scheme 'CI' -enableThreadSanitizer YES test $(XCPRETTY)

.PHONY: ipackage
ipackage: $(IOS_PROJ_PATH)
	FORMAT=$(FORMAT) BUILD_DEVICE=$(BUILD_DEVICE) SYMBOLS=$(SYMBOLS) \
	./platform/ios/scripts/package.sh

.PHONY: ipackage-strip
ipackage-strip: $(IOS_PROJ_PATH)
	FORMAT=$(FORMAT) BUILD_DEVICE=$(BUILD_DEVICE) SYMBOLS=NO \
	./platform/ios/scripts/package.sh

.PHONY: ipackage-sim
ipackage-sim: $(IOS_PROJ_PATH)
	BUILDTYPE=Debug FORMAT=dynamic BUILD_DEVICE=false SYMBOLS=$(SYMBOLS) \
	./platform/ios/scripts/package.sh

.PHONY: iframework
iframework: $(IOS_PROJ_PATH)
	FORMAT=dynamic BUILD_DEVICE=$(BUILD_DEVICE) SYMBOLS=$(SYMBOLS) \
	./platform/ios/scripts/package.sh

.PHONY: ideploy
ideploy:
	caffeinate -i ./platform/ios/scripts/deploy-packages.sh

.PHONY: idocument
idocument:
	OUTPUT=$(OUTPUT) ./platform/ios/scripts/document.sh

.PHONY: darwin-style-code
darwin-style-code:
	node platform/darwin/scripts/generate-style-code.js
	node platform/darwin/scripts/update-examples.js
style-code: darwin-style-code

.PHONY: darwin-update-examples
darwin-update-examples:
	node platform/darwin/scripts/update-examples.js

.PHONY: check-public-symbols
check-public-symbols:
	node platform/darwin/scripts/check-public-symbols.js macOS iOS
endif

#### Linux targets #####################################################

ifeq ($(HOST_PLATFORM), linux)

export PATH := $(shell pwd)/platform/linux:$(PATH)
export LINUX_OUTPUT_PATH = build/linux-$(shell uname -m)/$(BUILDTYPE)
LINUX_BUILD = $(LINUX_OUTPUT_PATH)/build.ninja

$(LINUX_BUILD): $(BUILD_DEPS)
	mkdir -p $(LINUX_OUTPUT_PATH)
	(cd $(LINUX_OUTPUT_PATH) && cmake -G Ninja ../../.. \
		-DCMAKE_BUILD_TYPE=$(BUILDTYPE) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		-DWITH_CXX11ABI=${WITH_CXX11ABI} \
		-DWITH_COVERAGE=${WITH_COVERAGE} \
		-DWITH_OSMESA=${WITH_OSMESA} \
		-DWITH_EGL=${WITH_EGL})

.PHONY: linux
linux: glfw-app render offline

.PHONY: linux-core
linux-core: $(LINUX_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-core mbgl-loop-uv mbgl-filesource

.PHONY: test
test: $(LINUX_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-test

.PHONY: benchmark
benchmark: $(LINUX_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-benchmark

ifneq (,$(shell command -v gdb 2> /dev/null))
  GDB ?= $(shell scripts/mason.sh PREFIX gdb VERSION 2017-04-08-aebcde5)/bin/gdb \
        	-batch -return-child-result \
        	-ex 'set print thread-events off' \
        	-ex 'set disable-randomization off' \
        	-ex 'run' \
        	-ex 'thread apply all bt' --args
endif

.PHONY: run-test
run-test: run-test-*

run-test-%: test
	$(GDB) $(LINUX_OUTPUT_PATH)/mbgl-test --gtest_catch_exceptions=0 --gtest_filter=$*

.PHONY: run-benchmark
run-benchmark: run-benchmark-.

run-benchmark-%: benchmark
	$(LINUX_OUTPUT_PATH)/mbgl-benchmark --benchmark_filter=$*

.PHONY: render
render: $(LINUX_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-render

.PHONY: offline
offline: $(LINUX_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-offline

.PHONY: glfw-app
glfw-app: $(LINUX_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-glfw

.PHONY: run-glfw-app
run-glfw-app: glfw-app
	cd $(LINUX_OUTPUT_PATH) && ./mbgl-glfw

.PHONY: node
node: $(LINUX_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(LINUX_OUTPUT_PATH) mbgl-node

.PHONY: compdb
compdb: $(LINUX_BUILD)
	# Ninja generator already outputs the file at the right location

.PHONY: tidy
tidy: compdb
	scripts/clang-tools.sh $(LINUX_OUTPUT_PATH)

.PHONY: check
check: compdb
	scripts/clang-tools.sh $(LINUX_OUTPUT_PATH) --diff

endif

#### Qt targets #####################################################

QT_QMAKE_FOUND := $(shell command -v qmake 2> /dev/null)
ifdef QT_QMAKE_FOUND
  export QT_INSTALL_DOCS = $(shell qmake -query QT_INSTALL_DOCS)
  ifeq ($(shell qmake -query QT_VERSION | head -c1), 4)
    QT_ROOT_PATH = build/qt4-$(BUILD_PLATFORM)-$(BUILD_PLATFORM_VERSION)
    WITH_QT_4=1
  else
    QT_ROOT_PATH = build/qt-$(BUILD_PLATFORM)-$(BUILD_PLATFORM_VERSION)
    WITH_QT_4=0
  endif
endif

export QT_OUTPUT_PATH = $(QT_ROOT_PATH)/$(BUILDTYPE)
QT_BUILD = $(QT_OUTPUT_PATH)/build.ninja

$(QT_BUILD): $(BUILD_DEPS)
	@scripts/check-qt.sh
	mkdir -p $(QT_OUTPUT_PATH)
	(cd $(QT_OUTPUT_PATH) && cmake -G Ninja ../../.. \
		-DCMAKE_BUILD_TYPE=$(BUILDTYPE) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		-DMBGL_PLATFORM=qt \
		-DMASON_PLATFORM=$(MASON_PLATFORM) \
		-DMASON_PLATFORM_VERSION=$(MASON_PLATFORM_VERSION) \
		-DWITH_QT_DECODERS=${WITH_QT_DECODERS} \
		-DWITH_QT_I18N=${WITH_QT_I18N} \
		-DWITH_QT_4=${WITH_QT_4} \
		-DWITH_CXX11ABI=${WITH_CXX11ABI} \
		-DWITH_COVERAGE=${WITH_COVERAGE})

ifeq ($(HOST_PLATFORM), macos)

MACOS_QT_PROJ_PATH = $(QT_ROOT_PATH)/xcode/mbgl.xcodeproj
$(MACOS_QT_PROJ_PATH): $(BUILD_DEPS)
	@scripts/check-qt.sh
	mkdir -p $(QT_ROOT_PATH)/xcode
	(cd $(QT_ROOT_PATH)/xcode && cmake -G Xcode ../../.. \
		-DMBGL_PLATFORM=qt \
		-DMASON_PLATFORM=$(MASON_PLATFORM) \
		-DMASON_PLATFORM_VERSION=$(MASON_PLATFORM_VERSION) \
		-DWITH_QT_DECODERS=${WITH_QT_DECODERS} \
		-DWITH_QT_I18N=${WITH_QT_I18N} \
		-DWITH_QT_4=${WITH_QT_4} \
		-DWITH_CXX11ABI=${WITH_CXX11ABI} \
		-DWITH_COVERAGE=${WITH_COVERAGE})

.PHONY: qtproj
qtproj: $(MACOS_QT_PROJ_PATH)
	open $(MACOS_QT_PROJ_PATH)

endif

.PHONY: qt-lib
qt-lib: $(QT_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(QT_OUTPUT_PATH) qmapboxgl

.PHONY: qt-app
qt-app: $(QT_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(QT_OUTPUT_PATH) mbgl-qt

.PHONY: run-qt-app
run-qt-app: qt-app
	$(QT_OUTPUT_PATH)/mbgl-qt

.PHONY: qt-test
qt-test: $(QT_BUILD)
	$(NINJA) $(NINJA_ARGS) -j$(JOBS) -C $(QT_OUTPUT_PATH) mbgl-test

run-qt-test-%: qt-test
	$(QT_OUTPUT_PATH)/mbgl-test --gtest_catch_exceptions=0 --gtest_filter=$*

.PHONY: run-qt-test
run-qt-test: run-qt-test-*

.PHONY: qt-docs
qt-docs:
	qdoc $(shell pwd)/platform/qt/config.qdocconf -outputdir $(shell pwd)/$(QT_OUTPUT_PATH)/docs

#### Node targets ##############################################################

.PHONY: test-node
test-node: node
	npm test
	npm run test-suite

.PHONY: test-node-recycle-map
test-node-recycle-map: node
	npm test
	npm run test-render -- --recycle-map --shuffle
	npm run test-query

#### Android targets ###########################################################

MBGL_ANDROID_ABIS  = arm-v5;armeabi
MBGL_ANDROID_ABIS += arm-v7;armeabi-v7a
MBGL_ANDROID_ABIS += arm-v8;arm64-v8a
MBGL_ANDROID_ABIS += x86;x86
MBGL_ANDROID_ABIS += x86-64;x86_64
MBGL_ANDROID_ABIS += mips;mips

MBGL_ANDROID_LOCAL_WORK_DIR = /data/local/tmp/core-tests
MBGL_ANDROID_LIBDIR = lib$(if $(filter arm-v8 x86-64,$1),64)
MBGL_ANDROID_DALVIKVM = dalvikvm$(if $(filter arm-v8 x86-64,$1),64,32)
MBGL_ANDROID_APK_SUFFIX = $(if $(filter Release,$(BUILDTYPE)),release-unsigned,debug)
MBGL_ANDROID_CORE_TEST_DIR = platform/android/MapboxGLAndroidSDK/.externalNativeBuild/cmake/$(buildtype)/$2/core-tests
MBGL_ANDROID_GRADLE = ./gradlew --parallel --max-workers=$(JOBS) -Pmapbox.buildtype=$(buildtype)

# Lists all devices, and extracts the identifiers, then obtains the ABI for every one.
# Some devices return \r\n, so we'll have to remove the carriage return before concatenating.
MBGL_ANDROID_ACTIVE_ARCHS = $(shell adb devices | sed '1d;/^\*/d;s/[[:space:]].*//' | xargs -n 1 -I DEV `type -P adb` -s DEV shell getprop ro.product.cpu.abi | tr -d '\r')

# Generate code based on the style specification
.PHONY: android-style-code
android-style-code:
	node platform/android/scripts/generate-style-code.js
style-code: android-style-code

# Configuration file for running CMake from Gradle within Android Studio.
platform/android/configuration.gradle:
	@echo "ext {\n    node = '`command -v node || command -v nodejs`'\n    npm = '`command -v npm`'\n    ccache = '`command -v ccache`'\n}" > $@

define ANDROID_RULES
# $1 = arm-v7 (short arch)
# $2 = armeabi-v7a (internal arch)

.PHONY: android-test-lib-$1
android-test-lib-$1: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=$2 -Pmapbox.with_test=true :MapboxGLAndroidSDKTestApp:assemble$(BUILDTYPE)

# Build SDK for for specified abi
.PHONY: android-lib-$1
android-lib-$1: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=$2 :MapboxGLAndroidSDK:assemble$(BUILDTYPE)

# Build test app and SDK for for specified abi
.PHONY: android-$1
android-$1: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=$2 :MapboxGLAndroidSDKTestApp:assemble$(BUILDTYPE)

# Build the core test for specified abi
.PHONY: android-core-test-$1
android-core-test-$1: android-test-lib-$1
	# Compile main sources and extract the classes (using the test app to get all transitive dependencies in one place)
	mkdir -p $(MBGL_ANDROID_CORE_TEST_DIR)
	unzip -o platform/android/MapboxGLAndroidSDKTestApp/build/outputs/apk/MapboxGLAndroidSDKTestApp-$(MBGL_ANDROID_APK_SUFFIX).apk classes.dex -d $(MBGL_ANDROID_CORE_TEST_DIR)

	# Compile Test runner
	find platform/android/src/test -name "*.java" > $(MBGL_ANDROID_CORE_TEST_DIR)/java-sources.txt
	javac -sourcepath platform/android/src/test -d $(MBGL_ANDROID_CORE_TEST_DIR) -source 1.7 -target 1.7 @$(MBGL_ANDROID_CORE_TEST_DIR)/java-sources.txt

	# Combine and dex
	cd $(MBGL_ANDROID_CORE_TEST_DIR) && $(ANDROID_HOME)/build-tools/25.0.0/dx --dex --output=test.jar *.class classes.dex

run-android-core-test-$1-%: android-core-test-$1
	# Ensure clean state on the device
	adb shell "rm -Rf $(MBGL_ANDROID_LOCAL_WORK_DIR) && mkdir -p $(MBGL_ANDROID_LOCAL_WORK_DIR)/test"

	# Push all needed files to the device
	adb push $(MBGL_ANDROID_CORE_TEST_DIR)/test.jar $(MBGL_ANDROID_LOCAL_WORK_DIR) > /dev/null 2>&1
	adb push test/fixtures $(MBGL_ANDROID_LOCAL_WORK_DIR)/test > /dev/null 2>&1
	adb push platform/android/MapboxGLAndroidSDK/build/intermediates/bundles/default/jni/$2/libmapbox-gl.so $(MBGL_ANDROID_LOCAL_WORK_DIR) > /dev/null 2>&1
	adb push platform/android/MapboxGLAndroidSDK/build/intermediates/bundles/default/jni/$2/libmbgl-test.so $(MBGL_ANDROID_LOCAL_WORK_DIR) > /dev/null 2>&1

	# Kick off the tests
	adb shell "export LD_LIBRARY_PATH=/system/$(MBGL_ANDROID_LIBDIR):$(MBGL_ANDROID_LOCAL_WORK_DIR) && cd $(MBGL_ANDROID_LOCAL_WORK_DIR) && $(MBGL_ANDROID_DALVIKVM) -cp $(MBGL_ANDROID_LOCAL_WORK_DIR)/test.jar Main --gtest_filter=$$*"

	# Gather the results and unpack them
	adb shell "cd $(MBGL_ANDROID_LOCAL_WORK_DIR) && tar -cvzf results.tgz test/fixtures/*  > /dev/null 2>&1"
	adb pull $(MBGL_ANDROID_LOCAL_WORK_DIR)/results.tgz $(MBGL_ANDROID_CORE_TEST_DIR)/ > /dev/null 2>&1
	rm -rf $(MBGL_ANDROID_CORE_TEST_DIR)/results && mkdir -p $(MBGL_ANDROID_CORE_TEST_DIR)/results
	tar -xzf $(MBGL_ANDROID_CORE_TEST_DIR)/results.tgz --strip-components=2 -C $(MBGL_ANDROID_CORE_TEST_DIR)/results

# Run the core test for specified abi
.PHONY: run-android-core-test-$1
run-android-core-test-$1: run-android-core-test-$1-*

# Run the test app on connected android device with specified abi
.PHONY: run-android-$1
run-android-$1: platform/android/configuration.gradle
	-adb uninstall com.mapbox.mapboxsdk.testapp 2> /dev/null
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=$2 :MapboxGLAndroidSDKTestApp:install$(BUILDTYPE) && adb shell am start -n com.mapbox.mapboxsdk.testapp/.activity.FeatureOverviewActivity

# Build test app instrumentation tests apk and test app apk for specified abi
.PHONY: android-ui-test-$1
android-ui-test-$1: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=$2 :MapboxGLAndroidSDKTestApp:assembleDebug :MapboxGLAndroidSDKTestApp:assembleAndroidTest

# Run test app instrumentation tests on a connected android device or emulator with specified abi
.PHONY: run-android-ui-test-$1
run-android-ui-test-$1: platform/android/configuration.gradle
	-adb uninstall com.mapbox.mapboxsdk.testapp 2> /dev/null
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=$2 :MapboxGLAndroidSDKTestApp:connectedAndroidTest

# Run Java Instrumentation tests on a connected android device or emulator with specified abi and test filter
run-android-ui-test-$1-%: platform/android/configuration.gradle
	-adb uninstall com.mapbox.mapboxsdk.testapp 2> /dev/null
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=$2 :MapboxGLAndroidSDKTestApp:connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class="$$*"

# Symbolicate native stack trace with the specified abi
.PHONY: android-ndk-stack-$1
android-ndk-stack-$1: platform/android/configuration.gradle
	adb logcat | ndk-stack -sym platform/android/MapboxGLAndroidSDK/build/intermediates/cmake/debug/obj/$2/

endef

# Explodes the arguments into individual variables
define ANDROID_RULES_INVOKER
$(call ANDROID_RULES,$(word 1,$1),$(word 2,$1))
endef

$(foreach abi,$(MBGL_ANDROID_ABIS),$(eval $(call ANDROID_RULES_INVOKER,$(subst ;, ,$(abi)))))

# Build the Android SDK and test app with abi set to arm-v7
.PHONY: android
android: android-arm-v7

# Build the Android SDK with abi set to arm-v7
.PHONY: android-lib
android-lib: android-lib-arm-v7

# Run the test app on connected android device with abi set to arm-v7
.PHONY: run-android
run-android: run-android-arm-v7

# Run Java Instrumentation tests on a connected android device or emulator with abi set to arm-v7
.PHONY: run-android-ui-test
run-android-ui-test: run-android-ui-test-arm-v7
run-android-ui-test-%: run-android-ui-test-arm-v7-%

# Run Java Unit tests on the JVM of the development machine executing this
.PHONY: run-android-unit-test
run-android-unit-test: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=none :MapboxGLAndroidSDK:testDebugUnitTest
run-android-unit-test-%: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=none :MapboxGLAndroidSDK:testDebugUnitTest --tests "$*"

# Run Instrumentation tests on AWS device farm, requires additional authentication through gradle.properties
.PHONY: run-android-ui-test-aws
run-android-ui-test-aws: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=all devicefarmUpload

# Builds a release package of the Android SDK
.PHONY: apackage
apackage: platform/android/configuration.gradle
	make android-lib-arm-v5 && make android-lib-arm-v7 && make android-lib-arm-v8 && make android-lib-x86 && make android-lib-x86-64 && make android-lib-mips
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=all assemble$(BUILDTYPE)

# Uploads the compiled Android SDK to Maven
.PHONY: run-android-upload-archives
run-android-upload-archives: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=all :MapboxGLAndroidSDK:uploadArchives

# Dump system graphics information for the test app
.PHONY: android-gfxinfo
android-gfxinfo:
	adb shell dumpsys gfxinfo com.mapbox.mapboxsdk.testapp reset

# Runs Android UI tests on all connected devices using Spoon
.PHONY: run-android-ui-test-spoon
run-android-ui-test-spoon: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis="$(MBGL_ANDROID_ACTIVE_ARCHS)" spoon

# Generates Activity sanity tests
.PHONY: test-code-android
test-code-android:
	node platform/android/scripts/generate-test-code.js

# Runs checkstyle and lint on the Android code
.PHONY: android-check
android-check : android-checkstyle android-lint-sdk android-lint-test-app

# Runs checkstyle on the Android code
.PHONY: android-checkstyle
android-checkstyle: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=none checkstyle

# Runs lint on the Android SDK code
.PHONY: android-lint-sdk
android-lint-sdk: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=none :MapboxGLAndroidSDK:lint

# Runs lint on the Android test app code
.PHONY: android-lint-test-app
android-lint-test-app: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=none :MapboxGLAndroidSDKTestApp:lint

# Generates javadoc from the Android SDK
.PHONY: android-javadoc
android-javadoc: platform/android/configuration.gradle
	cd platform/android && $(MBGL_ANDROID_GRADLE) -Pmapbox.abis=none :MapboxGLAndroidSDK:javadocrelease

# Symbolicate ndk stack traces for the arm-v7 abi
.PHONY: android-ndk-stack
android-ndk-stack: android-ndk-stack-arm-v7

# Open Android Studio if machine is macos
ifeq ($(HOST_PLATFORM), macos)
.PHONY: aproj
aproj: platform/android/configuration.gradle
	open -b com.google.android.studio platform/android
endif

# Creates the configuration needed to build with Android Studio
.PHONY: android-configuration
android-configuration: platform/android/configuration.gradle
	cat platform/android/configuration.gradle

#### Miscellaneous targets #####################################################

.PHONY: style-code
style-code:
	node scripts/generate-style-code.js
	node scripts/generate-shaders.js

.PHONY: codestyle
codestyle:
	scripts/codestyle.sh

.PHONY: clean
clean:
	$(MAKE) -f CMakeFiles/Makefile2 clean
.PHONY : clean

# The main clean target
clean/fast: clean

.PHONY : clean/fast

# Prepare targets for installation.
preinstall: all
	$(MAKE) -f CMakeFiles/Makefile2 preinstall
.PHONY : preinstall

# Prepare targets for installation.
preinstall/fast:
	$(MAKE) -f CMakeFiles/Makefile2 preinstall
.PHONY : preinstall/fast

# clear depends
depend:
	$(CMAKE_COMMAND) -H$(CMAKE_SOURCE_DIR) -B$(CMAKE_BINARY_DIR) --check-build-system CMakeFiles/Makefile.cmake 1
.PHONY : depend

#=============================================================================
# Target rules for targets named mbgl-node

# Build rule for target.
mbgl-node: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-node
.PHONY : mbgl-node

# fast build rule for target.
mbgl-node/fast:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/build
.PHONY : mbgl-node/fast

#=============================================================================
# Target rules for targets named mbgl-offline

# Build rule for target.
mbgl-offline: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-offline
.PHONY : mbgl-offline

# fast build rule for target.
mbgl-offline/fast:
	$(MAKE) -f CMakeFiles/mbgl-offline.dir/build.make CMakeFiles/mbgl-offline.dir/build
.PHONY : mbgl-offline/fast

#=============================================================================
# Target rules for targets named mbgl-glfw

# Build rule for target.
mbgl-glfw: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-glfw
.PHONY : mbgl-glfw

# fast build rule for target.
mbgl-glfw/fast:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/build
.PHONY : mbgl-glfw/fast

#=============================================================================
# Target rules for targets named mbgl-benchmark

# Build rule for target.
mbgl-benchmark: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-benchmark
.PHONY : mbgl-benchmark

# fast build rule for target.
mbgl-benchmark/fast:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/build
.PHONY : mbgl-benchmark/fast

#=============================================================================
# Target rules for targets named npm-install

# Build rule for target.
npm-install: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 npm-install
.PHONY : npm-install

# fast build rule for target.
npm-install/fast:
	$(MAKE) -f CMakeFiles/npm-install.dir/build.make CMakeFiles/npm-install.dir/build
.PHONY : npm-install/fast

#=============================================================================
# Target rules for targets named alk-rts

# Build rule for target.
alk-rts: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 alk-rts
.PHONY : alk-rts

# fast build rule for target.
alk-rts/fast:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/build
.PHONY : alk-rts/fast

#=============================================================================
# Target rules for targets named mbgl-render

# Build rule for target.
mbgl-render: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-render
.PHONY : mbgl-render

# fast build rule for target.
mbgl-render/fast:
	$(MAKE) -f CMakeFiles/mbgl-render.dir/build.make CMakeFiles/mbgl-render.dir/build
.PHONY : mbgl-render/fast

#=============================================================================
# Target rules for targets named mbgl-core

# Build rule for target.
mbgl-core: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-core
.PHONY : mbgl-core

# fast build rule for target.
mbgl-core/fast:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/build
.PHONY : mbgl-core/fast

#=============================================================================
# Target rules for targets named mbgl-test

# Build rule for target.
mbgl-test: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-test
.PHONY : mbgl-test

# fast build rule for target.
mbgl-test/fast:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/build
.PHONY : mbgl-test/fast

#=============================================================================
# Target rules for targets named update-submodules

# Build rule for target.
update-submodules: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 update-submodules
.PHONY : update-submodules

# fast build rule for target.
update-submodules/fast:
	$(MAKE) -f CMakeFiles/update-submodules.dir/build.make CMakeFiles/update-submodules.dir/build
.PHONY : update-submodules/fast

#=============================================================================
# Target rules for targets named mbgl-loop-uv

# Build rule for target.
mbgl-loop-uv: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-loop-uv
.PHONY : mbgl-loop-uv

# fast build rule for target.
mbgl-loop-uv/fast:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/build
.PHONY : mbgl-loop-uv/fast

#=============================================================================
# Target rules for targets named mbgl-filesource

# Build rule for target.
mbgl-filesource: cmake_check_build_system
	$(MAKE) -f CMakeFiles/Makefile2 mbgl-filesource
.PHONY : mbgl-filesource

# fast build rule for target.
mbgl-filesource/fast:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/build
.PHONY : mbgl-filesource/fast

alk/Frontend.o: alk/Frontend.cpp.o

.PHONY : alk/Frontend.o

# target to build an object file
alk/Frontend.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Frontend.cpp.o
.PHONY : alk/Frontend.cpp.o

alk/Frontend.i: alk/Frontend.cpp.i

.PHONY : alk/Frontend.i

# target to preprocess a source file
alk/Frontend.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Frontend.cpp.i
.PHONY : alk/Frontend.cpp.i

alk/Frontend.s: alk/Frontend.cpp.s

.PHONY : alk/Frontend.s

# target to generate assembly for a file
alk/Frontend.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Frontend.cpp.s
.PHONY : alk/Frontend.cpp.s

alk/Map.o: alk/Map.cpp.o

.PHONY : alk/Map.o

# target to build an object file
alk/Map.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Map.cpp.o
.PHONY : alk/Map.cpp.o

alk/Map.i: alk/Map.cpp.i

.PHONY : alk/Map.i

# target to preprocess a source file
alk/Map.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Map.cpp.i
.PHONY : alk/Map.cpp.i

alk/Map.s: alk/Map.cpp.s

.PHONY : alk/Map.s

# target to generate assembly for a file
alk/Map.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Map.cpp.s
.PHONY : alk/Map.cpp.s

alk/RasterTileRenderer.o: alk/RasterTileRenderer.cpp.o

.PHONY : alk/RasterTileRenderer.o

# target to build an object file
alk/RasterTileRenderer.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/RasterTileRenderer.cpp.o
.PHONY : alk/RasterTileRenderer.cpp.o

alk/RasterTileRenderer.i: alk/RasterTileRenderer.cpp.i

.PHONY : alk/RasterTileRenderer.i

# target to preprocess a source file
alk/RasterTileRenderer.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/RasterTileRenderer.cpp.i
.PHONY : alk/RasterTileRenderer.cpp.i

alk/RasterTileRenderer.s: alk/RasterTileRenderer.cpp.s

.PHONY : alk/RasterTileRenderer.s

# target to generate assembly for a file
alk/RasterTileRenderer.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/RasterTileRenderer.cpp.s
.PHONY : alk/RasterTileRenderer.cpp.s

alk/RenderCache.o: alk/RenderCache.cpp.o

.PHONY : alk/RenderCache.o

# target to build an object file
alk/RenderCache.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/RenderCache.cpp.o
.PHONY : alk/RenderCache.cpp.o

alk/RenderCache.i: alk/RenderCache.cpp.i

.PHONY : alk/RenderCache.i

# target to preprocess a source file
alk/RenderCache.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/RenderCache.cpp.i
.PHONY : alk/RenderCache.cpp.i

alk/RenderCache.s: alk/RenderCache.cpp.s

.PHONY : alk/RenderCache.s

# target to generate assembly for a file
alk/RenderCache.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/RenderCache.cpp.s
.PHONY : alk/RenderCache.cpp.s

alk/Tile.o: alk/Tile.cpp.o

.PHONY : alk/Tile.o

# target to build an object file
alk/Tile.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Tile.cpp.o
.PHONY : alk/Tile.cpp.o

alk/Tile.i: alk/Tile.cpp.i

.PHONY : alk/Tile.i

# target to preprocess a source file
alk/Tile.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Tile.cpp.i
.PHONY : alk/Tile.cpp.i

alk/Tile.s: alk/Tile.cpp.s

.PHONY : alk/Tile.s

# target to generate assembly for a file
alk/Tile.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/Tile.cpp.s
.PHONY : alk/Tile.cpp.s

alk/TileHandler.o: alk/TileHandler.cpp.o

.PHONY : alk/TileHandler.o

# target to build an object file
alk/TileHandler.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileHandler.cpp.o
.PHONY : alk/TileHandler.cpp.o

alk/TileHandler.i: alk/TileHandler.cpp.i

.PHONY : alk/TileHandler.i

# target to preprocess a source file
alk/TileHandler.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileHandler.cpp.i
.PHONY : alk/TileHandler.cpp.i

alk/TileHandler.s: alk/TileHandler.cpp.s

.PHONY : alk/TileHandler.s

# target to generate assembly for a file
alk/TileHandler.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileHandler.cpp.s
.PHONY : alk/TileHandler.cpp.s

alk/TileLoader.o: alk/TileLoader.cpp.o

.PHONY : alk/TileLoader.o

# target to build an object file
alk/TileLoader.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileLoader.cpp.o
.PHONY : alk/TileLoader.cpp.o

alk/TileLoader.i: alk/TileLoader.cpp.i

.PHONY : alk/TileLoader.i

# target to preprocess a source file
alk/TileLoader.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileLoader.cpp.i
.PHONY : alk/TileLoader.cpp.i

alk/TileLoader.s: alk/TileLoader.cpp.s

.PHONY : alk/TileLoader.s

# target to generate assembly for a file
alk/TileLoader.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileLoader.cpp.s
.PHONY : alk/TileLoader.cpp.s

alk/TilePath.o: alk/TilePath.cpp.o

.PHONY : alk/TilePath.o

# target to build an object file
alk/TilePath.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TilePath.cpp.o
.PHONY : alk/TilePath.cpp.o

alk/TilePath.i: alk/TilePath.cpp.i

.PHONY : alk/TilePath.i

# target to preprocess a source file
alk/TilePath.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TilePath.cpp.i
.PHONY : alk/TilePath.cpp.i

alk/TilePath.s: alk/TilePath.cpp.s

.PHONY : alk/TilePath.s

# target to generate assembly for a file
alk/TilePath.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TilePath.cpp.s
.PHONY : alk/TilePath.cpp.s

alk/TileServer.o: alk/TileServer.cpp.o

.PHONY : alk/TileServer.o

# target to build an object file
alk/TileServer.cpp.o:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileServer.cpp.o
.PHONY : alk/TileServer.cpp.o

alk/TileServer.i: alk/TileServer.cpp.i

.PHONY : alk/TileServer.i

# target to preprocess a source file
alk/TileServer.cpp.i:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileServer.cpp.i
.PHONY : alk/TileServer.cpp.i

alk/TileServer.s: alk/TileServer.cpp.s

.PHONY : alk/TileServer.s

# target to generate assembly for a file
alk/TileServer.cpp.s:
	$(MAKE) -f CMakeFiles/alk-rts.dir/build.make CMakeFiles/alk-rts.dir/alk/TileServer.cpp.s
.PHONY : alk/TileServer.cpp.s

benchmark/api/query.benchmark.o: benchmark/api/query.benchmark.cpp.o

.PHONY : benchmark/api/query.benchmark.o

# target to build an object file
benchmark/api/query.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/api/query.benchmark.cpp.o
.PHONY : benchmark/api/query.benchmark.cpp.o

benchmark/api/query.benchmark.i: benchmark/api/query.benchmark.cpp.i

.PHONY : benchmark/api/query.benchmark.i

# target to preprocess a source file
benchmark/api/query.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/api/query.benchmark.cpp.i
.PHONY : benchmark/api/query.benchmark.cpp.i

benchmark/api/query.benchmark.s: benchmark/api/query.benchmark.cpp.s

.PHONY : benchmark/api/query.benchmark.s

# target to generate assembly for a file
benchmark/api/query.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/api/query.benchmark.cpp.s
.PHONY : benchmark/api/query.benchmark.cpp.s

benchmark/api/render.benchmark.o: benchmark/api/render.benchmark.cpp.o

.PHONY : benchmark/api/render.benchmark.o

# target to build an object file
benchmark/api/render.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/api/render.benchmark.cpp.o
.PHONY : benchmark/api/render.benchmark.cpp.o

benchmark/api/render.benchmark.i: benchmark/api/render.benchmark.cpp.i

.PHONY : benchmark/api/render.benchmark.i

# target to preprocess a source file
benchmark/api/render.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/api/render.benchmark.cpp.i
.PHONY : benchmark/api/render.benchmark.cpp.i

benchmark/api/render.benchmark.s: benchmark/api/render.benchmark.cpp.s

.PHONY : benchmark/api/render.benchmark.s

# target to generate assembly for a file
benchmark/api/render.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/api/render.benchmark.cpp.s
.PHONY : benchmark/api/render.benchmark.cpp.s

benchmark/function/camera_function.benchmark.o: benchmark/function/camera_function.benchmark.cpp.o

.PHONY : benchmark/function/camera_function.benchmark.o

# target to build an object file
benchmark/function/camera_function.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/camera_function.benchmark.cpp.o
.PHONY : benchmark/function/camera_function.benchmark.cpp.o

benchmark/function/camera_function.benchmark.i: benchmark/function/camera_function.benchmark.cpp.i

.PHONY : benchmark/function/camera_function.benchmark.i

# target to preprocess a source file
benchmark/function/camera_function.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/camera_function.benchmark.cpp.i
.PHONY : benchmark/function/camera_function.benchmark.cpp.i

benchmark/function/camera_function.benchmark.s: benchmark/function/camera_function.benchmark.cpp.s

.PHONY : benchmark/function/camera_function.benchmark.s

# target to generate assembly for a file
benchmark/function/camera_function.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/camera_function.benchmark.cpp.s
.PHONY : benchmark/function/camera_function.benchmark.cpp.s

benchmark/function/composite_function.benchmark.o: benchmark/function/composite_function.benchmark.cpp.o

.PHONY : benchmark/function/composite_function.benchmark.o

# target to build an object file
benchmark/function/composite_function.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/composite_function.benchmark.cpp.o
.PHONY : benchmark/function/composite_function.benchmark.cpp.o

benchmark/function/composite_function.benchmark.i: benchmark/function/composite_function.benchmark.cpp.i

.PHONY : benchmark/function/composite_function.benchmark.i

# target to preprocess a source file
benchmark/function/composite_function.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/composite_function.benchmark.cpp.i
.PHONY : benchmark/function/composite_function.benchmark.cpp.i

benchmark/function/composite_function.benchmark.s: benchmark/function/composite_function.benchmark.cpp.s

.PHONY : benchmark/function/composite_function.benchmark.s

# target to generate assembly for a file
benchmark/function/composite_function.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/composite_function.benchmark.cpp.s
.PHONY : benchmark/function/composite_function.benchmark.cpp.s

benchmark/function/source_function.benchmark.o: benchmark/function/source_function.benchmark.cpp.o

.PHONY : benchmark/function/source_function.benchmark.o

# target to build an object file
benchmark/function/source_function.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/source_function.benchmark.cpp.o
.PHONY : benchmark/function/source_function.benchmark.cpp.o

benchmark/function/source_function.benchmark.i: benchmark/function/source_function.benchmark.cpp.i

.PHONY : benchmark/function/source_function.benchmark.i

# target to preprocess a source file
benchmark/function/source_function.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/source_function.benchmark.cpp.i
.PHONY : benchmark/function/source_function.benchmark.cpp.i

benchmark/function/source_function.benchmark.s: benchmark/function/source_function.benchmark.cpp.s

.PHONY : benchmark/function/source_function.benchmark.s

# target to generate assembly for a file
benchmark/function/source_function.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/function/source_function.benchmark.cpp.s
.PHONY : benchmark/function/source_function.benchmark.cpp.s

benchmark/parse/filter.benchmark.o: benchmark/parse/filter.benchmark.cpp.o

.PHONY : benchmark/parse/filter.benchmark.o

# target to build an object file
benchmark/parse/filter.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/filter.benchmark.cpp.o
.PHONY : benchmark/parse/filter.benchmark.cpp.o

benchmark/parse/filter.benchmark.i: benchmark/parse/filter.benchmark.cpp.i

.PHONY : benchmark/parse/filter.benchmark.i

# target to preprocess a source file
benchmark/parse/filter.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/filter.benchmark.cpp.i
.PHONY : benchmark/parse/filter.benchmark.cpp.i

benchmark/parse/filter.benchmark.s: benchmark/parse/filter.benchmark.cpp.s

.PHONY : benchmark/parse/filter.benchmark.s

# target to generate assembly for a file
benchmark/parse/filter.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/filter.benchmark.cpp.s
.PHONY : benchmark/parse/filter.benchmark.cpp.s

benchmark/parse/tile_mask.benchmark.o: benchmark/parse/tile_mask.benchmark.cpp.o

.PHONY : benchmark/parse/tile_mask.benchmark.o

# target to build an object file
benchmark/parse/tile_mask.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/tile_mask.benchmark.cpp.o
.PHONY : benchmark/parse/tile_mask.benchmark.cpp.o

benchmark/parse/tile_mask.benchmark.i: benchmark/parse/tile_mask.benchmark.cpp.i

.PHONY : benchmark/parse/tile_mask.benchmark.i

# target to preprocess a source file
benchmark/parse/tile_mask.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/tile_mask.benchmark.cpp.i
.PHONY : benchmark/parse/tile_mask.benchmark.cpp.i

benchmark/parse/tile_mask.benchmark.s: benchmark/parse/tile_mask.benchmark.cpp.s

.PHONY : benchmark/parse/tile_mask.benchmark.s

# target to generate assembly for a file
benchmark/parse/tile_mask.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/tile_mask.benchmark.cpp.s
.PHONY : benchmark/parse/tile_mask.benchmark.cpp.s

benchmark/parse/vector_tile.benchmark.o: benchmark/parse/vector_tile.benchmark.cpp.o

.PHONY : benchmark/parse/vector_tile.benchmark.o

# target to build an object file
benchmark/parse/vector_tile.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/vector_tile.benchmark.cpp.o
.PHONY : benchmark/parse/vector_tile.benchmark.cpp.o

benchmark/parse/vector_tile.benchmark.i: benchmark/parse/vector_tile.benchmark.cpp.i

.PHONY : benchmark/parse/vector_tile.benchmark.i

# target to preprocess a source file
benchmark/parse/vector_tile.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/vector_tile.benchmark.cpp.i
.PHONY : benchmark/parse/vector_tile.benchmark.cpp.i

benchmark/parse/vector_tile.benchmark.s: benchmark/parse/vector_tile.benchmark.cpp.s

.PHONY : benchmark/parse/vector_tile.benchmark.s

# target to generate assembly for a file
benchmark/parse/vector_tile.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/parse/vector_tile.benchmark.cpp.s
.PHONY : benchmark/parse/vector_tile.benchmark.cpp.s

benchmark/src/main.o: benchmark/src/main.cpp.o

.PHONY : benchmark/src/main.o

# target to build an object file
benchmark/src/main.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/src/main.cpp.o
.PHONY : benchmark/src/main.cpp.o

benchmark/src/main.i: benchmark/src/main.cpp.i

.PHONY : benchmark/src/main.i

# target to preprocess a source file
benchmark/src/main.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/src/main.cpp.i
.PHONY : benchmark/src/main.cpp.i

benchmark/src/main.s: benchmark/src/main.cpp.s

.PHONY : benchmark/src/main.s

# target to generate assembly for a file
benchmark/src/main.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/src/main.cpp.s
.PHONY : benchmark/src/main.cpp.s

benchmark/src/mbgl/benchmark/benchmark.o: benchmark/src/mbgl/benchmark/benchmark.cpp.o

.PHONY : benchmark/src/mbgl/benchmark/benchmark.o

# target to build an object file
benchmark/src/mbgl/benchmark/benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/src/mbgl/benchmark/benchmark.cpp.o
.PHONY : benchmark/src/mbgl/benchmark/benchmark.cpp.o

benchmark/src/mbgl/benchmark/benchmark.i: benchmark/src/mbgl/benchmark/benchmark.cpp.i

.PHONY : benchmark/src/mbgl/benchmark/benchmark.i

# target to preprocess a source file
benchmark/src/mbgl/benchmark/benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/src/mbgl/benchmark/benchmark.cpp.i
.PHONY : benchmark/src/mbgl/benchmark/benchmark.cpp.i

benchmark/src/mbgl/benchmark/benchmark.s: benchmark/src/mbgl/benchmark/benchmark.cpp.s

.PHONY : benchmark/src/mbgl/benchmark/benchmark.s

# target to generate assembly for a file
benchmark/src/mbgl/benchmark/benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/src/mbgl/benchmark/benchmark.cpp.s
.PHONY : benchmark/src/mbgl/benchmark/benchmark.cpp.s

benchmark/util/dtoa.benchmark.o: benchmark/util/dtoa.benchmark.cpp.o

.PHONY : benchmark/util/dtoa.benchmark.o

# target to build an object file
benchmark/util/dtoa.benchmark.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/util/dtoa.benchmark.cpp.o
.PHONY : benchmark/util/dtoa.benchmark.cpp.o

benchmark/util/dtoa.benchmark.i: benchmark/util/dtoa.benchmark.cpp.i

.PHONY : benchmark/util/dtoa.benchmark.i

# target to preprocess a source file
benchmark/util/dtoa.benchmark.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/util/dtoa.benchmark.cpp.i
.PHONY : benchmark/util/dtoa.benchmark.cpp.i

benchmark/util/dtoa.benchmark.s: benchmark/util/dtoa.benchmark.cpp.s

.PHONY : benchmark/util/dtoa.benchmark.s

# target to generate assembly for a file
benchmark/util/dtoa.benchmark.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-benchmark.dir/build.make CMakeFiles/mbgl-benchmark.dir/benchmark/util/dtoa.benchmark.cpp.s
.PHONY : benchmark/util/dtoa.benchmark.cpp.s

bin/offline.o: bin/offline.cpp.o

.PHONY : bin/offline.o

# target to build an object file
bin/offline.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-offline.dir/build.make CMakeFiles/mbgl-offline.dir/bin/offline.cpp.o
.PHONY : bin/offline.cpp.o

bin/offline.i: bin/offline.cpp.i

.PHONY : bin/offline.i

# target to preprocess a source file
bin/offline.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-offline.dir/build.make CMakeFiles/mbgl-offline.dir/bin/offline.cpp.i
.PHONY : bin/offline.cpp.i

bin/offline.s: bin/offline.cpp.s

.PHONY : bin/offline.s

# target to generate assembly for a file
bin/offline.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-offline.dir/build.make CMakeFiles/mbgl-offline.dir/bin/offline.cpp.s
.PHONY : bin/offline.cpp.s

bin/render.o: bin/render.cpp.o

.PHONY : bin/render.o

# target to build an object file
bin/render.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-render.dir/build.make CMakeFiles/mbgl-render.dir/bin/render.cpp.o
.PHONY : bin/render.cpp.o

bin/render.i: bin/render.cpp.i

.PHONY : bin/render.i

# target to preprocess a source file
bin/render.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-render.dir/build.make CMakeFiles/mbgl-render.dir/bin/render.cpp.i
.PHONY : bin/render.cpp.i

bin/render.s: bin/render.cpp.s

.PHONY : bin/render.s

# target to generate assembly for a file
bin/render.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-render.dir/build.make CMakeFiles/mbgl-render.dir/bin/render.cpp.s
.PHONY : bin/render.cpp.s

platform/default/asset_file_source.o: platform/default/asset_file_source.cpp.o

.PHONY : platform/default/asset_file_source.o

# target to build an object file
platform/default/asset_file_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/asset_file_source.cpp.o
.PHONY : platform/default/asset_file_source.cpp.o

platform/default/asset_file_source.i: platform/default/asset_file_source.cpp.i

.PHONY : platform/default/asset_file_source.i

# target to preprocess a source file
platform/default/asset_file_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/asset_file_source.cpp.i
.PHONY : platform/default/asset_file_source.cpp.i

platform/default/asset_file_source.s: platform/default/asset_file_source.cpp.s

.PHONY : platform/default/asset_file_source.s

# target to generate assembly for a file
platform/default/asset_file_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/asset_file_source.cpp.s
.PHONY : platform/default/asset_file_source.cpp.s

platform/default/async_task.o: platform/default/async_task.cpp.o

.PHONY : platform/default/async_task.o

# target to build an object file
platform/default/async_task.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/async_task.cpp.o
.PHONY : platform/default/async_task.cpp.o

platform/default/async_task.i: platform/default/async_task.cpp.i

.PHONY : platform/default/async_task.i

# target to preprocess a source file
platform/default/async_task.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/async_task.cpp.i
.PHONY : platform/default/async_task.cpp.i

platform/default/async_task.s: platform/default/async_task.cpp.s

.PHONY : platform/default/async_task.s

# target to generate assembly for a file
platform/default/async_task.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/async_task.cpp.s
.PHONY : platform/default/async_task.cpp.s

platform/default/bidi.o: platform/default/bidi.cpp.o

.PHONY : platform/default/bidi.o

# target to build an object file
platform/default/bidi.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/bidi.cpp.o
.PHONY : platform/default/bidi.cpp.o

platform/default/bidi.i: platform/default/bidi.cpp.i

.PHONY : platform/default/bidi.i

# target to preprocess a source file
platform/default/bidi.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/bidi.cpp.i
.PHONY : platform/default/bidi.cpp.i

platform/default/bidi.s: platform/default/bidi.cpp.s

.PHONY : platform/default/bidi.s

# target to generate assembly for a file
platform/default/bidi.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/bidi.cpp.s
.PHONY : platform/default/bidi.cpp.s

platform/default/default_file_source.o: platform/default/default_file_source.cpp.o

.PHONY : platform/default/default_file_source.o

# target to build an object file
platform/default/default_file_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/default_file_source.cpp.o
.PHONY : platform/default/default_file_source.cpp.o

platform/default/default_file_source.i: platform/default/default_file_source.cpp.i

.PHONY : platform/default/default_file_source.i

# target to preprocess a source file
platform/default/default_file_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/default_file_source.cpp.i
.PHONY : platform/default/default_file_source.cpp.i

platform/default/default_file_source.s: platform/default/default_file_source.cpp.s

.PHONY : platform/default/default_file_source.s

# target to generate assembly for a file
platform/default/default_file_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/default_file_source.cpp.s
.PHONY : platform/default/default_file_source.cpp.s

platform/default/file_source_request.o: platform/default/file_source_request.cpp.o

.PHONY : platform/default/file_source_request.o

# target to build an object file
platform/default/file_source_request.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/file_source_request.cpp.o
.PHONY : platform/default/file_source_request.cpp.o

platform/default/file_source_request.i: platform/default/file_source_request.cpp.i

.PHONY : platform/default/file_source_request.i

# target to preprocess a source file
platform/default/file_source_request.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/file_source_request.cpp.i
.PHONY : platform/default/file_source_request.cpp.i

platform/default/file_source_request.s: platform/default/file_source_request.cpp.s

.PHONY : platform/default/file_source_request.s

# target to generate assembly for a file
platform/default/file_source_request.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/file_source_request.cpp.s
.PHONY : platform/default/file_source_request.cpp.s

platform/default/http_file_source.o: platform/default/http_file_source.cpp.o

.PHONY : platform/default/http_file_source.o

# target to build an object file
platform/default/http_file_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/http_file_source.cpp.o
.PHONY : platform/default/http_file_source.cpp.o

platform/default/http_file_source.i: platform/default/http_file_source.cpp.i

.PHONY : platform/default/http_file_source.i

# target to preprocess a source file
platform/default/http_file_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/http_file_source.cpp.i
.PHONY : platform/default/http_file_source.cpp.i

platform/default/http_file_source.s: platform/default/http_file_source.cpp.s

.PHONY : platform/default/http_file_source.s

# target to generate assembly for a file
platform/default/http_file_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/http_file_source.cpp.s
.PHONY : platform/default/http_file_source.cpp.s

platform/default/image.o: platform/default/image.cpp.o

.PHONY : platform/default/image.o

# target to build an object file
platform/default/image.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/image.cpp.o
.PHONY : platform/default/image.cpp.o

platform/default/image.i: platform/default/image.cpp.i

.PHONY : platform/default/image.i

# target to preprocess a source file
platform/default/image.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/image.cpp.i
.PHONY : platform/default/image.cpp.i

platform/default/image.s: platform/default/image.cpp.s

.PHONY : platform/default/image.s

# target to generate assembly for a file
platform/default/image.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/image.cpp.s
.PHONY : platform/default/image.cpp.s

platform/default/jpeg_reader.o: platform/default/jpeg_reader.cpp.o

.PHONY : platform/default/jpeg_reader.o

# target to build an object file
platform/default/jpeg_reader.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/jpeg_reader.cpp.o
.PHONY : platform/default/jpeg_reader.cpp.o

platform/default/jpeg_reader.i: platform/default/jpeg_reader.cpp.i

.PHONY : platform/default/jpeg_reader.i

# target to preprocess a source file
platform/default/jpeg_reader.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/jpeg_reader.cpp.i
.PHONY : platform/default/jpeg_reader.cpp.i

platform/default/jpeg_reader.s: platform/default/jpeg_reader.cpp.s

.PHONY : platform/default/jpeg_reader.s

# target to generate assembly for a file
platform/default/jpeg_reader.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/jpeg_reader.cpp.s
.PHONY : platform/default/jpeg_reader.cpp.s

platform/default/local_file_source.o: platform/default/local_file_source.cpp.o

.PHONY : platform/default/local_file_source.o

# target to build an object file
platform/default/local_file_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/local_file_source.cpp.o
.PHONY : platform/default/local_file_source.cpp.o

platform/default/local_file_source.i: platform/default/local_file_source.cpp.i

.PHONY : platform/default/local_file_source.i

# target to preprocess a source file
platform/default/local_file_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/local_file_source.cpp.i
.PHONY : platform/default/local_file_source.cpp.i

platform/default/local_file_source.s: platform/default/local_file_source.cpp.s

.PHONY : platform/default/local_file_source.s

# target to generate assembly for a file
platform/default/local_file_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/local_file_source.cpp.s
.PHONY : platform/default/local_file_source.cpp.s

platform/default/logging_stderr.o: platform/default/logging_stderr.cpp.o

.PHONY : platform/default/logging_stderr.o

# target to build an object file
platform/default/logging_stderr.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/logging_stderr.cpp.o
.PHONY : platform/default/logging_stderr.cpp.o

platform/default/logging_stderr.i: platform/default/logging_stderr.cpp.i

.PHONY : platform/default/logging_stderr.i

# target to preprocess a source file
platform/default/logging_stderr.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/logging_stderr.cpp.i
.PHONY : platform/default/logging_stderr.cpp.i

platform/default/logging_stderr.s: platform/default/logging_stderr.cpp.s

.PHONY : platform/default/logging_stderr.s

# target to generate assembly for a file
platform/default/logging_stderr.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/logging_stderr.cpp.s
.PHONY : platform/default/logging_stderr.cpp.s

platform/default/mbgl/gl/headless_backend.o: platform/default/mbgl/gl/headless_backend.cpp.o

.PHONY : platform/default/mbgl/gl/headless_backend.o

# target to build an object file
platform/default/mbgl/gl/headless_backend.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/gl/headless_backend.cpp.o
.PHONY : platform/default/mbgl/gl/headless_backend.cpp.o

platform/default/mbgl/gl/headless_backend.i: platform/default/mbgl/gl/headless_backend.cpp.i

.PHONY : platform/default/mbgl/gl/headless_backend.i

# target to preprocess a source file
platform/default/mbgl/gl/headless_backend.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/gl/headless_backend.cpp.i
.PHONY : platform/default/mbgl/gl/headless_backend.cpp.i

platform/default/mbgl/gl/headless_backend.s: platform/default/mbgl/gl/headless_backend.cpp.s

.PHONY : platform/default/mbgl/gl/headless_backend.s

# target to generate assembly for a file
platform/default/mbgl/gl/headless_backend.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/gl/headless_backend.cpp.s
.PHONY : platform/default/mbgl/gl/headless_backend.cpp.s

platform/default/mbgl/gl/headless_frontend.o: platform/default/mbgl/gl/headless_frontend.cpp.o

.PHONY : platform/default/mbgl/gl/headless_frontend.o

# target to build an object file
platform/default/mbgl/gl/headless_frontend.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/gl/headless_frontend.cpp.o
.PHONY : platform/default/mbgl/gl/headless_frontend.cpp.o

platform/default/mbgl/gl/headless_frontend.i: platform/default/mbgl/gl/headless_frontend.cpp.i

.PHONY : platform/default/mbgl/gl/headless_frontend.i

# target to preprocess a source file
platform/default/mbgl/gl/headless_frontend.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/gl/headless_frontend.cpp.i
.PHONY : platform/default/mbgl/gl/headless_frontend.cpp.i

platform/default/mbgl/gl/headless_frontend.s: platform/default/mbgl/gl/headless_frontend.cpp.s

.PHONY : platform/default/mbgl/gl/headless_frontend.s

# target to generate assembly for a file
platform/default/mbgl/gl/headless_frontend.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/gl/headless_frontend.cpp.s
.PHONY : platform/default/mbgl/gl/headless_frontend.cpp.s

platform/default/mbgl/storage/offline.o: platform/default/mbgl/storage/offline.cpp.o

.PHONY : platform/default/mbgl/storage/offline.o

# target to build an object file
platform/default/mbgl/storage/offline.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline.cpp.o
.PHONY : platform/default/mbgl/storage/offline.cpp.o

platform/default/mbgl/storage/offline.i: platform/default/mbgl/storage/offline.cpp.i

.PHONY : platform/default/mbgl/storage/offline.i

# target to preprocess a source file
platform/default/mbgl/storage/offline.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline.cpp.i
.PHONY : platform/default/mbgl/storage/offline.cpp.i

platform/default/mbgl/storage/offline.s: platform/default/mbgl/storage/offline.cpp.s

.PHONY : platform/default/mbgl/storage/offline.s

# target to generate assembly for a file
platform/default/mbgl/storage/offline.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline.cpp.s
.PHONY : platform/default/mbgl/storage/offline.cpp.s

platform/default/mbgl/storage/offline_database.o: platform/default/mbgl/storage/offline_database.cpp.o

.PHONY : platform/default/mbgl/storage/offline_database.o

# target to build an object file
platform/default/mbgl/storage/offline_database.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline_database.cpp.o
.PHONY : platform/default/mbgl/storage/offline_database.cpp.o

platform/default/mbgl/storage/offline_database.i: platform/default/mbgl/storage/offline_database.cpp.i

.PHONY : platform/default/mbgl/storage/offline_database.i

# target to preprocess a source file
platform/default/mbgl/storage/offline_database.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline_database.cpp.i
.PHONY : platform/default/mbgl/storage/offline_database.cpp.i

platform/default/mbgl/storage/offline_database.s: platform/default/mbgl/storage/offline_database.cpp.s

.PHONY : platform/default/mbgl/storage/offline_database.s

# target to generate assembly for a file
platform/default/mbgl/storage/offline_database.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline_database.cpp.s
.PHONY : platform/default/mbgl/storage/offline_database.cpp.s

platform/default/mbgl/storage/offline_download.o: platform/default/mbgl/storage/offline_download.cpp.o

.PHONY : platform/default/mbgl/storage/offline_download.o

# target to build an object file
platform/default/mbgl/storage/offline_download.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline_download.cpp.o
.PHONY : platform/default/mbgl/storage/offline_download.cpp.o

platform/default/mbgl/storage/offline_download.i: platform/default/mbgl/storage/offline_download.cpp.i

.PHONY : platform/default/mbgl/storage/offline_download.i

# target to preprocess a source file
platform/default/mbgl/storage/offline_download.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline_download.cpp.i
.PHONY : platform/default/mbgl/storage/offline_download.cpp.i

platform/default/mbgl/storage/offline_download.s: platform/default/mbgl/storage/offline_download.cpp.s

.PHONY : platform/default/mbgl/storage/offline_download.s

# target to generate assembly for a file
platform/default/mbgl/storage/offline_download.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/mbgl/storage/offline_download.cpp.s
.PHONY : platform/default/mbgl/storage/offline_download.cpp.s

platform/default/mbgl/test/main.o: platform/default/mbgl/test/main.cpp.o

.PHONY : platform/default/mbgl/test/main.o

# target to build an object file
platform/default/mbgl/test/main.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/platform/default/mbgl/test/main.cpp.o
.PHONY : platform/default/mbgl/test/main.cpp.o

platform/default/mbgl/test/main.i: platform/default/mbgl/test/main.cpp.i

.PHONY : platform/default/mbgl/test/main.i

# target to preprocess a source file
platform/default/mbgl/test/main.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/platform/default/mbgl/test/main.cpp.i
.PHONY : platform/default/mbgl/test/main.cpp.i

platform/default/mbgl/test/main.s: platform/default/mbgl/test/main.cpp.s

.PHONY : platform/default/mbgl/test/main.s

# target to generate assembly for a file
platform/default/mbgl/test/main.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/platform/default/mbgl/test/main.cpp.s
.PHONY : platform/default/mbgl/test/main.cpp.s

platform/default/mbgl/util/default_thread_pool.o: platform/default/mbgl/util/default_thread_pool.cpp.o

.PHONY : platform/default/mbgl/util/default_thread_pool.o

# target to build an object file
platform/default/mbgl/util/default_thread_pool.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/util/default_thread_pool.cpp.o
.PHONY : platform/default/mbgl/util/default_thread_pool.cpp.o

platform/default/mbgl/util/default_thread_pool.i: platform/default/mbgl/util/default_thread_pool.cpp.i

.PHONY : platform/default/mbgl/util/default_thread_pool.i

# target to preprocess a source file
platform/default/mbgl/util/default_thread_pool.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/util/default_thread_pool.cpp.i
.PHONY : platform/default/mbgl/util/default_thread_pool.cpp.i

platform/default/mbgl/util/default_thread_pool.s: platform/default/mbgl/util/default_thread_pool.cpp.s

.PHONY : platform/default/mbgl/util/default_thread_pool.s

# target to generate assembly for a file
platform/default/mbgl/util/default_thread_pool.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/util/default_thread_pool.cpp.s
.PHONY : platform/default/mbgl/util/default_thread_pool.cpp.s

platform/default/mbgl/util/shared_thread_pool.o: platform/default/mbgl/util/shared_thread_pool.cpp.o

.PHONY : platform/default/mbgl/util/shared_thread_pool.o

# target to build an object file
platform/default/mbgl/util/shared_thread_pool.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/util/shared_thread_pool.cpp.o
.PHONY : platform/default/mbgl/util/shared_thread_pool.cpp.o

platform/default/mbgl/util/shared_thread_pool.i: platform/default/mbgl/util/shared_thread_pool.cpp.i

.PHONY : platform/default/mbgl/util/shared_thread_pool.i

# target to preprocess a source file
platform/default/mbgl/util/shared_thread_pool.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/util/shared_thread_pool.cpp.i
.PHONY : platform/default/mbgl/util/shared_thread_pool.cpp.i

platform/default/mbgl/util/shared_thread_pool.s: platform/default/mbgl/util/shared_thread_pool.cpp.s

.PHONY : platform/default/mbgl/util/shared_thread_pool.s

# target to generate assembly for a file
platform/default/mbgl/util/shared_thread_pool.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/mbgl/util/shared_thread_pool.cpp.s
.PHONY : platform/default/mbgl/util/shared_thread_pool.cpp.s

platform/default/online_file_source.o: platform/default/online_file_source.cpp.o

.PHONY : platform/default/online_file_source.o

# target to build an object file
platform/default/online_file_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/online_file_source.cpp.o
.PHONY : platform/default/online_file_source.cpp.o

platform/default/online_file_source.i: platform/default/online_file_source.cpp.i

.PHONY : platform/default/online_file_source.i

# target to preprocess a source file
platform/default/online_file_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/online_file_source.cpp.i
.PHONY : platform/default/online_file_source.cpp.i

platform/default/online_file_source.s: platform/default/online_file_source.cpp.s

.PHONY : platform/default/online_file_source.s

# target to generate assembly for a file
platform/default/online_file_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/online_file_source.cpp.s
.PHONY : platform/default/online_file_source.cpp.s

platform/default/png_reader.o: platform/default/png_reader.cpp.o

.PHONY : platform/default/png_reader.o

# target to build an object file
platform/default/png_reader.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/png_reader.cpp.o
.PHONY : platform/default/png_reader.cpp.o

platform/default/png_reader.i: platform/default/png_reader.cpp.i

.PHONY : platform/default/png_reader.i

# target to preprocess a source file
platform/default/png_reader.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/png_reader.cpp.i
.PHONY : platform/default/png_reader.cpp.i

platform/default/png_reader.s: platform/default/png_reader.cpp.s

.PHONY : platform/default/png_reader.s

# target to generate assembly for a file
platform/default/png_reader.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/png_reader.cpp.s
.PHONY : platform/default/png_reader.cpp.s

platform/default/png_writer.o: platform/default/png_writer.cpp.o

.PHONY : platform/default/png_writer.o

# target to build an object file
platform/default/png_writer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/png_writer.cpp.o
.PHONY : platform/default/png_writer.cpp.o

platform/default/png_writer.i: platform/default/png_writer.cpp.i

.PHONY : platform/default/png_writer.i

# target to preprocess a source file
platform/default/png_writer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/png_writer.cpp.i
.PHONY : platform/default/png_writer.cpp.i

platform/default/png_writer.s: platform/default/png_writer.cpp.s

.PHONY : platform/default/png_writer.s

# target to generate assembly for a file
platform/default/png_writer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/png_writer.cpp.s
.PHONY : platform/default/png_writer.cpp.s

platform/default/run_loop.o: platform/default/run_loop.cpp.o

.PHONY : platform/default/run_loop.o

# target to build an object file
platform/default/run_loop.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/run_loop.cpp.o
.PHONY : platform/default/run_loop.cpp.o

platform/default/run_loop.i: platform/default/run_loop.cpp.i

.PHONY : platform/default/run_loop.i

# target to preprocess a source file
platform/default/run_loop.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/run_loop.cpp.i
.PHONY : platform/default/run_loop.cpp.i

platform/default/run_loop.s: platform/default/run_loop.cpp.s

.PHONY : platform/default/run_loop.s

# target to generate assembly for a file
platform/default/run_loop.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/run_loop.cpp.s
.PHONY : platform/default/run_loop.cpp.s

platform/default/sqlite3.o: platform/default/sqlite3.cpp.o

.PHONY : platform/default/sqlite3.o

# target to build an object file
platform/default/sqlite3.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/sqlite3.cpp.o
.PHONY : platform/default/sqlite3.cpp.o

platform/default/sqlite3.i: platform/default/sqlite3.cpp.i

.PHONY : platform/default/sqlite3.i

# target to preprocess a source file
platform/default/sqlite3.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/sqlite3.cpp.i
.PHONY : platform/default/sqlite3.cpp.i

platform/default/sqlite3.s: platform/default/sqlite3.cpp.s

.PHONY : platform/default/sqlite3.s

# target to generate assembly for a file
platform/default/sqlite3.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-filesource.dir/build.make CMakeFiles/mbgl-filesource.dir/platform/default/sqlite3.cpp.s
.PHONY : platform/default/sqlite3.cpp.s

platform/default/string_stdlib.o: platform/default/string_stdlib.cpp.o

.PHONY : platform/default/string_stdlib.o

# target to build an object file
platform/default/string_stdlib.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/string_stdlib.cpp.o
.PHONY : platform/default/string_stdlib.cpp.o

platform/default/string_stdlib.i: platform/default/string_stdlib.cpp.i

.PHONY : platform/default/string_stdlib.i

# target to preprocess a source file
platform/default/string_stdlib.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/string_stdlib.cpp.i
.PHONY : platform/default/string_stdlib.cpp.i

platform/default/string_stdlib.s: platform/default/string_stdlib.cpp.s

.PHONY : platform/default/string_stdlib.s

# target to generate assembly for a file
platform/default/string_stdlib.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/string_stdlib.cpp.s
.PHONY : platform/default/string_stdlib.cpp.s

platform/default/thread.o: platform/default/thread.cpp.o

.PHONY : platform/default/thread.o

# target to build an object file
platform/default/thread.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/thread.cpp.o
.PHONY : platform/default/thread.cpp.o

platform/default/thread.i: platform/default/thread.cpp.i

.PHONY : platform/default/thread.i

# target to preprocess a source file
platform/default/thread.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/thread.cpp.i
.PHONY : platform/default/thread.cpp.i

platform/default/thread.s: platform/default/thread.cpp.s

.PHONY : platform/default/thread.s

# target to generate assembly for a file
platform/default/thread.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/thread.cpp.s
.PHONY : platform/default/thread.cpp.s

platform/default/thread_local.o: platform/default/thread_local.cpp.o

.PHONY : platform/default/thread_local.o

# target to build an object file
platform/default/thread_local.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/thread_local.cpp.o
.PHONY : platform/default/thread_local.cpp.o

platform/default/thread_local.i: platform/default/thread_local.cpp.i

.PHONY : platform/default/thread_local.i

# target to preprocess a source file
platform/default/thread_local.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/thread_local.cpp.i
.PHONY : platform/default/thread_local.cpp.i

platform/default/thread_local.s: platform/default/thread_local.cpp.s

.PHONY : platform/default/thread_local.s

# target to generate assembly for a file
platform/default/thread_local.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/thread_local.cpp.s
.PHONY : platform/default/thread_local.cpp.s

platform/default/timer.o: platform/default/timer.cpp.o

.PHONY : platform/default/timer.o

# target to build an object file
platform/default/timer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/timer.cpp.o
.PHONY : platform/default/timer.cpp.o

platform/default/timer.i: platform/default/timer.cpp.i

.PHONY : platform/default/timer.i

# target to preprocess a source file
platform/default/timer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/timer.cpp.i
.PHONY : platform/default/timer.cpp.i

platform/default/timer.s: platform/default/timer.cpp.s

.PHONY : platform/default/timer.s

# target to generate assembly for a file
platform/default/timer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-loop-uv.dir/build.make CMakeFiles/mbgl-loop-uv.dir/platform/default/timer.cpp.s
.PHONY : platform/default/timer.cpp.s

platform/default/utf.o: platform/default/utf.cpp.o

.PHONY : platform/default/utf.o

# target to build an object file
platform/default/utf.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/utf.cpp.o
.PHONY : platform/default/utf.cpp.o

platform/default/utf.i: platform/default/utf.cpp.i

.PHONY : platform/default/utf.i

# target to preprocess a source file
platform/default/utf.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/utf.cpp.i
.PHONY : platform/default/utf.cpp.i

platform/default/utf.s: platform/default/utf.cpp.s

.PHONY : platform/default/utf.s

# target to generate assembly for a file
platform/default/utf.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/utf.cpp.s
.PHONY : platform/default/utf.cpp.s

platform/default/webp_reader.o: platform/default/webp_reader.cpp.o

.PHONY : platform/default/webp_reader.o

# target to build an object file
platform/default/webp_reader.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/webp_reader.cpp.o
.PHONY : platform/default/webp_reader.cpp.o

platform/default/webp_reader.i: platform/default/webp_reader.cpp.i

.PHONY : platform/default/webp_reader.i

# target to preprocess a source file
platform/default/webp_reader.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/webp_reader.cpp.i
.PHONY : platform/default/webp_reader.cpp.i

platform/default/webp_reader.s: platform/default/webp_reader.cpp.s

.PHONY : platform/default/webp_reader.s

# target to generate assembly for a file
platform/default/webp_reader.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/default/webp_reader.cpp.s
.PHONY : platform/default/webp_reader.cpp.s

platform/glfw/glfw_renderer_frontend.o: platform/glfw/glfw_renderer_frontend.cpp.o

.PHONY : platform/glfw/glfw_renderer_frontend.o

# target to build an object file
platform/glfw/glfw_renderer_frontend.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/glfw_renderer_frontend.cpp.o
.PHONY : platform/glfw/glfw_renderer_frontend.cpp.o

platform/glfw/glfw_renderer_frontend.i: platform/glfw/glfw_renderer_frontend.cpp.i

.PHONY : platform/glfw/glfw_renderer_frontend.i

# target to preprocess a source file
platform/glfw/glfw_renderer_frontend.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/glfw_renderer_frontend.cpp.i
.PHONY : platform/glfw/glfw_renderer_frontend.cpp.i

platform/glfw/glfw_renderer_frontend.s: platform/glfw/glfw_renderer_frontend.cpp.s

.PHONY : platform/glfw/glfw_renderer_frontend.s

# target to generate assembly for a file
platform/glfw/glfw_renderer_frontend.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/glfw_renderer_frontend.cpp.s
.PHONY : platform/glfw/glfw_renderer_frontend.cpp.s

platform/glfw/glfw_view.o: platform/glfw/glfw_view.cpp.o

.PHONY : platform/glfw/glfw_view.o

# target to build an object file
platform/glfw/glfw_view.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/glfw_view.cpp.o
.PHONY : platform/glfw/glfw_view.cpp.o

platform/glfw/glfw_view.i: platform/glfw/glfw_view.cpp.i

.PHONY : platform/glfw/glfw_view.i

# target to preprocess a source file
platform/glfw/glfw_view.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/glfw_view.cpp.i
.PHONY : platform/glfw/glfw_view.cpp.i

platform/glfw/glfw_view.s: platform/glfw/glfw_view.cpp.s

.PHONY : platform/glfw/glfw_view.s

# target to generate assembly for a file
platform/glfw/glfw_view.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/glfw_view.cpp.s
.PHONY : platform/glfw/glfw_view.cpp.s

platform/glfw/main.o: platform/glfw/main.cpp.o

.PHONY : platform/glfw/main.o

# target to build an object file
platform/glfw/main.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/main.cpp.o
.PHONY : platform/glfw/main.cpp.o

platform/glfw/main.i: platform/glfw/main.cpp.i

.PHONY : platform/glfw/main.i

# target to preprocess a source file
platform/glfw/main.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/main.cpp.i
.PHONY : platform/glfw/main.cpp.i

platform/glfw/main.s: platform/glfw/main.cpp.s

.PHONY : platform/glfw/main.s

# target to generate assembly for a file
platform/glfw/main.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/main.cpp.s
.PHONY : platform/glfw/main.cpp.s

platform/glfw/settings_json.o: platform/glfw/settings_json.cpp.o

.PHONY : platform/glfw/settings_json.o

# target to build an object file
platform/glfw/settings_json.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/settings_json.cpp.o
.PHONY : platform/glfw/settings_json.cpp.o

platform/glfw/settings_json.i: platform/glfw/settings_json.cpp.i

.PHONY : platform/glfw/settings_json.i

# target to preprocess a source file
platform/glfw/settings_json.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/settings_json.cpp.i
.PHONY : platform/glfw/settings_json.cpp.i

platform/glfw/settings_json.s: platform/glfw/settings_json.cpp.s

.PHONY : platform/glfw/settings_json.s

# target to generate assembly for a file
platform/glfw/settings_json.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-glfw.dir/build.make CMakeFiles/mbgl-glfw.dir/platform/glfw/settings_json.cpp.s
.PHONY : platform/glfw/settings_json.cpp.s

platform/linux/src/headless_backend_glx.o: platform/linux/src/headless_backend_glx.cpp.o

.PHONY : platform/linux/src/headless_backend_glx.o

# target to build an object file
platform/linux/src/headless_backend_glx.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/linux/src/headless_backend_glx.cpp.o
.PHONY : platform/linux/src/headless_backend_glx.cpp.o

platform/linux/src/headless_backend_glx.i: platform/linux/src/headless_backend_glx.cpp.i

.PHONY : platform/linux/src/headless_backend_glx.i

# target to preprocess a source file
platform/linux/src/headless_backend_glx.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/linux/src/headless_backend_glx.cpp.i
.PHONY : platform/linux/src/headless_backend_glx.cpp.i

platform/linux/src/headless_backend_glx.s: platform/linux/src/headless_backend_glx.cpp.s

.PHONY : platform/linux/src/headless_backend_glx.s

# target to generate assembly for a file
platform/linux/src/headless_backend_glx.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/linux/src/headless_backend_glx.cpp.s
.PHONY : platform/linux/src/headless_backend_glx.cpp.s

platform/linux/src/headless_display_glx.o: platform/linux/src/headless_display_glx.cpp.o

.PHONY : platform/linux/src/headless_display_glx.o

# target to build an object file
platform/linux/src/headless_display_glx.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/linux/src/headless_display_glx.cpp.o
.PHONY : platform/linux/src/headless_display_glx.cpp.o

platform/linux/src/headless_display_glx.i: platform/linux/src/headless_display_glx.cpp.i

.PHONY : platform/linux/src/headless_display_glx.i

# target to preprocess a source file
platform/linux/src/headless_display_glx.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/linux/src/headless_display_glx.cpp.i
.PHONY : platform/linux/src/headless_display_glx.cpp.i

platform/linux/src/headless_display_glx.s: platform/linux/src/headless_display_glx.cpp.s

.PHONY : platform/linux/src/headless_display_glx.s

# target to generate assembly for a file
platform/linux/src/headless_display_glx.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/platform/linux/src/headless_display_glx.cpp.s
.PHONY : platform/linux/src/headless_display_glx.cpp.s

platform/node/src/node_feature.o: platform/node/src/node_feature.cpp.o

.PHONY : platform/node/src/node_feature.o

# target to build an object file
platform/node/src/node_feature.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_feature.cpp.o
.PHONY : platform/node/src/node_feature.cpp.o

platform/node/src/node_feature.i: platform/node/src/node_feature.cpp.i

.PHONY : platform/node/src/node_feature.i

# target to preprocess a source file
platform/node/src/node_feature.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_feature.cpp.i
.PHONY : platform/node/src/node_feature.cpp.i

platform/node/src/node_feature.s: platform/node/src/node_feature.cpp.s

.PHONY : platform/node/src/node_feature.s

# target to generate assembly for a file
platform/node/src/node_feature.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_feature.cpp.s
.PHONY : platform/node/src/node_feature.cpp.s

platform/node/src/node_logging.o: platform/node/src/node_logging.cpp.o

.PHONY : platform/node/src/node_logging.o

# target to build an object file
platform/node/src/node_logging.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_logging.cpp.o
.PHONY : platform/node/src/node_logging.cpp.o

platform/node/src/node_logging.i: platform/node/src/node_logging.cpp.i

.PHONY : platform/node/src/node_logging.i

# target to preprocess a source file
platform/node/src/node_logging.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_logging.cpp.i
.PHONY : platform/node/src/node_logging.cpp.i

platform/node/src/node_logging.s: platform/node/src/node_logging.cpp.s

.PHONY : platform/node/src/node_logging.s

# target to generate assembly for a file
platform/node/src/node_logging.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_logging.cpp.s
.PHONY : platform/node/src/node_logging.cpp.s

platform/node/src/node_map.o: platform/node/src/node_map.cpp.o

.PHONY : platform/node/src/node_map.o

# target to build an object file
platform/node/src/node_map.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_map.cpp.o
.PHONY : platform/node/src/node_map.cpp.o

platform/node/src/node_map.i: platform/node/src/node_map.cpp.i

.PHONY : platform/node/src/node_map.i

# target to preprocess a source file
platform/node/src/node_map.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_map.cpp.i
.PHONY : platform/node/src/node_map.cpp.i

platform/node/src/node_map.s: platform/node/src/node_map.cpp.s

.PHONY : platform/node/src/node_map.s

# target to generate assembly for a file
platform/node/src/node_map.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_map.cpp.s
.PHONY : platform/node/src/node_map.cpp.s

platform/node/src/node_mapbox_gl_native.o: platform/node/src/node_mapbox_gl_native.cpp.o

.PHONY : platform/node/src/node_mapbox_gl_native.o

# target to build an object file
platform/node/src/node_mapbox_gl_native.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_mapbox_gl_native.cpp.o
.PHONY : platform/node/src/node_mapbox_gl_native.cpp.o

platform/node/src/node_mapbox_gl_native.i: platform/node/src/node_mapbox_gl_native.cpp.i

.PHONY : platform/node/src/node_mapbox_gl_native.i

# target to preprocess a source file
platform/node/src/node_mapbox_gl_native.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_mapbox_gl_native.cpp.i
.PHONY : platform/node/src/node_mapbox_gl_native.cpp.i

platform/node/src/node_mapbox_gl_native.s: platform/node/src/node_mapbox_gl_native.cpp.s

.PHONY : platform/node/src/node_mapbox_gl_native.s

# target to generate assembly for a file
platform/node/src/node_mapbox_gl_native.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_mapbox_gl_native.cpp.s
.PHONY : platform/node/src/node_mapbox_gl_native.cpp.s

platform/node/src/node_request.o: platform/node/src/node_request.cpp.o

.PHONY : platform/node/src/node_request.o

# target to build an object file
platform/node/src/node_request.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_request.cpp.o
.PHONY : platform/node/src/node_request.cpp.o

platform/node/src/node_request.i: platform/node/src/node_request.cpp.i

.PHONY : platform/node/src/node_request.i

# target to preprocess a source file
platform/node/src/node_request.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_request.cpp.i
.PHONY : platform/node/src/node_request.cpp.i

platform/node/src/node_request.s: platform/node/src/node_request.cpp.s

.PHONY : platform/node/src/node_request.s

# target to generate assembly for a file
platform/node/src/node_request.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_request.cpp.s
.PHONY : platform/node/src/node_request.cpp.s

platform/node/src/node_thread_pool.o: platform/node/src/node_thread_pool.cpp.o

.PHONY : platform/node/src/node_thread_pool.o

# target to build an object file
platform/node/src/node_thread_pool.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_thread_pool.cpp.o
.PHONY : platform/node/src/node_thread_pool.cpp.o

platform/node/src/node_thread_pool.i: platform/node/src/node_thread_pool.cpp.i

.PHONY : platform/node/src/node_thread_pool.i

# target to preprocess a source file
platform/node/src/node_thread_pool.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_thread_pool.cpp.i
.PHONY : platform/node/src/node_thread_pool.cpp.i

platform/node/src/node_thread_pool.s: platform/node/src/node_thread_pool.cpp.s

.PHONY : platform/node/src/node_thread_pool.s

# target to generate assembly for a file
platform/node/src/node_thread_pool.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-node.dir/build.make CMakeFiles/mbgl-node.dir/platform/node/src/node_thread_pool.cpp.s
.PHONY : platform/node/src/node_thread_pool.cpp.s

src/csscolorparser/csscolorparser.o: src/csscolorparser/csscolorparser.cpp.o

.PHONY : src/csscolorparser/csscolorparser.o

# target to build an object file
src/csscolorparser/csscolorparser.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/csscolorparser/csscolorparser.cpp.o
.PHONY : src/csscolorparser/csscolorparser.cpp.o

src/csscolorparser/csscolorparser.i: src/csscolorparser/csscolorparser.cpp.i

.PHONY : src/csscolorparser/csscolorparser.i

# target to preprocess a source file
src/csscolorparser/csscolorparser.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/csscolorparser/csscolorparser.cpp.i
.PHONY : src/csscolorparser/csscolorparser.cpp.i

src/csscolorparser/csscolorparser.s: src/csscolorparser/csscolorparser.cpp.s

.PHONY : src/csscolorparser/csscolorparser.s

# target to generate assembly for a file
src/csscolorparser/csscolorparser.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/csscolorparser/csscolorparser.cpp.s
.PHONY : src/csscolorparser/csscolorparser.cpp.s

src/mbgl/actor/mailbox.o: src/mbgl/actor/mailbox.cpp.o

.PHONY : src/mbgl/actor/mailbox.o

# target to build an object file
src/mbgl/actor/mailbox.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/actor/mailbox.cpp.o
.PHONY : src/mbgl/actor/mailbox.cpp.o

src/mbgl/actor/mailbox.i: src/mbgl/actor/mailbox.cpp.i

.PHONY : src/mbgl/actor/mailbox.i

# target to preprocess a source file
src/mbgl/actor/mailbox.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/actor/mailbox.cpp.i
.PHONY : src/mbgl/actor/mailbox.cpp.i

src/mbgl/actor/mailbox.s: src/mbgl/actor/mailbox.cpp.s

.PHONY : src/mbgl/actor/mailbox.s

# target to generate assembly for a file
src/mbgl/actor/mailbox.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/actor/mailbox.cpp.s
.PHONY : src/mbgl/actor/mailbox.cpp.s

src/mbgl/actor/scheduler.o: src/mbgl/actor/scheduler.cpp.o

.PHONY : src/mbgl/actor/scheduler.o

# target to build an object file
src/mbgl/actor/scheduler.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/actor/scheduler.cpp.o
.PHONY : src/mbgl/actor/scheduler.cpp.o

src/mbgl/actor/scheduler.i: src/mbgl/actor/scheduler.cpp.i

.PHONY : src/mbgl/actor/scheduler.i

# target to preprocess a source file
src/mbgl/actor/scheduler.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/actor/scheduler.cpp.i
.PHONY : src/mbgl/actor/scheduler.cpp.i

src/mbgl/actor/scheduler.s: src/mbgl/actor/scheduler.cpp.s

.PHONY : src/mbgl/actor/scheduler.s

# target to generate assembly for a file
src/mbgl/actor/scheduler.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/actor/scheduler.cpp.s
.PHONY : src/mbgl/actor/scheduler.cpp.s

src/mbgl/algorithm/generate_clip_ids.o: src/mbgl/algorithm/generate_clip_ids.cpp.o

.PHONY : src/mbgl/algorithm/generate_clip_ids.o

# target to build an object file
src/mbgl/algorithm/generate_clip_ids.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/algorithm/generate_clip_ids.cpp.o
.PHONY : src/mbgl/algorithm/generate_clip_ids.cpp.o

src/mbgl/algorithm/generate_clip_ids.i: src/mbgl/algorithm/generate_clip_ids.cpp.i

.PHONY : src/mbgl/algorithm/generate_clip_ids.i

# target to preprocess a source file
src/mbgl/algorithm/generate_clip_ids.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/algorithm/generate_clip_ids.cpp.i
.PHONY : src/mbgl/algorithm/generate_clip_ids.cpp.i

src/mbgl/algorithm/generate_clip_ids.s: src/mbgl/algorithm/generate_clip_ids.cpp.s

.PHONY : src/mbgl/algorithm/generate_clip_ids.s

# target to generate assembly for a file
src/mbgl/algorithm/generate_clip_ids.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/algorithm/generate_clip_ids.cpp.s
.PHONY : src/mbgl/algorithm/generate_clip_ids.cpp.s

src/mbgl/annotation/annotation_manager.o: src/mbgl/annotation/annotation_manager.cpp.o

.PHONY : src/mbgl/annotation/annotation_manager.o

# target to build an object file
src/mbgl/annotation/annotation_manager.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_manager.cpp.o
.PHONY : src/mbgl/annotation/annotation_manager.cpp.o

src/mbgl/annotation/annotation_manager.i: src/mbgl/annotation/annotation_manager.cpp.i

.PHONY : src/mbgl/annotation/annotation_manager.i

# target to preprocess a source file
src/mbgl/annotation/annotation_manager.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_manager.cpp.i
.PHONY : src/mbgl/annotation/annotation_manager.cpp.i

src/mbgl/annotation/annotation_manager.s: src/mbgl/annotation/annotation_manager.cpp.s

.PHONY : src/mbgl/annotation/annotation_manager.s

# target to generate assembly for a file
src/mbgl/annotation/annotation_manager.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_manager.cpp.s
.PHONY : src/mbgl/annotation/annotation_manager.cpp.s

src/mbgl/annotation/annotation_source.o: src/mbgl/annotation/annotation_source.cpp.o

.PHONY : src/mbgl/annotation/annotation_source.o

# target to build an object file
src/mbgl/annotation/annotation_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_source.cpp.o
.PHONY : src/mbgl/annotation/annotation_source.cpp.o

src/mbgl/annotation/annotation_source.i: src/mbgl/annotation/annotation_source.cpp.i

.PHONY : src/mbgl/annotation/annotation_source.i

# target to preprocess a source file
src/mbgl/annotation/annotation_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_source.cpp.i
.PHONY : src/mbgl/annotation/annotation_source.cpp.i

src/mbgl/annotation/annotation_source.s: src/mbgl/annotation/annotation_source.cpp.s

.PHONY : src/mbgl/annotation/annotation_source.s

# target to generate assembly for a file
src/mbgl/annotation/annotation_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_source.cpp.s
.PHONY : src/mbgl/annotation/annotation_source.cpp.s

src/mbgl/annotation/annotation_tile.o: src/mbgl/annotation/annotation_tile.cpp.o

.PHONY : src/mbgl/annotation/annotation_tile.o

# target to build an object file
src/mbgl/annotation/annotation_tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_tile.cpp.o
.PHONY : src/mbgl/annotation/annotation_tile.cpp.o

src/mbgl/annotation/annotation_tile.i: src/mbgl/annotation/annotation_tile.cpp.i

.PHONY : src/mbgl/annotation/annotation_tile.i

# target to preprocess a source file
src/mbgl/annotation/annotation_tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_tile.cpp.i
.PHONY : src/mbgl/annotation/annotation_tile.cpp.i

src/mbgl/annotation/annotation_tile.s: src/mbgl/annotation/annotation_tile.cpp.s

.PHONY : src/mbgl/annotation/annotation_tile.s

# target to generate assembly for a file
src/mbgl/annotation/annotation_tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/annotation_tile.cpp.s
.PHONY : src/mbgl/annotation/annotation_tile.cpp.s

src/mbgl/annotation/fill_annotation_impl.o: src/mbgl/annotation/fill_annotation_impl.cpp.o

.PHONY : src/mbgl/annotation/fill_annotation_impl.o

# target to build an object file
src/mbgl/annotation/fill_annotation_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/fill_annotation_impl.cpp.o
.PHONY : src/mbgl/annotation/fill_annotation_impl.cpp.o

src/mbgl/annotation/fill_annotation_impl.i: src/mbgl/annotation/fill_annotation_impl.cpp.i

.PHONY : src/mbgl/annotation/fill_annotation_impl.i

# target to preprocess a source file
src/mbgl/annotation/fill_annotation_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/fill_annotation_impl.cpp.i
.PHONY : src/mbgl/annotation/fill_annotation_impl.cpp.i

src/mbgl/annotation/fill_annotation_impl.s: src/mbgl/annotation/fill_annotation_impl.cpp.s

.PHONY : src/mbgl/annotation/fill_annotation_impl.s

# target to generate assembly for a file
src/mbgl/annotation/fill_annotation_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/fill_annotation_impl.cpp.s
.PHONY : src/mbgl/annotation/fill_annotation_impl.cpp.s

src/mbgl/annotation/line_annotation_impl.o: src/mbgl/annotation/line_annotation_impl.cpp.o

.PHONY : src/mbgl/annotation/line_annotation_impl.o

# target to build an object file
src/mbgl/annotation/line_annotation_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/line_annotation_impl.cpp.o
.PHONY : src/mbgl/annotation/line_annotation_impl.cpp.o

src/mbgl/annotation/line_annotation_impl.i: src/mbgl/annotation/line_annotation_impl.cpp.i

.PHONY : src/mbgl/annotation/line_annotation_impl.i

# target to preprocess a source file
src/mbgl/annotation/line_annotation_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/line_annotation_impl.cpp.i
.PHONY : src/mbgl/annotation/line_annotation_impl.cpp.i

src/mbgl/annotation/line_annotation_impl.s: src/mbgl/annotation/line_annotation_impl.cpp.s

.PHONY : src/mbgl/annotation/line_annotation_impl.s

# target to generate assembly for a file
src/mbgl/annotation/line_annotation_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/line_annotation_impl.cpp.s
.PHONY : src/mbgl/annotation/line_annotation_impl.cpp.s

src/mbgl/annotation/render_annotation_source.o: src/mbgl/annotation/render_annotation_source.cpp.o

.PHONY : src/mbgl/annotation/render_annotation_source.o

# target to build an object file
src/mbgl/annotation/render_annotation_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/render_annotation_source.cpp.o
.PHONY : src/mbgl/annotation/render_annotation_source.cpp.o

src/mbgl/annotation/render_annotation_source.i: src/mbgl/annotation/render_annotation_source.cpp.i

.PHONY : src/mbgl/annotation/render_annotation_source.i

# target to preprocess a source file
src/mbgl/annotation/render_annotation_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/render_annotation_source.cpp.i
.PHONY : src/mbgl/annotation/render_annotation_source.cpp.i

src/mbgl/annotation/render_annotation_source.s: src/mbgl/annotation/render_annotation_source.cpp.s

.PHONY : src/mbgl/annotation/render_annotation_source.s

# target to generate assembly for a file
src/mbgl/annotation/render_annotation_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/render_annotation_source.cpp.s
.PHONY : src/mbgl/annotation/render_annotation_source.cpp.s

src/mbgl/annotation/shape_annotation_impl.o: src/mbgl/annotation/shape_annotation_impl.cpp.o

.PHONY : src/mbgl/annotation/shape_annotation_impl.o

# target to build an object file
src/mbgl/annotation/shape_annotation_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/shape_annotation_impl.cpp.o
.PHONY : src/mbgl/annotation/shape_annotation_impl.cpp.o

src/mbgl/annotation/shape_annotation_impl.i: src/mbgl/annotation/shape_annotation_impl.cpp.i

.PHONY : src/mbgl/annotation/shape_annotation_impl.i

# target to preprocess a source file
src/mbgl/annotation/shape_annotation_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/shape_annotation_impl.cpp.i
.PHONY : src/mbgl/annotation/shape_annotation_impl.cpp.i

src/mbgl/annotation/shape_annotation_impl.s: src/mbgl/annotation/shape_annotation_impl.cpp.s

.PHONY : src/mbgl/annotation/shape_annotation_impl.s

# target to generate assembly for a file
src/mbgl/annotation/shape_annotation_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/shape_annotation_impl.cpp.s
.PHONY : src/mbgl/annotation/shape_annotation_impl.cpp.s

src/mbgl/annotation/symbol_annotation_impl.o: src/mbgl/annotation/symbol_annotation_impl.cpp.o

.PHONY : src/mbgl/annotation/symbol_annotation_impl.o

# target to build an object file
src/mbgl/annotation/symbol_annotation_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/symbol_annotation_impl.cpp.o
.PHONY : src/mbgl/annotation/symbol_annotation_impl.cpp.o

src/mbgl/annotation/symbol_annotation_impl.i: src/mbgl/annotation/symbol_annotation_impl.cpp.i

.PHONY : src/mbgl/annotation/symbol_annotation_impl.i

# target to preprocess a source file
src/mbgl/annotation/symbol_annotation_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/symbol_annotation_impl.cpp.i
.PHONY : src/mbgl/annotation/symbol_annotation_impl.cpp.i

src/mbgl/annotation/symbol_annotation_impl.s: src/mbgl/annotation/symbol_annotation_impl.cpp.s

.PHONY : src/mbgl/annotation/symbol_annotation_impl.s

# target to generate assembly for a file
src/mbgl/annotation/symbol_annotation_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/annotation/symbol_annotation_impl.cpp.s
.PHONY : src/mbgl/annotation/symbol_annotation_impl.cpp.s

src/mbgl/geometry/feature_index.o: src/mbgl/geometry/feature_index.cpp.o

.PHONY : src/mbgl/geometry/feature_index.o

# target to build an object file
src/mbgl/geometry/feature_index.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/geometry/feature_index.cpp.o
.PHONY : src/mbgl/geometry/feature_index.cpp.o

src/mbgl/geometry/feature_index.i: src/mbgl/geometry/feature_index.cpp.i

.PHONY : src/mbgl/geometry/feature_index.i

# target to preprocess a source file
src/mbgl/geometry/feature_index.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/geometry/feature_index.cpp.i
.PHONY : src/mbgl/geometry/feature_index.cpp.i

src/mbgl/geometry/feature_index.s: src/mbgl/geometry/feature_index.cpp.s

.PHONY : src/mbgl/geometry/feature_index.s

# target to generate assembly for a file
src/mbgl/geometry/feature_index.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/geometry/feature_index.cpp.s
.PHONY : src/mbgl/geometry/feature_index.cpp.s

src/mbgl/geometry/line_atlas.o: src/mbgl/geometry/line_atlas.cpp.o

.PHONY : src/mbgl/geometry/line_atlas.o

# target to build an object file
src/mbgl/geometry/line_atlas.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/geometry/line_atlas.cpp.o
.PHONY : src/mbgl/geometry/line_atlas.cpp.o

src/mbgl/geometry/line_atlas.i: src/mbgl/geometry/line_atlas.cpp.i

.PHONY : src/mbgl/geometry/line_atlas.i

# target to preprocess a source file
src/mbgl/geometry/line_atlas.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/geometry/line_atlas.cpp.i
.PHONY : src/mbgl/geometry/line_atlas.cpp.i

src/mbgl/geometry/line_atlas.s: src/mbgl/geometry/line_atlas.cpp.s

.PHONY : src/mbgl/geometry/line_atlas.s

# target to generate assembly for a file
src/mbgl/geometry/line_atlas.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/geometry/line_atlas.cpp.s
.PHONY : src/mbgl/geometry/line_atlas.cpp.s

src/mbgl/gl/attribute.o: src/mbgl/gl/attribute.cpp.o

.PHONY : src/mbgl/gl/attribute.o

# target to build an object file
src/mbgl/gl/attribute.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/attribute.cpp.o
.PHONY : src/mbgl/gl/attribute.cpp.o

src/mbgl/gl/attribute.i: src/mbgl/gl/attribute.cpp.i

.PHONY : src/mbgl/gl/attribute.i

# target to preprocess a source file
src/mbgl/gl/attribute.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/attribute.cpp.i
.PHONY : src/mbgl/gl/attribute.cpp.i

src/mbgl/gl/attribute.s: src/mbgl/gl/attribute.cpp.s

.PHONY : src/mbgl/gl/attribute.s

# target to generate assembly for a file
src/mbgl/gl/attribute.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/attribute.cpp.s
.PHONY : src/mbgl/gl/attribute.cpp.s

src/mbgl/gl/color_mode.o: src/mbgl/gl/color_mode.cpp.o

.PHONY : src/mbgl/gl/color_mode.o

# target to build an object file
src/mbgl/gl/color_mode.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/color_mode.cpp.o
.PHONY : src/mbgl/gl/color_mode.cpp.o

src/mbgl/gl/color_mode.i: src/mbgl/gl/color_mode.cpp.i

.PHONY : src/mbgl/gl/color_mode.i

# target to preprocess a source file
src/mbgl/gl/color_mode.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/color_mode.cpp.i
.PHONY : src/mbgl/gl/color_mode.cpp.i

src/mbgl/gl/color_mode.s: src/mbgl/gl/color_mode.cpp.s

.PHONY : src/mbgl/gl/color_mode.s

# target to generate assembly for a file
src/mbgl/gl/color_mode.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/color_mode.cpp.s
.PHONY : src/mbgl/gl/color_mode.cpp.s

src/mbgl/gl/context.o: src/mbgl/gl/context.cpp.o

.PHONY : src/mbgl/gl/context.o

# target to build an object file
src/mbgl/gl/context.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/context.cpp.o
.PHONY : src/mbgl/gl/context.cpp.o

src/mbgl/gl/context.i: src/mbgl/gl/context.cpp.i

.PHONY : src/mbgl/gl/context.i

# target to preprocess a source file
src/mbgl/gl/context.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/context.cpp.i
.PHONY : src/mbgl/gl/context.cpp.i

src/mbgl/gl/context.s: src/mbgl/gl/context.cpp.s

.PHONY : src/mbgl/gl/context.s

# target to generate assembly for a file
src/mbgl/gl/context.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/context.cpp.s
.PHONY : src/mbgl/gl/context.cpp.s

src/mbgl/gl/debugging.o: src/mbgl/gl/debugging.cpp.o

.PHONY : src/mbgl/gl/debugging.o

# target to build an object file
src/mbgl/gl/debugging.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/debugging.cpp.o
.PHONY : src/mbgl/gl/debugging.cpp.o

src/mbgl/gl/debugging.i: src/mbgl/gl/debugging.cpp.i

.PHONY : src/mbgl/gl/debugging.i

# target to preprocess a source file
src/mbgl/gl/debugging.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/debugging.cpp.i
.PHONY : src/mbgl/gl/debugging.cpp.i

src/mbgl/gl/debugging.s: src/mbgl/gl/debugging.cpp.s

.PHONY : src/mbgl/gl/debugging.s

# target to generate assembly for a file
src/mbgl/gl/debugging.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/debugging.cpp.s
.PHONY : src/mbgl/gl/debugging.cpp.s

src/mbgl/gl/debugging_extension.o: src/mbgl/gl/debugging_extension.cpp.o

.PHONY : src/mbgl/gl/debugging_extension.o

# target to build an object file
src/mbgl/gl/debugging_extension.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/debugging_extension.cpp.o
.PHONY : src/mbgl/gl/debugging_extension.cpp.o

src/mbgl/gl/debugging_extension.i: src/mbgl/gl/debugging_extension.cpp.i

.PHONY : src/mbgl/gl/debugging_extension.i

# target to preprocess a source file
src/mbgl/gl/debugging_extension.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/debugging_extension.cpp.i
.PHONY : src/mbgl/gl/debugging_extension.cpp.i

src/mbgl/gl/debugging_extension.s: src/mbgl/gl/debugging_extension.cpp.s

.PHONY : src/mbgl/gl/debugging_extension.s

# target to generate assembly for a file
src/mbgl/gl/debugging_extension.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/debugging_extension.cpp.s
.PHONY : src/mbgl/gl/debugging_extension.cpp.s

src/mbgl/gl/depth_mode.o: src/mbgl/gl/depth_mode.cpp.o

.PHONY : src/mbgl/gl/depth_mode.o

# target to build an object file
src/mbgl/gl/depth_mode.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/depth_mode.cpp.o
.PHONY : src/mbgl/gl/depth_mode.cpp.o

src/mbgl/gl/depth_mode.i: src/mbgl/gl/depth_mode.cpp.i

.PHONY : src/mbgl/gl/depth_mode.i

# target to preprocess a source file
src/mbgl/gl/depth_mode.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/depth_mode.cpp.i
.PHONY : src/mbgl/gl/depth_mode.cpp.i

src/mbgl/gl/depth_mode.s: src/mbgl/gl/depth_mode.cpp.s

.PHONY : src/mbgl/gl/depth_mode.s

# target to generate assembly for a file
src/mbgl/gl/depth_mode.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/depth_mode.cpp.s
.PHONY : src/mbgl/gl/depth_mode.cpp.s

src/mbgl/gl/gl.o: src/mbgl/gl/gl.cpp.o

.PHONY : src/mbgl/gl/gl.o

# target to build an object file
src/mbgl/gl/gl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/gl.cpp.o
.PHONY : src/mbgl/gl/gl.cpp.o

src/mbgl/gl/gl.i: src/mbgl/gl/gl.cpp.i

.PHONY : src/mbgl/gl/gl.i

# target to preprocess a source file
src/mbgl/gl/gl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/gl.cpp.i
.PHONY : src/mbgl/gl/gl.cpp.i

src/mbgl/gl/gl.s: src/mbgl/gl/gl.cpp.s

.PHONY : src/mbgl/gl/gl.s

# target to generate assembly for a file
src/mbgl/gl/gl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/gl.cpp.s
.PHONY : src/mbgl/gl/gl.cpp.s

src/mbgl/gl/object.o: src/mbgl/gl/object.cpp.o

.PHONY : src/mbgl/gl/object.o

# target to build an object file
src/mbgl/gl/object.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/object.cpp.o
.PHONY : src/mbgl/gl/object.cpp.o

src/mbgl/gl/object.i: src/mbgl/gl/object.cpp.i

.PHONY : src/mbgl/gl/object.i

# target to preprocess a source file
src/mbgl/gl/object.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/object.cpp.i
.PHONY : src/mbgl/gl/object.cpp.i

src/mbgl/gl/object.s: src/mbgl/gl/object.cpp.s

.PHONY : src/mbgl/gl/object.s

# target to generate assembly for a file
src/mbgl/gl/object.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/object.cpp.s
.PHONY : src/mbgl/gl/object.cpp.s

src/mbgl/gl/stencil_mode.o: src/mbgl/gl/stencil_mode.cpp.o

.PHONY : src/mbgl/gl/stencil_mode.o

# target to build an object file
src/mbgl/gl/stencil_mode.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/stencil_mode.cpp.o
.PHONY : src/mbgl/gl/stencil_mode.cpp.o

src/mbgl/gl/stencil_mode.i: src/mbgl/gl/stencil_mode.cpp.i

.PHONY : src/mbgl/gl/stencil_mode.i

# target to preprocess a source file
src/mbgl/gl/stencil_mode.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/stencil_mode.cpp.i
.PHONY : src/mbgl/gl/stencil_mode.cpp.i

src/mbgl/gl/stencil_mode.s: src/mbgl/gl/stencil_mode.cpp.s

.PHONY : src/mbgl/gl/stencil_mode.s

# target to generate assembly for a file
src/mbgl/gl/stencil_mode.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/stencil_mode.cpp.s
.PHONY : src/mbgl/gl/stencil_mode.cpp.s

src/mbgl/gl/uniform.o: src/mbgl/gl/uniform.cpp.o

.PHONY : src/mbgl/gl/uniform.o

# target to build an object file
src/mbgl/gl/uniform.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/uniform.cpp.o
.PHONY : src/mbgl/gl/uniform.cpp.o

src/mbgl/gl/uniform.i: src/mbgl/gl/uniform.cpp.i

.PHONY : src/mbgl/gl/uniform.i

# target to preprocess a source file
src/mbgl/gl/uniform.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/uniform.cpp.i
.PHONY : src/mbgl/gl/uniform.cpp.i

src/mbgl/gl/uniform.s: src/mbgl/gl/uniform.cpp.s

.PHONY : src/mbgl/gl/uniform.s

# target to generate assembly for a file
src/mbgl/gl/uniform.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/uniform.cpp.s
.PHONY : src/mbgl/gl/uniform.cpp.s

src/mbgl/gl/value.o: src/mbgl/gl/value.cpp.o

.PHONY : src/mbgl/gl/value.o

# target to build an object file
src/mbgl/gl/value.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/value.cpp.o
.PHONY : src/mbgl/gl/value.cpp.o

src/mbgl/gl/value.i: src/mbgl/gl/value.cpp.i

.PHONY : src/mbgl/gl/value.i

# target to preprocess a source file
src/mbgl/gl/value.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/value.cpp.i
.PHONY : src/mbgl/gl/value.cpp.i

src/mbgl/gl/value.s: src/mbgl/gl/value.cpp.s

.PHONY : src/mbgl/gl/value.s

# target to generate assembly for a file
src/mbgl/gl/value.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/value.cpp.s
.PHONY : src/mbgl/gl/value.cpp.s

src/mbgl/gl/vertex_array.o: src/mbgl/gl/vertex_array.cpp.o

.PHONY : src/mbgl/gl/vertex_array.o

# target to build an object file
src/mbgl/gl/vertex_array.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/vertex_array.cpp.o
.PHONY : src/mbgl/gl/vertex_array.cpp.o

src/mbgl/gl/vertex_array.i: src/mbgl/gl/vertex_array.cpp.i

.PHONY : src/mbgl/gl/vertex_array.i

# target to preprocess a source file
src/mbgl/gl/vertex_array.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/vertex_array.cpp.i
.PHONY : src/mbgl/gl/vertex_array.cpp.i

src/mbgl/gl/vertex_array.s: src/mbgl/gl/vertex_array.cpp.s

.PHONY : src/mbgl/gl/vertex_array.s

# target to generate assembly for a file
src/mbgl/gl/vertex_array.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/gl/vertex_array.cpp.s
.PHONY : src/mbgl/gl/vertex_array.cpp.s

src/mbgl/layout/clip_lines.o: src/mbgl/layout/clip_lines.cpp.o

.PHONY : src/mbgl/layout/clip_lines.o

# target to build an object file
src/mbgl/layout/clip_lines.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/clip_lines.cpp.o
.PHONY : src/mbgl/layout/clip_lines.cpp.o

src/mbgl/layout/clip_lines.i: src/mbgl/layout/clip_lines.cpp.i

.PHONY : src/mbgl/layout/clip_lines.i

# target to preprocess a source file
src/mbgl/layout/clip_lines.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/clip_lines.cpp.i
.PHONY : src/mbgl/layout/clip_lines.cpp.i

src/mbgl/layout/clip_lines.s: src/mbgl/layout/clip_lines.cpp.s

.PHONY : src/mbgl/layout/clip_lines.s

# target to generate assembly for a file
src/mbgl/layout/clip_lines.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/clip_lines.cpp.s
.PHONY : src/mbgl/layout/clip_lines.cpp.s

src/mbgl/layout/merge_lines.o: src/mbgl/layout/merge_lines.cpp.o

.PHONY : src/mbgl/layout/merge_lines.o

# target to build an object file
src/mbgl/layout/merge_lines.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/merge_lines.cpp.o
.PHONY : src/mbgl/layout/merge_lines.cpp.o

src/mbgl/layout/merge_lines.i: src/mbgl/layout/merge_lines.cpp.i

.PHONY : src/mbgl/layout/merge_lines.i

# target to preprocess a source file
src/mbgl/layout/merge_lines.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/merge_lines.cpp.i
.PHONY : src/mbgl/layout/merge_lines.cpp.i

src/mbgl/layout/merge_lines.s: src/mbgl/layout/merge_lines.cpp.s

.PHONY : src/mbgl/layout/merge_lines.s

# target to generate assembly for a file
src/mbgl/layout/merge_lines.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/merge_lines.cpp.s
.PHONY : src/mbgl/layout/merge_lines.cpp.s

src/mbgl/layout/symbol_instance.o: src/mbgl/layout/symbol_instance.cpp.o

.PHONY : src/mbgl/layout/symbol_instance.o

# target to build an object file
src/mbgl/layout/symbol_instance.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_instance.cpp.o
.PHONY : src/mbgl/layout/symbol_instance.cpp.o

src/mbgl/layout/symbol_instance.i: src/mbgl/layout/symbol_instance.cpp.i

.PHONY : src/mbgl/layout/symbol_instance.i

# target to preprocess a source file
src/mbgl/layout/symbol_instance.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_instance.cpp.i
.PHONY : src/mbgl/layout/symbol_instance.cpp.i

src/mbgl/layout/symbol_instance.s: src/mbgl/layout/symbol_instance.cpp.s

.PHONY : src/mbgl/layout/symbol_instance.s

# target to generate assembly for a file
src/mbgl/layout/symbol_instance.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_instance.cpp.s
.PHONY : src/mbgl/layout/symbol_instance.cpp.s

src/mbgl/layout/symbol_layout.o: src/mbgl/layout/symbol_layout.cpp.o

.PHONY : src/mbgl/layout/symbol_layout.o

# target to build an object file
src/mbgl/layout/symbol_layout.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_layout.cpp.o
.PHONY : src/mbgl/layout/symbol_layout.cpp.o

src/mbgl/layout/symbol_layout.i: src/mbgl/layout/symbol_layout.cpp.i

.PHONY : src/mbgl/layout/symbol_layout.i

# target to preprocess a source file
src/mbgl/layout/symbol_layout.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_layout.cpp.i
.PHONY : src/mbgl/layout/symbol_layout.cpp.i

src/mbgl/layout/symbol_layout.s: src/mbgl/layout/symbol_layout.cpp.s

.PHONY : src/mbgl/layout/symbol_layout.s

# target to generate assembly for a file
src/mbgl/layout/symbol_layout.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_layout.cpp.s
.PHONY : src/mbgl/layout/symbol_layout.cpp.s

src/mbgl/layout/symbol_projection.o: src/mbgl/layout/symbol_projection.cpp.o

.PHONY : src/mbgl/layout/symbol_projection.o

# target to build an object file
src/mbgl/layout/symbol_projection.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_projection.cpp.o
.PHONY : src/mbgl/layout/symbol_projection.cpp.o

src/mbgl/layout/symbol_projection.i: src/mbgl/layout/symbol_projection.cpp.i

.PHONY : src/mbgl/layout/symbol_projection.i

# target to preprocess a source file
src/mbgl/layout/symbol_projection.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_projection.cpp.i
.PHONY : src/mbgl/layout/symbol_projection.cpp.i

src/mbgl/layout/symbol_projection.s: src/mbgl/layout/symbol_projection.cpp.s

.PHONY : src/mbgl/layout/symbol_projection.s

# target to generate assembly for a file
src/mbgl/layout/symbol_projection.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/layout/symbol_projection.cpp.s
.PHONY : src/mbgl/layout/symbol_projection.cpp.s

src/mbgl/map/map.o: src/mbgl/map/map.cpp.o

.PHONY : src/mbgl/map/map.o

# target to build an object file
src/mbgl/map/map.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/map.cpp.o
.PHONY : src/mbgl/map/map.cpp.o

src/mbgl/map/map.i: src/mbgl/map/map.cpp.i

.PHONY : src/mbgl/map/map.i

# target to preprocess a source file
src/mbgl/map/map.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/map.cpp.i
.PHONY : src/mbgl/map/map.cpp.i

src/mbgl/map/map.s: src/mbgl/map/map.cpp.s

.PHONY : src/mbgl/map/map.s

# target to generate assembly for a file
src/mbgl/map/map.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/map.cpp.s
.PHONY : src/mbgl/map/map.cpp.s

src/mbgl/map/transform.o: src/mbgl/map/transform.cpp.o

.PHONY : src/mbgl/map/transform.o

# target to build an object file
src/mbgl/map/transform.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/transform.cpp.o
.PHONY : src/mbgl/map/transform.cpp.o

src/mbgl/map/transform.i: src/mbgl/map/transform.cpp.i

.PHONY : src/mbgl/map/transform.i

# target to preprocess a source file
src/mbgl/map/transform.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/transform.cpp.i
.PHONY : src/mbgl/map/transform.cpp.i

src/mbgl/map/transform.s: src/mbgl/map/transform.cpp.s

.PHONY : src/mbgl/map/transform.s

# target to generate assembly for a file
src/mbgl/map/transform.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/transform.cpp.s
.PHONY : src/mbgl/map/transform.cpp.s

src/mbgl/map/transform_state.o: src/mbgl/map/transform_state.cpp.o

.PHONY : src/mbgl/map/transform_state.o

# target to build an object file
src/mbgl/map/transform_state.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/transform_state.cpp.o
.PHONY : src/mbgl/map/transform_state.cpp.o

src/mbgl/map/transform_state.i: src/mbgl/map/transform_state.cpp.i

.PHONY : src/mbgl/map/transform_state.i

# target to preprocess a source file
src/mbgl/map/transform_state.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/transform_state.cpp.i
.PHONY : src/mbgl/map/transform_state.cpp.i

src/mbgl/map/transform_state.s: src/mbgl/map/transform_state.cpp.s

.PHONY : src/mbgl/map/transform_state.s

# target to generate assembly for a file
src/mbgl/map/transform_state.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/map/transform_state.cpp.s
.PHONY : src/mbgl/map/transform_state.cpp.s

src/mbgl/math/log2.o: src/mbgl/math/log2.cpp.o

.PHONY : src/mbgl/math/log2.o

# target to build an object file
src/mbgl/math/log2.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/math/log2.cpp.o
.PHONY : src/mbgl/math/log2.cpp.o

src/mbgl/math/log2.i: src/mbgl/math/log2.cpp.i

.PHONY : src/mbgl/math/log2.i

# target to preprocess a source file
src/mbgl/math/log2.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/math/log2.cpp.i
.PHONY : src/mbgl/math/log2.cpp.i

src/mbgl/math/log2.s: src/mbgl/math/log2.cpp.s

.PHONY : src/mbgl/math/log2.s

# target to generate assembly for a file
src/mbgl/math/log2.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/math/log2.cpp.s
.PHONY : src/mbgl/math/log2.cpp.s

src/mbgl/programs/binary_program.o: src/mbgl/programs/binary_program.cpp.o

.PHONY : src/mbgl/programs/binary_program.o

# target to build an object file
src/mbgl/programs/binary_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/binary_program.cpp.o
.PHONY : src/mbgl/programs/binary_program.cpp.o

src/mbgl/programs/binary_program.i: src/mbgl/programs/binary_program.cpp.i

.PHONY : src/mbgl/programs/binary_program.i

# target to preprocess a source file
src/mbgl/programs/binary_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/binary_program.cpp.i
.PHONY : src/mbgl/programs/binary_program.cpp.i

src/mbgl/programs/binary_program.s: src/mbgl/programs/binary_program.cpp.s

.PHONY : src/mbgl/programs/binary_program.s

# target to generate assembly for a file
src/mbgl/programs/binary_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/binary_program.cpp.s
.PHONY : src/mbgl/programs/binary_program.cpp.s

src/mbgl/programs/circle_program.o: src/mbgl/programs/circle_program.cpp.o

.PHONY : src/mbgl/programs/circle_program.o

# target to build an object file
src/mbgl/programs/circle_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/circle_program.cpp.o
.PHONY : src/mbgl/programs/circle_program.cpp.o

src/mbgl/programs/circle_program.i: src/mbgl/programs/circle_program.cpp.i

.PHONY : src/mbgl/programs/circle_program.i

# target to preprocess a source file
src/mbgl/programs/circle_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/circle_program.cpp.i
.PHONY : src/mbgl/programs/circle_program.cpp.i

src/mbgl/programs/circle_program.s: src/mbgl/programs/circle_program.cpp.s

.PHONY : src/mbgl/programs/circle_program.s

# target to generate assembly for a file
src/mbgl/programs/circle_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/circle_program.cpp.s
.PHONY : src/mbgl/programs/circle_program.cpp.s

src/mbgl/programs/collision_box_program.o: src/mbgl/programs/collision_box_program.cpp.o

.PHONY : src/mbgl/programs/collision_box_program.o

# target to build an object file
src/mbgl/programs/collision_box_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/collision_box_program.cpp.o
.PHONY : src/mbgl/programs/collision_box_program.cpp.o

src/mbgl/programs/collision_box_program.i: src/mbgl/programs/collision_box_program.cpp.i

.PHONY : src/mbgl/programs/collision_box_program.i

# target to preprocess a source file
src/mbgl/programs/collision_box_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/collision_box_program.cpp.i
.PHONY : src/mbgl/programs/collision_box_program.cpp.i

src/mbgl/programs/collision_box_program.s: src/mbgl/programs/collision_box_program.cpp.s

.PHONY : src/mbgl/programs/collision_box_program.s

# target to generate assembly for a file
src/mbgl/programs/collision_box_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/collision_box_program.cpp.s
.PHONY : src/mbgl/programs/collision_box_program.cpp.s

src/mbgl/programs/extrusion_texture_program.o: src/mbgl/programs/extrusion_texture_program.cpp.o

.PHONY : src/mbgl/programs/extrusion_texture_program.o

# target to build an object file
src/mbgl/programs/extrusion_texture_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/extrusion_texture_program.cpp.o
.PHONY : src/mbgl/programs/extrusion_texture_program.cpp.o

src/mbgl/programs/extrusion_texture_program.i: src/mbgl/programs/extrusion_texture_program.cpp.i

.PHONY : src/mbgl/programs/extrusion_texture_program.i

# target to preprocess a source file
src/mbgl/programs/extrusion_texture_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/extrusion_texture_program.cpp.i
.PHONY : src/mbgl/programs/extrusion_texture_program.cpp.i

src/mbgl/programs/extrusion_texture_program.s: src/mbgl/programs/extrusion_texture_program.cpp.s

.PHONY : src/mbgl/programs/extrusion_texture_program.s

# target to generate assembly for a file
src/mbgl/programs/extrusion_texture_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/extrusion_texture_program.cpp.s
.PHONY : src/mbgl/programs/extrusion_texture_program.cpp.s

src/mbgl/programs/fill_extrusion_program.o: src/mbgl/programs/fill_extrusion_program.cpp.o

.PHONY : src/mbgl/programs/fill_extrusion_program.o

# target to build an object file
src/mbgl/programs/fill_extrusion_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/fill_extrusion_program.cpp.o
.PHONY : src/mbgl/programs/fill_extrusion_program.cpp.o

src/mbgl/programs/fill_extrusion_program.i: src/mbgl/programs/fill_extrusion_program.cpp.i

.PHONY : src/mbgl/programs/fill_extrusion_program.i

# target to preprocess a source file
src/mbgl/programs/fill_extrusion_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/fill_extrusion_program.cpp.i
.PHONY : src/mbgl/programs/fill_extrusion_program.cpp.i

src/mbgl/programs/fill_extrusion_program.s: src/mbgl/programs/fill_extrusion_program.cpp.s

.PHONY : src/mbgl/programs/fill_extrusion_program.s

# target to generate assembly for a file
src/mbgl/programs/fill_extrusion_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/fill_extrusion_program.cpp.s
.PHONY : src/mbgl/programs/fill_extrusion_program.cpp.s

src/mbgl/programs/fill_program.o: src/mbgl/programs/fill_program.cpp.o

.PHONY : src/mbgl/programs/fill_program.o

# target to build an object file
src/mbgl/programs/fill_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/fill_program.cpp.o
.PHONY : src/mbgl/programs/fill_program.cpp.o

src/mbgl/programs/fill_program.i: src/mbgl/programs/fill_program.cpp.i

.PHONY : src/mbgl/programs/fill_program.i

# target to preprocess a source file
src/mbgl/programs/fill_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/fill_program.cpp.i
.PHONY : src/mbgl/programs/fill_program.cpp.i

src/mbgl/programs/fill_program.s: src/mbgl/programs/fill_program.cpp.s

.PHONY : src/mbgl/programs/fill_program.s

# target to generate assembly for a file
src/mbgl/programs/fill_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/fill_program.cpp.s
.PHONY : src/mbgl/programs/fill_program.cpp.s

src/mbgl/programs/line_program.o: src/mbgl/programs/line_program.cpp.o

.PHONY : src/mbgl/programs/line_program.o

# target to build an object file
src/mbgl/programs/line_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/line_program.cpp.o
.PHONY : src/mbgl/programs/line_program.cpp.o

src/mbgl/programs/line_program.i: src/mbgl/programs/line_program.cpp.i

.PHONY : src/mbgl/programs/line_program.i

# target to preprocess a source file
src/mbgl/programs/line_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/line_program.cpp.i
.PHONY : src/mbgl/programs/line_program.cpp.i

src/mbgl/programs/line_program.s: src/mbgl/programs/line_program.cpp.s

.PHONY : src/mbgl/programs/line_program.s

# target to generate assembly for a file
src/mbgl/programs/line_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/line_program.cpp.s
.PHONY : src/mbgl/programs/line_program.cpp.s

src/mbgl/programs/program_parameters.o: src/mbgl/programs/program_parameters.cpp.o

.PHONY : src/mbgl/programs/program_parameters.o

# target to build an object file
src/mbgl/programs/program_parameters.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/program_parameters.cpp.o
.PHONY : src/mbgl/programs/program_parameters.cpp.o

src/mbgl/programs/program_parameters.i: src/mbgl/programs/program_parameters.cpp.i

.PHONY : src/mbgl/programs/program_parameters.i

# target to preprocess a source file
src/mbgl/programs/program_parameters.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/program_parameters.cpp.i
.PHONY : src/mbgl/programs/program_parameters.cpp.i

src/mbgl/programs/program_parameters.s: src/mbgl/programs/program_parameters.cpp.s

.PHONY : src/mbgl/programs/program_parameters.s

# target to generate assembly for a file
src/mbgl/programs/program_parameters.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/program_parameters.cpp.s
.PHONY : src/mbgl/programs/program_parameters.cpp.s

src/mbgl/programs/raster_program.o: src/mbgl/programs/raster_program.cpp.o

.PHONY : src/mbgl/programs/raster_program.o

# target to build an object file
src/mbgl/programs/raster_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/raster_program.cpp.o
.PHONY : src/mbgl/programs/raster_program.cpp.o

src/mbgl/programs/raster_program.i: src/mbgl/programs/raster_program.cpp.i

.PHONY : src/mbgl/programs/raster_program.i

# target to preprocess a source file
src/mbgl/programs/raster_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/raster_program.cpp.i
.PHONY : src/mbgl/programs/raster_program.cpp.i

src/mbgl/programs/raster_program.s: src/mbgl/programs/raster_program.cpp.s

.PHONY : src/mbgl/programs/raster_program.s

# target to generate assembly for a file
src/mbgl/programs/raster_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/raster_program.cpp.s
.PHONY : src/mbgl/programs/raster_program.cpp.s

src/mbgl/programs/symbol_program.o: src/mbgl/programs/symbol_program.cpp.o

.PHONY : src/mbgl/programs/symbol_program.o

# target to build an object file
src/mbgl/programs/symbol_program.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/symbol_program.cpp.o
.PHONY : src/mbgl/programs/symbol_program.cpp.o

src/mbgl/programs/symbol_program.i: src/mbgl/programs/symbol_program.cpp.i

.PHONY : src/mbgl/programs/symbol_program.i

# target to preprocess a source file
src/mbgl/programs/symbol_program.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/symbol_program.cpp.i
.PHONY : src/mbgl/programs/symbol_program.cpp.i

src/mbgl/programs/symbol_program.s: src/mbgl/programs/symbol_program.cpp.s

.PHONY : src/mbgl/programs/symbol_program.s

# target to generate assembly for a file
src/mbgl/programs/symbol_program.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/programs/symbol_program.cpp.s
.PHONY : src/mbgl/programs/symbol_program.cpp.s

src/mbgl/renderer/backend_scope.o: src/mbgl/renderer/backend_scope.cpp.o

.PHONY : src/mbgl/renderer/backend_scope.o

# target to build an object file
src/mbgl/renderer/backend_scope.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/backend_scope.cpp.o
.PHONY : src/mbgl/renderer/backend_scope.cpp.o

src/mbgl/renderer/backend_scope.i: src/mbgl/renderer/backend_scope.cpp.i

.PHONY : src/mbgl/renderer/backend_scope.i

# target to preprocess a source file
src/mbgl/renderer/backend_scope.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/backend_scope.cpp.i
.PHONY : src/mbgl/renderer/backend_scope.cpp.i

src/mbgl/renderer/backend_scope.s: src/mbgl/renderer/backend_scope.cpp.s

.PHONY : src/mbgl/renderer/backend_scope.s

# target to generate assembly for a file
src/mbgl/renderer/backend_scope.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/backend_scope.cpp.s
.PHONY : src/mbgl/renderer/backend_scope.cpp.s

src/mbgl/renderer/bucket_parameters.o: src/mbgl/renderer/bucket_parameters.cpp.o

.PHONY : src/mbgl/renderer/bucket_parameters.o

# target to build an object file
src/mbgl/renderer/bucket_parameters.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/bucket_parameters.cpp.o
.PHONY : src/mbgl/renderer/bucket_parameters.cpp.o

src/mbgl/renderer/bucket_parameters.i: src/mbgl/renderer/bucket_parameters.cpp.i

.PHONY : src/mbgl/renderer/bucket_parameters.i

# target to preprocess a source file
src/mbgl/renderer/bucket_parameters.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/bucket_parameters.cpp.i
.PHONY : src/mbgl/renderer/bucket_parameters.cpp.i

src/mbgl/renderer/bucket_parameters.s: src/mbgl/renderer/bucket_parameters.cpp.s

.PHONY : src/mbgl/renderer/bucket_parameters.s

# target to generate assembly for a file
src/mbgl/renderer/bucket_parameters.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/bucket_parameters.cpp.s
.PHONY : src/mbgl/renderer/bucket_parameters.cpp.s

src/mbgl/renderer/buckets/circle_bucket.o: src/mbgl/renderer/buckets/circle_bucket.cpp.o

.PHONY : src/mbgl/renderer/buckets/circle_bucket.o

# target to build an object file
src/mbgl/renderer/buckets/circle_bucket.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/circle_bucket.cpp.o
.PHONY : src/mbgl/renderer/buckets/circle_bucket.cpp.o

src/mbgl/renderer/buckets/circle_bucket.i: src/mbgl/renderer/buckets/circle_bucket.cpp.i

.PHONY : src/mbgl/renderer/buckets/circle_bucket.i

# target to preprocess a source file
src/mbgl/renderer/buckets/circle_bucket.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/circle_bucket.cpp.i
.PHONY : src/mbgl/renderer/buckets/circle_bucket.cpp.i

src/mbgl/renderer/buckets/circle_bucket.s: src/mbgl/renderer/buckets/circle_bucket.cpp.s

.PHONY : src/mbgl/renderer/buckets/circle_bucket.s

# target to generate assembly for a file
src/mbgl/renderer/buckets/circle_bucket.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/circle_bucket.cpp.s
.PHONY : src/mbgl/renderer/buckets/circle_bucket.cpp.s

src/mbgl/renderer/buckets/debug_bucket.o: src/mbgl/renderer/buckets/debug_bucket.cpp.o

.PHONY : src/mbgl/renderer/buckets/debug_bucket.o

# target to build an object file
src/mbgl/renderer/buckets/debug_bucket.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/debug_bucket.cpp.o
.PHONY : src/mbgl/renderer/buckets/debug_bucket.cpp.o

src/mbgl/renderer/buckets/debug_bucket.i: src/mbgl/renderer/buckets/debug_bucket.cpp.i

.PHONY : src/mbgl/renderer/buckets/debug_bucket.i

# target to preprocess a source file
src/mbgl/renderer/buckets/debug_bucket.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/debug_bucket.cpp.i
.PHONY : src/mbgl/renderer/buckets/debug_bucket.cpp.i

src/mbgl/renderer/buckets/debug_bucket.s: src/mbgl/renderer/buckets/debug_bucket.cpp.s

.PHONY : src/mbgl/renderer/buckets/debug_bucket.s

# target to generate assembly for a file
src/mbgl/renderer/buckets/debug_bucket.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/debug_bucket.cpp.s
.PHONY : src/mbgl/renderer/buckets/debug_bucket.cpp.s

src/mbgl/renderer/buckets/fill_bucket.o: src/mbgl/renderer/buckets/fill_bucket.cpp.o

.PHONY : src/mbgl/renderer/buckets/fill_bucket.o

# target to build an object file
src/mbgl/renderer/buckets/fill_bucket.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/fill_bucket.cpp.o
.PHONY : src/mbgl/renderer/buckets/fill_bucket.cpp.o

src/mbgl/renderer/buckets/fill_bucket.i: src/mbgl/renderer/buckets/fill_bucket.cpp.i

.PHONY : src/mbgl/renderer/buckets/fill_bucket.i

# target to preprocess a source file
src/mbgl/renderer/buckets/fill_bucket.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/fill_bucket.cpp.i
.PHONY : src/mbgl/renderer/buckets/fill_bucket.cpp.i

src/mbgl/renderer/buckets/fill_bucket.s: src/mbgl/renderer/buckets/fill_bucket.cpp.s

.PHONY : src/mbgl/renderer/buckets/fill_bucket.s

# target to generate assembly for a file
src/mbgl/renderer/buckets/fill_bucket.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/fill_bucket.cpp.s
.PHONY : src/mbgl/renderer/buckets/fill_bucket.cpp.s

src/mbgl/renderer/buckets/fill_extrusion_bucket.o: src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.o

.PHONY : src/mbgl/renderer/buckets/fill_extrusion_bucket.o

# target to build an object file
src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.o
.PHONY : src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.o

src/mbgl/renderer/buckets/fill_extrusion_bucket.i: src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.i

.PHONY : src/mbgl/renderer/buckets/fill_extrusion_bucket.i

# target to preprocess a source file
src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.i
.PHONY : src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.i

src/mbgl/renderer/buckets/fill_extrusion_bucket.s: src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.s

.PHONY : src/mbgl/renderer/buckets/fill_extrusion_bucket.s

# target to generate assembly for a file
src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.s
.PHONY : src/mbgl/renderer/buckets/fill_extrusion_bucket.cpp.s

src/mbgl/renderer/buckets/line_bucket.o: src/mbgl/renderer/buckets/line_bucket.cpp.o

.PHONY : src/mbgl/renderer/buckets/line_bucket.o

# target to build an object file
src/mbgl/renderer/buckets/line_bucket.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/line_bucket.cpp.o
.PHONY : src/mbgl/renderer/buckets/line_bucket.cpp.o

src/mbgl/renderer/buckets/line_bucket.i: src/mbgl/renderer/buckets/line_bucket.cpp.i

.PHONY : src/mbgl/renderer/buckets/line_bucket.i

# target to preprocess a source file
src/mbgl/renderer/buckets/line_bucket.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/line_bucket.cpp.i
.PHONY : src/mbgl/renderer/buckets/line_bucket.cpp.i

src/mbgl/renderer/buckets/line_bucket.s: src/mbgl/renderer/buckets/line_bucket.cpp.s

.PHONY : src/mbgl/renderer/buckets/line_bucket.s

# target to generate assembly for a file
src/mbgl/renderer/buckets/line_bucket.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/line_bucket.cpp.s
.PHONY : src/mbgl/renderer/buckets/line_bucket.cpp.s

src/mbgl/renderer/buckets/raster_bucket.o: src/mbgl/renderer/buckets/raster_bucket.cpp.o

.PHONY : src/mbgl/renderer/buckets/raster_bucket.o

# target to build an object file
src/mbgl/renderer/buckets/raster_bucket.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/raster_bucket.cpp.o
.PHONY : src/mbgl/renderer/buckets/raster_bucket.cpp.o

src/mbgl/renderer/buckets/raster_bucket.i: src/mbgl/renderer/buckets/raster_bucket.cpp.i

.PHONY : src/mbgl/renderer/buckets/raster_bucket.i

# target to preprocess a source file
src/mbgl/renderer/buckets/raster_bucket.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/raster_bucket.cpp.i
.PHONY : src/mbgl/renderer/buckets/raster_bucket.cpp.i

src/mbgl/renderer/buckets/raster_bucket.s: src/mbgl/renderer/buckets/raster_bucket.cpp.s

.PHONY : src/mbgl/renderer/buckets/raster_bucket.s

# target to generate assembly for a file
src/mbgl/renderer/buckets/raster_bucket.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/raster_bucket.cpp.s
.PHONY : src/mbgl/renderer/buckets/raster_bucket.cpp.s

src/mbgl/renderer/buckets/symbol_bucket.o: src/mbgl/renderer/buckets/symbol_bucket.cpp.o

.PHONY : src/mbgl/renderer/buckets/symbol_bucket.o

# target to build an object file
src/mbgl/renderer/buckets/symbol_bucket.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/symbol_bucket.cpp.o
.PHONY : src/mbgl/renderer/buckets/symbol_bucket.cpp.o

src/mbgl/renderer/buckets/symbol_bucket.i: src/mbgl/renderer/buckets/symbol_bucket.cpp.i

.PHONY : src/mbgl/renderer/buckets/symbol_bucket.i

# target to preprocess a source file
src/mbgl/renderer/buckets/symbol_bucket.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/symbol_bucket.cpp.i
.PHONY : src/mbgl/renderer/buckets/symbol_bucket.cpp.i

src/mbgl/renderer/buckets/symbol_bucket.s: src/mbgl/renderer/buckets/symbol_bucket.cpp.s

.PHONY : src/mbgl/renderer/buckets/symbol_bucket.s

# target to generate assembly for a file
src/mbgl/renderer/buckets/symbol_bucket.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/buckets/symbol_bucket.cpp.s
.PHONY : src/mbgl/renderer/buckets/symbol_bucket.cpp.s

src/mbgl/renderer/cross_faded_property_evaluator.o: src/mbgl/renderer/cross_faded_property_evaluator.cpp.o

.PHONY : src/mbgl/renderer/cross_faded_property_evaluator.o

# target to build an object file
src/mbgl/renderer/cross_faded_property_evaluator.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/cross_faded_property_evaluator.cpp.o
.PHONY : src/mbgl/renderer/cross_faded_property_evaluator.cpp.o

src/mbgl/renderer/cross_faded_property_evaluator.i: src/mbgl/renderer/cross_faded_property_evaluator.cpp.i

.PHONY : src/mbgl/renderer/cross_faded_property_evaluator.i

# target to preprocess a source file
src/mbgl/renderer/cross_faded_property_evaluator.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/cross_faded_property_evaluator.cpp.i
.PHONY : src/mbgl/renderer/cross_faded_property_evaluator.cpp.i

src/mbgl/renderer/cross_faded_property_evaluator.s: src/mbgl/renderer/cross_faded_property_evaluator.cpp.s

.PHONY : src/mbgl/renderer/cross_faded_property_evaluator.s

# target to generate assembly for a file
src/mbgl/renderer/cross_faded_property_evaluator.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/cross_faded_property_evaluator.cpp.s
.PHONY : src/mbgl/renderer/cross_faded_property_evaluator.cpp.s

src/mbgl/renderer/frame_history.o: src/mbgl/renderer/frame_history.cpp.o

.PHONY : src/mbgl/renderer/frame_history.o

# target to build an object file
src/mbgl/renderer/frame_history.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/frame_history.cpp.o
.PHONY : src/mbgl/renderer/frame_history.cpp.o

src/mbgl/renderer/frame_history.i: src/mbgl/renderer/frame_history.cpp.i

.PHONY : src/mbgl/renderer/frame_history.i

# target to preprocess a source file
src/mbgl/renderer/frame_history.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/frame_history.cpp.i
.PHONY : src/mbgl/renderer/frame_history.cpp.i

src/mbgl/renderer/frame_history.s: src/mbgl/renderer/frame_history.cpp.s

.PHONY : src/mbgl/renderer/frame_history.s

# target to generate assembly for a file
src/mbgl/renderer/frame_history.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/frame_history.cpp.s
.PHONY : src/mbgl/renderer/frame_history.cpp.s

src/mbgl/renderer/group_by_layout.o: src/mbgl/renderer/group_by_layout.cpp.o

.PHONY : src/mbgl/renderer/group_by_layout.o

# target to build an object file
src/mbgl/renderer/group_by_layout.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/group_by_layout.cpp.o
.PHONY : src/mbgl/renderer/group_by_layout.cpp.o

src/mbgl/renderer/group_by_layout.i: src/mbgl/renderer/group_by_layout.cpp.i

.PHONY : src/mbgl/renderer/group_by_layout.i

# target to preprocess a source file
src/mbgl/renderer/group_by_layout.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/group_by_layout.cpp.i
.PHONY : src/mbgl/renderer/group_by_layout.cpp.i

src/mbgl/renderer/group_by_layout.s: src/mbgl/renderer/group_by_layout.cpp.s

.PHONY : src/mbgl/renderer/group_by_layout.s

# target to generate assembly for a file
src/mbgl/renderer/group_by_layout.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/group_by_layout.cpp.s
.PHONY : src/mbgl/renderer/group_by_layout.cpp.s

src/mbgl/renderer/image_atlas.o: src/mbgl/renderer/image_atlas.cpp.o

.PHONY : src/mbgl/renderer/image_atlas.o

# target to build an object file
src/mbgl/renderer/image_atlas.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/image_atlas.cpp.o
.PHONY : src/mbgl/renderer/image_atlas.cpp.o

src/mbgl/renderer/image_atlas.i: src/mbgl/renderer/image_atlas.cpp.i

.PHONY : src/mbgl/renderer/image_atlas.i

# target to preprocess a source file
src/mbgl/renderer/image_atlas.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/image_atlas.cpp.i
.PHONY : src/mbgl/renderer/image_atlas.cpp.i

src/mbgl/renderer/image_atlas.s: src/mbgl/renderer/image_atlas.cpp.s

.PHONY : src/mbgl/renderer/image_atlas.s

# target to generate assembly for a file
src/mbgl/renderer/image_atlas.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/image_atlas.cpp.s
.PHONY : src/mbgl/renderer/image_atlas.cpp.s

src/mbgl/renderer/image_manager.o: src/mbgl/renderer/image_manager.cpp.o

.PHONY : src/mbgl/renderer/image_manager.o

# target to build an object file
src/mbgl/renderer/image_manager.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/image_manager.cpp.o
.PHONY : src/mbgl/renderer/image_manager.cpp.o

src/mbgl/renderer/image_manager.i: src/mbgl/renderer/image_manager.cpp.i

.PHONY : src/mbgl/renderer/image_manager.i

# target to preprocess a source file
src/mbgl/renderer/image_manager.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/image_manager.cpp.i
.PHONY : src/mbgl/renderer/image_manager.cpp.i

src/mbgl/renderer/image_manager.s: src/mbgl/renderer/image_manager.cpp.s

.PHONY : src/mbgl/renderer/image_manager.s

# target to generate assembly for a file
src/mbgl/renderer/image_manager.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/image_manager.cpp.s
.PHONY : src/mbgl/renderer/image_manager.cpp.s

src/mbgl/renderer/layers/render_background_layer.o: src/mbgl/renderer/layers/render_background_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_background_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_background_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_background_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_background_layer.cpp.o

src/mbgl/renderer/layers/render_background_layer.i: src/mbgl/renderer/layers/render_background_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_background_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_background_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_background_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_background_layer.cpp.i

src/mbgl/renderer/layers/render_background_layer.s: src/mbgl/renderer/layers/render_background_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_background_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_background_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_background_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_background_layer.cpp.s

src/mbgl/renderer/layers/render_circle_layer.o: src/mbgl/renderer/layers/render_circle_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_circle_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_circle_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_circle_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_circle_layer.cpp.o

src/mbgl/renderer/layers/render_circle_layer.i: src/mbgl/renderer/layers/render_circle_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_circle_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_circle_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_circle_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_circle_layer.cpp.i

src/mbgl/renderer/layers/render_circle_layer.s: src/mbgl/renderer/layers/render_circle_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_circle_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_circle_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_circle_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_circle_layer.cpp.s

src/mbgl/renderer/layers/render_custom_layer.o: src/mbgl/renderer/layers/render_custom_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_custom_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_custom_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_custom_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_custom_layer.cpp.o

src/mbgl/renderer/layers/render_custom_layer.i: src/mbgl/renderer/layers/render_custom_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_custom_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_custom_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_custom_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_custom_layer.cpp.i

src/mbgl/renderer/layers/render_custom_layer.s: src/mbgl/renderer/layers/render_custom_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_custom_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_custom_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_custom_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_custom_layer.cpp.s

src/mbgl/renderer/layers/render_fill_extrusion_layer.o: src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_fill_extrusion_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.o

src/mbgl/renderer/layers/render_fill_extrusion_layer.i: src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_fill_extrusion_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.i

src/mbgl/renderer/layers/render_fill_extrusion_layer.s: src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_fill_extrusion_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_fill_extrusion_layer.cpp.s

src/mbgl/renderer/layers/render_fill_layer.o: src/mbgl/renderer/layers/render_fill_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_fill_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_fill_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_fill_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_fill_layer.cpp.o

src/mbgl/renderer/layers/render_fill_layer.i: src/mbgl/renderer/layers/render_fill_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_fill_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_fill_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_fill_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_fill_layer.cpp.i

src/mbgl/renderer/layers/render_fill_layer.s: src/mbgl/renderer/layers/render_fill_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_fill_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_fill_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_fill_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_fill_layer.cpp.s

src/mbgl/renderer/layers/render_line_layer.o: src/mbgl/renderer/layers/render_line_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_line_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_line_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_line_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_line_layer.cpp.o

src/mbgl/renderer/layers/render_line_layer.i: src/mbgl/renderer/layers/render_line_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_line_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_line_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_line_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_line_layer.cpp.i

src/mbgl/renderer/layers/render_line_layer.s: src/mbgl/renderer/layers/render_line_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_line_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_line_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_line_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_line_layer.cpp.s

src/mbgl/renderer/layers/render_raster_layer.o: src/mbgl/renderer/layers/render_raster_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_raster_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_raster_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_raster_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_raster_layer.cpp.o

src/mbgl/renderer/layers/render_raster_layer.i: src/mbgl/renderer/layers/render_raster_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_raster_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_raster_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_raster_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_raster_layer.cpp.i

src/mbgl/renderer/layers/render_raster_layer.s: src/mbgl/renderer/layers/render_raster_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_raster_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_raster_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_raster_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_raster_layer.cpp.s

src/mbgl/renderer/layers/render_symbol_layer.o: src/mbgl/renderer/layers/render_symbol_layer.cpp.o

.PHONY : src/mbgl/renderer/layers/render_symbol_layer.o

# target to build an object file
src/mbgl/renderer/layers/render_symbol_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_symbol_layer.cpp.o
.PHONY : src/mbgl/renderer/layers/render_symbol_layer.cpp.o

src/mbgl/renderer/layers/render_symbol_layer.i: src/mbgl/renderer/layers/render_symbol_layer.cpp.i

.PHONY : src/mbgl/renderer/layers/render_symbol_layer.i

# target to preprocess a source file
src/mbgl/renderer/layers/render_symbol_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_symbol_layer.cpp.i
.PHONY : src/mbgl/renderer/layers/render_symbol_layer.cpp.i

src/mbgl/renderer/layers/render_symbol_layer.s: src/mbgl/renderer/layers/render_symbol_layer.cpp.s

.PHONY : src/mbgl/renderer/layers/render_symbol_layer.s

# target to generate assembly for a file
src/mbgl/renderer/layers/render_symbol_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/layers/render_symbol_layer.cpp.s
.PHONY : src/mbgl/renderer/layers/render_symbol_layer.cpp.s

src/mbgl/renderer/paint_parameters.o: src/mbgl/renderer/paint_parameters.cpp.o

.PHONY : src/mbgl/renderer/paint_parameters.o

# target to build an object file
src/mbgl/renderer/paint_parameters.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/paint_parameters.cpp.o
.PHONY : src/mbgl/renderer/paint_parameters.cpp.o

src/mbgl/renderer/paint_parameters.i: src/mbgl/renderer/paint_parameters.cpp.i

.PHONY : src/mbgl/renderer/paint_parameters.i

# target to preprocess a source file
src/mbgl/renderer/paint_parameters.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/paint_parameters.cpp.i
.PHONY : src/mbgl/renderer/paint_parameters.cpp.i

src/mbgl/renderer/paint_parameters.s: src/mbgl/renderer/paint_parameters.cpp.s

.PHONY : src/mbgl/renderer/paint_parameters.s

# target to generate assembly for a file
src/mbgl/renderer/paint_parameters.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/paint_parameters.cpp.s
.PHONY : src/mbgl/renderer/paint_parameters.cpp.s

src/mbgl/renderer/render_layer.o: src/mbgl/renderer/render_layer.cpp.o

.PHONY : src/mbgl/renderer/render_layer.o

# target to build an object file
src/mbgl/renderer/render_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_layer.cpp.o
.PHONY : src/mbgl/renderer/render_layer.cpp.o

src/mbgl/renderer/render_layer.i: src/mbgl/renderer/render_layer.cpp.i

.PHONY : src/mbgl/renderer/render_layer.i

# target to preprocess a source file
src/mbgl/renderer/render_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_layer.cpp.i
.PHONY : src/mbgl/renderer/render_layer.cpp.i

src/mbgl/renderer/render_layer.s: src/mbgl/renderer/render_layer.cpp.s

.PHONY : src/mbgl/renderer/render_layer.s

# target to generate assembly for a file
src/mbgl/renderer/render_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_layer.cpp.s
.PHONY : src/mbgl/renderer/render_layer.cpp.s

src/mbgl/renderer/render_light.o: src/mbgl/renderer/render_light.cpp.o

.PHONY : src/mbgl/renderer/render_light.o

# target to build an object file
src/mbgl/renderer/render_light.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_light.cpp.o
.PHONY : src/mbgl/renderer/render_light.cpp.o

src/mbgl/renderer/render_light.i: src/mbgl/renderer/render_light.cpp.i

.PHONY : src/mbgl/renderer/render_light.i

# target to preprocess a source file
src/mbgl/renderer/render_light.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_light.cpp.i
.PHONY : src/mbgl/renderer/render_light.cpp.i

src/mbgl/renderer/render_light.s: src/mbgl/renderer/render_light.cpp.s

.PHONY : src/mbgl/renderer/render_light.s

# target to generate assembly for a file
src/mbgl/renderer/render_light.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_light.cpp.s
.PHONY : src/mbgl/renderer/render_light.cpp.s

src/mbgl/renderer/render_source.o: src/mbgl/renderer/render_source.cpp.o

.PHONY : src/mbgl/renderer/render_source.o

# target to build an object file
src/mbgl/renderer/render_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_source.cpp.o
.PHONY : src/mbgl/renderer/render_source.cpp.o

src/mbgl/renderer/render_source.i: src/mbgl/renderer/render_source.cpp.i

.PHONY : src/mbgl/renderer/render_source.i

# target to preprocess a source file
src/mbgl/renderer/render_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_source.cpp.i
.PHONY : src/mbgl/renderer/render_source.cpp.i

src/mbgl/renderer/render_source.s: src/mbgl/renderer/render_source.cpp.s

.PHONY : src/mbgl/renderer/render_source.s

# target to generate assembly for a file
src/mbgl/renderer/render_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_source.cpp.s
.PHONY : src/mbgl/renderer/render_source.cpp.s

src/mbgl/renderer/render_static_data.o: src/mbgl/renderer/render_static_data.cpp.o

.PHONY : src/mbgl/renderer/render_static_data.o

# target to build an object file
src/mbgl/renderer/render_static_data.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_static_data.cpp.o
.PHONY : src/mbgl/renderer/render_static_data.cpp.o

src/mbgl/renderer/render_static_data.i: src/mbgl/renderer/render_static_data.cpp.i

.PHONY : src/mbgl/renderer/render_static_data.i

# target to preprocess a source file
src/mbgl/renderer/render_static_data.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_static_data.cpp.i
.PHONY : src/mbgl/renderer/render_static_data.cpp.i

src/mbgl/renderer/render_static_data.s: src/mbgl/renderer/render_static_data.cpp.s

.PHONY : src/mbgl/renderer/render_static_data.s

# target to generate assembly for a file
src/mbgl/renderer/render_static_data.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_static_data.cpp.s
.PHONY : src/mbgl/renderer/render_static_data.cpp.s

src/mbgl/renderer/render_tile.o: src/mbgl/renderer/render_tile.cpp.o

.PHONY : src/mbgl/renderer/render_tile.o

# target to build an object file
src/mbgl/renderer/render_tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_tile.cpp.o
.PHONY : src/mbgl/renderer/render_tile.cpp.o

src/mbgl/renderer/render_tile.i: src/mbgl/renderer/render_tile.cpp.i

.PHONY : src/mbgl/renderer/render_tile.i

# target to preprocess a source file
src/mbgl/renderer/render_tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_tile.cpp.i
.PHONY : src/mbgl/renderer/render_tile.cpp.i

src/mbgl/renderer/render_tile.s: src/mbgl/renderer/render_tile.cpp.s

.PHONY : src/mbgl/renderer/render_tile.s

# target to generate assembly for a file
src/mbgl/renderer/render_tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/render_tile.cpp.s
.PHONY : src/mbgl/renderer/render_tile.cpp.s

src/mbgl/renderer/renderer.o: src/mbgl/renderer/renderer.cpp.o

.PHONY : src/mbgl/renderer/renderer.o

# target to build an object file
src/mbgl/renderer/renderer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer.cpp.o
.PHONY : src/mbgl/renderer/renderer.cpp.o

src/mbgl/renderer/renderer.i: src/mbgl/renderer/renderer.cpp.i

.PHONY : src/mbgl/renderer/renderer.i

# target to preprocess a source file
src/mbgl/renderer/renderer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer.cpp.i
.PHONY : src/mbgl/renderer/renderer.cpp.i

src/mbgl/renderer/renderer.s: src/mbgl/renderer/renderer.cpp.s

.PHONY : src/mbgl/renderer/renderer.s

# target to generate assembly for a file
src/mbgl/renderer/renderer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer.cpp.s
.PHONY : src/mbgl/renderer/renderer.cpp.s

src/mbgl/renderer/renderer_backend.o: src/mbgl/renderer/renderer_backend.cpp.o

.PHONY : src/mbgl/renderer/renderer_backend.o

# target to build an object file
src/mbgl/renderer/renderer_backend.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer_backend.cpp.o
.PHONY : src/mbgl/renderer/renderer_backend.cpp.o

src/mbgl/renderer/renderer_backend.i: src/mbgl/renderer/renderer_backend.cpp.i

.PHONY : src/mbgl/renderer/renderer_backend.i

# target to preprocess a source file
src/mbgl/renderer/renderer_backend.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer_backend.cpp.i
.PHONY : src/mbgl/renderer/renderer_backend.cpp.i

src/mbgl/renderer/renderer_backend.s: src/mbgl/renderer/renderer_backend.cpp.s

.PHONY : src/mbgl/renderer/renderer_backend.s

# target to generate assembly for a file
src/mbgl/renderer/renderer_backend.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer_backend.cpp.s
.PHONY : src/mbgl/renderer/renderer_backend.cpp.s

src/mbgl/renderer/renderer_impl.o: src/mbgl/renderer/renderer_impl.cpp.o

.PHONY : src/mbgl/renderer/renderer_impl.o

# target to build an object file
src/mbgl/renderer/renderer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer_impl.cpp.o
.PHONY : src/mbgl/renderer/renderer_impl.cpp.o

src/mbgl/renderer/renderer_impl.i: src/mbgl/renderer/renderer_impl.cpp.i

.PHONY : src/mbgl/renderer/renderer_impl.i

# target to preprocess a source file
src/mbgl/renderer/renderer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer_impl.cpp.i
.PHONY : src/mbgl/renderer/renderer_impl.cpp.i

src/mbgl/renderer/renderer_impl.s: src/mbgl/renderer/renderer_impl.cpp.s

.PHONY : src/mbgl/renderer/renderer_impl.s

# target to generate assembly for a file
src/mbgl/renderer/renderer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/renderer_impl.cpp.s
.PHONY : src/mbgl/renderer/renderer_impl.cpp.s

src/mbgl/renderer/sources/render_geojson_source.o: src/mbgl/renderer/sources/render_geojson_source.cpp.o

.PHONY : src/mbgl/renderer/sources/render_geojson_source.o

# target to build an object file
src/mbgl/renderer/sources/render_geojson_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_geojson_source.cpp.o
.PHONY : src/mbgl/renderer/sources/render_geojson_source.cpp.o

src/mbgl/renderer/sources/render_geojson_source.i: src/mbgl/renderer/sources/render_geojson_source.cpp.i

.PHONY : src/mbgl/renderer/sources/render_geojson_source.i

# target to preprocess a source file
src/mbgl/renderer/sources/render_geojson_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_geojson_source.cpp.i
.PHONY : src/mbgl/renderer/sources/render_geojson_source.cpp.i

src/mbgl/renderer/sources/render_geojson_source.s: src/mbgl/renderer/sources/render_geojson_source.cpp.s

.PHONY : src/mbgl/renderer/sources/render_geojson_source.s

# target to generate assembly for a file
src/mbgl/renderer/sources/render_geojson_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_geojson_source.cpp.s
.PHONY : src/mbgl/renderer/sources/render_geojson_source.cpp.s

src/mbgl/renderer/sources/render_image_source.o: src/mbgl/renderer/sources/render_image_source.cpp.o

.PHONY : src/mbgl/renderer/sources/render_image_source.o

# target to build an object file
src/mbgl/renderer/sources/render_image_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_image_source.cpp.o
.PHONY : src/mbgl/renderer/sources/render_image_source.cpp.o

src/mbgl/renderer/sources/render_image_source.i: src/mbgl/renderer/sources/render_image_source.cpp.i

.PHONY : src/mbgl/renderer/sources/render_image_source.i

# target to preprocess a source file
src/mbgl/renderer/sources/render_image_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_image_source.cpp.i
.PHONY : src/mbgl/renderer/sources/render_image_source.cpp.i

src/mbgl/renderer/sources/render_image_source.s: src/mbgl/renderer/sources/render_image_source.cpp.s

.PHONY : src/mbgl/renderer/sources/render_image_source.s

# target to generate assembly for a file
src/mbgl/renderer/sources/render_image_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_image_source.cpp.s
.PHONY : src/mbgl/renderer/sources/render_image_source.cpp.s

src/mbgl/renderer/sources/render_raster_source.o: src/mbgl/renderer/sources/render_raster_source.cpp.o

.PHONY : src/mbgl/renderer/sources/render_raster_source.o

# target to build an object file
src/mbgl/renderer/sources/render_raster_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_raster_source.cpp.o
.PHONY : src/mbgl/renderer/sources/render_raster_source.cpp.o

src/mbgl/renderer/sources/render_raster_source.i: src/mbgl/renderer/sources/render_raster_source.cpp.i

.PHONY : src/mbgl/renderer/sources/render_raster_source.i

# target to preprocess a source file
src/mbgl/renderer/sources/render_raster_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_raster_source.cpp.i
.PHONY : src/mbgl/renderer/sources/render_raster_source.cpp.i

src/mbgl/renderer/sources/render_raster_source.s: src/mbgl/renderer/sources/render_raster_source.cpp.s

.PHONY : src/mbgl/renderer/sources/render_raster_source.s

# target to generate assembly for a file
src/mbgl/renderer/sources/render_raster_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_raster_source.cpp.s
.PHONY : src/mbgl/renderer/sources/render_raster_source.cpp.s

src/mbgl/renderer/sources/render_vector_source.o: src/mbgl/renderer/sources/render_vector_source.cpp.o

.PHONY : src/mbgl/renderer/sources/render_vector_source.o

# target to build an object file
src/mbgl/renderer/sources/render_vector_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_vector_source.cpp.o
.PHONY : src/mbgl/renderer/sources/render_vector_source.cpp.o

src/mbgl/renderer/sources/render_vector_source.i: src/mbgl/renderer/sources/render_vector_source.cpp.i

.PHONY : src/mbgl/renderer/sources/render_vector_source.i

# target to preprocess a source file
src/mbgl/renderer/sources/render_vector_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_vector_source.cpp.i
.PHONY : src/mbgl/renderer/sources/render_vector_source.cpp.i

src/mbgl/renderer/sources/render_vector_source.s: src/mbgl/renderer/sources/render_vector_source.cpp.s

.PHONY : src/mbgl/renderer/sources/render_vector_source.s

# target to generate assembly for a file
src/mbgl/renderer/sources/render_vector_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/sources/render_vector_source.cpp.s
.PHONY : src/mbgl/renderer/sources/render_vector_source.cpp.s

src/mbgl/renderer/style_diff.o: src/mbgl/renderer/style_diff.cpp.o

.PHONY : src/mbgl/renderer/style_diff.o

# target to build an object file
src/mbgl/renderer/style_diff.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/style_diff.cpp.o
.PHONY : src/mbgl/renderer/style_diff.cpp.o

src/mbgl/renderer/style_diff.i: src/mbgl/renderer/style_diff.cpp.i

.PHONY : src/mbgl/renderer/style_diff.i

# target to preprocess a source file
src/mbgl/renderer/style_diff.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/style_diff.cpp.i
.PHONY : src/mbgl/renderer/style_diff.cpp.i

src/mbgl/renderer/style_diff.s: src/mbgl/renderer/style_diff.cpp.s

.PHONY : src/mbgl/renderer/style_diff.s

# target to generate assembly for a file
src/mbgl/renderer/style_diff.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/style_diff.cpp.s
.PHONY : src/mbgl/renderer/style_diff.cpp.s

src/mbgl/renderer/tile_pyramid.o: src/mbgl/renderer/tile_pyramid.cpp.o

.PHONY : src/mbgl/renderer/tile_pyramid.o

# target to build an object file
src/mbgl/renderer/tile_pyramid.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/tile_pyramid.cpp.o
.PHONY : src/mbgl/renderer/tile_pyramid.cpp.o

src/mbgl/renderer/tile_pyramid.i: src/mbgl/renderer/tile_pyramid.cpp.i

.PHONY : src/mbgl/renderer/tile_pyramid.i

# target to preprocess a source file
src/mbgl/renderer/tile_pyramid.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/tile_pyramid.cpp.i
.PHONY : src/mbgl/renderer/tile_pyramid.cpp.i

src/mbgl/renderer/tile_pyramid.s: src/mbgl/renderer/tile_pyramid.cpp.s

.PHONY : src/mbgl/renderer/tile_pyramid.s

# target to generate assembly for a file
src/mbgl/renderer/tile_pyramid.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/renderer/tile_pyramid.cpp.s
.PHONY : src/mbgl/renderer/tile_pyramid.cpp.s

src/mbgl/shaders/circle.o: src/mbgl/shaders/circle.cpp.o

.PHONY : src/mbgl/shaders/circle.o

# target to build an object file
src/mbgl/shaders/circle.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/circle.cpp.o
.PHONY : src/mbgl/shaders/circle.cpp.o

src/mbgl/shaders/circle.i: src/mbgl/shaders/circle.cpp.i

.PHONY : src/mbgl/shaders/circle.i

# target to preprocess a source file
src/mbgl/shaders/circle.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/circle.cpp.i
.PHONY : src/mbgl/shaders/circle.cpp.i

src/mbgl/shaders/circle.s: src/mbgl/shaders/circle.cpp.s

.PHONY : src/mbgl/shaders/circle.s

# target to generate assembly for a file
src/mbgl/shaders/circle.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/circle.cpp.s
.PHONY : src/mbgl/shaders/circle.cpp.s

src/mbgl/shaders/collision_box.o: src/mbgl/shaders/collision_box.cpp.o

.PHONY : src/mbgl/shaders/collision_box.o

# target to build an object file
src/mbgl/shaders/collision_box.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/collision_box.cpp.o
.PHONY : src/mbgl/shaders/collision_box.cpp.o

src/mbgl/shaders/collision_box.i: src/mbgl/shaders/collision_box.cpp.i

.PHONY : src/mbgl/shaders/collision_box.i

# target to preprocess a source file
src/mbgl/shaders/collision_box.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/collision_box.cpp.i
.PHONY : src/mbgl/shaders/collision_box.cpp.i

src/mbgl/shaders/collision_box.s: src/mbgl/shaders/collision_box.cpp.s

.PHONY : src/mbgl/shaders/collision_box.s

# target to generate assembly for a file
src/mbgl/shaders/collision_box.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/collision_box.cpp.s
.PHONY : src/mbgl/shaders/collision_box.cpp.s

src/mbgl/shaders/debug.o: src/mbgl/shaders/debug.cpp.o

.PHONY : src/mbgl/shaders/debug.o

# target to build an object file
src/mbgl/shaders/debug.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/debug.cpp.o
.PHONY : src/mbgl/shaders/debug.cpp.o

src/mbgl/shaders/debug.i: src/mbgl/shaders/debug.cpp.i

.PHONY : src/mbgl/shaders/debug.i

# target to preprocess a source file
src/mbgl/shaders/debug.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/debug.cpp.i
.PHONY : src/mbgl/shaders/debug.cpp.i

src/mbgl/shaders/debug.s: src/mbgl/shaders/debug.cpp.s

.PHONY : src/mbgl/shaders/debug.s

# target to generate assembly for a file
src/mbgl/shaders/debug.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/debug.cpp.s
.PHONY : src/mbgl/shaders/debug.cpp.s

src/mbgl/shaders/extrusion_texture.o: src/mbgl/shaders/extrusion_texture.cpp.o

.PHONY : src/mbgl/shaders/extrusion_texture.o

# target to build an object file
src/mbgl/shaders/extrusion_texture.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/extrusion_texture.cpp.o
.PHONY : src/mbgl/shaders/extrusion_texture.cpp.o

src/mbgl/shaders/extrusion_texture.i: src/mbgl/shaders/extrusion_texture.cpp.i

.PHONY : src/mbgl/shaders/extrusion_texture.i

# target to preprocess a source file
src/mbgl/shaders/extrusion_texture.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/extrusion_texture.cpp.i
.PHONY : src/mbgl/shaders/extrusion_texture.cpp.i

src/mbgl/shaders/extrusion_texture.s: src/mbgl/shaders/extrusion_texture.cpp.s

.PHONY : src/mbgl/shaders/extrusion_texture.s

# target to generate assembly for a file
src/mbgl/shaders/extrusion_texture.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/extrusion_texture.cpp.s
.PHONY : src/mbgl/shaders/extrusion_texture.cpp.s

src/mbgl/shaders/fill.o: src/mbgl/shaders/fill.cpp.o

.PHONY : src/mbgl/shaders/fill.o

# target to build an object file
src/mbgl/shaders/fill.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill.cpp.o
.PHONY : src/mbgl/shaders/fill.cpp.o

src/mbgl/shaders/fill.i: src/mbgl/shaders/fill.cpp.i

.PHONY : src/mbgl/shaders/fill.i

# target to preprocess a source file
src/mbgl/shaders/fill.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill.cpp.i
.PHONY : src/mbgl/shaders/fill.cpp.i

src/mbgl/shaders/fill.s: src/mbgl/shaders/fill.cpp.s

.PHONY : src/mbgl/shaders/fill.s

# target to generate assembly for a file
src/mbgl/shaders/fill.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill.cpp.s
.PHONY : src/mbgl/shaders/fill.cpp.s

src/mbgl/shaders/fill_extrusion.o: src/mbgl/shaders/fill_extrusion.cpp.o

.PHONY : src/mbgl/shaders/fill_extrusion.o

# target to build an object file
src/mbgl/shaders/fill_extrusion.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_extrusion.cpp.o
.PHONY : src/mbgl/shaders/fill_extrusion.cpp.o

src/mbgl/shaders/fill_extrusion.i: src/mbgl/shaders/fill_extrusion.cpp.i

.PHONY : src/mbgl/shaders/fill_extrusion.i

# target to preprocess a source file
src/mbgl/shaders/fill_extrusion.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_extrusion.cpp.i
.PHONY : src/mbgl/shaders/fill_extrusion.cpp.i

src/mbgl/shaders/fill_extrusion.s: src/mbgl/shaders/fill_extrusion.cpp.s

.PHONY : src/mbgl/shaders/fill_extrusion.s

# target to generate assembly for a file
src/mbgl/shaders/fill_extrusion.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_extrusion.cpp.s
.PHONY : src/mbgl/shaders/fill_extrusion.cpp.s

src/mbgl/shaders/fill_extrusion_pattern.o: src/mbgl/shaders/fill_extrusion_pattern.cpp.o

.PHONY : src/mbgl/shaders/fill_extrusion_pattern.o

# target to build an object file
src/mbgl/shaders/fill_extrusion_pattern.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_extrusion_pattern.cpp.o
.PHONY : src/mbgl/shaders/fill_extrusion_pattern.cpp.o

src/mbgl/shaders/fill_extrusion_pattern.i: src/mbgl/shaders/fill_extrusion_pattern.cpp.i

.PHONY : src/mbgl/shaders/fill_extrusion_pattern.i

# target to preprocess a source file
src/mbgl/shaders/fill_extrusion_pattern.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_extrusion_pattern.cpp.i
.PHONY : src/mbgl/shaders/fill_extrusion_pattern.cpp.i

src/mbgl/shaders/fill_extrusion_pattern.s: src/mbgl/shaders/fill_extrusion_pattern.cpp.s

.PHONY : src/mbgl/shaders/fill_extrusion_pattern.s

# target to generate assembly for a file
src/mbgl/shaders/fill_extrusion_pattern.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_extrusion_pattern.cpp.s
.PHONY : src/mbgl/shaders/fill_extrusion_pattern.cpp.s

src/mbgl/shaders/fill_outline.o: src/mbgl/shaders/fill_outline.cpp.o

.PHONY : src/mbgl/shaders/fill_outline.o

# target to build an object file
src/mbgl/shaders/fill_outline.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_outline.cpp.o
.PHONY : src/mbgl/shaders/fill_outline.cpp.o

src/mbgl/shaders/fill_outline.i: src/mbgl/shaders/fill_outline.cpp.i

.PHONY : src/mbgl/shaders/fill_outline.i

# target to preprocess a source file
src/mbgl/shaders/fill_outline.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_outline.cpp.i
.PHONY : src/mbgl/shaders/fill_outline.cpp.i

src/mbgl/shaders/fill_outline.s: src/mbgl/shaders/fill_outline.cpp.s

.PHONY : src/mbgl/shaders/fill_outline.s

# target to generate assembly for a file
src/mbgl/shaders/fill_outline.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_outline.cpp.s
.PHONY : src/mbgl/shaders/fill_outline.cpp.s

src/mbgl/shaders/fill_outline_pattern.o: src/mbgl/shaders/fill_outline_pattern.cpp.o

.PHONY : src/mbgl/shaders/fill_outline_pattern.o

# target to build an object file
src/mbgl/shaders/fill_outline_pattern.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_outline_pattern.cpp.o
.PHONY : src/mbgl/shaders/fill_outline_pattern.cpp.o

src/mbgl/shaders/fill_outline_pattern.i: src/mbgl/shaders/fill_outline_pattern.cpp.i

.PHONY : src/mbgl/shaders/fill_outline_pattern.i

# target to preprocess a source file
src/mbgl/shaders/fill_outline_pattern.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_outline_pattern.cpp.i
.PHONY : src/mbgl/shaders/fill_outline_pattern.cpp.i

src/mbgl/shaders/fill_outline_pattern.s: src/mbgl/shaders/fill_outline_pattern.cpp.s

.PHONY : src/mbgl/shaders/fill_outline_pattern.s

# target to generate assembly for a file
src/mbgl/shaders/fill_outline_pattern.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_outline_pattern.cpp.s
.PHONY : src/mbgl/shaders/fill_outline_pattern.cpp.s

src/mbgl/shaders/fill_pattern.o: src/mbgl/shaders/fill_pattern.cpp.o

.PHONY : src/mbgl/shaders/fill_pattern.o

# target to build an object file
src/mbgl/shaders/fill_pattern.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_pattern.cpp.o
.PHONY : src/mbgl/shaders/fill_pattern.cpp.o

src/mbgl/shaders/fill_pattern.i: src/mbgl/shaders/fill_pattern.cpp.i

.PHONY : src/mbgl/shaders/fill_pattern.i

# target to preprocess a source file
src/mbgl/shaders/fill_pattern.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_pattern.cpp.i
.PHONY : src/mbgl/shaders/fill_pattern.cpp.i

src/mbgl/shaders/fill_pattern.s: src/mbgl/shaders/fill_pattern.cpp.s

.PHONY : src/mbgl/shaders/fill_pattern.s

# target to generate assembly for a file
src/mbgl/shaders/fill_pattern.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/fill_pattern.cpp.s
.PHONY : src/mbgl/shaders/fill_pattern.cpp.s

src/mbgl/shaders/line.o: src/mbgl/shaders/line.cpp.o

.PHONY : src/mbgl/shaders/line.o

# target to build an object file
src/mbgl/shaders/line.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line.cpp.o
.PHONY : src/mbgl/shaders/line.cpp.o

src/mbgl/shaders/line.i: src/mbgl/shaders/line.cpp.i

.PHONY : src/mbgl/shaders/line.i

# target to preprocess a source file
src/mbgl/shaders/line.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line.cpp.i
.PHONY : src/mbgl/shaders/line.cpp.i

src/mbgl/shaders/line.s: src/mbgl/shaders/line.cpp.s

.PHONY : src/mbgl/shaders/line.s

# target to generate assembly for a file
src/mbgl/shaders/line.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line.cpp.s
.PHONY : src/mbgl/shaders/line.cpp.s

src/mbgl/shaders/line_pattern.o: src/mbgl/shaders/line_pattern.cpp.o

.PHONY : src/mbgl/shaders/line_pattern.o

# target to build an object file
src/mbgl/shaders/line_pattern.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line_pattern.cpp.o
.PHONY : src/mbgl/shaders/line_pattern.cpp.o

src/mbgl/shaders/line_pattern.i: src/mbgl/shaders/line_pattern.cpp.i

.PHONY : src/mbgl/shaders/line_pattern.i

# target to preprocess a source file
src/mbgl/shaders/line_pattern.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line_pattern.cpp.i
.PHONY : src/mbgl/shaders/line_pattern.cpp.i

src/mbgl/shaders/line_pattern.s: src/mbgl/shaders/line_pattern.cpp.s

.PHONY : src/mbgl/shaders/line_pattern.s

# target to generate assembly for a file
src/mbgl/shaders/line_pattern.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line_pattern.cpp.s
.PHONY : src/mbgl/shaders/line_pattern.cpp.s

src/mbgl/shaders/line_sdf.o: src/mbgl/shaders/line_sdf.cpp.o

.PHONY : src/mbgl/shaders/line_sdf.o

# target to build an object file
src/mbgl/shaders/line_sdf.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line_sdf.cpp.o
.PHONY : src/mbgl/shaders/line_sdf.cpp.o

src/mbgl/shaders/line_sdf.i: src/mbgl/shaders/line_sdf.cpp.i

.PHONY : src/mbgl/shaders/line_sdf.i

# target to preprocess a source file
src/mbgl/shaders/line_sdf.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line_sdf.cpp.i
.PHONY : src/mbgl/shaders/line_sdf.cpp.i

src/mbgl/shaders/line_sdf.s: src/mbgl/shaders/line_sdf.cpp.s

.PHONY : src/mbgl/shaders/line_sdf.s

# target to generate assembly for a file
src/mbgl/shaders/line_sdf.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/line_sdf.cpp.s
.PHONY : src/mbgl/shaders/line_sdf.cpp.s

src/mbgl/shaders/preludes.o: src/mbgl/shaders/preludes.cpp.o

.PHONY : src/mbgl/shaders/preludes.o

# target to build an object file
src/mbgl/shaders/preludes.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/preludes.cpp.o
.PHONY : src/mbgl/shaders/preludes.cpp.o

src/mbgl/shaders/preludes.i: src/mbgl/shaders/preludes.cpp.i

.PHONY : src/mbgl/shaders/preludes.i

# target to preprocess a source file
src/mbgl/shaders/preludes.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/preludes.cpp.i
.PHONY : src/mbgl/shaders/preludes.cpp.i

src/mbgl/shaders/preludes.s: src/mbgl/shaders/preludes.cpp.s

.PHONY : src/mbgl/shaders/preludes.s

# target to generate assembly for a file
src/mbgl/shaders/preludes.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/preludes.cpp.s
.PHONY : src/mbgl/shaders/preludes.cpp.s

src/mbgl/shaders/raster.o: src/mbgl/shaders/raster.cpp.o

.PHONY : src/mbgl/shaders/raster.o

# target to build an object file
src/mbgl/shaders/raster.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/raster.cpp.o
.PHONY : src/mbgl/shaders/raster.cpp.o

src/mbgl/shaders/raster.i: src/mbgl/shaders/raster.cpp.i

.PHONY : src/mbgl/shaders/raster.i

# target to preprocess a source file
src/mbgl/shaders/raster.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/raster.cpp.i
.PHONY : src/mbgl/shaders/raster.cpp.i

src/mbgl/shaders/raster.s: src/mbgl/shaders/raster.cpp.s

.PHONY : src/mbgl/shaders/raster.s

# target to generate assembly for a file
src/mbgl/shaders/raster.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/raster.cpp.s
.PHONY : src/mbgl/shaders/raster.cpp.s

src/mbgl/shaders/shaders.o: src/mbgl/shaders/shaders.cpp.o

.PHONY : src/mbgl/shaders/shaders.o

# target to build an object file
src/mbgl/shaders/shaders.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/shaders.cpp.o
.PHONY : src/mbgl/shaders/shaders.cpp.o

src/mbgl/shaders/shaders.i: src/mbgl/shaders/shaders.cpp.i

.PHONY : src/mbgl/shaders/shaders.i

# target to preprocess a source file
src/mbgl/shaders/shaders.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/shaders.cpp.i
.PHONY : src/mbgl/shaders/shaders.cpp.i

src/mbgl/shaders/shaders.s: src/mbgl/shaders/shaders.cpp.s

.PHONY : src/mbgl/shaders/shaders.s

# target to generate assembly for a file
src/mbgl/shaders/shaders.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/shaders.cpp.s
.PHONY : src/mbgl/shaders/shaders.cpp.s

src/mbgl/shaders/symbol_icon.o: src/mbgl/shaders/symbol_icon.cpp.o

.PHONY : src/mbgl/shaders/symbol_icon.o

# target to build an object file
src/mbgl/shaders/symbol_icon.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/symbol_icon.cpp.o
.PHONY : src/mbgl/shaders/symbol_icon.cpp.o

src/mbgl/shaders/symbol_icon.i: src/mbgl/shaders/symbol_icon.cpp.i

.PHONY : src/mbgl/shaders/symbol_icon.i

# target to preprocess a source file
src/mbgl/shaders/symbol_icon.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/symbol_icon.cpp.i
.PHONY : src/mbgl/shaders/symbol_icon.cpp.i

src/mbgl/shaders/symbol_icon.s: src/mbgl/shaders/symbol_icon.cpp.s

.PHONY : src/mbgl/shaders/symbol_icon.s

# target to generate assembly for a file
src/mbgl/shaders/symbol_icon.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/symbol_icon.cpp.s
.PHONY : src/mbgl/shaders/symbol_icon.cpp.s

src/mbgl/shaders/symbol_sdf.o: src/mbgl/shaders/symbol_sdf.cpp.o

.PHONY : src/mbgl/shaders/symbol_sdf.o

# target to build an object file
src/mbgl/shaders/symbol_sdf.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/symbol_sdf.cpp.o
.PHONY : src/mbgl/shaders/symbol_sdf.cpp.o

src/mbgl/shaders/symbol_sdf.i: src/mbgl/shaders/symbol_sdf.cpp.i

.PHONY : src/mbgl/shaders/symbol_sdf.i

# target to preprocess a source file
src/mbgl/shaders/symbol_sdf.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/symbol_sdf.cpp.i
.PHONY : src/mbgl/shaders/symbol_sdf.cpp.i

src/mbgl/shaders/symbol_sdf.s: src/mbgl/shaders/symbol_sdf.cpp.s

.PHONY : src/mbgl/shaders/symbol_sdf.s

# target to generate assembly for a file
src/mbgl/shaders/symbol_sdf.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/shaders/symbol_sdf.cpp.s
.PHONY : src/mbgl/shaders/symbol_sdf.cpp.s

src/mbgl/sprite/sprite_loader.o: src/mbgl/sprite/sprite_loader.cpp.o

.PHONY : src/mbgl/sprite/sprite_loader.o

# target to build an object file
src/mbgl/sprite/sprite_loader.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_loader.cpp.o
.PHONY : src/mbgl/sprite/sprite_loader.cpp.o

src/mbgl/sprite/sprite_loader.i: src/mbgl/sprite/sprite_loader.cpp.i

.PHONY : src/mbgl/sprite/sprite_loader.i

# target to preprocess a source file
src/mbgl/sprite/sprite_loader.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_loader.cpp.i
.PHONY : src/mbgl/sprite/sprite_loader.cpp.i

src/mbgl/sprite/sprite_loader.s: src/mbgl/sprite/sprite_loader.cpp.s

.PHONY : src/mbgl/sprite/sprite_loader.s

# target to generate assembly for a file
src/mbgl/sprite/sprite_loader.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_loader.cpp.s
.PHONY : src/mbgl/sprite/sprite_loader.cpp.s

src/mbgl/sprite/sprite_loader_worker.o: src/mbgl/sprite/sprite_loader_worker.cpp.o

.PHONY : src/mbgl/sprite/sprite_loader_worker.o

# target to build an object file
src/mbgl/sprite/sprite_loader_worker.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_loader_worker.cpp.o
.PHONY : src/mbgl/sprite/sprite_loader_worker.cpp.o

src/mbgl/sprite/sprite_loader_worker.i: src/mbgl/sprite/sprite_loader_worker.cpp.i

.PHONY : src/mbgl/sprite/sprite_loader_worker.i

# target to preprocess a source file
src/mbgl/sprite/sprite_loader_worker.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_loader_worker.cpp.i
.PHONY : src/mbgl/sprite/sprite_loader_worker.cpp.i

src/mbgl/sprite/sprite_loader_worker.s: src/mbgl/sprite/sprite_loader_worker.cpp.s

.PHONY : src/mbgl/sprite/sprite_loader_worker.s

# target to generate assembly for a file
src/mbgl/sprite/sprite_loader_worker.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_loader_worker.cpp.s
.PHONY : src/mbgl/sprite/sprite_loader_worker.cpp.s

src/mbgl/sprite/sprite_parser.o: src/mbgl/sprite/sprite_parser.cpp.o

.PHONY : src/mbgl/sprite/sprite_parser.o

# target to build an object file
src/mbgl/sprite/sprite_parser.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_parser.cpp.o
.PHONY : src/mbgl/sprite/sprite_parser.cpp.o

src/mbgl/sprite/sprite_parser.i: src/mbgl/sprite/sprite_parser.cpp.i

.PHONY : src/mbgl/sprite/sprite_parser.i

# target to preprocess a source file
src/mbgl/sprite/sprite_parser.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_parser.cpp.i
.PHONY : src/mbgl/sprite/sprite_parser.cpp.i

src/mbgl/sprite/sprite_parser.s: src/mbgl/sprite/sprite_parser.cpp.s

.PHONY : src/mbgl/sprite/sprite_parser.s

# target to generate assembly for a file
src/mbgl/sprite/sprite_parser.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/sprite/sprite_parser.cpp.s
.PHONY : src/mbgl/sprite/sprite_parser.cpp.s

src/mbgl/storage/network_status.o: src/mbgl/storage/network_status.cpp.o

.PHONY : src/mbgl/storage/network_status.o

# target to build an object file
src/mbgl/storage/network_status.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/network_status.cpp.o
.PHONY : src/mbgl/storage/network_status.cpp.o

src/mbgl/storage/network_status.i: src/mbgl/storage/network_status.cpp.i

.PHONY : src/mbgl/storage/network_status.i

# target to preprocess a source file
src/mbgl/storage/network_status.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/network_status.cpp.i
.PHONY : src/mbgl/storage/network_status.cpp.i

src/mbgl/storage/network_status.s: src/mbgl/storage/network_status.cpp.s

.PHONY : src/mbgl/storage/network_status.s

# target to generate assembly for a file
src/mbgl/storage/network_status.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/network_status.cpp.s
.PHONY : src/mbgl/storage/network_status.cpp.s

src/mbgl/storage/resource.o: src/mbgl/storage/resource.cpp.o

.PHONY : src/mbgl/storage/resource.o

# target to build an object file
src/mbgl/storage/resource.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/resource.cpp.o
.PHONY : src/mbgl/storage/resource.cpp.o

src/mbgl/storage/resource.i: src/mbgl/storage/resource.cpp.i

.PHONY : src/mbgl/storage/resource.i

# target to preprocess a source file
src/mbgl/storage/resource.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/resource.cpp.i
.PHONY : src/mbgl/storage/resource.cpp.i

src/mbgl/storage/resource.s: src/mbgl/storage/resource.cpp.s

.PHONY : src/mbgl/storage/resource.s

# target to generate assembly for a file
src/mbgl/storage/resource.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/resource.cpp.s
.PHONY : src/mbgl/storage/resource.cpp.s

src/mbgl/storage/resource_transform.o: src/mbgl/storage/resource_transform.cpp.o

.PHONY : src/mbgl/storage/resource_transform.o

# target to build an object file
src/mbgl/storage/resource_transform.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/resource_transform.cpp.o
.PHONY : src/mbgl/storage/resource_transform.cpp.o

src/mbgl/storage/resource_transform.i: src/mbgl/storage/resource_transform.cpp.i

.PHONY : src/mbgl/storage/resource_transform.i

# target to preprocess a source file
src/mbgl/storage/resource_transform.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/resource_transform.cpp.i
.PHONY : src/mbgl/storage/resource_transform.cpp.i

src/mbgl/storage/resource_transform.s: src/mbgl/storage/resource_transform.cpp.s

.PHONY : src/mbgl/storage/resource_transform.s

# target to generate assembly for a file
src/mbgl/storage/resource_transform.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/resource_transform.cpp.s
.PHONY : src/mbgl/storage/resource_transform.cpp.s

src/mbgl/storage/response.o: src/mbgl/storage/response.cpp.o

.PHONY : src/mbgl/storage/response.o

# target to build an object file
src/mbgl/storage/response.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/response.cpp.o
.PHONY : src/mbgl/storage/response.cpp.o

src/mbgl/storage/response.i: src/mbgl/storage/response.cpp.i

.PHONY : src/mbgl/storage/response.i

# target to preprocess a source file
src/mbgl/storage/response.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/response.cpp.i
.PHONY : src/mbgl/storage/response.cpp.i

src/mbgl/storage/response.s: src/mbgl/storage/response.cpp.s

.PHONY : src/mbgl/storage/response.s

# target to generate assembly for a file
src/mbgl/storage/response.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/storage/response.cpp.s
.PHONY : src/mbgl/storage/response.cpp.s

src/mbgl/style/conversion/constant.o: src/mbgl/style/conversion/constant.cpp.o

.PHONY : src/mbgl/style/conversion/constant.o

# target to build an object file
src/mbgl/style/conversion/constant.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/constant.cpp.o
.PHONY : src/mbgl/style/conversion/constant.cpp.o

src/mbgl/style/conversion/constant.i: src/mbgl/style/conversion/constant.cpp.i

.PHONY : src/mbgl/style/conversion/constant.i

# target to preprocess a source file
src/mbgl/style/conversion/constant.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/constant.cpp.i
.PHONY : src/mbgl/style/conversion/constant.cpp.i

src/mbgl/style/conversion/constant.s: src/mbgl/style/conversion/constant.cpp.s

.PHONY : src/mbgl/style/conversion/constant.s

# target to generate assembly for a file
src/mbgl/style/conversion/constant.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/constant.cpp.s
.PHONY : src/mbgl/style/conversion/constant.cpp.s

src/mbgl/style/conversion/coordinate.o: src/mbgl/style/conversion/coordinate.cpp.o

.PHONY : src/mbgl/style/conversion/coordinate.o

# target to build an object file
src/mbgl/style/conversion/coordinate.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/coordinate.cpp.o
.PHONY : src/mbgl/style/conversion/coordinate.cpp.o

src/mbgl/style/conversion/coordinate.i: src/mbgl/style/conversion/coordinate.cpp.i

.PHONY : src/mbgl/style/conversion/coordinate.i

# target to preprocess a source file
src/mbgl/style/conversion/coordinate.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/coordinate.cpp.i
.PHONY : src/mbgl/style/conversion/coordinate.cpp.i

src/mbgl/style/conversion/coordinate.s: src/mbgl/style/conversion/coordinate.cpp.s

.PHONY : src/mbgl/style/conversion/coordinate.s

# target to generate assembly for a file
src/mbgl/style/conversion/coordinate.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/coordinate.cpp.s
.PHONY : src/mbgl/style/conversion/coordinate.cpp.s

src/mbgl/style/conversion/filter.o: src/mbgl/style/conversion/filter.cpp.o

.PHONY : src/mbgl/style/conversion/filter.o

# target to build an object file
src/mbgl/style/conversion/filter.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/filter.cpp.o
.PHONY : src/mbgl/style/conversion/filter.cpp.o

src/mbgl/style/conversion/filter.i: src/mbgl/style/conversion/filter.cpp.i

.PHONY : src/mbgl/style/conversion/filter.i

# target to preprocess a source file
src/mbgl/style/conversion/filter.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/filter.cpp.i
.PHONY : src/mbgl/style/conversion/filter.cpp.i

src/mbgl/style/conversion/filter.s: src/mbgl/style/conversion/filter.cpp.s

.PHONY : src/mbgl/style/conversion/filter.s

# target to generate assembly for a file
src/mbgl/style/conversion/filter.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/filter.cpp.s
.PHONY : src/mbgl/style/conversion/filter.cpp.s

src/mbgl/style/conversion/geojson.o: src/mbgl/style/conversion/geojson.cpp.o

.PHONY : src/mbgl/style/conversion/geojson.o

# target to build an object file
src/mbgl/style/conversion/geojson.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/geojson.cpp.o
.PHONY : src/mbgl/style/conversion/geojson.cpp.o

src/mbgl/style/conversion/geojson.i: src/mbgl/style/conversion/geojson.cpp.i

.PHONY : src/mbgl/style/conversion/geojson.i

# target to preprocess a source file
src/mbgl/style/conversion/geojson.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/geojson.cpp.i
.PHONY : src/mbgl/style/conversion/geojson.cpp.i

src/mbgl/style/conversion/geojson.s: src/mbgl/style/conversion/geojson.cpp.s

.PHONY : src/mbgl/style/conversion/geojson.s

# target to generate assembly for a file
src/mbgl/style/conversion/geojson.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/geojson.cpp.s
.PHONY : src/mbgl/style/conversion/geojson.cpp.s

src/mbgl/style/conversion/geojson_options.o: src/mbgl/style/conversion/geojson_options.cpp.o

.PHONY : src/mbgl/style/conversion/geojson_options.o

# target to build an object file
src/mbgl/style/conversion/geojson_options.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/geojson_options.cpp.o
.PHONY : src/mbgl/style/conversion/geojson_options.cpp.o

src/mbgl/style/conversion/geojson_options.i: src/mbgl/style/conversion/geojson_options.cpp.i

.PHONY : src/mbgl/style/conversion/geojson_options.i

# target to preprocess a source file
src/mbgl/style/conversion/geojson_options.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/geojson_options.cpp.i
.PHONY : src/mbgl/style/conversion/geojson_options.cpp.i

src/mbgl/style/conversion/geojson_options.s: src/mbgl/style/conversion/geojson_options.cpp.s

.PHONY : src/mbgl/style/conversion/geojson_options.s

# target to generate assembly for a file
src/mbgl/style/conversion/geojson_options.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/geojson_options.cpp.s
.PHONY : src/mbgl/style/conversion/geojson_options.cpp.s

src/mbgl/style/conversion/layer.o: src/mbgl/style/conversion/layer.cpp.o

.PHONY : src/mbgl/style/conversion/layer.o

# target to build an object file
src/mbgl/style/conversion/layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/layer.cpp.o
.PHONY : src/mbgl/style/conversion/layer.cpp.o

src/mbgl/style/conversion/layer.i: src/mbgl/style/conversion/layer.cpp.i

.PHONY : src/mbgl/style/conversion/layer.i

# target to preprocess a source file
src/mbgl/style/conversion/layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/layer.cpp.i
.PHONY : src/mbgl/style/conversion/layer.cpp.i

src/mbgl/style/conversion/layer.s: src/mbgl/style/conversion/layer.cpp.s

.PHONY : src/mbgl/style/conversion/layer.s

# target to generate assembly for a file
src/mbgl/style/conversion/layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/layer.cpp.s
.PHONY : src/mbgl/style/conversion/layer.cpp.s

src/mbgl/style/conversion/light.o: src/mbgl/style/conversion/light.cpp.o

.PHONY : src/mbgl/style/conversion/light.o

# target to build an object file
src/mbgl/style/conversion/light.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/light.cpp.o
.PHONY : src/mbgl/style/conversion/light.cpp.o

src/mbgl/style/conversion/light.i: src/mbgl/style/conversion/light.cpp.i

.PHONY : src/mbgl/style/conversion/light.i

# target to preprocess a source file
src/mbgl/style/conversion/light.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/light.cpp.i
.PHONY : src/mbgl/style/conversion/light.cpp.i

src/mbgl/style/conversion/light.s: src/mbgl/style/conversion/light.cpp.s

.PHONY : src/mbgl/style/conversion/light.s

# target to generate assembly for a file
src/mbgl/style/conversion/light.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/light.cpp.s
.PHONY : src/mbgl/style/conversion/light.cpp.s

src/mbgl/style/conversion/position.o: src/mbgl/style/conversion/position.cpp.o

.PHONY : src/mbgl/style/conversion/position.o

# target to build an object file
src/mbgl/style/conversion/position.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/position.cpp.o
.PHONY : src/mbgl/style/conversion/position.cpp.o

src/mbgl/style/conversion/position.i: src/mbgl/style/conversion/position.cpp.i

.PHONY : src/mbgl/style/conversion/position.i

# target to preprocess a source file
src/mbgl/style/conversion/position.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/position.cpp.i
.PHONY : src/mbgl/style/conversion/position.cpp.i

src/mbgl/style/conversion/position.s: src/mbgl/style/conversion/position.cpp.s

.PHONY : src/mbgl/style/conversion/position.s

# target to generate assembly for a file
src/mbgl/style/conversion/position.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/position.cpp.s
.PHONY : src/mbgl/style/conversion/position.cpp.s

src/mbgl/style/conversion/source.o: src/mbgl/style/conversion/source.cpp.o

.PHONY : src/mbgl/style/conversion/source.o

# target to build an object file
src/mbgl/style/conversion/source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/source.cpp.o
.PHONY : src/mbgl/style/conversion/source.cpp.o

src/mbgl/style/conversion/source.i: src/mbgl/style/conversion/source.cpp.i

.PHONY : src/mbgl/style/conversion/source.i

# target to preprocess a source file
src/mbgl/style/conversion/source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/source.cpp.i
.PHONY : src/mbgl/style/conversion/source.cpp.i

src/mbgl/style/conversion/source.s: src/mbgl/style/conversion/source.cpp.s

.PHONY : src/mbgl/style/conversion/source.s

# target to generate assembly for a file
src/mbgl/style/conversion/source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/source.cpp.s
.PHONY : src/mbgl/style/conversion/source.cpp.s

src/mbgl/style/conversion/tileset.o: src/mbgl/style/conversion/tileset.cpp.o

.PHONY : src/mbgl/style/conversion/tileset.o

# target to build an object file
src/mbgl/style/conversion/tileset.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/tileset.cpp.o
.PHONY : src/mbgl/style/conversion/tileset.cpp.o

src/mbgl/style/conversion/tileset.i: src/mbgl/style/conversion/tileset.cpp.i

.PHONY : src/mbgl/style/conversion/tileset.i

# target to preprocess a source file
src/mbgl/style/conversion/tileset.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/tileset.cpp.i
.PHONY : src/mbgl/style/conversion/tileset.cpp.i

src/mbgl/style/conversion/tileset.s: src/mbgl/style/conversion/tileset.cpp.s

.PHONY : src/mbgl/style/conversion/tileset.s

# target to generate assembly for a file
src/mbgl/style/conversion/tileset.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/tileset.cpp.s
.PHONY : src/mbgl/style/conversion/tileset.cpp.s

src/mbgl/style/conversion/transition_options.o: src/mbgl/style/conversion/transition_options.cpp.o

.PHONY : src/mbgl/style/conversion/transition_options.o

# target to build an object file
src/mbgl/style/conversion/transition_options.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/transition_options.cpp.o
.PHONY : src/mbgl/style/conversion/transition_options.cpp.o

src/mbgl/style/conversion/transition_options.i: src/mbgl/style/conversion/transition_options.cpp.i

.PHONY : src/mbgl/style/conversion/transition_options.i

# target to preprocess a source file
src/mbgl/style/conversion/transition_options.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/transition_options.cpp.i
.PHONY : src/mbgl/style/conversion/transition_options.cpp.i

src/mbgl/style/conversion/transition_options.s: src/mbgl/style/conversion/transition_options.cpp.s

.PHONY : src/mbgl/style/conversion/transition_options.s

# target to generate assembly for a file
src/mbgl/style/conversion/transition_options.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/conversion/transition_options.cpp.s
.PHONY : src/mbgl/style/conversion/transition_options.cpp.s

src/mbgl/style/function/categorical_stops.o: src/mbgl/style/function/categorical_stops.cpp.o

.PHONY : src/mbgl/style/function/categorical_stops.o

# target to build an object file
src/mbgl/style/function/categorical_stops.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/function/categorical_stops.cpp.o
.PHONY : src/mbgl/style/function/categorical_stops.cpp.o

src/mbgl/style/function/categorical_stops.i: src/mbgl/style/function/categorical_stops.cpp.i

.PHONY : src/mbgl/style/function/categorical_stops.i

# target to preprocess a source file
src/mbgl/style/function/categorical_stops.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/function/categorical_stops.cpp.i
.PHONY : src/mbgl/style/function/categorical_stops.cpp.i

src/mbgl/style/function/categorical_stops.s: src/mbgl/style/function/categorical_stops.cpp.s

.PHONY : src/mbgl/style/function/categorical_stops.s

# target to generate assembly for a file
src/mbgl/style/function/categorical_stops.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/function/categorical_stops.cpp.s
.PHONY : src/mbgl/style/function/categorical_stops.cpp.s

src/mbgl/style/function/identity_stops.o: src/mbgl/style/function/identity_stops.cpp.o

.PHONY : src/mbgl/style/function/identity_stops.o

# target to build an object file
src/mbgl/style/function/identity_stops.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/function/identity_stops.cpp.o
.PHONY : src/mbgl/style/function/identity_stops.cpp.o

src/mbgl/style/function/identity_stops.i: src/mbgl/style/function/identity_stops.cpp.i

.PHONY : src/mbgl/style/function/identity_stops.i

# target to preprocess a source file
src/mbgl/style/function/identity_stops.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/function/identity_stops.cpp.i
.PHONY : src/mbgl/style/function/identity_stops.cpp.i

src/mbgl/style/function/identity_stops.s: src/mbgl/style/function/identity_stops.cpp.s

.PHONY : src/mbgl/style/function/identity_stops.s

# target to generate assembly for a file
src/mbgl/style/function/identity_stops.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/function/identity_stops.cpp.s
.PHONY : src/mbgl/style/function/identity_stops.cpp.s

src/mbgl/style/image.o: src/mbgl/style/image.cpp.o

.PHONY : src/mbgl/style/image.o

# target to build an object file
src/mbgl/style/image.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/image.cpp.o
.PHONY : src/mbgl/style/image.cpp.o

src/mbgl/style/image.i: src/mbgl/style/image.cpp.i

.PHONY : src/mbgl/style/image.i

# target to preprocess a source file
src/mbgl/style/image.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/image.cpp.i
.PHONY : src/mbgl/style/image.cpp.i

src/mbgl/style/image.s: src/mbgl/style/image.cpp.s

.PHONY : src/mbgl/style/image.s

# target to generate assembly for a file
src/mbgl/style/image.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/image.cpp.s
.PHONY : src/mbgl/style/image.cpp.s

src/mbgl/style/image_impl.o: src/mbgl/style/image_impl.cpp.o

.PHONY : src/mbgl/style/image_impl.o

# target to build an object file
src/mbgl/style/image_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/image_impl.cpp.o
.PHONY : src/mbgl/style/image_impl.cpp.o

src/mbgl/style/image_impl.i: src/mbgl/style/image_impl.cpp.i

.PHONY : src/mbgl/style/image_impl.i

# target to preprocess a source file
src/mbgl/style/image_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/image_impl.cpp.i
.PHONY : src/mbgl/style/image_impl.cpp.i

src/mbgl/style/image_impl.s: src/mbgl/style/image_impl.cpp.s

.PHONY : src/mbgl/style/image_impl.s

# target to generate assembly for a file
src/mbgl/style/image_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/image_impl.cpp.s
.PHONY : src/mbgl/style/image_impl.cpp.s

src/mbgl/style/layer.o: src/mbgl/style/layer.cpp.o

.PHONY : src/mbgl/style/layer.o

# target to build an object file
src/mbgl/style/layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layer.cpp.o
.PHONY : src/mbgl/style/layer.cpp.o

src/mbgl/style/layer.i: src/mbgl/style/layer.cpp.i

.PHONY : src/mbgl/style/layer.i

# target to preprocess a source file
src/mbgl/style/layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layer.cpp.i
.PHONY : src/mbgl/style/layer.cpp.i

src/mbgl/style/layer.s: src/mbgl/style/layer.cpp.s

.PHONY : src/mbgl/style/layer.s

# target to generate assembly for a file
src/mbgl/style/layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layer.cpp.s
.PHONY : src/mbgl/style/layer.cpp.s

src/mbgl/style/layer_impl.o: src/mbgl/style/layer_impl.cpp.o

.PHONY : src/mbgl/style/layer_impl.o

# target to build an object file
src/mbgl/style/layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layer_impl.cpp.o
.PHONY : src/mbgl/style/layer_impl.cpp.o

src/mbgl/style/layer_impl.i: src/mbgl/style/layer_impl.cpp.i

.PHONY : src/mbgl/style/layer_impl.i

# target to preprocess a source file
src/mbgl/style/layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layer_impl.cpp.i
.PHONY : src/mbgl/style/layer_impl.cpp.i

src/mbgl/style/layer_impl.s: src/mbgl/style/layer_impl.cpp.s

.PHONY : src/mbgl/style/layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layer_impl.cpp.s
.PHONY : src/mbgl/style/layer_impl.cpp.s

src/mbgl/style/layers/background_layer.o: src/mbgl/style/layers/background_layer.cpp.o

.PHONY : src/mbgl/style/layers/background_layer.o

# target to build an object file
src/mbgl/style/layers/background_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer.cpp.o
.PHONY : src/mbgl/style/layers/background_layer.cpp.o

src/mbgl/style/layers/background_layer.i: src/mbgl/style/layers/background_layer.cpp.i

.PHONY : src/mbgl/style/layers/background_layer.i

# target to preprocess a source file
src/mbgl/style/layers/background_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer.cpp.i
.PHONY : src/mbgl/style/layers/background_layer.cpp.i

src/mbgl/style/layers/background_layer.s: src/mbgl/style/layers/background_layer.cpp.s

.PHONY : src/mbgl/style/layers/background_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/background_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer.cpp.s
.PHONY : src/mbgl/style/layers/background_layer.cpp.s

src/mbgl/style/layers/background_layer_impl.o: src/mbgl/style/layers/background_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/background_layer_impl.o

# target to build an object file
src/mbgl/style/layers/background_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/background_layer_impl.cpp.o

src/mbgl/style/layers/background_layer_impl.i: src/mbgl/style/layers/background_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/background_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/background_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/background_layer_impl.cpp.i

src/mbgl/style/layers/background_layer_impl.s: src/mbgl/style/layers/background_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/background_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/background_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/background_layer_impl.cpp.s

src/mbgl/style/layers/background_layer_properties.o: src/mbgl/style/layers/background_layer_properties.cpp.o

.PHONY : src/mbgl/style/layers/background_layer_properties.o

# target to build an object file
src/mbgl/style/layers/background_layer_properties.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer_properties.cpp.o
.PHONY : src/mbgl/style/layers/background_layer_properties.cpp.o

src/mbgl/style/layers/background_layer_properties.i: src/mbgl/style/layers/background_layer_properties.cpp.i

.PHONY : src/mbgl/style/layers/background_layer_properties.i

# target to preprocess a source file
src/mbgl/style/layers/background_layer_properties.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer_properties.cpp.i
.PHONY : src/mbgl/style/layers/background_layer_properties.cpp.i

src/mbgl/style/layers/background_layer_properties.s: src/mbgl/style/layers/background_layer_properties.cpp.s

.PHONY : src/mbgl/style/layers/background_layer_properties.s

# target to generate assembly for a file
src/mbgl/style/layers/background_layer_properties.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/background_layer_properties.cpp.s
.PHONY : src/mbgl/style/layers/background_layer_properties.cpp.s

src/mbgl/style/layers/circle_layer.o: src/mbgl/style/layers/circle_layer.cpp.o

.PHONY : src/mbgl/style/layers/circle_layer.o

# target to build an object file
src/mbgl/style/layers/circle_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer.cpp.o
.PHONY : src/mbgl/style/layers/circle_layer.cpp.o

src/mbgl/style/layers/circle_layer.i: src/mbgl/style/layers/circle_layer.cpp.i

.PHONY : src/mbgl/style/layers/circle_layer.i

# target to preprocess a source file
src/mbgl/style/layers/circle_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer.cpp.i
.PHONY : src/mbgl/style/layers/circle_layer.cpp.i

src/mbgl/style/layers/circle_layer.s: src/mbgl/style/layers/circle_layer.cpp.s

.PHONY : src/mbgl/style/layers/circle_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/circle_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer.cpp.s
.PHONY : src/mbgl/style/layers/circle_layer.cpp.s

src/mbgl/style/layers/circle_layer_impl.o: src/mbgl/style/layers/circle_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/circle_layer_impl.o

# target to build an object file
src/mbgl/style/layers/circle_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/circle_layer_impl.cpp.o

src/mbgl/style/layers/circle_layer_impl.i: src/mbgl/style/layers/circle_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/circle_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/circle_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/circle_layer_impl.cpp.i

src/mbgl/style/layers/circle_layer_impl.s: src/mbgl/style/layers/circle_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/circle_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/circle_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/circle_layer_impl.cpp.s

src/mbgl/style/layers/circle_layer_properties.o: src/mbgl/style/layers/circle_layer_properties.cpp.o

.PHONY : src/mbgl/style/layers/circle_layer_properties.o

# target to build an object file
src/mbgl/style/layers/circle_layer_properties.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer_properties.cpp.o
.PHONY : src/mbgl/style/layers/circle_layer_properties.cpp.o

src/mbgl/style/layers/circle_layer_properties.i: src/mbgl/style/layers/circle_layer_properties.cpp.i

.PHONY : src/mbgl/style/layers/circle_layer_properties.i

# target to preprocess a source file
src/mbgl/style/layers/circle_layer_properties.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer_properties.cpp.i
.PHONY : src/mbgl/style/layers/circle_layer_properties.cpp.i

src/mbgl/style/layers/circle_layer_properties.s: src/mbgl/style/layers/circle_layer_properties.cpp.s

.PHONY : src/mbgl/style/layers/circle_layer_properties.s

# target to generate assembly for a file
src/mbgl/style/layers/circle_layer_properties.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/circle_layer_properties.cpp.s
.PHONY : src/mbgl/style/layers/circle_layer_properties.cpp.s

src/mbgl/style/layers/custom_layer.o: src/mbgl/style/layers/custom_layer.cpp.o

.PHONY : src/mbgl/style/layers/custom_layer.o

# target to build an object file
src/mbgl/style/layers/custom_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/custom_layer.cpp.o
.PHONY : src/mbgl/style/layers/custom_layer.cpp.o

src/mbgl/style/layers/custom_layer.i: src/mbgl/style/layers/custom_layer.cpp.i

.PHONY : src/mbgl/style/layers/custom_layer.i

# target to preprocess a source file
src/mbgl/style/layers/custom_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/custom_layer.cpp.i
.PHONY : src/mbgl/style/layers/custom_layer.cpp.i

src/mbgl/style/layers/custom_layer.s: src/mbgl/style/layers/custom_layer.cpp.s

.PHONY : src/mbgl/style/layers/custom_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/custom_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/custom_layer.cpp.s
.PHONY : src/mbgl/style/layers/custom_layer.cpp.s

src/mbgl/style/layers/custom_layer_impl.o: src/mbgl/style/layers/custom_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/custom_layer_impl.o

# target to build an object file
src/mbgl/style/layers/custom_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/custom_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/custom_layer_impl.cpp.o

src/mbgl/style/layers/custom_layer_impl.i: src/mbgl/style/layers/custom_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/custom_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/custom_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/custom_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/custom_layer_impl.cpp.i

src/mbgl/style/layers/custom_layer_impl.s: src/mbgl/style/layers/custom_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/custom_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/custom_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/custom_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/custom_layer_impl.cpp.s

src/mbgl/style/layers/fill_extrusion_layer.o: src/mbgl/style/layers/fill_extrusion_layer.cpp.o

.PHONY : src/mbgl/style/layers/fill_extrusion_layer.o

# target to build an object file
src/mbgl/style/layers/fill_extrusion_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer.cpp.o
.PHONY : src/mbgl/style/layers/fill_extrusion_layer.cpp.o

src/mbgl/style/layers/fill_extrusion_layer.i: src/mbgl/style/layers/fill_extrusion_layer.cpp.i

.PHONY : src/mbgl/style/layers/fill_extrusion_layer.i

# target to preprocess a source file
src/mbgl/style/layers/fill_extrusion_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer.cpp.i
.PHONY : src/mbgl/style/layers/fill_extrusion_layer.cpp.i

src/mbgl/style/layers/fill_extrusion_layer.s: src/mbgl/style/layers/fill_extrusion_layer.cpp.s

.PHONY : src/mbgl/style/layers/fill_extrusion_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/fill_extrusion_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer.cpp.s
.PHONY : src/mbgl/style/layers/fill_extrusion_layer.cpp.s

src/mbgl/style/layers/fill_extrusion_layer_impl.o: src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/fill_extrusion_layer_impl.o

# target to build an object file
src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.o

src/mbgl/style/layers/fill_extrusion_layer_impl.i: src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/fill_extrusion_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.i

src/mbgl/style/layers/fill_extrusion_layer_impl.s: src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/fill_extrusion_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/fill_extrusion_layer_impl.cpp.s

src/mbgl/style/layers/fill_extrusion_layer_properties.o: src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.o

.PHONY : src/mbgl/style/layers/fill_extrusion_layer_properties.o

# target to build an object file
src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.o
.PHONY : src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.o

src/mbgl/style/layers/fill_extrusion_layer_properties.i: src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.i

.PHONY : src/mbgl/style/layers/fill_extrusion_layer_properties.i

# target to preprocess a source file
src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.i
.PHONY : src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.i

src/mbgl/style/layers/fill_extrusion_layer_properties.s: src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.s

.PHONY : src/mbgl/style/layers/fill_extrusion_layer_properties.s

# target to generate assembly for a file
src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.s
.PHONY : src/mbgl/style/layers/fill_extrusion_layer_properties.cpp.s

src/mbgl/style/layers/fill_layer.o: src/mbgl/style/layers/fill_layer.cpp.o

.PHONY : src/mbgl/style/layers/fill_layer.o

# target to build an object file
src/mbgl/style/layers/fill_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer.cpp.o
.PHONY : src/mbgl/style/layers/fill_layer.cpp.o

src/mbgl/style/layers/fill_layer.i: src/mbgl/style/layers/fill_layer.cpp.i

.PHONY : src/mbgl/style/layers/fill_layer.i

# target to preprocess a source file
src/mbgl/style/layers/fill_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer.cpp.i
.PHONY : src/mbgl/style/layers/fill_layer.cpp.i

src/mbgl/style/layers/fill_layer.s: src/mbgl/style/layers/fill_layer.cpp.s

.PHONY : src/mbgl/style/layers/fill_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/fill_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer.cpp.s
.PHONY : src/mbgl/style/layers/fill_layer.cpp.s

src/mbgl/style/layers/fill_layer_impl.o: src/mbgl/style/layers/fill_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/fill_layer_impl.o

# target to build an object file
src/mbgl/style/layers/fill_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/fill_layer_impl.cpp.o

src/mbgl/style/layers/fill_layer_impl.i: src/mbgl/style/layers/fill_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/fill_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/fill_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/fill_layer_impl.cpp.i

src/mbgl/style/layers/fill_layer_impl.s: src/mbgl/style/layers/fill_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/fill_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/fill_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/fill_layer_impl.cpp.s

src/mbgl/style/layers/fill_layer_properties.o: src/mbgl/style/layers/fill_layer_properties.cpp.o

.PHONY : src/mbgl/style/layers/fill_layer_properties.o

# target to build an object file
src/mbgl/style/layers/fill_layer_properties.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer_properties.cpp.o
.PHONY : src/mbgl/style/layers/fill_layer_properties.cpp.o

src/mbgl/style/layers/fill_layer_properties.i: src/mbgl/style/layers/fill_layer_properties.cpp.i

.PHONY : src/mbgl/style/layers/fill_layer_properties.i

# target to preprocess a source file
src/mbgl/style/layers/fill_layer_properties.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer_properties.cpp.i
.PHONY : src/mbgl/style/layers/fill_layer_properties.cpp.i

src/mbgl/style/layers/fill_layer_properties.s: src/mbgl/style/layers/fill_layer_properties.cpp.s

.PHONY : src/mbgl/style/layers/fill_layer_properties.s

# target to generate assembly for a file
src/mbgl/style/layers/fill_layer_properties.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/fill_layer_properties.cpp.s
.PHONY : src/mbgl/style/layers/fill_layer_properties.cpp.s

src/mbgl/style/layers/line_layer.o: src/mbgl/style/layers/line_layer.cpp.o

.PHONY : src/mbgl/style/layers/line_layer.o

# target to build an object file
src/mbgl/style/layers/line_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer.cpp.o
.PHONY : src/mbgl/style/layers/line_layer.cpp.o

src/mbgl/style/layers/line_layer.i: src/mbgl/style/layers/line_layer.cpp.i

.PHONY : src/mbgl/style/layers/line_layer.i

# target to preprocess a source file
src/mbgl/style/layers/line_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer.cpp.i
.PHONY : src/mbgl/style/layers/line_layer.cpp.i

src/mbgl/style/layers/line_layer.s: src/mbgl/style/layers/line_layer.cpp.s

.PHONY : src/mbgl/style/layers/line_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/line_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer.cpp.s
.PHONY : src/mbgl/style/layers/line_layer.cpp.s

src/mbgl/style/layers/line_layer_impl.o: src/mbgl/style/layers/line_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/line_layer_impl.o

# target to build an object file
src/mbgl/style/layers/line_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/line_layer_impl.cpp.o

src/mbgl/style/layers/line_layer_impl.i: src/mbgl/style/layers/line_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/line_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/line_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/line_layer_impl.cpp.i

src/mbgl/style/layers/line_layer_impl.s: src/mbgl/style/layers/line_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/line_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/line_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/line_layer_impl.cpp.s

src/mbgl/style/layers/line_layer_properties.o: src/mbgl/style/layers/line_layer_properties.cpp.o

.PHONY : src/mbgl/style/layers/line_layer_properties.o

# target to build an object file
src/mbgl/style/layers/line_layer_properties.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer_properties.cpp.o
.PHONY : src/mbgl/style/layers/line_layer_properties.cpp.o

src/mbgl/style/layers/line_layer_properties.i: src/mbgl/style/layers/line_layer_properties.cpp.i

.PHONY : src/mbgl/style/layers/line_layer_properties.i

# target to preprocess a source file
src/mbgl/style/layers/line_layer_properties.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer_properties.cpp.i
.PHONY : src/mbgl/style/layers/line_layer_properties.cpp.i

src/mbgl/style/layers/line_layer_properties.s: src/mbgl/style/layers/line_layer_properties.cpp.s

.PHONY : src/mbgl/style/layers/line_layer_properties.s

# target to generate assembly for a file
src/mbgl/style/layers/line_layer_properties.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/line_layer_properties.cpp.s
.PHONY : src/mbgl/style/layers/line_layer_properties.cpp.s

src/mbgl/style/layers/raster_layer.o: src/mbgl/style/layers/raster_layer.cpp.o

.PHONY : src/mbgl/style/layers/raster_layer.o

# target to build an object file
src/mbgl/style/layers/raster_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer.cpp.o
.PHONY : src/mbgl/style/layers/raster_layer.cpp.o

src/mbgl/style/layers/raster_layer.i: src/mbgl/style/layers/raster_layer.cpp.i

.PHONY : src/mbgl/style/layers/raster_layer.i

# target to preprocess a source file
src/mbgl/style/layers/raster_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer.cpp.i
.PHONY : src/mbgl/style/layers/raster_layer.cpp.i

src/mbgl/style/layers/raster_layer.s: src/mbgl/style/layers/raster_layer.cpp.s

.PHONY : src/mbgl/style/layers/raster_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/raster_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer.cpp.s
.PHONY : src/mbgl/style/layers/raster_layer.cpp.s

src/mbgl/style/layers/raster_layer_impl.o: src/mbgl/style/layers/raster_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/raster_layer_impl.o

# target to build an object file
src/mbgl/style/layers/raster_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/raster_layer_impl.cpp.o

src/mbgl/style/layers/raster_layer_impl.i: src/mbgl/style/layers/raster_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/raster_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/raster_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/raster_layer_impl.cpp.i

src/mbgl/style/layers/raster_layer_impl.s: src/mbgl/style/layers/raster_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/raster_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/raster_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/raster_layer_impl.cpp.s

src/mbgl/style/layers/raster_layer_properties.o: src/mbgl/style/layers/raster_layer_properties.cpp.o

.PHONY : src/mbgl/style/layers/raster_layer_properties.o

# target to build an object file
src/mbgl/style/layers/raster_layer_properties.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer_properties.cpp.o
.PHONY : src/mbgl/style/layers/raster_layer_properties.cpp.o

src/mbgl/style/layers/raster_layer_properties.i: src/mbgl/style/layers/raster_layer_properties.cpp.i

.PHONY : src/mbgl/style/layers/raster_layer_properties.i

# target to preprocess a source file
src/mbgl/style/layers/raster_layer_properties.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer_properties.cpp.i
.PHONY : src/mbgl/style/layers/raster_layer_properties.cpp.i

src/mbgl/style/layers/raster_layer_properties.s: src/mbgl/style/layers/raster_layer_properties.cpp.s

.PHONY : src/mbgl/style/layers/raster_layer_properties.s

# target to generate assembly for a file
src/mbgl/style/layers/raster_layer_properties.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/raster_layer_properties.cpp.s
.PHONY : src/mbgl/style/layers/raster_layer_properties.cpp.s

src/mbgl/style/layers/symbol_layer.o: src/mbgl/style/layers/symbol_layer.cpp.o

.PHONY : src/mbgl/style/layers/symbol_layer.o

# target to build an object file
src/mbgl/style/layers/symbol_layer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer.cpp.o
.PHONY : src/mbgl/style/layers/symbol_layer.cpp.o

src/mbgl/style/layers/symbol_layer.i: src/mbgl/style/layers/symbol_layer.cpp.i

.PHONY : src/mbgl/style/layers/symbol_layer.i

# target to preprocess a source file
src/mbgl/style/layers/symbol_layer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer.cpp.i
.PHONY : src/mbgl/style/layers/symbol_layer.cpp.i

src/mbgl/style/layers/symbol_layer.s: src/mbgl/style/layers/symbol_layer.cpp.s

.PHONY : src/mbgl/style/layers/symbol_layer.s

# target to generate assembly for a file
src/mbgl/style/layers/symbol_layer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer.cpp.s
.PHONY : src/mbgl/style/layers/symbol_layer.cpp.s

src/mbgl/style/layers/symbol_layer_impl.o: src/mbgl/style/layers/symbol_layer_impl.cpp.o

.PHONY : src/mbgl/style/layers/symbol_layer_impl.o

# target to build an object file
src/mbgl/style/layers/symbol_layer_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer_impl.cpp.o
.PHONY : src/mbgl/style/layers/symbol_layer_impl.cpp.o

src/mbgl/style/layers/symbol_layer_impl.i: src/mbgl/style/layers/symbol_layer_impl.cpp.i

.PHONY : src/mbgl/style/layers/symbol_layer_impl.i

# target to preprocess a source file
src/mbgl/style/layers/symbol_layer_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer_impl.cpp.i
.PHONY : src/mbgl/style/layers/symbol_layer_impl.cpp.i

src/mbgl/style/layers/symbol_layer_impl.s: src/mbgl/style/layers/symbol_layer_impl.cpp.s

.PHONY : src/mbgl/style/layers/symbol_layer_impl.s

# target to generate assembly for a file
src/mbgl/style/layers/symbol_layer_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer_impl.cpp.s
.PHONY : src/mbgl/style/layers/symbol_layer_impl.cpp.s

src/mbgl/style/layers/symbol_layer_properties.o: src/mbgl/style/layers/symbol_layer_properties.cpp.o

.PHONY : src/mbgl/style/layers/symbol_layer_properties.o

# target to build an object file
src/mbgl/style/layers/symbol_layer_properties.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer_properties.cpp.o
.PHONY : src/mbgl/style/layers/symbol_layer_properties.cpp.o

src/mbgl/style/layers/symbol_layer_properties.i: src/mbgl/style/layers/symbol_layer_properties.cpp.i

.PHONY : src/mbgl/style/layers/symbol_layer_properties.i

# target to preprocess a source file
src/mbgl/style/layers/symbol_layer_properties.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer_properties.cpp.i
.PHONY : src/mbgl/style/layers/symbol_layer_properties.cpp.i

src/mbgl/style/layers/symbol_layer_properties.s: src/mbgl/style/layers/symbol_layer_properties.cpp.s

.PHONY : src/mbgl/style/layers/symbol_layer_properties.s

# target to generate assembly for a file
src/mbgl/style/layers/symbol_layer_properties.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/layers/symbol_layer_properties.cpp.s
.PHONY : src/mbgl/style/layers/symbol_layer_properties.cpp.s

src/mbgl/style/light.o: src/mbgl/style/light.cpp.o

.PHONY : src/mbgl/style/light.o

# target to build an object file
src/mbgl/style/light.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/light.cpp.o
.PHONY : src/mbgl/style/light.cpp.o

src/mbgl/style/light.i: src/mbgl/style/light.cpp.i

.PHONY : src/mbgl/style/light.i

# target to preprocess a source file
src/mbgl/style/light.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/light.cpp.i
.PHONY : src/mbgl/style/light.cpp.i

src/mbgl/style/light.s: src/mbgl/style/light.cpp.s

.PHONY : src/mbgl/style/light.s

# target to generate assembly for a file
src/mbgl/style/light.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/light.cpp.s
.PHONY : src/mbgl/style/light.cpp.s

src/mbgl/style/light_impl.o: src/mbgl/style/light_impl.cpp.o

.PHONY : src/mbgl/style/light_impl.o

# target to build an object file
src/mbgl/style/light_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/light_impl.cpp.o
.PHONY : src/mbgl/style/light_impl.cpp.o

src/mbgl/style/light_impl.i: src/mbgl/style/light_impl.cpp.i

.PHONY : src/mbgl/style/light_impl.i

# target to preprocess a source file
src/mbgl/style/light_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/light_impl.cpp.i
.PHONY : src/mbgl/style/light_impl.cpp.i

src/mbgl/style/light_impl.s: src/mbgl/style/light_impl.cpp.s

.PHONY : src/mbgl/style/light_impl.s

# target to generate assembly for a file
src/mbgl/style/light_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/light_impl.cpp.s
.PHONY : src/mbgl/style/light_impl.cpp.s

src/mbgl/style/parser.o: src/mbgl/style/parser.cpp.o

.PHONY : src/mbgl/style/parser.o

# target to build an object file
src/mbgl/style/parser.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/parser.cpp.o
.PHONY : src/mbgl/style/parser.cpp.o

src/mbgl/style/parser.i: src/mbgl/style/parser.cpp.i

.PHONY : src/mbgl/style/parser.i

# target to preprocess a source file
src/mbgl/style/parser.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/parser.cpp.i
.PHONY : src/mbgl/style/parser.cpp.i

src/mbgl/style/parser.s: src/mbgl/style/parser.cpp.s

.PHONY : src/mbgl/style/parser.s

# target to generate assembly for a file
src/mbgl/style/parser.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/parser.cpp.s
.PHONY : src/mbgl/style/parser.cpp.s

src/mbgl/style/source.o: src/mbgl/style/source.cpp.o

.PHONY : src/mbgl/style/source.o

# target to build an object file
src/mbgl/style/source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/source.cpp.o
.PHONY : src/mbgl/style/source.cpp.o

src/mbgl/style/source.i: src/mbgl/style/source.cpp.i

.PHONY : src/mbgl/style/source.i

# target to preprocess a source file
src/mbgl/style/source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/source.cpp.i
.PHONY : src/mbgl/style/source.cpp.i

src/mbgl/style/source.s: src/mbgl/style/source.cpp.s

.PHONY : src/mbgl/style/source.s

# target to generate assembly for a file
src/mbgl/style/source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/source.cpp.s
.PHONY : src/mbgl/style/source.cpp.s

src/mbgl/style/source_impl.o: src/mbgl/style/source_impl.cpp.o

.PHONY : src/mbgl/style/source_impl.o

# target to build an object file
src/mbgl/style/source_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/source_impl.cpp.o
.PHONY : src/mbgl/style/source_impl.cpp.o

src/mbgl/style/source_impl.i: src/mbgl/style/source_impl.cpp.i

.PHONY : src/mbgl/style/source_impl.i

# target to preprocess a source file
src/mbgl/style/source_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/source_impl.cpp.i
.PHONY : src/mbgl/style/source_impl.cpp.i

src/mbgl/style/source_impl.s: src/mbgl/style/source_impl.cpp.s

.PHONY : src/mbgl/style/source_impl.s

# target to generate assembly for a file
src/mbgl/style/source_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/source_impl.cpp.s
.PHONY : src/mbgl/style/source_impl.cpp.s

src/mbgl/style/sources/geojson_source.o: src/mbgl/style/sources/geojson_source.cpp.o

.PHONY : src/mbgl/style/sources/geojson_source.o

# target to build an object file
src/mbgl/style/sources/geojson_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/geojson_source.cpp.o
.PHONY : src/mbgl/style/sources/geojson_source.cpp.o

src/mbgl/style/sources/geojson_source.i: src/mbgl/style/sources/geojson_source.cpp.i

.PHONY : src/mbgl/style/sources/geojson_source.i

# target to preprocess a source file
src/mbgl/style/sources/geojson_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/geojson_source.cpp.i
.PHONY : src/mbgl/style/sources/geojson_source.cpp.i

src/mbgl/style/sources/geojson_source.s: src/mbgl/style/sources/geojson_source.cpp.s

.PHONY : src/mbgl/style/sources/geojson_source.s

# target to generate assembly for a file
src/mbgl/style/sources/geojson_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/geojson_source.cpp.s
.PHONY : src/mbgl/style/sources/geojson_source.cpp.s

src/mbgl/style/sources/geojson_source_impl.o: src/mbgl/style/sources/geojson_source_impl.cpp.o

.PHONY : src/mbgl/style/sources/geojson_source_impl.o

# target to build an object file
src/mbgl/style/sources/geojson_source_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/geojson_source_impl.cpp.o
.PHONY : src/mbgl/style/sources/geojson_source_impl.cpp.o

src/mbgl/style/sources/geojson_source_impl.i: src/mbgl/style/sources/geojson_source_impl.cpp.i

.PHONY : src/mbgl/style/sources/geojson_source_impl.i

# target to preprocess a source file
src/mbgl/style/sources/geojson_source_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/geojson_source_impl.cpp.i
.PHONY : src/mbgl/style/sources/geojson_source_impl.cpp.i

src/mbgl/style/sources/geojson_source_impl.s: src/mbgl/style/sources/geojson_source_impl.cpp.s

.PHONY : src/mbgl/style/sources/geojson_source_impl.s

# target to generate assembly for a file
src/mbgl/style/sources/geojson_source_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/geojson_source_impl.cpp.s
.PHONY : src/mbgl/style/sources/geojson_source_impl.cpp.s

src/mbgl/style/sources/image_source.o: src/mbgl/style/sources/image_source.cpp.o

.PHONY : src/mbgl/style/sources/image_source.o

# target to build an object file
src/mbgl/style/sources/image_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/image_source.cpp.o
.PHONY : src/mbgl/style/sources/image_source.cpp.o

src/mbgl/style/sources/image_source.i: src/mbgl/style/sources/image_source.cpp.i

.PHONY : src/mbgl/style/sources/image_source.i

# target to preprocess a source file
src/mbgl/style/sources/image_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/image_source.cpp.i
.PHONY : src/mbgl/style/sources/image_source.cpp.i

src/mbgl/style/sources/image_source.s: src/mbgl/style/sources/image_source.cpp.s

.PHONY : src/mbgl/style/sources/image_source.s

# target to generate assembly for a file
src/mbgl/style/sources/image_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/image_source.cpp.s
.PHONY : src/mbgl/style/sources/image_source.cpp.s

src/mbgl/style/sources/image_source_impl.o: src/mbgl/style/sources/image_source_impl.cpp.o

.PHONY : src/mbgl/style/sources/image_source_impl.o

# target to build an object file
src/mbgl/style/sources/image_source_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/image_source_impl.cpp.o
.PHONY : src/mbgl/style/sources/image_source_impl.cpp.o

src/mbgl/style/sources/image_source_impl.i: src/mbgl/style/sources/image_source_impl.cpp.i

.PHONY : src/mbgl/style/sources/image_source_impl.i

# target to preprocess a source file
src/mbgl/style/sources/image_source_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/image_source_impl.cpp.i
.PHONY : src/mbgl/style/sources/image_source_impl.cpp.i

src/mbgl/style/sources/image_source_impl.s: src/mbgl/style/sources/image_source_impl.cpp.s

.PHONY : src/mbgl/style/sources/image_source_impl.s

# target to generate assembly for a file
src/mbgl/style/sources/image_source_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/image_source_impl.cpp.s
.PHONY : src/mbgl/style/sources/image_source_impl.cpp.s

src/mbgl/style/sources/raster_source.o: src/mbgl/style/sources/raster_source.cpp.o

.PHONY : src/mbgl/style/sources/raster_source.o

# target to build an object file
src/mbgl/style/sources/raster_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/raster_source.cpp.o
.PHONY : src/mbgl/style/sources/raster_source.cpp.o

src/mbgl/style/sources/raster_source.i: src/mbgl/style/sources/raster_source.cpp.i

.PHONY : src/mbgl/style/sources/raster_source.i

# target to preprocess a source file
src/mbgl/style/sources/raster_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/raster_source.cpp.i
.PHONY : src/mbgl/style/sources/raster_source.cpp.i

src/mbgl/style/sources/raster_source.s: src/mbgl/style/sources/raster_source.cpp.s

.PHONY : src/mbgl/style/sources/raster_source.s

# target to generate assembly for a file
src/mbgl/style/sources/raster_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/raster_source.cpp.s
.PHONY : src/mbgl/style/sources/raster_source.cpp.s

src/mbgl/style/sources/raster_source_impl.o: src/mbgl/style/sources/raster_source_impl.cpp.o

.PHONY : src/mbgl/style/sources/raster_source_impl.o

# target to build an object file
src/mbgl/style/sources/raster_source_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/raster_source_impl.cpp.o
.PHONY : src/mbgl/style/sources/raster_source_impl.cpp.o

src/mbgl/style/sources/raster_source_impl.i: src/mbgl/style/sources/raster_source_impl.cpp.i

.PHONY : src/mbgl/style/sources/raster_source_impl.i

# target to preprocess a source file
src/mbgl/style/sources/raster_source_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/raster_source_impl.cpp.i
.PHONY : src/mbgl/style/sources/raster_source_impl.cpp.i

src/mbgl/style/sources/raster_source_impl.s: src/mbgl/style/sources/raster_source_impl.cpp.s

.PHONY : src/mbgl/style/sources/raster_source_impl.s

# target to generate assembly for a file
src/mbgl/style/sources/raster_source_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/raster_source_impl.cpp.s
.PHONY : src/mbgl/style/sources/raster_source_impl.cpp.s

src/mbgl/style/sources/vector_source.o: src/mbgl/style/sources/vector_source.cpp.o

.PHONY : src/mbgl/style/sources/vector_source.o

# target to build an object file
src/mbgl/style/sources/vector_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/vector_source.cpp.o
.PHONY : src/mbgl/style/sources/vector_source.cpp.o

src/mbgl/style/sources/vector_source.i: src/mbgl/style/sources/vector_source.cpp.i

.PHONY : src/mbgl/style/sources/vector_source.i

# target to preprocess a source file
src/mbgl/style/sources/vector_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/vector_source.cpp.i
.PHONY : src/mbgl/style/sources/vector_source.cpp.i

src/mbgl/style/sources/vector_source.s: src/mbgl/style/sources/vector_source.cpp.s

.PHONY : src/mbgl/style/sources/vector_source.s

# target to generate assembly for a file
src/mbgl/style/sources/vector_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/vector_source.cpp.s
.PHONY : src/mbgl/style/sources/vector_source.cpp.s

src/mbgl/style/sources/vector_source_impl.o: src/mbgl/style/sources/vector_source_impl.cpp.o

.PHONY : src/mbgl/style/sources/vector_source_impl.o

# target to build an object file
src/mbgl/style/sources/vector_source_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/vector_source_impl.cpp.o
.PHONY : src/mbgl/style/sources/vector_source_impl.cpp.o

src/mbgl/style/sources/vector_source_impl.i: src/mbgl/style/sources/vector_source_impl.cpp.i

.PHONY : src/mbgl/style/sources/vector_source_impl.i

# target to preprocess a source file
src/mbgl/style/sources/vector_source_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/vector_source_impl.cpp.i
.PHONY : src/mbgl/style/sources/vector_source_impl.cpp.i

src/mbgl/style/sources/vector_source_impl.s: src/mbgl/style/sources/vector_source_impl.cpp.s

.PHONY : src/mbgl/style/sources/vector_source_impl.s

# target to generate assembly for a file
src/mbgl/style/sources/vector_source_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/sources/vector_source_impl.cpp.s
.PHONY : src/mbgl/style/sources/vector_source_impl.cpp.s

src/mbgl/style/style.o: src/mbgl/style/style.cpp.o

.PHONY : src/mbgl/style/style.o

# target to build an object file
src/mbgl/style/style.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/style.cpp.o
.PHONY : src/mbgl/style/style.cpp.o

src/mbgl/style/style.i: src/mbgl/style/style.cpp.i

.PHONY : src/mbgl/style/style.i

# target to preprocess a source file
src/mbgl/style/style.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/style.cpp.i
.PHONY : src/mbgl/style/style.cpp.i

src/mbgl/style/style.s: src/mbgl/style/style.cpp.s

.PHONY : src/mbgl/style/style.s

# target to generate assembly for a file
src/mbgl/style/style.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/style.cpp.s
.PHONY : src/mbgl/style/style.cpp.s

src/mbgl/style/style_impl.o: src/mbgl/style/style_impl.cpp.o

.PHONY : src/mbgl/style/style_impl.o

# target to build an object file
src/mbgl/style/style_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/style_impl.cpp.o
.PHONY : src/mbgl/style/style_impl.cpp.o

src/mbgl/style/style_impl.i: src/mbgl/style/style_impl.cpp.i

.PHONY : src/mbgl/style/style_impl.i

# target to preprocess a source file
src/mbgl/style/style_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/style_impl.cpp.i
.PHONY : src/mbgl/style/style_impl.cpp.i

src/mbgl/style/style_impl.s: src/mbgl/style/style_impl.cpp.s

.PHONY : src/mbgl/style/style_impl.s

# target to generate assembly for a file
src/mbgl/style/style_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/style_impl.cpp.s
.PHONY : src/mbgl/style/style_impl.cpp.s

src/mbgl/style/types.o: src/mbgl/style/types.cpp.o

.PHONY : src/mbgl/style/types.o

# target to build an object file
src/mbgl/style/types.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/types.cpp.o
.PHONY : src/mbgl/style/types.cpp.o

src/mbgl/style/types.i: src/mbgl/style/types.cpp.i

.PHONY : src/mbgl/style/types.i

# target to preprocess a source file
src/mbgl/style/types.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/types.cpp.i
.PHONY : src/mbgl/style/types.cpp.i

src/mbgl/style/types.s: src/mbgl/style/types.cpp.s

.PHONY : src/mbgl/style/types.s

# target to generate assembly for a file
src/mbgl/style/types.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/style/types.cpp.s
.PHONY : src/mbgl/style/types.cpp.s

src/mbgl/text/check_max_angle.o: src/mbgl/text/check_max_angle.cpp.o

.PHONY : src/mbgl/text/check_max_angle.o

# target to build an object file
src/mbgl/text/check_max_angle.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/check_max_angle.cpp.o
.PHONY : src/mbgl/text/check_max_angle.cpp.o

src/mbgl/text/check_max_angle.i: src/mbgl/text/check_max_angle.cpp.i

.PHONY : src/mbgl/text/check_max_angle.i

# target to preprocess a source file
src/mbgl/text/check_max_angle.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/check_max_angle.cpp.i
.PHONY : src/mbgl/text/check_max_angle.cpp.i

src/mbgl/text/check_max_angle.s: src/mbgl/text/check_max_angle.cpp.s

.PHONY : src/mbgl/text/check_max_angle.s

# target to generate assembly for a file
src/mbgl/text/check_max_angle.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/check_max_angle.cpp.s
.PHONY : src/mbgl/text/check_max_angle.cpp.s

src/mbgl/text/collision_feature.o: src/mbgl/text/collision_feature.cpp.o

.PHONY : src/mbgl/text/collision_feature.o

# target to build an object file
src/mbgl/text/collision_feature.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/collision_feature.cpp.o
.PHONY : src/mbgl/text/collision_feature.cpp.o

src/mbgl/text/collision_feature.i: src/mbgl/text/collision_feature.cpp.i

.PHONY : src/mbgl/text/collision_feature.i

# target to preprocess a source file
src/mbgl/text/collision_feature.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/collision_feature.cpp.i
.PHONY : src/mbgl/text/collision_feature.cpp.i

src/mbgl/text/collision_feature.s: src/mbgl/text/collision_feature.cpp.s

.PHONY : src/mbgl/text/collision_feature.s

# target to generate assembly for a file
src/mbgl/text/collision_feature.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/collision_feature.cpp.s
.PHONY : src/mbgl/text/collision_feature.cpp.s

src/mbgl/text/collision_tile.o: src/mbgl/text/collision_tile.cpp.o

.PHONY : src/mbgl/text/collision_tile.o

# target to build an object file
src/mbgl/text/collision_tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/collision_tile.cpp.o
.PHONY : src/mbgl/text/collision_tile.cpp.o

src/mbgl/text/collision_tile.i: src/mbgl/text/collision_tile.cpp.i

.PHONY : src/mbgl/text/collision_tile.i

# target to preprocess a source file
src/mbgl/text/collision_tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/collision_tile.cpp.i
.PHONY : src/mbgl/text/collision_tile.cpp.i

src/mbgl/text/collision_tile.s: src/mbgl/text/collision_tile.cpp.s

.PHONY : src/mbgl/text/collision_tile.s

# target to generate assembly for a file
src/mbgl/text/collision_tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/collision_tile.cpp.s
.PHONY : src/mbgl/text/collision_tile.cpp.s

src/mbgl/text/get_anchors.o: src/mbgl/text/get_anchors.cpp.o

.PHONY : src/mbgl/text/get_anchors.o

# target to build an object file
src/mbgl/text/get_anchors.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/get_anchors.cpp.o
.PHONY : src/mbgl/text/get_anchors.cpp.o

src/mbgl/text/get_anchors.i: src/mbgl/text/get_anchors.cpp.i

.PHONY : src/mbgl/text/get_anchors.i

# target to preprocess a source file
src/mbgl/text/get_anchors.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/get_anchors.cpp.i
.PHONY : src/mbgl/text/get_anchors.cpp.i

src/mbgl/text/get_anchors.s: src/mbgl/text/get_anchors.cpp.s

.PHONY : src/mbgl/text/get_anchors.s

# target to generate assembly for a file
src/mbgl/text/get_anchors.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/get_anchors.cpp.s
.PHONY : src/mbgl/text/get_anchors.cpp.s

src/mbgl/text/glyph.o: src/mbgl/text/glyph.cpp.o

.PHONY : src/mbgl/text/glyph.o

# target to build an object file
src/mbgl/text/glyph.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph.cpp.o
.PHONY : src/mbgl/text/glyph.cpp.o

src/mbgl/text/glyph.i: src/mbgl/text/glyph.cpp.i

.PHONY : src/mbgl/text/glyph.i

# target to preprocess a source file
src/mbgl/text/glyph.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph.cpp.i
.PHONY : src/mbgl/text/glyph.cpp.i

src/mbgl/text/glyph.s: src/mbgl/text/glyph.cpp.s

.PHONY : src/mbgl/text/glyph.s

# target to generate assembly for a file
src/mbgl/text/glyph.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph.cpp.s
.PHONY : src/mbgl/text/glyph.cpp.s

src/mbgl/text/glyph_atlas.o: src/mbgl/text/glyph_atlas.cpp.o

.PHONY : src/mbgl/text/glyph_atlas.o

# target to build an object file
src/mbgl/text/glyph_atlas.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_atlas.cpp.o
.PHONY : src/mbgl/text/glyph_atlas.cpp.o

src/mbgl/text/glyph_atlas.i: src/mbgl/text/glyph_atlas.cpp.i

.PHONY : src/mbgl/text/glyph_atlas.i

# target to preprocess a source file
src/mbgl/text/glyph_atlas.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_atlas.cpp.i
.PHONY : src/mbgl/text/glyph_atlas.cpp.i

src/mbgl/text/glyph_atlas.s: src/mbgl/text/glyph_atlas.cpp.s

.PHONY : src/mbgl/text/glyph_atlas.s

# target to generate assembly for a file
src/mbgl/text/glyph_atlas.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_atlas.cpp.s
.PHONY : src/mbgl/text/glyph_atlas.cpp.s

src/mbgl/text/glyph_manager.o: src/mbgl/text/glyph_manager.cpp.o

.PHONY : src/mbgl/text/glyph_manager.o

# target to build an object file
src/mbgl/text/glyph_manager.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_manager.cpp.o
.PHONY : src/mbgl/text/glyph_manager.cpp.o

src/mbgl/text/glyph_manager.i: src/mbgl/text/glyph_manager.cpp.i

.PHONY : src/mbgl/text/glyph_manager.i

# target to preprocess a source file
src/mbgl/text/glyph_manager.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_manager.cpp.i
.PHONY : src/mbgl/text/glyph_manager.cpp.i

src/mbgl/text/glyph_manager.s: src/mbgl/text/glyph_manager.cpp.s

.PHONY : src/mbgl/text/glyph_manager.s

# target to generate assembly for a file
src/mbgl/text/glyph_manager.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_manager.cpp.s
.PHONY : src/mbgl/text/glyph_manager.cpp.s

src/mbgl/text/glyph_pbf.o: src/mbgl/text/glyph_pbf.cpp.o

.PHONY : src/mbgl/text/glyph_pbf.o

# target to build an object file
src/mbgl/text/glyph_pbf.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_pbf.cpp.o
.PHONY : src/mbgl/text/glyph_pbf.cpp.o

src/mbgl/text/glyph_pbf.i: src/mbgl/text/glyph_pbf.cpp.i

.PHONY : src/mbgl/text/glyph_pbf.i

# target to preprocess a source file
src/mbgl/text/glyph_pbf.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_pbf.cpp.i
.PHONY : src/mbgl/text/glyph_pbf.cpp.i

src/mbgl/text/glyph_pbf.s: src/mbgl/text/glyph_pbf.cpp.s

.PHONY : src/mbgl/text/glyph_pbf.s

# target to generate assembly for a file
src/mbgl/text/glyph_pbf.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/glyph_pbf.cpp.s
.PHONY : src/mbgl/text/glyph_pbf.cpp.s

src/mbgl/text/quads.o: src/mbgl/text/quads.cpp.o

.PHONY : src/mbgl/text/quads.o

# target to build an object file
src/mbgl/text/quads.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/quads.cpp.o
.PHONY : src/mbgl/text/quads.cpp.o

src/mbgl/text/quads.i: src/mbgl/text/quads.cpp.i

.PHONY : src/mbgl/text/quads.i

# target to preprocess a source file
src/mbgl/text/quads.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/quads.cpp.i
.PHONY : src/mbgl/text/quads.cpp.i

src/mbgl/text/quads.s: src/mbgl/text/quads.cpp.s

.PHONY : src/mbgl/text/quads.s

# target to generate assembly for a file
src/mbgl/text/quads.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/quads.cpp.s
.PHONY : src/mbgl/text/quads.cpp.s

src/mbgl/text/shaping.o: src/mbgl/text/shaping.cpp.o

.PHONY : src/mbgl/text/shaping.o

# target to build an object file
src/mbgl/text/shaping.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/shaping.cpp.o
.PHONY : src/mbgl/text/shaping.cpp.o

src/mbgl/text/shaping.i: src/mbgl/text/shaping.cpp.i

.PHONY : src/mbgl/text/shaping.i

# target to preprocess a source file
src/mbgl/text/shaping.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/shaping.cpp.i
.PHONY : src/mbgl/text/shaping.cpp.i

src/mbgl/text/shaping.s: src/mbgl/text/shaping.cpp.s

.PHONY : src/mbgl/text/shaping.s

# target to generate assembly for a file
src/mbgl/text/shaping.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/text/shaping.cpp.s
.PHONY : src/mbgl/text/shaping.cpp.s

src/mbgl/tile/geojson_tile.o: src/mbgl/tile/geojson_tile.cpp.o

.PHONY : src/mbgl/tile/geojson_tile.o

# target to build an object file
src/mbgl/tile/geojson_tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geojson_tile.cpp.o
.PHONY : src/mbgl/tile/geojson_tile.cpp.o

src/mbgl/tile/geojson_tile.i: src/mbgl/tile/geojson_tile.cpp.i

.PHONY : src/mbgl/tile/geojson_tile.i

# target to preprocess a source file
src/mbgl/tile/geojson_tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geojson_tile.cpp.i
.PHONY : src/mbgl/tile/geojson_tile.cpp.i

src/mbgl/tile/geojson_tile.s: src/mbgl/tile/geojson_tile.cpp.s

.PHONY : src/mbgl/tile/geojson_tile.s

# target to generate assembly for a file
src/mbgl/tile/geojson_tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geojson_tile.cpp.s
.PHONY : src/mbgl/tile/geojson_tile.cpp.s

src/mbgl/tile/geometry_tile.o: src/mbgl/tile/geometry_tile.cpp.o

.PHONY : src/mbgl/tile/geometry_tile.o

# target to build an object file
src/mbgl/tile/geometry_tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile.cpp.o
.PHONY : src/mbgl/tile/geometry_tile.cpp.o

src/mbgl/tile/geometry_tile.i: src/mbgl/tile/geometry_tile.cpp.i

.PHONY : src/mbgl/tile/geometry_tile.i

# target to preprocess a source file
src/mbgl/tile/geometry_tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile.cpp.i
.PHONY : src/mbgl/tile/geometry_tile.cpp.i

src/mbgl/tile/geometry_tile.s: src/mbgl/tile/geometry_tile.cpp.s

.PHONY : src/mbgl/tile/geometry_tile.s

# target to generate assembly for a file
src/mbgl/tile/geometry_tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile.cpp.s
.PHONY : src/mbgl/tile/geometry_tile.cpp.s

src/mbgl/tile/geometry_tile_data.o: src/mbgl/tile/geometry_tile_data.cpp.o

.PHONY : src/mbgl/tile/geometry_tile_data.o

# target to build an object file
src/mbgl/tile/geometry_tile_data.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile_data.cpp.o
.PHONY : src/mbgl/tile/geometry_tile_data.cpp.o

src/mbgl/tile/geometry_tile_data.i: src/mbgl/tile/geometry_tile_data.cpp.i

.PHONY : src/mbgl/tile/geometry_tile_data.i

# target to preprocess a source file
src/mbgl/tile/geometry_tile_data.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile_data.cpp.i
.PHONY : src/mbgl/tile/geometry_tile_data.cpp.i

src/mbgl/tile/geometry_tile_data.s: src/mbgl/tile/geometry_tile_data.cpp.s

.PHONY : src/mbgl/tile/geometry_tile_data.s

# target to generate assembly for a file
src/mbgl/tile/geometry_tile_data.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile_data.cpp.s
.PHONY : src/mbgl/tile/geometry_tile_data.cpp.s

src/mbgl/tile/geometry_tile_worker.o: src/mbgl/tile/geometry_tile_worker.cpp.o

.PHONY : src/mbgl/tile/geometry_tile_worker.o

# target to build an object file
src/mbgl/tile/geometry_tile_worker.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile_worker.cpp.o
.PHONY : src/mbgl/tile/geometry_tile_worker.cpp.o

src/mbgl/tile/geometry_tile_worker.i: src/mbgl/tile/geometry_tile_worker.cpp.i

.PHONY : src/mbgl/tile/geometry_tile_worker.i

# target to preprocess a source file
src/mbgl/tile/geometry_tile_worker.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile_worker.cpp.i
.PHONY : src/mbgl/tile/geometry_tile_worker.cpp.i

src/mbgl/tile/geometry_tile_worker.s: src/mbgl/tile/geometry_tile_worker.cpp.s

.PHONY : src/mbgl/tile/geometry_tile_worker.s

# target to generate assembly for a file
src/mbgl/tile/geometry_tile_worker.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/geometry_tile_worker.cpp.s
.PHONY : src/mbgl/tile/geometry_tile_worker.cpp.s

src/mbgl/tile/raster_tile.o: src/mbgl/tile/raster_tile.cpp.o

.PHONY : src/mbgl/tile/raster_tile.o

# target to build an object file
src/mbgl/tile/raster_tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/raster_tile.cpp.o
.PHONY : src/mbgl/tile/raster_tile.cpp.o

src/mbgl/tile/raster_tile.i: src/mbgl/tile/raster_tile.cpp.i

.PHONY : src/mbgl/tile/raster_tile.i

# target to preprocess a source file
src/mbgl/tile/raster_tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/raster_tile.cpp.i
.PHONY : src/mbgl/tile/raster_tile.cpp.i

src/mbgl/tile/raster_tile.s: src/mbgl/tile/raster_tile.cpp.s

.PHONY : src/mbgl/tile/raster_tile.s

# target to generate assembly for a file
src/mbgl/tile/raster_tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/raster_tile.cpp.s
.PHONY : src/mbgl/tile/raster_tile.cpp.s

src/mbgl/tile/raster_tile_worker.o: src/mbgl/tile/raster_tile_worker.cpp.o

.PHONY : src/mbgl/tile/raster_tile_worker.o

# target to build an object file
src/mbgl/tile/raster_tile_worker.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/raster_tile_worker.cpp.o
.PHONY : src/mbgl/tile/raster_tile_worker.cpp.o

src/mbgl/tile/raster_tile_worker.i: src/mbgl/tile/raster_tile_worker.cpp.i

.PHONY : src/mbgl/tile/raster_tile_worker.i

# target to preprocess a source file
src/mbgl/tile/raster_tile_worker.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/raster_tile_worker.cpp.i
.PHONY : src/mbgl/tile/raster_tile_worker.cpp.i

src/mbgl/tile/raster_tile_worker.s: src/mbgl/tile/raster_tile_worker.cpp.s

.PHONY : src/mbgl/tile/raster_tile_worker.s

# target to generate assembly for a file
src/mbgl/tile/raster_tile_worker.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/raster_tile_worker.cpp.s
.PHONY : src/mbgl/tile/raster_tile_worker.cpp.s

src/mbgl/tile/tile.o: src/mbgl/tile/tile.cpp.o

.PHONY : src/mbgl/tile/tile.o

# target to build an object file
src/mbgl/tile/tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile.cpp.o
.PHONY : src/mbgl/tile/tile.cpp.o

src/mbgl/tile/tile.i: src/mbgl/tile/tile.cpp.i

.PHONY : src/mbgl/tile/tile.i

# target to preprocess a source file
src/mbgl/tile/tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile.cpp.i
.PHONY : src/mbgl/tile/tile.cpp.i

src/mbgl/tile/tile.s: src/mbgl/tile/tile.cpp.s

.PHONY : src/mbgl/tile/tile.s

# target to generate assembly for a file
src/mbgl/tile/tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile.cpp.s
.PHONY : src/mbgl/tile/tile.cpp.s

src/mbgl/tile/tile_cache.o: src/mbgl/tile/tile_cache.cpp.o

.PHONY : src/mbgl/tile/tile_cache.o

# target to build an object file
src/mbgl/tile/tile_cache.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_cache.cpp.o
.PHONY : src/mbgl/tile/tile_cache.cpp.o

src/mbgl/tile/tile_cache.i: src/mbgl/tile/tile_cache.cpp.i

.PHONY : src/mbgl/tile/tile_cache.i

# target to preprocess a source file
src/mbgl/tile/tile_cache.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_cache.cpp.i
.PHONY : src/mbgl/tile/tile_cache.cpp.i

src/mbgl/tile/tile_cache.s: src/mbgl/tile/tile_cache.cpp.s

.PHONY : src/mbgl/tile/tile_cache.s

# target to generate assembly for a file
src/mbgl/tile/tile_cache.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_cache.cpp.s
.PHONY : src/mbgl/tile/tile_cache.cpp.s

src/mbgl/tile/tile_id_hash.o: src/mbgl/tile/tile_id_hash.cpp.o

.PHONY : src/mbgl/tile/tile_id_hash.o

# target to build an object file
src/mbgl/tile/tile_id_hash.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_id_hash.cpp.o
.PHONY : src/mbgl/tile/tile_id_hash.cpp.o

src/mbgl/tile/tile_id_hash.i: src/mbgl/tile/tile_id_hash.cpp.i

.PHONY : src/mbgl/tile/tile_id_hash.i

# target to preprocess a source file
src/mbgl/tile/tile_id_hash.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_id_hash.cpp.i
.PHONY : src/mbgl/tile/tile_id_hash.cpp.i

src/mbgl/tile/tile_id_hash.s: src/mbgl/tile/tile_id_hash.cpp.s

.PHONY : src/mbgl/tile/tile_id_hash.s

# target to generate assembly for a file
src/mbgl/tile/tile_id_hash.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_id_hash.cpp.s
.PHONY : src/mbgl/tile/tile_id_hash.cpp.s

src/mbgl/tile/tile_id_io.o: src/mbgl/tile/tile_id_io.cpp.o

.PHONY : src/mbgl/tile/tile_id_io.o

# target to build an object file
src/mbgl/tile/tile_id_io.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_id_io.cpp.o
.PHONY : src/mbgl/tile/tile_id_io.cpp.o

src/mbgl/tile/tile_id_io.i: src/mbgl/tile/tile_id_io.cpp.i

.PHONY : src/mbgl/tile/tile_id_io.i

# target to preprocess a source file
src/mbgl/tile/tile_id_io.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_id_io.cpp.i
.PHONY : src/mbgl/tile/tile_id_io.cpp.i

src/mbgl/tile/tile_id_io.s: src/mbgl/tile/tile_id_io.cpp.s

.PHONY : src/mbgl/tile/tile_id_io.s

# target to generate assembly for a file
src/mbgl/tile/tile_id_io.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/tile_id_io.cpp.s
.PHONY : src/mbgl/tile/tile_id_io.cpp.s

src/mbgl/tile/vector_tile.o: src/mbgl/tile/vector_tile.cpp.o

.PHONY : src/mbgl/tile/vector_tile.o

# target to build an object file
src/mbgl/tile/vector_tile.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/vector_tile.cpp.o
.PHONY : src/mbgl/tile/vector_tile.cpp.o

src/mbgl/tile/vector_tile.i: src/mbgl/tile/vector_tile.cpp.i

.PHONY : src/mbgl/tile/vector_tile.i

# target to preprocess a source file
src/mbgl/tile/vector_tile.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/vector_tile.cpp.i
.PHONY : src/mbgl/tile/vector_tile.cpp.i

src/mbgl/tile/vector_tile.s: src/mbgl/tile/vector_tile.cpp.s

.PHONY : src/mbgl/tile/vector_tile.s

# target to generate assembly for a file
src/mbgl/tile/vector_tile.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/vector_tile.cpp.s
.PHONY : src/mbgl/tile/vector_tile.cpp.s

src/mbgl/tile/vector_tile_data.o: src/mbgl/tile/vector_tile_data.cpp.o

.PHONY : src/mbgl/tile/vector_tile_data.o

# target to build an object file
src/mbgl/tile/vector_tile_data.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/vector_tile_data.cpp.o
.PHONY : src/mbgl/tile/vector_tile_data.cpp.o

src/mbgl/tile/vector_tile_data.i: src/mbgl/tile/vector_tile_data.cpp.i

.PHONY : src/mbgl/tile/vector_tile_data.i

# target to preprocess a source file
src/mbgl/tile/vector_tile_data.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/vector_tile_data.cpp.i
.PHONY : src/mbgl/tile/vector_tile_data.cpp.i

src/mbgl/tile/vector_tile_data.s: src/mbgl/tile/vector_tile_data.cpp.s

.PHONY : src/mbgl/tile/vector_tile_data.s

# target to generate assembly for a file
src/mbgl/tile/vector_tile_data.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/tile/vector_tile_data.cpp.s
.PHONY : src/mbgl/tile/vector_tile_data.cpp.s

src/mbgl/util/chrono.o: src/mbgl/util/chrono.cpp.o

.PHONY : src/mbgl/util/chrono.o

# target to build an object file
src/mbgl/util/chrono.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/chrono.cpp.o
.PHONY : src/mbgl/util/chrono.cpp.o

src/mbgl/util/chrono.i: src/mbgl/util/chrono.cpp.i

.PHONY : src/mbgl/util/chrono.i

# target to preprocess a source file
src/mbgl/util/chrono.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/chrono.cpp.i
.PHONY : src/mbgl/util/chrono.cpp.i

src/mbgl/util/chrono.s: src/mbgl/util/chrono.cpp.s

.PHONY : src/mbgl/util/chrono.s

# target to generate assembly for a file
src/mbgl/util/chrono.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/chrono.cpp.s
.PHONY : src/mbgl/util/chrono.cpp.s

src/mbgl/util/clip_id.o: src/mbgl/util/clip_id.cpp.o

.PHONY : src/mbgl/util/clip_id.o

# target to build an object file
src/mbgl/util/clip_id.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/clip_id.cpp.o
.PHONY : src/mbgl/util/clip_id.cpp.o

src/mbgl/util/clip_id.i: src/mbgl/util/clip_id.cpp.i

.PHONY : src/mbgl/util/clip_id.i

# target to preprocess a source file
src/mbgl/util/clip_id.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/clip_id.cpp.i
.PHONY : src/mbgl/util/clip_id.cpp.i

src/mbgl/util/clip_id.s: src/mbgl/util/clip_id.cpp.s

.PHONY : src/mbgl/util/clip_id.s

# target to generate assembly for a file
src/mbgl/util/clip_id.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/clip_id.cpp.s
.PHONY : src/mbgl/util/clip_id.cpp.s

src/mbgl/util/color.o: src/mbgl/util/color.cpp.o

.PHONY : src/mbgl/util/color.o

# target to build an object file
src/mbgl/util/color.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/color.cpp.o
.PHONY : src/mbgl/util/color.cpp.o

src/mbgl/util/color.i: src/mbgl/util/color.cpp.i

.PHONY : src/mbgl/util/color.i

# target to preprocess a source file
src/mbgl/util/color.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/color.cpp.i
.PHONY : src/mbgl/util/color.cpp.i

src/mbgl/util/color.s: src/mbgl/util/color.cpp.s

.PHONY : src/mbgl/util/color.s

# target to generate assembly for a file
src/mbgl/util/color.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/color.cpp.s
.PHONY : src/mbgl/util/color.cpp.s

src/mbgl/util/compression.o: src/mbgl/util/compression.cpp.o

.PHONY : src/mbgl/util/compression.o

# target to build an object file
src/mbgl/util/compression.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/compression.cpp.o
.PHONY : src/mbgl/util/compression.cpp.o

src/mbgl/util/compression.i: src/mbgl/util/compression.cpp.i

.PHONY : src/mbgl/util/compression.i

# target to preprocess a source file
src/mbgl/util/compression.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/compression.cpp.i
.PHONY : src/mbgl/util/compression.cpp.i

src/mbgl/util/compression.s: src/mbgl/util/compression.cpp.s

.PHONY : src/mbgl/util/compression.s

# target to generate assembly for a file
src/mbgl/util/compression.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/compression.cpp.s
.PHONY : src/mbgl/util/compression.cpp.s

src/mbgl/util/constants.o: src/mbgl/util/constants.cpp.o

.PHONY : src/mbgl/util/constants.o

# target to build an object file
src/mbgl/util/constants.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/constants.cpp.o
.PHONY : src/mbgl/util/constants.cpp.o

src/mbgl/util/constants.i: src/mbgl/util/constants.cpp.i

.PHONY : src/mbgl/util/constants.i

# target to preprocess a source file
src/mbgl/util/constants.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/constants.cpp.i
.PHONY : src/mbgl/util/constants.cpp.i

src/mbgl/util/constants.s: src/mbgl/util/constants.cpp.s

.PHONY : src/mbgl/util/constants.s

# target to generate assembly for a file
src/mbgl/util/constants.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/constants.cpp.s
.PHONY : src/mbgl/util/constants.cpp.s

src/mbgl/util/convert.o: src/mbgl/util/convert.cpp.o

.PHONY : src/mbgl/util/convert.o

# target to build an object file
src/mbgl/util/convert.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/convert.cpp.o
.PHONY : src/mbgl/util/convert.cpp.o

src/mbgl/util/convert.i: src/mbgl/util/convert.cpp.i

.PHONY : src/mbgl/util/convert.i

# target to preprocess a source file
src/mbgl/util/convert.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/convert.cpp.i
.PHONY : src/mbgl/util/convert.cpp.i

src/mbgl/util/convert.s: src/mbgl/util/convert.cpp.s

.PHONY : src/mbgl/util/convert.s

# target to generate assembly for a file
src/mbgl/util/convert.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/convert.cpp.s
.PHONY : src/mbgl/util/convert.cpp.s

src/mbgl/util/dtoa.o: src/mbgl/util/dtoa.cpp.o

.PHONY : src/mbgl/util/dtoa.o

# target to build an object file
src/mbgl/util/dtoa.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/dtoa.cpp.o
.PHONY : src/mbgl/util/dtoa.cpp.o

src/mbgl/util/dtoa.i: src/mbgl/util/dtoa.cpp.i

.PHONY : src/mbgl/util/dtoa.i

# target to preprocess a source file
src/mbgl/util/dtoa.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/dtoa.cpp.i
.PHONY : src/mbgl/util/dtoa.cpp.i

src/mbgl/util/dtoa.s: src/mbgl/util/dtoa.cpp.s

.PHONY : src/mbgl/util/dtoa.s

# target to generate assembly for a file
src/mbgl/util/dtoa.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/dtoa.cpp.s
.PHONY : src/mbgl/util/dtoa.cpp.s

src/mbgl/util/event.o: src/mbgl/util/event.cpp.o

.PHONY : src/mbgl/util/event.o

# target to build an object file
src/mbgl/util/event.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/event.cpp.o
.PHONY : src/mbgl/util/event.cpp.o

src/mbgl/util/event.i: src/mbgl/util/event.cpp.i

.PHONY : src/mbgl/util/event.i

# target to preprocess a source file
src/mbgl/util/event.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/event.cpp.i
.PHONY : src/mbgl/util/event.cpp.i

src/mbgl/util/event.s: src/mbgl/util/event.cpp.s

.PHONY : src/mbgl/util/event.s

# target to generate assembly for a file
src/mbgl/util/event.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/event.cpp.s
.PHONY : src/mbgl/util/event.cpp.s

src/mbgl/util/font_stack.o: src/mbgl/util/font_stack.cpp.o

.PHONY : src/mbgl/util/font_stack.o

# target to build an object file
src/mbgl/util/font_stack.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/font_stack.cpp.o
.PHONY : src/mbgl/util/font_stack.cpp.o

src/mbgl/util/font_stack.i: src/mbgl/util/font_stack.cpp.i

.PHONY : src/mbgl/util/font_stack.i

# target to preprocess a source file
src/mbgl/util/font_stack.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/font_stack.cpp.i
.PHONY : src/mbgl/util/font_stack.cpp.i

src/mbgl/util/font_stack.s: src/mbgl/util/font_stack.cpp.s

.PHONY : src/mbgl/util/font_stack.s

# target to generate assembly for a file
src/mbgl/util/font_stack.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/font_stack.cpp.s
.PHONY : src/mbgl/util/font_stack.cpp.s

src/mbgl/util/geo.o: src/mbgl/util/geo.cpp.o

.PHONY : src/mbgl/util/geo.o

# target to build an object file
src/mbgl/util/geo.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/geo.cpp.o
.PHONY : src/mbgl/util/geo.cpp.o

src/mbgl/util/geo.i: src/mbgl/util/geo.cpp.i

.PHONY : src/mbgl/util/geo.i

# target to preprocess a source file
src/mbgl/util/geo.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/geo.cpp.i
.PHONY : src/mbgl/util/geo.cpp.i

src/mbgl/util/geo.s: src/mbgl/util/geo.cpp.s

.PHONY : src/mbgl/util/geo.s

# target to generate assembly for a file
src/mbgl/util/geo.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/geo.cpp.s
.PHONY : src/mbgl/util/geo.cpp.s

src/mbgl/util/geojson_impl.o: src/mbgl/util/geojson_impl.cpp.o

.PHONY : src/mbgl/util/geojson_impl.o

# target to build an object file
src/mbgl/util/geojson_impl.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/geojson_impl.cpp.o
.PHONY : src/mbgl/util/geojson_impl.cpp.o

src/mbgl/util/geojson_impl.i: src/mbgl/util/geojson_impl.cpp.i

.PHONY : src/mbgl/util/geojson_impl.i

# target to preprocess a source file
src/mbgl/util/geojson_impl.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/geojson_impl.cpp.i
.PHONY : src/mbgl/util/geojson_impl.cpp.i

src/mbgl/util/geojson_impl.s: src/mbgl/util/geojson_impl.cpp.s

.PHONY : src/mbgl/util/geojson_impl.s

# target to generate assembly for a file
src/mbgl/util/geojson_impl.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/geojson_impl.cpp.s
.PHONY : src/mbgl/util/geojson_impl.cpp.s

src/mbgl/util/grid_index.o: src/mbgl/util/grid_index.cpp.o

.PHONY : src/mbgl/util/grid_index.o

# target to build an object file
src/mbgl/util/grid_index.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/grid_index.cpp.o
.PHONY : src/mbgl/util/grid_index.cpp.o

src/mbgl/util/grid_index.i: src/mbgl/util/grid_index.cpp.i

.PHONY : src/mbgl/util/grid_index.i

# target to preprocess a source file
src/mbgl/util/grid_index.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/grid_index.cpp.i
.PHONY : src/mbgl/util/grid_index.cpp.i

src/mbgl/util/grid_index.s: src/mbgl/util/grid_index.cpp.s

.PHONY : src/mbgl/util/grid_index.s

# target to generate assembly for a file
src/mbgl/util/grid_index.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/grid_index.cpp.s
.PHONY : src/mbgl/util/grid_index.cpp.s

src/mbgl/util/http_header.o: src/mbgl/util/http_header.cpp.o

.PHONY : src/mbgl/util/http_header.o

# target to build an object file
src/mbgl/util/http_header.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/http_header.cpp.o
.PHONY : src/mbgl/util/http_header.cpp.o

src/mbgl/util/http_header.i: src/mbgl/util/http_header.cpp.i

.PHONY : src/mbgl/util/http_header.i

# target to preprocess a source file
src/mbgl/util/http_header.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/http_header.cpp.i
.PHONY : src/mbgl/util/http_header.cpp.i

src/mbgl/util/http_header.s: src/mbgl/util/http_header.cpp.s

.PHONY : src/mbgl/util/http_header.s

# target to generate assembly for a file
src/mbgl/util/http_header.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/http_header.cpp.s
.PHONY : src/mbgl/util/http_header.cpp.s

src/mbgl/util/http_timeout.o: src/mbgl/util/http_timeout.cpp.o

.PHONY : src/mbgl/util/http_timeout.o

# target to build an object file
src/mbgl/util/http_timeout.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/http_timeout.cpp.o
.PHONY : src/mbgl/util/http_timeout.cpp.o

src/mbgl/util/http_timeout.i: src/mbgl/util/http_timeout.cpp.i

.PHONY : src/mbgl/util/http_timeout.i

# target to preprocess a source file
src/mbgl/util/http_timeout.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/http_timeout.cpp.i
.PHONY : src/mbgl/util/http_timeout.cpp.i

src/mbgl/util/http_timeout.s: src/mbgl/util/http_timeout.cpp.s

.PHONY : src/mbgl/util/http_timeout.s

# target to generate assembly for a file
src/mbgl/util/http_timeout.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/http_timeout.cpp.s
.PHONY : src/mbgl/util/http_timeout.cpp.s

src/mbgl/util/i18n.o: src/mbgl/util/i18n.cpp.o

.PHONY : src/mbgl/util/i18n.o

# target to build an object file
src/mbgl/util/i18n.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/i18n.cpp.o
.PHONY : src/mbgl/util/i18n.cpp.o

src/mbgl/util/i18n.i: src/mbgl/util/i18n.cpp.i

.PHONY : src/mbgl/util/i18n.i

# target to preprocess a source file
src/mbgl/util/i18n.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/i18n.cpp.i
.PHONY : src/mbgl/util/i18n.cpp.i

src/mbgl/util/i18n.s: src/mbgl/util/i18n.cpp.s

.PHONY : src/mbgl/util/i18n.s

# target to generate assembly for a file
src/mbgl/util/i18n.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/i18n.cpp.s
.PHONY : src/mbgl/util/i18n.cpp.s

src/mbgl/util/interpolate.o: src/mbgl/util/interpolate.cpp.o

.PHONY : src/mbgl/util/interpolate.o

# target to build an object file
src/mbgl/util/interpolate.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/interpolate.cpp.o
.PHONY : src/mbgl/util/interpolate.cpp.o

src/mbgl/util/interpolate.i: src/mbgl/util/interpolate.cpp.i

.PHONY : src/mbgl/util/interpolate.i

# target to preprocess a source file
src/mbgl/util/interpolate.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/interpolate.cpp.i
.PHONY : src/mbgl/util/interpolate.cpp.i

src/mbgl/util/interpolate.s: src/mbgl/util/interpolate.cpp.s

.PHONY : src/mbgl/util/interpolate.s

# target to generate assembly for a file
src/mbgl/util/interpolate.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/interpolate.cpp.s
.PHONY : src/mbgl/util/interpolate.cpp.s

src/mbgl/util/intersection_tests.o: src/mbgl/util/intersection_tests.cpp.o

.PHONY : src/mbgl/util/intersection_tests.o

# target to build an object file
src/mbgl/util/intersection_tests.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/intersection_tests.cpp.o
.PHONY : src/mbgl/util/intersection_tests.cpp.o

src/mbgl/util/intersection_tests.i: src/mbgl/util/intersection_tests.cpp.i

.PHONY : src/mbgl/util/intersection_tests.i

# target to preprocess a source file
src/mbgl/util/intersection_tests.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/intersection_tests.cpp.i
.PHONY : src/mbgl/util/intersection_tests.cpp.i

src/mbgl/util/intersection_tests.s: src/mbgl/util/intersection_tests.cpp.s

.PHONY : src/mbgl/util/intersection_tests.s

# target to generate assembly for a file
src/mbgl/util/intersection_tests.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/intersection_tests.cpp.s
.PHONY : src/mbgl/util/intersection_tests.cpp.s

src/mbgl/util/io.o: src/mbgl/util/io.cpp.o

.PHONY : src/mbgl/util/io.o

# target to build an object file
src/mbgl/util/io.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/io.cpp.o
.PHONY : src/mbgl/util/io.cpp.o

src/mbgl/util/io.i: src/mbgl/util/io.cpp.i

.PHONY : src/mbgl/util/io.i

# target to preprocess a source file
src/mbgl/util/io.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/io.cpp.i
.PHONY : src/mbgl/util/io.cpp.i

src/mbgl/util/io.s: src/mbgl/util/io.cpp.s

.PHONY : src/mbgl/util/io.s

# target to generate assembly for a file
src/mbgl/util/io.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/io.cpp.s
.PHONY : src/mbgl/util/io.cpp.s

src/mbgl/util/logging.o: src/mbgl/util/logging.cpp.o

.PHONY : src/mbgl/util/logging.o

# target to build an object file
src/mbgl/util/logging.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/logging.cpp.o
.PHONY : src/mbgl/util/logging.cpp.o

src/mbgl/util/logging.i: src/mbgl/util/logging.cpp.i

.PHONY : src/mbgl/util/logging.i

# target to preprocess a source file
src/mbgl/util/logging.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/logging.cpp.i
.PHONY : src/mbgl/util/logging.cpp.i

src/mbgl/util/logging.s: src/mbgl/util/logging.cpp.s

.PHONY : src/mbgl/util/logging.s

# target to generate assembly for a file
src/mbgl/util/logging.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/logging.cpp.s
.PHONY : src/mbgl/util/logging.cpp.s

src/mbgl/util/mapbox.o: src/mbgl/util/mapbox.cpp.o

.PHONY : src/mbgl/util/mapbox.o

# target to build an object file
src/mbgl/util/mapbox.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mapbox.cpp.o
.PHONY : src/mbgl/util/mapbox.cpp.o

src/mbgl/util/mapbox.i: src/mbgl/util/mapbox.cpp.i

.PHONY : src/mbgl/util/mapbox.i

# target to preprocess a source file
src/mbgl/util/mapbox.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mapbox.cpp.i
.PHONY : src/mbgl/util/mapbox.cpp.i

src/mbgl/util/mapbox.s: src/mbgl/util/mapbox.cpp.s

.PHONY : src/mbgl/util/mapbox.s

# target to generate assembly for a file
src/mbgl/util/mapbox.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mapbox.cpp.s
.PHONY : src/mbgl/util/mapbox.cpp.s

src/mbgl/util/mat2.o: src/mbgl/util/mat2.cpp.o

.PHONY : src/mbgl/util/mat2.o

# target to build an object file
src/mbgl/util/mat2.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat2.cpp.o
.PHONY : src/mbgl/util/mat2.cpp.o

src/mbgl/util/mat2.i: src/mbgl/util/mat2.cpp.i

.PHONY : src/mbgl/util/mat2.i

# target to preprocess a source file
src/mbgl/util/mat2.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat2.cpp.i
.PHONY : src/mbgl/util/mat2.cpp.i

src/mbgl/util/mat2.s: src/mbgl/util/mat2.cpp.s

.PHONY : src/mbgl/util/mat2.s

# target to generate assembly for a file
src/mbgl/util/mat2.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat2.cpp.s
.PHONY : src/mbgl/util/mat2.cpp.s

src/mbgl/util/mat3.o: src/mbgl/util/mat3.cpp.o

.PHONY : src/mbgl/util/mat3.o

# target to build an object file
src/mbgl/util/mat3.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat3.cpp.o
.PHONY : src/mbgl/util/mat3.cpp.o

src/mbgl/util/mat3.i: src/mbgl/util/mat3.cpp.i

.PHONY : src/mbgl/util/mat3.i

# target to preprocess a source file
src/mbgl/util/mat3.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat3.cpp.i
.PHONY : src/mbgl/util/mat3.cpp.i

src/mbgl/util/mat3.s: src/mbgl/util/mat3.cpp.s

.PHONY : src/mbgl/util/mat3.s

# target to generate assembly for a file
src/mbgl/util/mat3.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat3.cpp.s
.PHONY : src/mbgl/util/mat3.cpp.s

src/mbgl/util/mat4.o: src/mbgl/util/mat4.cpp.o

.PHONY : src/mbgl/util/mat4.o

# target to build an object file
src/mbgl/util/mat4.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat4.cpp.o
.PHONY : src/mbgl/util/mat4.cpp.o

src/mbgl/util/mat4.i: src/mbgl/util/mat4.cpp.i

.PHONY : src/mbgl/util/mat4.i

# target to preprocess a source file
src/mbgl/util/mat4.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat4.cpp.i
.PHONY : src/mbgl/util/mat4.cpp.i

src/mbgl/util/mat4.s: src/mbgl/util/mat4.cpp.s

.PHONY : src/mbgl/util/mat4.s

# target to generate assembly for a file
src/mbgl/util/mat4.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/mat4.cpp.s
.PHONY : src/mbgl/util/mat4.cpp.s

src/mbgl/util/offscreen_texture.o: src/mbgl/util/offscreen_texture.cpp.o

.PHONY : src/mbgl/util/offscreen_texture.o

# target to build an object file
src/mbgl/util/offscreen_texture.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/offscreen_texture.cpp.o
.PHONY : src/mbgl/util/offscreen_texture.cpp.o

src/mbgl/util/offscreen_texture.i: src/mbgl/util/offscreen_texture.cpp.i

.PHONY : src/mbgl/util/offscreen_texture.i

# target to preprocess a source file
src/mbgl/util/offscreen_texture.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/offscreen_texture.cpp.i
.PHONY : src/mbgl/util/offscreen_texture.cpp.i

src/mbgl/util/offscreen_texture.s: src/mbgl/util/offscreen_texture.cpp.s

.PHONY : src/mbgl/util/offscreen_texture.s

# target to generate assembly for a file
src/mbgl/util/offscreen_texture.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/offscreen_texture.cpp.s
.PHONY : src/mbgl/util/offscreen_texture.cpp.s

src/mbgl/util/premultiply.o: src/mbgl/util/premultiply.cpp.o

.PHONY : src/mbgl/util/premultiply.o

# target to build an object file
src/mbgl/util/premultiply.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/premultiply.cpp.o
.PHONY : src/mbgl/util/premultiply.cpp.o

src/mbgl/util/premultiply.i: src/mbgl/util/premultiply.cpp.i

.PHONY : src/mbgl/util/premultiply.i

# target to preprocess a source file
src/mbgl/util/premultiply.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/premultiply.cpp.i
.PHONY : src/mbgl/util/premultiply.cpp.i

src/mbgl/util/premultiply.s: src/mbgl/util/premultiply.cpp.s

.PHONY : src/mbgl/util/premultiply.s

# target to generate assembly for a file
src/mbgl/util/premultiply.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/premultiply.cpp.s
.PHONY : src/mbgl/util/premultiply.cpp.s

src/mbgl/util/stopwatch.o: src/mbgl/util/stopwatch.cpp.o

.PHONY : src/mbgl/util/stopwatch.o

# target to build an object file
src/mbgl/util/stopwatch.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/stopwatch.cpp.o
.PHONY : src/mbgl/util/stopwatch.cpp.o

src/mbgl/util/stopwatch.i: src/mbgl/util/stopwatch.cpp.i

.PHONY : src/mbgl/util/stopwatch.i

# target to preprocess a source file
src/mbgl/util/stopwatch.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/stopwatch.cpp.i
.PHONY : src/mbgl/util/stopwatch.cpp.i

src/mbgl/util/stopwatch.s: src/mbgl/util/stopwatch.cpp.s

.PHONY : src/mbgl/util/stopwatch.s

# target to generate assembly for a file
src/mbgl/util/stopwatch.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/stopwatch.cpp.s
.PHONY : src/mbgl/util/stopwatch.cpp.s

src/mbgl/util/string.o: src/mbgl/util/string.cpp.o

.PHONY : src/mbgl/util/string.o

# target to build an object file
src/mbgl/util/string.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/string.cpp.o
.PHONY : src/mbgl/util/string.cpp.o

src/mbgl/util/string.i: src/mbgl/util/string.cpp.i

.PHONY : src/mbgl/util/string.i

# target to preprocess a source file
src/mbgl/util/string.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/string.cpp.i
.PHONY : src/mbgl/util/string.cpp.i

src/mbgl/util/string.s: src/mbgl/util/string.cpp.s

.PHONY : src/mbgl/util/string.s

# target to generate assembly for a file
src/mbgl/util/string.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/string.cpp.s
.PHONY : src/mbgl/util/string.cpp.s

src/mbgl/util/throttler.o: src/mbgl/util/throttler.cpp.o

.PHONY : src/mbgl/util/throttler.o

# target to build an object file
src/mbgl/util/throttler.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/throttler.cpp.o
.PHONY : src/mbgl/util/throttler.cpp.o

src/mbgl/util/throttler.i: src/mbgl/util/throttler.cpp.i

.PHONY : src/mbgl/util/throttler.i

# target to preprocess a source file
src/mbgl/util/throttler.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/throttler.cpp.i
.PHONY : src/mbgl/util/throttler.cpp.i

src/mbgl/util/throttler.s: src/mbgl/util/throttler.cpp.s

.PHONY : src/mbgl/util/throttler.s

# target to generate assembly for a file
src/mbgl/util/throttler.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/throttler.cpp.s
.PHONY : src/mbgl/util/throttler.cpp.s

src/mbgl/util/tile_cover.o: src/mbgl/util/tile_cover.cpp.o

.PHONY : src/mbgl/util/tile_cover.o

# target to build an object file
src/mbgl/util/tile_cover.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/tile_cover.cpp.o
.PHONY : src/mbgl/util/tile_cover.cpp.o

src/mbgl/util/tile_cover.i: src/mbgl/util/tile_cover.cpp.i

.PHONY : src/mbgl/util/tile_cover.i

# target to preprocess a source file
src/mbgl/util/tile_cover.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/tile_cover.cpp.i
.PHONY : src/mbgl/util/tile_cover.cpp.i

src/mbgl/util/tile_cover.s: src/mbgl/util/tile_cover.cpp.s

.PHONY : src/mbgl/util/tile_cover.s

# target to generate assembly for a file
src/mbgl/util/tile_cover.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/tile_cover.cpp.s
.PHONY : src/mbgl/util/tile_cover.cpp.s

src/mbgl/util/url.o: src/mbgl/util/url.cpp.o

.PHONY : src/mbgl/util/url.o

# target to build an object file
src/mbgl/util/url.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/url.cpp.o
.PHONY : src/mbgl/util/url.cpp.o

src/mbgl/util/url.i: src/mbgl/util/url.cpp.i

.PHONY : src/mbgl/util/url.i

# target to preprocess a source file
src/mbgl/util/url.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/url.cpp.i
.PHONY : src/mbgl/util/url.cpp.i

src/mbgl/util/url.s: src/mbgl/util/url.cpp.s

.PHONY : src/mbgl/util/url.s

# target to generate assembly for a file
src/mbgl/util/url.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/url.cpp.s
.PHONY : src/mbgl/util/url.cpp.s

src/mbgl/util/version.o: src/mbgl/util/version.cpp.o

.PHONY : src/mbgl/util/version.o

# target to build an object file
src/mbgl/util/version.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/version.cpp.o
.PHONY : src/mbgl/util/version.cpp.o

src/mbgl/util/version.i: src/mbgl/util/version.cpp.i

.PHONY : src/mbgl/util/version.i

# target to preprocess a source file
src/mbgl/util/version.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/version.cpp.i
.PHONY : src/mbgl/util/version.cpp.i

src/mbgl/util/version.s: src/mbgl/util/version.cpp.s

.PHONY : src/mbgl/util/version.s

# target to generate assembly for a file
src/mbgl/util/version.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/version.cpp.s
.PHONY : src/mbgl/util/version.cpp.s

src/mbgl/util/work_request.o: src/mbgl/util/work_request.cpp.o

.PHONY : src/mbgl/util/work_request.o

# target to build an object file
src/mbgl/util/work_request.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/work_request.cpp.o
.PHONY : src/mbgl/util/work_request.cpp.o

src/mbgl/util/work_request.i: src/mbgl/util/work_request.cpp.i

.PHONY : src/mbgl/util/work_request.i

# target to preprocess a source file
src/mbgl/util/work_request.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/work_request.cpp.i
.PHONY : src/mbgl/util/work_request.cpp.i

src/mbgl/util/work_request.s: src/mbgl/util/work_request.cpp.s

.PHONY : src/mbgl/util/work_request.s

# target to generate assembly for a file
src/mbgl/util/work_request.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/mbgl/util/work_request.cpp.s
.PHONY : src/mbgl/util/work_request.cpp.s

src/parsedate/parsedate.o: src/parsedate/parsedate.c.o

.PHONY : src/parsedate/parsedate.o

# target to build an object file
src/parsedate/parsedate.c.o:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/parsedate/parsedate.c.o
.PHONY : src/parsedate/parsedate.c.o

src/parsedate/parsedate.i: src/parsedate/parsedate.c.i

.PHONY : src/parsedate/parsedate.i

# target to preprocess a source file
src/parsedate/parsedate.c.i:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/parsedate/parsedate.c.i
.PHONY : src/parsedate/parsedate.c.i

src/parsedate/parsedate.s: src/parsedate/parsedate.c.s

.PHONY : src/parsedate/parsedate.s

# target to generate assembly for a file
src/parsedate/parsedate.c.s:
	$(MAKE) -f CMakeFiles/mbgl-core.dir/build.make CMakeFiles/mbgl-core.dir/src/parsedate/parsedate.c.s
.PHONY : src/parsedate/parsedate.c.s

test/actor/actor.test.o: test/actor/actor.test.cpp.o

.PHONY : test/actor/actor.test.o

# target to build an object file
test/actor/actor.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/actor/actor.test.cpp.o
.PHONY : test/actor/actor.test.cpp.o

test/actor/actor.test.i: test/actor/actor.test.cpp.i

.PHONY : test/actor/actor.test.i

# target to preprocess a source file
test/actor/actor.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/actor/actor.test.cpp.i
.PHONY : test/actor/actor.test.cpp.i

test/actor/actor.test.s: test/actor/actor.test.cpp.s

.PHONY : test/actor/actor.test.s

# target to generate assembly for a file
test/actor/actor.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/actor/actor.test.cpp.s
.PHONY : test/actor/actor.test.cpp.s

test/actor/actor_ref.test.o: test/actor/actor_ref.test.cpp.o

.PHONY : test/actor/actor_ref.test.o

# target to build an object file
test/actor/actor_ref.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/actor/actor_ref.test.cpp.o
.PHONY : test/actor/actor_ref.test.cpp.o

test/actor/actor_ref.test.i: test/actor/actor_ref.test.cpp.i

.PHONY : test/actor/actor_ref.test.i

# target to preprocess a source file
test/actor/actor_ref.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/actor/actor_ref.test.cpp.i
.PHONY : test/actor/actor_ref.test.cpp.i

test/actor/actor_ref.test.s: test/actor/actor_ref.test.cpp.s

.PHONY : test/actor/actor_ref.test.s

# target to generate assembly for a file
test/actor/actor_ref.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/actor/actor_ref.test.cpp.s
.PHONY : test/actor/actor_ref.test.cpp.s

test/algorithm/covered_by_children.test.o: test/algorithm/covered_by_children.test.cpp.o

.PHONY : test/algorithm/covered_by_children.test.o

# target to build an object file
test/algorithm/covered_by_children.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/covered_by_children.test.cpp.o
.PHONY : test/algorithm/covered_by_children.test.cpp.o

test/algorithm/covered_by_children.test.i: test/algorithm/covered_by_children.test.cpp.i

.PHONY : test/algorithm/covered_by_children.test.i

# target to preprocess a source file
test/algorithm/covered_by_children.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/covered_by_children.test.cpp.i
.PHONY : test/algorithm/covered_by_children.test.cpp.i

test/algorithm/covered_by_children.test.s: test/algorithm/covered_by_children.test.cpp.s

.PHONY : test/algorithm/covered_by_children.test.s

# target to generate assembly for a file
test/algorithm/covered_by_children.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/covered_by_children.test.cpp.s
.PHONY : test/algorithm/covered_by_children.test.cpp.s

test/algorithm/generate_clip_ids.test.o: test/algorithm/generate_clip_ids.test.cpp.o

.PHONY : test/algorithm/generate_clip_ids.test.o

# target to build an object file
test/algorithm/generate_clip_ids.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/generate_clip_ids.test.cpp.o
.PHONY : test/algorithm/generate_clip_ids.test.cpp.o

test/algorithm/generate_clip_ids.test.i: test/algorithm/generate_clip_ids.test.cpp.i

.PHONY : test/algorithm/generate_clip_ids.test.i

# target to preprocess a source file
test/algorithm/generate_clip_ids.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/generate_clip_ids.test.cpp.i
.PHONY : test/algorithm/generate_clip_ids.test.cpp.i

test/algorithm/generate_clip_ids.test.s: test/algorithm/generate_clip_ids.test.cpp.s

.PHONY : test/algorithm/generate_clip_ids.test.s

# target to generate assembly for a file
test/algorithm/generate_clip_ids.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/generate_clip_ids.test.cpp.s
.PHONY : test/algorithm/generate_clip_ids.test.cpp.s

test/algorithm/update_renderables.test.o: test/algorithm/update_renderables.test.cpp.o

.PHONY : test/algorithm/update_renderables.test.o

# target to build an object file
test/algorithm/update_renderables.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/update_renderables.test.cpp.o
.PHONY : test/algorithm/update_renderables.test.cpp.o

test/algorithm/update_renderables.test.i: test/algorithm/update_renderables.test.cpp.i

.PHONY : test/algorithm/update_renderables.test.i

# target to preprocess a source file
test/algorithm/update_renderables.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/update_renderables.test.cpp.i
.PHONY : test/algorithm/update_renderables.test.cpp.i

test/algorithm/update_renderables.test.s: test/algorithm/update_renderables.test.cpp.s

.PHONY : test/algorithm/update_renderables.test.s

# target to generate assembly for a file
test/algorithm/update_renderables.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/update_renderables.test.cpp.s
.PHONY : test/algorithm/update_renderables.test.cpp.s

test/algorithm/update_tile_masks.test.o: test/algorithm/update_tile_masks.test.cpp.o

.PHONY : test/algorithm/update_tile_masks.test.o

# target to build an object file
test/algorithm/update_tile_masks.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/update_tile_masks.test.cpp.o
.PHONY : test/algorithm/update_tile_masks.test.cpp.o

test/algorithm/update_tile_masks.test.i: test/algorithm/update_tile_masks.test.cpp.i

.PHONY : test/algorithm/update_tile_masks.test.i

# target to preprocess a source file
test/algorithm/update_tile_masks.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/update_tile_masks.test.cpp.i
.PHONY : test/algorithm/update_tile_masks.test.cpp.i

test/algorithm/update_tile_masks.test.s: test/algorithm/update_tile_masks.test.cpp.s

.PHONY : test/algorithm/update_tile_masks.test.s

# target to generate assembly for a file
test/algorithm/update_tile_masks.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/algorithm/update_tile_masks.test.cpp.s
.PHONY : test/algorithm/update_tile_masks.test.cpp.s

test/api/annotations.test.o: test/api/annotations.test.cpp.o

.PHONY : test/api/annotations.test.o

# target to build an object file
test/api/annotations.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/annotations.test.cpp.o
.PHONY : test/api/annotations.test.cpp.o

test/api/annotations.test.i: test/api/annotations.test.cpp.i

.PHONY : test/api/annotations.test.i

# target to preprocess a source file
test/api/annotations.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/annotations.test.cpp.i
.PHONY : test/api/annotations.test.cpp.i

test/api/annotations.test.s: test/api/annotations.test.cpp.s

.PHONY : test/api/annotations.test.s

# target to generate assembly for a file
test/api/annotations.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/annotations.test.cpp.s
.PHONY : test/api/annotations.test.cpp.s

test/api/api_misuse.test.o: test/api/api_misuse.test.cpp.o

.PHONY : test/api/api_misuse.test.o

# target to build an object file
test/api/api_misuse.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/api_misuse.test.cpp.o
.PHONY : test/api/api_misuse.test.cpp.o

test/api/api_misuse.test.i: test/api/api_misuse.test.cpp.i

.PHONY : test/api/api_misuse.test.i

# target to preprocess a source file
test/api/api_misuse.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/api_misuse.test.cpp.i
.PHONY : test/api/api_misuse.test.cpp.i

test/api/api_misuse.test.s: test/api/api_misuse.test.cpp.s

.PHONY : test/api/api_misuse.test.s

# target to generate assembly for a file
test/api/api_misuse.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/api_misuse.test.cpp.s
.PHONY : test/api/api_misuse.test.cpp.s

test/api/custom_layer.test.o: test/api/custom_layer.test.cpp.o

.PHONY : test/api/custom_layer.test.o

# target to build an object file
test/api/custom_layer.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/custom_layer.test.cpp.o
.PHONY : test/api/custom_layer.test.cpp.o

test/api/custom_layer.test.i: test/api/custom_layer.test.cpp.i

.PHONY : test/api/custom_layer.test.i

# target to preprocess a source file
test/api/custom_layer.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/custom_layer.test.cpp.i
.PHONY : test/api/custom_layer.test.cpp.i

test/api/custom_layer.test.s: test/api/custom_layer.test.cpp.s

.PHONY : test/api/custom_layer.test.s

# target to generate assembly for a file
test/api/custom_layer.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/custom_layer.test.cpp.s
.PHONY : test/api/custom_layer.test.cpp.s

test/api/query.test.o: test/api/query.test.cpp.o

.PHONY : test/api/query.test.o

# target to build an object file
test/api/query.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/query.test.cpp.o
.PHONY : test/api/query.test.cpp.o

test/api/query.test.i: test/api/query.test.cpp.i

.PHONY : test/api/query.test.i

# target to preprocess a source file
test/api/query.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/query.test.cpp.i
.PHONY : test/api/query.test.cpp.i

test/api/query.test.s: test/api/query.test.cpp.s

.PHONY : test/api/query.test.s

# target to generate assembly for a file
test/api/query.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/query.test.cpp.s
.PHONY : test/api/query.test.cpp.s

test/api/recycle_map.o: test/api/recycle_map.cpp.o

.PHONY : test/api/recycle_map.o

# target to build an object file
test/api/recycle_map.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/recycle_map.cpp.o
.PHONY : test/api/recycle_map.cpp.o

test/api/recycle_map.i: test/api/recycle_map.cpp.i

.PHONY : test/api/recycle_map.i

# target to preprocess a source file
test/api/recycle_map.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/recycle_map.cpp.i
.PHONY : test/api/recycle_map.cpp.i

test/api/recycle_map.s: test/api/recycle_map.cpp.s

.PHONY : test/api/recycle_map.s

# target to generate assembly for a file
test/api/recycle_map.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/recycle_map.cpp.s
.PHONY : test/api/recycle_map.cpp.s

test/api/zoom_history.o: test/api/zoom_history.cpp.o

.PHONY : test/api/zoom_history.o

# target to build an object file
test/api/zoom_history.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/zoom_history.cpp.o
.PHONY : test/api/zoom_history.cpp.o

test/api/zoom_history.i: test/api/zoom_history.cpp.i

.PHONY : test/api/zoom_history.i

# target to preprocess a source file
test/api/zoom_history.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/zoom_history.cpp.i
.PHONY : test/api/zoom_history.cpp.i

test/api/zoom_history.s: test/api/zoom_history.cpp.s

.PHONY : test/api/zoom_history.s

# target to generate assembly for a file
test/api/zoom_history.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/api/zoom_history.cpp.s
.PHONY : test/api/zoom_history.cpp.s

test/gl/bucket.test.o: test/gl/bucket.test.cpp.o

.PHONY : test/gl/bucket.test.o

# target to build an object file
test/gl/bucket.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/bucket.test.cpp.o
.PHONY : test/gl/bucket.test.cpp.o

test/gl/bucket.test.i: test/gl/bucket.test.cpp.i

.PHONY : test/gl/bucket.test.i

# target to preprocess a source file
test/gl/bucket.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/bucket.test.cpp.i
.PHONY : test/gl/bucket.test.cpp.i

test/gl/bucket.test.s: test/gl/bucket.test.cpp.s

.PHONY : test/gl/bucket.test.s

# target to generate assembly for a file
test/gl/bucket.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/bucket.test.cpp.s
.PHONY : test/gl/bucket.test.cpp.s

test/gl/context.test.o: test/gl/context.test.cpp.o

.PHONY : test/gl/context.test.o

# target to build an object file
test/gl/context.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/context.test.cpp.o
.PHONY : test/gl/context.test.cpp.o

test/gl/context.test.i: test/gl/context.test.cpp.i

.PHONY : test/gl/context.test.i

# target to preprocess a source file
test/gl/context.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/context.test.cpp.i
.PHONY : test/gl/context.test.cpp.i

test/gl/context.test.s: test/gl/context.test.cpp.s

.PHONY : test/gl/context.test.s

# target to generate assembly for a file
test/gl/context.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/context.test.cpp.s
.PHONY : test/gl/context.test.cpp.s

test/gl/object.test.o: test/gl/object.test.cpp.o

.PHONY : test/gl/object.test.o

# target to build an object file
test/gl/object.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/object.test.cpp.o
.PHONY : test/gl/object.test.cpp.o

test/gl/object.test.i: test/gl/object.test.cpp.i

.PHONY : test/gl/object.test.i

# target to preprocess a source file
test/gl/object.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/object.test.cpp.i
.PHONY : test/gl/object.test.cpp.i

test/gl/object.test.s: test/gl/object.test.cpp.s

.PHONY : test/gl/object.test.s

# target to generate assembly for a file
test/gl/object.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/gl/object.test.cpp.s
.PHONY : test/gl/object.test.cpp.s

test/map/map.test.o: test/map/map.test.cpp.o

.PHONY : test/map/map.test.o

# target to build an object file
test/map/map.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/map.test.cpp.o
.PHONY : test/map/map.test.cpp.o

test/map/map.test.i: test/map/map.test.cpp.i

.PHONY : test/map/map.test.i

# target to preprocess a source file
test/map/map.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/map.test.cpp.i
.PHONY : test/map/map.test.cpp.i

test/map/map.test.s: test/map/map.test.cpp.s

.PHONY : test/map/map.test.s

# target to generate assembly for a file
test/map/map.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/map.test.cpp.s
.PHONY : test/map/map.test.cpp.s

test/map/prefetch.test.o: test/map/prefetch.test.cpp.o

.PHONY : test/map/prefetch.test.o

# target to build an object file
test/map/prefetch.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/prefetch.test.cpp.o
.PHONY : test/map/prefetch.test.cpp.o

test/map/prefetch.test.i: test/map/prefetch.test.cpp.i

.PHONY : test/map/prefetch.test.i

# target to preprocess a source file
test/map/prefetch.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/prefetch.test.cpp.i
.PHONY : test/map/prefetch.test.cpp.i

test/map/prefetch.test.s: test/map/prefetch.test.cpp.s

.PHONY : test/map/prefetch.test.s

# target to generate assembly for a file
test/map/prefetch.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/prefetch.test.cpp.s
.PHONY : test/map/prefetch.test.cpp.s

test/map/transform.test.o: test/map/transform.test.cpp.o

.PHONY : test/map/transform.test.o

# target to build an object file
test/map/transform.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/transform.test.cpp.o
.PHONY : test/map/transform.test.cpp.o

test/map/transform.test.i: test/map/transform.test.cpp.i

.PHONY : test/map/transform.test.i

# target to preprocess a source file
test/map/transform.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/transform.test.cpp.i
.PHONY : test/map/transform.test.cpp.i

test/map/transform.test.s: test/map/transform.test.cpp.s

.PHONY : test/map/transform.test.s

# target to generate assembly for a file
test/map/transform.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/map/transform.test.cpp.s
.PHONY : test/map/transform.test.cpp.s

test/math/clamp.test.o: test/math/clamp.test.cpp.o

.PHONY : test/math/clamp.test.o

# target to build an object file
test/math/clamp.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/clamp.test.cpp.o
.PHONY : test/math/clamp.test.cpp.o

test/math/clamp.test.i: test/math/clamp.test.cpp.i

.PHONY : test/math/clamp.test.i

# target to preprocess a source file
test/math/clamp.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/clamp.test.cpp.i
.PHONY : test/math/clamp.test.cpp.i

test/math/clamp.test.s: test/math/clamp.test.cpp.s

.PHONY : test/math/clamp.test.s

# target to generate assembly for a file
test/math/clamp.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/clamp.test.cpp.s
.PHONY : test/math/clamp.test.cpp.s

test/math/minmax.test.o: test/math/minmax.test.cpp.o

.PHONY : test/math/minmax.test.o

# target to build an object file
test/math/minmax.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/minmax.test.cpp.o
.PHONY : test/math/minmax.test.cpp.o

test/math/minmax.test.i: test/math/minmax.test.cpp.i

.PHONY : test/math/minmax.test.i

# target to preprocess a source file
test/math/minmax.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/minmax.test.cpp.i
.PHONY : test/math/minmax.test.cpp.i

test/math/minmax.test.s: test/math/minmax.test.cpp.s

.PHONY : test/math/minmax.test.s

# target to generate assembly for a file
test/math/minmax.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/minmax.test.cpp.s
.PHONY : test/math/minmax.test.cpp.s

test/math/wrap.test.o: test/math/wrap.test.cpp.o

.PHONY : test/math/wrap.test.o

# target to build an object file
test/math/wrap.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/wrap.test.cpp.o
.PHONY : test/math/wrap.test.cpp.o

test/math/wrap.test.i: test/math/wrap.test.cpp.i

.PHONY : test/math/wrap.test.i

# target to preprocess a source file
test/math/wrap.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/wrap.test.cpp.i
.PHONY : test/math/wrap.test.cpp.i

test/math/wrap.test.s: test/math/wrap.test.cpp.s

.PHONY : test/math/wrap.test.s

# target to generate assembly for a file
test/math/wrap.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/math/wrap.test.cpp.s
.PHONY : test/math/wrap.test.cpp.s

test/programs/binary_program.test.o: test/programs/binary_program.test.cpp.o

.PHONY : test/programs/binary_program.test.o

# target to build an object file
test/programs/binary_program.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/programs/binary_program.test.cpp.o
.PHONY : test/programs/binary_program.test.cpp.o

test/programs/binary_program.test.i: test/programs/binary_program.test.cpp.i

.PHONY : test/programs/binary_program.test.i

# target to preprocess a source file
test/programs/binary_program.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/programs/binary_program.test.cpp.i
.PHONY : test/programs/binary_program.test.cpp.i

test/programs/binary_program.test.s: test/programs/binary_program.test.cpp.s

.PHONY : test/programs/binary_program.test.s

# target to generate assembly for a file
test/programs/binary_program.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/programs/binary_program.test.cpp.s
.PHONY : test/programs/binary_program.test.cpp.s

test/programs/symbol_program.test.o: test/programs/symbol_program.test.cpp.o

.PHONY : test/programs/symbol_program.test.o

# target to build an object file
test/programs/symbol_program.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/programs/symbol_program.test.cpp.o
.PHONY : test/programs/symbol_program.test.cpp.o

test/programs/symbol_program.test.i: test/programs/symbol_program.test.cpp.i

.PHONY : test/programs/symbol_program.test.i

# target to preprocess a source file
test/programs/symbol_program.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/programs/symbol_program.test.cpp.i
.PHONY : test/programs/symbol_program.test.cpp.i

test/programs/symbol_program.test.s: test/programs/symbol_program.test.cpp.s

.PHONY : test/programs/symbol_program.test.s

# target to generate assembly for a file
test/programs/symbol_program.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/programs/symbol_program.test.cpp.s
.PHONY : test/programs/symbol_program.test.cpp.s

test/renderer/backend_scope.test.o: test/renderer/backend_scope.test.cpp.o

.PHONY : test/renderer/backend_scope.test.o

# target to build an object file
test/renderer/backend_scope.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/backend_scope.test.cpp.o
.PHONY : test/renderer/backend_scope.test.cpp.o

test/renderer/backend_scope.test.i: test/renderer/backend_scope.test.cpp.i

.PHONY : test/renderer/backend_scope.test.i

# target to preprocess a source file
test/renderer/backend_scope.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/backend_scope.test.cpp.i
.PHONY : test/renderer/backend_scope.test.cpp.i

test/renderer/backend_scope.test.s: test/renderer/backend_scope.test.cpp.s

.PHONY : test/renderer/backend_scope.test.s

# target to generate assembly for a file
test/renderer/backend_scope.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/backend_scope.test.cpp.s
.PHONY : test/renderer/backend_scope.test.cpp.s

test/renderer/group_by_layout.test.o: test/renderer/group_by_layout.test.cpp.o

.PHONY : test/renderer/group_by_layout.test.o

# target to build an object file
test/renderer/group_by_layout.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/group_by_layout.test.cpp.o
.PHONY : test/renderer/group_by_layout.test.cpp.o

test/renderer/group_by_layout.test.i: test/renderer/group_by_layout.test.cpp.i

.PHONY : test/renderer/group_by_layout.test.i

# target to preprocess a source file
test/renderer/group_by_layout.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/group_by_layout.test.cpp.i
.PHONY : test/renderer/group_by_layout.test.cpp.i

test/renderer/group_by_layout.test.s: test/renderer/group_by_layout.test.cpp.s

.PHONY : test/renderer/group_by_layout.test.s

# target to generate assembly for a file
test/renderer/group_by_layout.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/group_by_layout.test.cpp.s
.PHONY : test/renderer/group_by_layout.test.cpp.s

test/renderer/image_manager.test.o: test/renderer/image_manager.test.cpp.o

.PHONY : test/renderer/image_manager.test.o

# target to build an object file
test/renderer/image_manager.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/image_manager.test.cpp.o
.PHONY : test/renderer/image_manager.test.cpp.o

test/renderer/image_manager.test.i: test/renderer/image_manager.test.cpp.i

.PHONY : test/renderer/image_manager.test.i

# target to preprocess a source file
test/renderer/image_manager.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/image_manager.test.cpp.i
.PHONY : test/renderer/image_manager.test.cpp.i

test/renderer/image_manager.test.s: test/renderer/image_manager.test.cpp.s

.PHONY : test/renderer/image_manager.test.s

# target to generate assembly for a file
test/renderer/image_manager.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/renderer/image_manager.test.cpp.s
.PHONY : test/renderer/image_manager.test.cpp.s

test/sprite/sprite_loader.test.o: test/sprite/sprite_loader.test.cpp.o

.PHONY : test/sprite/sprite_loader.test.o

# target to build an object file
test/sprite/sprite_loader.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/sprite/sprite_loader.test.cpp.o
.PHONY : test/sprite/sprite_loader.test.cpp.o

test/sprite/sprite_loader.test.i: test/sprite/sprite_loader.test.cpp.i

.PHONY : test/sprite/sprite_loader.test.i

# target to preprocess a source file
test/sprite/sprite_loader.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/sprite/sprite_loader.test.cpp.i
.PHONY : test/sprite/sprite_loader.test.cpp.i

test/sprite/sprite_loader.test.s: test/sprite/sprite_loader.test.cpp.s

.PHONY : test/sprite/sprite_loader.test.s

# target to generate assembly for a file
test/sprite/sprite_loader.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/sprite/sprite_loader.test.cpp.s
.PHONY : test/sprite/sprite_loader.test.cpp.s

test/sprite/sprite_parser.test.o: test/sprite/sprite_parser.test.cpp.o

.PHONY : test/sprite/sprite_parser.test.o

# target to build an object file
test/sprite/sprite_parser.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/sprite/sprite_parser.test.cpp.o
.PHONY : test/sprite/sprite_parser.test.cpp.o

test/sprite/sprite_parser.test.i: test/sprite/sprite_parser.test.cpp.i

.PHONY : test/sprite/sprite_parser.test.i

# target to preprocess a source file
test/sprite/sprite_parser.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/sprite/sprite_parser.test.cpp.i
.PHONY : test/sprite/sprite_parser.test.cpp.i

test/sprite/sprite_parser.test.s: test/sprite/sprite_parser.test.cpp.s

.PHONY : test/sprite/sprite_parser.test.s

# target to generate assembly for a file
test/sprite/sprite_parser.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/sprite/sprite_parser.test.cpp.s
.PHONY : test/sprite/sprite_parser.test.cpp.s

test/src/mbgl/test/fixture_log_observer.o: test/src/mbgl/test/fixture_log_observer.cpp.o

.PHONY : test/src/mbgl/test/fixture_log_observer.o

# target to build an object file
test/src/mbgl/test/fixture_log_observer.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/fixture_log_observer.cpp.o
.PHONY : test/src/mbgl/test/fixture_log_observer.cpp.o

test/src/mbgl/test/fixture_log_observer.i: test/src/mbgl/test/fixture_log_observer.cpp.i

.PHONY : test/src/mbgl/test/fixture_log_observer.i

# target to preprocess a source file
test/src/mbgl/test/fixture_log_observer.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/fixture_log_observer.cpp.i
.PHONY : test/src/mbgl/test/fixture_log_observer.cpp.i

test/src/mbgl/test/fixture_log_observer.s: test/src/mbgl/test/fixture_log_observer.cpp.s

.PHONY : test/src/mbgl/test/fixture_log_observer.s

# target to generate assembly for a file
test/src/mbgl/test/fixture_log_observer.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/fixture_log_observer.cpp.s
.PHONY : test/src/mbgl/test/fixture_log_observer.cpp.s

test/src/mbgl/test/getrss.o: test/src/mbgl/test/getrss.cpp.o

.PHONY : test/src/mbgl/test/getrss.o

# target to build an object file
test/src/mbgl/test/getrss.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/getrss.cpp.o
.PHONY : test/src/mbgl/test/getrss.cpp.o

test/src/mbgl/test/getrss.i: test/src/mbgl/test/getrss.cpp.i

.PHONY : test/src/mbgl/test/getrss.i

# target to preprocess a source file
test/src/mbgl/test/getrss.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/getrss.cpp.i
.PHONY : test/src/mbgl/test/getrss.cpp.i

test/src/mbgl/test/getrss.s: test/src/mbgl/test/getrss.cpp.s

.PHONY : test/src/mbgl/test/getrss.s

# target to generate assembly for a file
test/src/mbgl/test/getrss.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/getrss.cpp.s
.PHONY : test/src/mbgl/test/getrss.cpp.s

test/src/mbgl/test/stub_file_source.o: test/src/mbgl/test/stub_file_source.cpp.o

.PHONY : test/src/mbgl/test/stub_file_source.o

# target to build an object file
test/src/mbgl/test/stub_file_source.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/stub_file_source.cpp.o
.PHONY : test/src/mbgl/test/stub_file_source.cpp.o

test/src/mbgl/test/stub_file_source.i: test/src/mbgl/test/stub_file_source.cpp.i

.PHONY : test/src/mbgl/test/stub_file_source.i

# target to preprocess a source file
test/src/mbgl/test/stub_file_source.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/stub_file_source.cpp.i
.PHONY : test/src/mbgl/test/stub_file_source.cpp.i

test/src/mbgl/test/stub_file_source.s: test/src/mbgl/test/stub_file_source.cpp.s

.PHONY : test/src/mbgl/test/stub_file_source.s

# target to generate assembly for a file
test/src/mbgl/test/stub_file_source.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/stub_file_source.cpp.s
.PHONY : test/src/mbgl/test/stub_file_source.cpp.s

test/src/mbgl/test/test.o: test/src/mbgl/test/test.cpp.o

.PHONY : test/src/mbgl/test/test.o

# target to build an object file
test/src/mbgl/test/test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/test.cpp.o
.PHONY : test/src/mbgl/test/test.cpp.o

test/src/mbgl/test/test.i: test/src/mbgl/test/test.cpp.i

.PHONY : test/src/mbgl/test/test.i

# target to preprocess a source file
test/src/mbgl/test/test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/test.cpp.i
.PHONY : test/src/mbgl/test/test.cpp.i

test/src/mbgl/test/test.s: test/src/mbgl/test/test.cpp.s

.PHONY : test/src/mbgl/test/test.s

# target to generate assembly for a file
test/src/mbgl/test/test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/test.cpp.s
.PHONY : test/src/mbgl/test/test.cpp.s

test/src/mbgl/test/util.o: test/src/mbgl/test/util.cpp.o

.PHONY : test/src/mbgl/test/util.o

# target to build an object file
test/src/mbgl/test/util.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/util.cpp.o
.PHONY : test/src/mbgl/test/util.cpp.o

test/src/mbgl/test/util.i: test/src/mbgl/test/util.cpp.i

.PHONY : test/src/mbgl/test/util.i

# target to preprocess a source file
test/src/mbgl/test/util.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/util.cpp.i
.PHONY : test/src/mbgl/test/util.cpp.i

test/src/mbgl/test/util.s: test/src/mbgl/test/util.cpp.s

.PHONY : test/src/mbgl/test/util.s

# target to generate assembly for a file
test/src/mbgl/test/util.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/src/mbgl/test/util.cpp.s
.PHONY : test/src/mbgl/test/util.cpp.s

test/storage/asset_file_source.test.o: test/storage/asset_file_source.test.cpp.o

.PHONY : test/storage/asset_file_source.test.o

# target to build an object file
test/storage/asset_file_source.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/asset_file_source.test.cpp.o
.PHONY : test/storage/asset_file_source.test.cpp.o

test/storage/asset_file_source.test.i: test/storage/asset_file_source.test.cpp.i

.PHONY : test/storage/asset_file_source.test.i

# target to preprocess a source file
test/storage/asset_file_source.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/asset_file_source.test.cpp.i
.PHONY : test/storage/asset_file_source.test.cpp.i

test/storage/asset_file_source.test.s: test/storage/asset_file_source.test.cpp.s

.PHONY : test/storage/asset_file_source.test.s

# target to generate assembly for a file
test/storage/asset_file_source.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/asset_file_source.test.cpp.s
.PHONY : test/storage/asset_file_source.test.cpp.s

test/storage/default_file_source.test.o: test/storage/default_file_source.test.cpp.o

.PHONY : test/storage/default_file_source.test.o

# target to build an object file
test/storage/default_file_source.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/default_file_source.test.cpp.o
.PHONY : test/storage/default_file_source.test.cpp.o

test/storage/default_file_source.test.i: test/storage/default_file_source.test.cpp.i

.PHONY : test/storage/default_file_source.test.i

# target to preprocess a source file
test/storage/default_file_source.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/default_file_source.test.cpp.i
.PHONY : test/storage/default_file_source.test.cpp.i

test/storage/default_file_source.test.s: test/storage/default_file_source.test.cpp.s

.PHONY : test/storage/default_file_source.test.s

# target to generate assembly for a file
test/storage/default_file_source.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/default_file_source.test.cpp.s
.PHONY : test/storage/default_file_source.test.cpp.s

test/storage/headers.test.o: test/storage/headers.test.cpp.o

.PHONY : test/storage/headers.test.o

# target to build an object file
test/storage/headers.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/headers.test.cpp.o
.PHONY : test/storage/headers.test.cpp.o

test/storage/headers.test.i: test/storage/headers.test.cpp.i

.PHONY : test/storage/headers.test.i

# target to preprocess a source file
test/storage/headers.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/headers.test.cpp.i
.PHONY : test/storage/headers.test.cpp.i

test/storage/headers.test.s: test/storage/headers.test.cpp.s

.PHONY : test/storage/headers.test.s

# target to generate assembly for a file
test/storage/headers.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/headers.test.cpp.s
.PHONY : test/storage/headers.test.cpp.s

test/storage/http_file_source.test.o: test/storage/http_file_source.test.cpp.o

.PHONY : test/storage/http_file_source.test.o

# target to build an object file
test/storage/http_file_source.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/http_file_source.test.cpp.o
.PHONY : test/storage/http_file_source.test.cpp.o

test/storage/http_file_source.test.i: test/storage/http_file_source.test.cpp.i

.PHONY : test/storage/http_file_source.test.i

# target to preprocess a source file
test/storage/http_file_source.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/http_file_source.test.cpp.i
.PHONY : test/storage/http_file_source.test.cpp.i

test/storage/http_file_source.test.s: test/storage/http_file_source.test.cpp.s

.PHONY : test/storage/http_file_source.test.s

# target to generate assembly for a file
test/storage/http_file_source.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/http_file_source.test.cpp.s
.PHONY : test/storage/http_file_source.test.cpp.s

test/storage/local_file_source.test.o: test/storage/local_file_source.test.cpp.o

.PHONY : test/storage/local_file_source.test.o

# target to build an object file
test/storage/local_file_source.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/local_file_source.test.cpp.o
.PHONY : test/storage/local_file_source.test.cpp.o

test/storage/local_file_source.test.i: test/storage/local_file_source.test.cpp.i

.PHONY : test/storage/local_file_source.test.i

# target to preprocess a source file
test/storage/local_file_source.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/local_file_source.test.cpp.i
.PHONY : test/storage/local_file_source.test.cpp.i

test/storage/local_file_source.test.s: test/storage/local_file_source.test.cpp.s

.PHONY : test/storage/local_file_source.test.s

# target to generate assembly for a file
test/storage/local_file_source.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/local_file_source.test.cpp.s
.PHONY : test/storage/local_file_source.test.cpp.s

test/storage/offline.test.o: test/storage/offline.test.cpp.o

.PHONY : test/storage/offline.test.o

# target to build an object file
test/storage/offline.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline.test.cpp.o
.PHONY : test/storage/offline.test.cpp.o

test/storage/offline.test.i: test/storage/offline.test.cpp.i

.PHONY : test/storage/offline.test.i

# target to preprocess a source file
test/storage/offline.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline.test.cpp.i
.PHONY : test/storage/offline.test.cpp.i

test/storage/offline.test.s: test/storage/offline.test.cpp.s

.PHONY : test/storage/offline.test.s

# target to generate assembly for a file
test/storage/offline.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline.test.cpp.s
.PHONY : test/storage/offline.test.cpp.s

test/storage/offline_database.test.o: test/storage/offline_database.test.cpp.o

.PHONY : test/storage/offline_database.test.o

# target to build an object file
test/storage/offline_database.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline_database.test.cpp.o
.PHONY : test/storage/offline_database.test.cpp.o

test/storage/offline_database.test.i: test/storage/offline_database.test.cpp.i

.PHONY : test/storage/offline_database.test.i

# target to preprocess a source file
test/storage/offline_database.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline_database.test.cpp.i
.PHONY : test/storage/offline_database.test.cpp.i

test/storage/offline_database.test.s: test/storage/offline_database.test.cpp.s

.PHONY : test/storage/offline_database.test.s

# target to generate assembly for a file
test/storage/offline_database.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline_database.test.cpp.s
.PHONY : test/storage/offline_database.test.cpp.s

test/storage/offline_download.test.o: test/storage/offline_download.test.cpp.o

.PHONY : test/storage/offline_download.test.o

# target to build an object file
test/storage/offline_download.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline_download.test.cpp.o
.PHONY : test/storage/offline_download.test.cpp.o

test/storage/offline_download.test.i: test/storage/offline_download.test.cpp.i

.PHONY : test/storage/offline_download.test.i

# target to preprocess a source file
test/storage/offline_download.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline_download.test.cpp.i
.PHONY : test/storage/offline_download.test.cpp.i

test/storage/offline_download.test.s: test/storage/offline_download.test.cpp.s

.PHONY : test/storage/offline_download.test.s

# target to generate assembly for a file
test/storage/offline_download.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/offline_download.test.cpp.s
.PHONY : test/storage/offline_download.test.cpp.s

test/storage/online_file_source.test.o: test/storage/online_file_source.test.cpp.o

.PHONY : test/storage/online_file_source.test.o

# target to build an object file
test/storage/online_file_source.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/online_file_source.test.cpp.o
.PHONY : test/storage/online_file_source.test.cpp.o

test/storage/online_file_source.test.i: test/storage/online_file_source.test.cpp.i

.PHONY : test/storage/online_file_source.test.i

# target to preprocess a source file
test/storage/online_file_source.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/online_file_source.test.cpp.i
.PHONY : test/storage/online_file_source.test.cpp.i

test/storage/online_file_source.test.s: test/storage/online_file_source.test.cpp.s

.PHONY : test/storage/online_file_source.test.s

# target to generate assembly for a file
test/storage/online_file_source.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/online_file_source.test.cpp.s
.PHONY : test/storage/online_file_source.test.cpp.s

test/storage/resource.test.o: test/storage/resource.test.cpp.o

.PHONY : test/storage/resource.test.o

# target to build an object file
test/storage/resource.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/resource.test.cpp.o
.PHONY : test/storage/resource.test.cpp.o

test/storage/resource.test.i: test/storage/resource.test.cpp.i

.PHONY : test/storage/resource.test.i

# target to preprocess a source file
test/storage/resource.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/resource.test.cpp.i
.PHONY : test/storage/resource.test.cpp.i

test/storage/resource.test.s: test/storage/resource.test.cpp.s

.PHONY : test/storage/resource.test.s

# target to generate assembly for a file
test/storage/resource.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/resource.test.cpp.s
.PHONY : test/storage/resource.test.cpp.s

test/storage/sqlite.test.o: test/storage/sqlite.test.cpp.o

.PHONY : test/storage/sqlite.test.o

# target to build an object file
test/storage/sqlite.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/sqlite.test.cpp.o
.PHONY : test/storage/sqlite.test.cpp.o

test/storage/sqlite.test.i: test/storage/sqlite.test.cpp.i

.PHONY : test/storage/sqlite.test.i

# target to preprocess a source file
test/storage/sqlite.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/sqlite.test.cpp.i
.PHONY : test/storage/sqlite.test.cpp.i

test/storage/sqlite.test.s: test/storage/sqlite.test.cpp.s

.PHONY : test/storage/sqlite.test.s

# target to generate assembly for a file
test/storage/sqlite.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/storage/sqlite.test.cpp.s
.PHONY : test/storage/sqlite.test.cpp.s

test/style/conversion/function.test.o: test/style/conversion/function.test.cpp.o

.PHONY : test/style/conversion/function.test.o

# target to build an object file
test/style/conversion/function.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/function.test.cpp.o
.PHONY : test/style/conversion/function.test.cpp.o

test/style/conversion/function.test.i: test/style/conversion/function.test.cpp.i

.PHONY : test/style/conversion/function.test.i

# target to preprocess a source file
test/style/conversion/function.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/function.test.cpp.i
.PHONY : test/style/conversion/function.test.cpp.i

test/style/conversion/function.test.s: test/style/conversion/function.test.cpp.s

.PHONY : test/style/conversion/function.test.s

# target to generate assembly for a file
test/style/conversion/function.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/function.test.cpp.s
.PHONY : test/style/conversion/function.test.cpp.s

test/style/conversion/geojson_options.test.o: test/style/conversion/geojson_options.test.cpp.o

.PHONY : test/style/conversion/geojson_options.test.o

# target to build an object file
test/style/conversion/geojson_options.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/geojson_options.test.cpp.o
.PHONY : test/style/conversion/geojson_options.test.cpp.o

test/style/conversion/geojson_options.test.i: test/style/conversion/geojson_options.test.cpp.i

.PHONY : test/style/conversion/geojson_options.test.i

# target to preprocess a source file
test/style/conversion/geojson_options.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/geojson_options.test.cpp.i
.PHONY : test/style/conversion/geojson_options.test.cpp.i

test/style/conversion/geojson_options.test.s: test/style/conversion/geojson_options.test.cpp.s

.PHONY : test/style/conversion/geojson_options.test.s

# target to generate assembly for a file
test/style/conversion/geojson_options.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/geojson_options.test.cpp.s
.PHONY : test/style/conversion/geojson_options.test.cpp.s

test/style/conversion/layer.test.o: test/style/conversion/layer.test.cpp.o

.PHONY : test/style/conversion/layer.test.o

# target to build an object file
test/style/conversion/layer.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/layer.test.cpp.o
.PHONY : test/style/conversion/layer.test.cpp.o

test/style/conversion/layer.test.i: test/style/conversion/layer.test.cpp.i

.PHONY : test/style/conversion/layer.test.i

# target to preprocess a source file
test/style/conversion/layer.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/layer.test.cpp.i
.PHONY : test/style/conversion/layer.test.cpp.i

test/style/conversion/layer.test.s: test/style/conversion/layer.test.cpp.s

.PHONY : test/style/conversion/layer.test.s

# target to generate assembly for a file
test/style/conversion/layer.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/layer.test.cpp.s
.PHONY : test/style/conversion/layer.test.cpp.s

test/style/conversion/light.test.o: test/style/conversion/light.test.cpp.o

.PHONY : test/style/conversion/light.test.o

# target to build an object file
test/style/conversion/light.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/light.test.cpp.o
.PHONY : test/style/conversion/light.test.cpp.o

test/style/conversion/light.test.i: test/style/conversion/light.test.cpp.i

.PHONY : test/style/conversion/light.test.i

# target to preprocess a source file
test/style/conversion/light.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/light.test.cpp.i
.PHONY : test/style/conversion/light.test.cpp.i

test/style/conversion/light.test.s: test/style/conversion/light.test.cpp.s

.PHONY : test/style/conversion/light.test.s

# target to generate assembly for a file
test/style/conversion/light.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/light.test.cpp.s
.PHONY : test/style/conversion/light.test.cpp.s

test/style/conversion/stringify.test.o: test/style/conversion/stringify.test.cpp.o

.PHONY : test/style/conversion/stringify.test.o

# target to build an object file
test/style/conversion/stringify.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/stringify.test.cpp.o
.PHONY : test/style/conversion/stringify.test.cpp.o

test/style/conversion/stringify.test.i: test/style/conversion/stringify.test.cpp.i

.PHONY : test/style/conversion/stringify.test.i

# target to preprocess a source file
test/style/conversion/stringify.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/stringify.test.cpp.i
.PHONY : test/style/conversion/stringify.test.cpp.i

test/style/conversion/stringify.test.s: test/style/conversion/stringify.test.cpp.s

.PHONY : test/style/conversion/stringify.test.s

# target to generate assembly for a file
test/style/conversion/stringify.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/conversion/stringify.test.cpp.s
.PHONY : test/style/conversion/stringify.test.cpp.s

test/style/filter.test.o: test/style/filter.test.cpp.o

.PHONY : test/style/filter.test.o

# target to build an object file
test/style/filter.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/filter.test.cpp.o
.PHONY : test/style/filter.test.cpp.o

test/style/filter.test.i: test/style/filter.test.cpp.i

.PHONY : test/style/filter.test.i

# target to preprocess a source file
test/style/filter.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/filter.test.cpp.i
.PHONY : test/style/filter.test.cpp.i

test/style/filter.test.s: test/style/filter.test.cpp.s

.PHONY : test/style/filter.test.s

# target to generate assembly for a file
test/style/filter.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/filter.test.cpp.s
.PHONY : test/style/filter.test.cpp.s

test/style/function/camera_function.test.o: test/style/function/camera_function.test.cpp.o

.PHONY : test/style/function/camera_function.test.o

# target to build an object file
test/style/function/camera_function.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/camera_function.test.cpp.o
.PHONY : test/style/function/camera_function.test.cpp.o

test/style/function/camera_function.test.i: test/style/function/camera_function.test.cpp.i

.PHONY : test/style/function/camera_function.test.i

# target to preprocess a source file
test/style/function/camera_function.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/camera_function.test.cpp.i
.PHONY : test/style/function/camera_function.test.cpp.i

test/style/function/camera_function.test.s: test/style/function/camera_function.test.cpp.s

.PHONY : test/style/function/camera_function.test.s

# target to generate assembly for a file
test/style/function/camera_function.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/camera_function.test.cpp.s
.PHONY : test/style/function/camera_function.test.cpp.s

test/style/function/composite_function.test.o: test/style/function/composite_function.test.cpp.o

.PHONY : test/style/function/composite_function.test.o

# target to build an object file
test/style/function/composite_function.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/composite_function.test.cpp.o
.PHONY : test/style/function/composite_function.test.cpp.o

test/style/function/composite_function.test.i: test/style/function/composite_function.test.cpp.i

.PHONY : test/style/function/composite_function.test.i

# target to preprocess a source file
test/style/function/composite_function.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/composite_function.test.cpp.i
.PHONY : test/style/function/composite_function.test.cpp.i

test/style/function/composite_function.test.s: test/style/function/composite_function.test.cpp.s

.PHONY : test/style/function/composite_function.test.s

# target to generate assembly for a file
test/style/function/composite_function.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/composite_function.test.cpp.s
.PHONY : test/style/function/composite_function.test.cpp.s

test/style/function/exponential_stops.test.o: test/style/function/exponential_stops.test.cpp.o

.PHONY : test/style/function/exponential_stops.test.o

# target to build an object file
test/style/function/exponential_stops.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/exponential_stops.test.cpp.o
.PHONY : test/style/function/exponential_stops.test.cpp.o

test/style/function/exponential_stops.test.i: test/style/function/exponential_stops.test.cpp.i

.PHONY : test/style/function/exponential_stops.test.i

# target to preprocess a source file
test/style/function/exponential_stops.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/exponential_stops.test.cpp.i
.PHONY : test/style/function/exponential_stops.test.cpp.i

test/style/function/exponential_stops.test.s: test/style/function/exponential_stops.test.cpp.s

.PHONY : test/style/function/exponential_stops.test.s

# target to generate assembly for a file
test/style/function/exponential_stops.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/exponential_stops.test.cpp.s
.PHONY : test/style/function/exponential_stops.test.cpp.s

test/style/function/interval_stops.test.o: test/style/function/interval_stops.test.cpp.o

.PHONY : test/style/function/interval_stops.test.o

# target to build an object file
test/style/function/interval_stops.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/interval_stops.test.cpp.o
.PHONY : test/style/function/interval_stops.test.cpp.o

test/style/function/interval_stops.test.i: test/style/function/interval_stops.test.cpp.i

.PHONY : test/style/function/interval_stops.test.i

# target to preprocess a source file
test/style/function/interval_stops.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/interval_stops.test.cpp.i
.PHONY : test/style/function/interval_stops.test.cpp.i

test/style/function/interval_stops.test.s: test/style/function/interval_stops.test.cpp.s

.PHONY : test/style/function/interval_stops.test.s

# target to generate assembly for a file
test/style/function/interval_stops.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/interval_stops.test.cpp.s
.PHONY : test/style/function/interval_stops.test.cpp.s

test/style/function/source_function.test.o: test/style/function/source_function.test.cpp.o

.PHONY : test/style/function/source_function.test.o

# target to build an object file
test/style/function/source_function.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/source_function.test.cpp.o
.PHONY : test/style/function/source_function.test.cpp.o

test/style/function/source_function.test.i: test/style/function/source_function.test.cpp.i

.PHONY : test/style/function/source_function.test.i

# target to preprocess a source file
test/style/function/source_function.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/source_function.test.cpp.i
.PHONY : test/style/function/source_function.test.cpp.i

test/style/function/source_function.test.s: test/style/function/source_function.test.cpp.s

.PHONY : test/style/function/source_function.test.s

# target to generate assembly for a file
test/style/function/source_function.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/function/source_function.test.cpp.s
.PHONY : test/style/function/source_function.test.cpp.s

test/style/properties.test.o: test/style/properties.test.cpp.o

.PHONY : test/style/properties.test.o

# target to build an object file
test/style/properties.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/properties.test.cpp.o
.PHONY : test/style/properties.test.cpp.o

test/style/properties.test.i: test/style/properties.test.cpp.i

.PHONY : test/style/properties.test.i

# target to preprocess a source file
test/style/properties.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/properties.test.cpp.i
.PHONY : test/style/properties.test.cpp.i

test/style/properties.test.s: test/style/properties.test.cpp.s

.PHONY : test/style/properties.test.s

# target to generate assembly for a file
test/style/properties.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/properties.test.cpp.s
.PHONY : test/style/properties.test.cpp.s

test/style/source.test.o: test/style/source.test.cpp.o

.PHONY : test/style/source.test.o

# target to build an object file
test/style/source.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/source.test.cpp.o
.PHONY : test/style/source.test.cpp.o

test/style/source.test.i: test/style/source.test.cpp.i

.PHONY : test/style/source.test.i

# target to preprocess a source file
test/style/source.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/source.test.cpp.i
.PHONY : test/style/source.test.cpp.i

test/style/source.test.s: test/style/source.test.cpp.s

.PHONY : test/style/source.test.s

# target to generate assembly for a file
test/style/source.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/source.test.cpp.s
.PHONY : test/style/source.test.cpp.s

test/style/style.test.o: test/style/style.test.cpp.o

.PHONY : test/style/style.test.o

# target to build an object file
test/style/style.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style.test.cpp.o
.PHONY : test/style/style.test.cpp.o

test/style/style.test.i: test/style/style.test.cpp.i

.PHONY : test/style/style.test.i

# target to preprocess a source file
test/style/style.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style.test.cpp.i
.PHONY : test/style/style.test.cpp.i

test/style/style.test.s: test/style/style.test.cpp.s

.PHONY : test/style/style.test.s

# target to generate assembly for a file
test/style/style.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style.test.cpp.s
.PHONY : test/style/style.test.cpp.s

test/style/style_image.test.o: test/style/style_image.test.cpp.o

.PHONY : test/style/style_image.test.o

# target to build an object file
test/style/style_image.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_image.test.cpp.o
.PHONY : test/style/style_image.test.cpp.o

test/style/style_image.test.i: test/style/style_image.test.cpp.i

.PHONY : test/style/style_image.test.i

# target to preprocess a source file
test/style/style_image.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_image.test.cpp.i
.PHONY : test/style/style_image.test.cpp.i

test/style/style_image.test.s: test/style/style_image.test.cpp.s

.PHONY : test/style/style_image.test.s

# target to generate assembly for a file
test/style/style_image.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_image.test.cpp.s
.PHONY : test/style/style_image.test.cpp.s

test/style/style_layer.test.o: test/style/style_layer.test.cpp.o

.PHONY : test/style/style_layer.test.o

# target to build an object file
test/style/style_layer.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_layer.test.cpp.o
.PHONY : test/style/style_layer.test.cpp.o

test/style/style_layer.test.i: test/style/style_layer.test.cpp.i

.PHONY : test/style/style_layer.test.i

# target to preprocess a source file
test/style/style_layer.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_layer.test.cpp.i
.PHONY : test/style/style_layer.test.cpp.i

test/style/style_layer.test.s: test/style/style_layer.test.cpp.s

.PHONY : test/style/style_layer.test.s

# target to generate assembly for a file
test/style/style_layer.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_layer.test.cpp.s
.PHONY : test/style/style_layer.test.cpp.s

test/style/style_parser.test.o: test/style/style_parser.test.cpp.o

.PHONY : test/style/style_parser.test.o

# target to build an object file
test/style/style_parser.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_parser.test.cpp.o
.PHONY : test/style/style_parser.test.cpp.o

test/style/style_parser.test.i: test/style/style_parser.test.cpp.i

.PHONY : test/style/style_parser.test.i

# target to preprocess a source file
test/style/style_parser.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_parser.test.cpp.i
.PHONY : test/style/style_parser.test.cpp.i

test/style/style_parser.test.s: test/style/style_parser.test.cpp.s

.PHONY : test/style/style_parser.test.s

# target to generate assembly for a file
test/style/style_parser.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/style/style_parser.test.cpp.s
.PHONY : test/style/style_parser.test.cpp.s

test/text/glyph_loader.test.o: test/text/glyph_loader.test.cpp.o

.PHONY : test/text/glyph_loader.test.o

# target to build an object file
test/text/glyph_loader.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/glyph_loader.test.cpp.o
.PHONY : test/text/glyph_loader.test.cpp.o

test/text/glyph_loader.test.i: test/text/glyph_loader.test.cpp.i

.PHONY : test/text/glyph_loader.test.i

# target to preprocess a source file
test/text/glyph_loader.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/glyph_loader.test.cpp.i
.PHONY : test/text/glyph_loader.test.cpp.i

test/text/glyph_loader.test.s: test/text/glyph_loader.test.cpp.s

.PHONY : test/text/glyph_loader.test.s

# target to generate assembly for a file
test/text/glyph_loader.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/glyph_loader.test.cpp.s
.PHONY : test/text/glyph_loader.test.cpp.s

test/text/glyph_pbf.test.o: test/text/glyph_pbf.test.cpp.o

.PHONY : test/text/glyph_pbf.test.o

# target to build an object file
test/text/glyph_pbf.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/glyph_pbf.test.cpp.o
.PHONY : test/text/glyph_pbf.test.cpp.o

test/text/glyph_pbf.test.i: test/text/glyph_pbf.test.cpp.i

.PHONY : test/text/glyph_pbf.test.i

# target to preprocess a source file
test/text/glyph_pbf.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/glyph_pbf.test.cpp.i
.PHONY : test/text/glyph_pbf.test.cpp.i

test/text/glyph_pbf.test.s: test/text/glyph_pbf.test.cpp.s

.PHONY : test/text/glyph_pbf.test.s

# target to generate assembly for a file
test/text/glyph_pbf.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/glyph_pbf.test.cpp.s
.PHONY : test/text/glyph_pbf.test.cpp.s

test/text/quads.test.o: test/text/quads.test.cpp.o

.PHONY : test/text/quads.test.o

# target to build an object file
test/text/quads.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/quads.test.cpp.o
.PHONY : test/text/quads.test.cpp.o

test/text/quads.test.i: test/text/quads.test.cpp.i

.PHONY : test/text/quads.test.i

# target to preprocess a source file
test/text/quads.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/quads.test.cpp.i
.PHONY : test/text/quads.test.cpp.i

test/text/quads.test.s: test/text/quads.test.cpp.s

.PHONY : test/text/quads.test.s

# target to generate assembly for a file
test/text/quads.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/text/quads.test.cpp.s
.PHONY : test/text/quads.test.cpp.s

test/tile/annotation_tile.test.o: test/tile/annotation_tile.test.cpp.o

.PHONY : test/tile/annotation_tile.test.o

# target to build an object file
test/tile/annotation_tile.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/annotation_tile.test.cpp.o
.PHONY : test/tile/annotation_tile.test.cpp.o

test/tile/annotation_tile.test.i: test/tile/annotation_tile.test.cpp.i

.PHONY : test/tile/annotation_tile.test.i

# target to preprocess a source file
test/tile/annotation_tile.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/annotation_tile.test.cpp.i
.PHONY : test/tile/annotation_tile.test.cpp.i

test/tile/annotation_tile.test.s: test/tile/annotation_tile.test.cpp.s

.PHONY : test/tile/annotation_tile.test.s

# target to generate assembly for a file
test/tile/annotation_tile.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/annotation_tile.test.cpp.s
.PHONY : test/tile/annotation_tile.test.cpp.s

test/tile/geojson_tile.test.o: test/tile/geojson_tile.test.cpp.o

.PHONY : test/tile/geojson_tile.test.o

# target to build an object file
test/tile/geojson_tile.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/geojson_tile.test.cpp.o
.PHONY : test/tile/geojson_tile.test.cpp.o

test/tile/geojson_tile.test.i: test/tile/geojson_tile.test.cpp.i

.PHONY : test/tile/geojson_tile.test.i

# target to preprocess a source file
test/tile/geojson_tile.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/geojson_tile.test.cpp.i
.PHONY : test/tile/geojson_tile.test.cpp.i

test/tile/geojson_tile.test.s: test/tile/geojson_tile.test.cpp.s

.PHONY : test/tile/geojson_tile.test.s

# target to generate assembly for a file
test/tile/geojson_tile.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/geojson_tile.test.cpp.s
.PHONY : test/tile/geojson_tile.test.cpp.s

test/tile/geometry_tile_data.test.o: test/tile/geometry_tile_data.test.cpp.o

.PHONY : test/tile/geometry_tile_data.test.o

# target to build an object file
test/tile/geometry_tile_data.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/geometry_tile_data.test.cpp.o
.PHONY : test/tile/geometry_tile_data.test.cpp.o

test/tile/geometry_tile_data.test.i: test/tile/geometry_tile_data.test.cpp.i

.PHONY : test/tile/geometry_tile_data.test.i

# target to preprocess a source file
test/tile/geometry_tile_data.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/geometry_tile_data.test.cpp.i
.PHONY : test/tile/geometry_tile_data.test.cpp.i

test/tile/geometry_tile_data.test.s: test/tile/geometry_tile_data.test.cpp.s

.PHONY : test/tile/geometry_tile_data.test.s

# target to generate assembly for a file
test/tile/geometry_tile_data.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/geometry_tile_data.test.cpp.s
.PHONY : test/tile/geometry_tile_data.test.cpp.s

test/tile/raster_tile.test.o: test/tile/raster_tile.test.cpp.o

.PHONY : test/tile/raster_tile.test.o

# target to build an object file
test/tile/raster_tile.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/raster_tile.test.cpp.o
.PHONY : test/tile/raster_tile.test.cpp.o

test/tile/raster_tile.test.i: test/tile/raster_tile.test.cpp.i

.PHONY : test/tile/raster_tile.test.i

# target to preprocess a source file
test/tile/raster_tile.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/raster_tile.test.cpp.i
.PHONY : test/tile/raster_tile.test.cpp.i

test/tile/raster_tile.test.s: test/tile/raster_tile.test.cpp.s

.PHONY : test/tile/raster_tile.test.s

# target to generate assembly for a file
test/tile/raster_tile.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/raster_tile.test.cpp.s
.PHONY : test/tile/raster_tile.test.cpp.s

test/tile/tile_coordinate.test.o: test/tile/tile_coordinate.test.cpp.o

.PHONY : test/tile/tile_coordinate.test.o

# target to build an object file
test/tile/tile_coordinate.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/tile_coordinate.test.cpp.o
.PHONY : test/tile/tile_coordinate.test.cpp.o

test/tile/tile_coordinate.test.i: test/tile/tile_coordinate.test.cpp.i

.PHONY : test/tile/tile_coordinate.test.i

# target to preprocess a source file
test/tile/tile_coordinate.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/tile_coordinate.test.cpp.i
.PHONY : test/tile/tile_coordinate.test.cpp.i

test/tile/tile_coordinate.test.s: test/tile/tile_coordinate.test.cpp.s

.PHONY : test/tile/tile_coordinate.test.s

# target to generate assembly for a file
test/tile/tile_coordinate.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/tile_coordinate.test.cpp.s
.PHONY : test/tile/tile_coordinate.test.cpp.s

test/tile/tile_id.test.o: test/tile/tile_id.test.cpp.o

.PHONY : test/tile/tile_id.test.o

# target to build an object file
test/tile/tile_id.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/tile_id.test.cpp.o
.PHONY : test/tile/tile_id.test.cpp.o

test/tile/tile_id.test.i: test/tile/tile_id.test.cpp.i

.PHONY : test/tile/tile_id.test.i

# target to preprocess a source file
test/tile/tile_id.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/tile_id.test.cpp.i
.PHONY : test/tile/tile_id.test.cpp.i

test/tile/tile_id.test.s: test/tile/tile_id.test.cpp.s

.PHONY : test/tile/tile_id.test.s

# target to generate assembly for a file
test/tile/tile_id.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/tile_id.test.cpp.s
.PHONY : test/tile/tile_id.test.cpp.s

test/tile/vector_tile.test.o: test/tile/vector_tile.test.cpp.o

.PHONY : test/tile/vector_tile.test.o

# target to build an object file
test/tile/vector_tile.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/vector_tile.test.cpp.o
.PHONY : test/tile/vector_tile.test.cpp.o

test/tile/vector_tile.test.i: test/tile/vector_tile.test.cpp.i

.PHONY : test/tile/vector_tile.test.i

# target to preprocess a source file
test/tile/vector_tile.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/vector_tile.test.cpp.i
.PHONY : test/tile/vector_tile.test.cpp.i

test/tile/vector_tile.test.s: test/tile/vector_tile.test.cpp.s

.PHONY : test/tile/vector_tile.test.s

# target to generate assembly for a file
test/tile/vector_tile.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/tile/vector_tile.test.cpp.s
.PHONY : test/tile/vector_tile.test.cpp.s

test/util/async_task.test.o: test/util/async_task.test.cpp.o

.PHONY : test/util/async_task.test.o

# target to build an object file
test/util/async_task.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/async_task.test.cpp.o
.PHONY : test/util/async_task.test.cpp.o

test/util/async_task.test.i: test/util/async_task.test.cpp.i

.PHONY : test/util/async_task.test.i

# target to preprocess a source file
test/util/async_task.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/async_task.test.cpp.i
.PHONY : test/util/async_task.test.cpp.i

test/util/async_task.test.s: test/util/async_task.test.cpp.s

.PHONY : test/util/async_task.test.s

# target to generate assembly for a file
test/util/async_task.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/async_task.test.cpp.s
.PHONY : test/util/async_task.test.cpp.s

test/util/dtoa.test.o: test/util/dtoa.test.cpp.o

.PHONY : test/util/dtoa.test.o

# target to build an object file
test/util/dtoa.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/dtoa.test.cpp.o
.PHONY : test/util/dtoa.test.cpp.o

test/util/dtoa.test.i: test/util/dtoa.test.cpp.i

.PHONY : test/util/dtoa.test.i

# target to preprocess a source file
test/util/dtoa.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/dtoa.test.cpp.i
.PHONY : test/util/dtoa.test.cpp.i

test/util/dtoa.test.s: test/util/dtoa.test.cpp.s

.PHONY : test/util/dtoa.test.s

# target to generate assembly for a file
test/util/dtoa.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/dtoa.test.cpp.s
.PHONY : test/util/dtoa.test.cpp.s

test/util/geo.test.o: test/util/geo.test.cpp.o

.PHONY : test/util/geo.test.o

# target to build an object file
test/util/geo.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/geo.test.cpp.o
.PHONY : test/util/geo.test.cpp.o

test/util/geo.test.i: test/util/geo.test.cpp.i

.PHONY : test/util/geo.test.i

# target to preprocess a source file
test/util/geo.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/geo.test.cpp.i
.PHONY : test/util/geo.test.cpp.i

test/util/geo.test.s: test/util/geo.test.cpp.s

.PHONY : test/util/geo.test.s

# target to generate assembly for a file
test/util/geo.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/geo.test.cpp.s
.PHONY : test/util/geo.test.cpp.s

test/util/http_timeout.test.o: test/util/http_timeout.test.cpp.o

.PHONY : test/util/http_timeout.test.o

# target to build an object file
test/util/http_timeout.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/http_timeout.test.cpp.o
.PHONY : test/util/http_timeout.test.cpp.o

test/util/http_timeout.test.i: test/util/http_timeout.test.cpp.i

.PHONY : test/util/http_timeout.test.i

# target to preprocess a source file
test/util/http_timeout.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/http_timeout.test.cpp.i
.PHONY : test/util/http_timeout.test.cpp.i

test/util/http_timeout.test.s: test/util/http_timeout.test.cpp.s

.PHONY : test/util/http_timeout.test.s

# target to generate assembly for a file
test/util/http_timeout.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/http_timeout.test.cpp.s
.PHONY : test/util/http_timeout.test.cpp.s

test/util/image.test.o: test/util/image.test.cpp.o

.PHONY : test/util/image.test.o

# target to build an object file
test/util/image.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/image.test.cpp.o
.PHONY : test/util/image.test.cpp.o

test/util/image.test.i: test/util/image.test.cpp.i

.PHONY : test/util/image.test.i

# target to preprocess a source file
test/util/image.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/image.test.cpp.i
.PHONY : test/util/image.test.cpp.i

test/util/image.test.s: test/util/image.test.cpp.s

.PHONY : test/util/image.test.s

# target to generate assembly for a file
test/util/image.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/image.test.cpp.s
.PHONY : test/util/image.test.cpp.s

test/util/mapbox.test.o: test/util/mapbox.test.cpp.o

.PHONY : test/util/mapbox.test.o

# target to build an object file
test/util/mapbox.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/mapbox.test.cpp.o
.PHONY : test/util/mapbox.test.cpp.o

test/util/mapbox.test.i: test/util/mapbox.test.cpp.i

.PHONY : test/util/mapbox.test.i

# target to preprocess a source file
test/util/mapbox.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/mapbox.test.cpp.i
.PHONY : test/util/mapbox.test.cpp.i

test/util/mapbox.test.s: test/util/mapbox.test.cpp.s

.PHONY : test/util/mapbox.test.s

# target to generate assembly for a file
test/util/mapbox.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/mapbox.test.cpp.s
.PHONY : test/util/mapbox.test.cpp.s

test/util/memory.test.o: test/util/memory.test.cpp.o

.PHONY : test/util/memory.test.o

# target to build an object file
test/util/memory.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/memory.test.cpp.o
.PHONY : test/util/memory.test.cpp.o

test/util/memory.test.i: test/util/memory.test.cpp.i

.PHONY : test/util/memory.test.i

# target to preprocess a source file
test/util/memory.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/memory.test.cpp.i
.PHONY : test/util/memory.test.cpp.i

test/util/memory.test.s: test/util/memory.test.cpp.s

.PHONY : test/util/memory.test.s

# target to generate assembly for a file
test/util/memory.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/memory.test.cpp.s
.PHONY : test/util/memory.test.cpp.s

test/util/merge_lines.test.o: test/util/merge_lines.test.cpp.o

.PHONY : test/util/merge_lines.test.o

# target to build an object file
test/util/merge_lines.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/merge_lines.test.cpp.o
.PHONY : test/util/merge_lines.test.cpp.o

test/util/merge_lines.test.i: test/util/merge_lines.test.cpp.i

.PHONY : test/util/merge_lines.test.i

# target to preprocess a source file
test/util/merge_lines.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/merge_lines.test.cpp.i
.PHONY : test/util/merge_lines.test.cpp.i

test/util/merge_lines.test.s: test/util/merge_lines.test.cpp.s

.PHONY : test/util/merge_lines.test.s

# target to generate assembly for a file
test/util/merge_lines.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/merge_lines.test.cpp.s
.PHONY : test/util/merge_lines.test.cpp.s

test/util/number_conversions.test.o: test/util/number_conversions.test.cpp.o

.PHONY : test/util/number_conversions.test.o

# target to build an object file
test/util/number_conversions.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/number_conversions.test.cpp.o
.PHONY : test/util/number_conversions.test.cpp.o

test/util/number_conversions.test.i: test/util/number_conversions.test.cpp.i

.PHONY : test/util/number_conversions.test.i

# target to preprocess a source file
test/util/number_conversions.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/number_conversions.test.cpp.i
.PHONY : test/util/number_conversions.test.cpp.i

test/util/number_conversions.test.s: test/util/number_conversions.test.cpp.s

.PHONY : test/util/number_conversions.test.s

# target to generate assembly for a file
test/util/number_conversions.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/number_conversions.test.cpp.s
.PHONY : test/util/number_conversions.test.cpp.s

test/util/offscreen_texture.test.o: test/util/offscreen_texture.test.cpp.o

.PHONY : test/util/offscreen_texture.test.o

# target to build an object file
test/util/offscreen_texture.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/offscreen_texture.test.cpp.o
.PHONY : test/util/offscreen_texture.test.cpp.o

test/util/offscreen_texture.test.i: test/util/offscreen_texture.test.cpp.i

.PHONY : test/util/offscreen_texture.test.i

# target to preprocess a source file
test/util/offscreen_texture.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/offscreen_texture.test.cpp.i
.PHONY : test/util/offscreen_texture.test.cpp.i

test/util/offscreen_texture.test.s: test/util/offscreen_texture.test.cpp.s

.PHONY : test/util/offscreen_texture.test.s

# target to generate assembly for a file
test/util/offscreen_texture.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/offscreen_texture.test.cpp.s
.PHONY : test/util/offscreen_texture.test.cpp.s

test/util/position.test.o: test/util/position.test.cpp.o

.PHONY : test/util/position.test.o

# target to build an object file
test/util/position.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/position.test.cpp.o
.PHONY : test/util/position.test.cpp.o

test/util/position.test.i: test/util/position.test.cpp.i

.PHONY : test/util/position.test.i

# target to preprocess a source file
test/util/position.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/position.test.cpp.i
.PHONY : test/util/position.test.cpp.i

test/util/position.test.s: test/util/position.test.cpp.s

.PHONY : test/util/position.test.s

# target to generate assembly for a file
test/util/position.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/position.test.cpp.s
.PHONY : test/util/position.test.cpp.s

test/util/projection.test.o: test/util/projection.test.cpp.o

.PHONY : test/util/projection.test.o

# target to build an object file
test/util/projection.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/projection.test.cpp.o
.PHONY : test/util/projection.test.cpp.o

test/util/projection.test.i: test/util/projection.test.cpp.i

.PHONY : test/util/projection.test.i

# target to preprocess a source file
test/util/projection.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/projection.test.cpp.i
.PHONY : test/util/projection.test.cpp.i

test/util/projection.test.s: test/util/projection.test.cpp.s

.PHONY : test/util/projection.test.s

# target to generate assembly for a file
test/util/projection.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/projection.test.cpp.s
.PHONY : test/util/projection.test.cpp.s

test/util/run_loop.test.o: test/util/run_loop.test.cpp.o

.PHONY : test/util/run_loop.test.o

# target to build an object file
test/util/run_loop.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/run_loop.test.cpp.o
.PHONY : test/util/run_loop.test.cpp.o

test/util/run_loop.test.i: test/util/run_loop.test.cpp.i

.PHONY : test/util/run_loop.test.i

# target to preprocess a source file
test/util/run_loop.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/run_loop.test.cpp.i
.PHONY : test/util/run_loop.test.cpp.i

test/util/run_loop.test.s: test/util/run_loop.test.cpp.s

.PHONY : test/util/run_loop.test.s

# target to generate assembly for a file
test/util/run_loop.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/run_loop.test.cpp.s
.PHONY : test/util/run_loop.test.cpp.s

test/util/text_conversions.test.o: test/util/text_conversions.test.cpp.o

.PHONY : test/util/text_conversions.test.o

# target to build an object file
test/util/text_conversions.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/text_conversions.test.cpp.o
.PHONY : test/util/text_conversions.test.cpp.o

test/util/text_conversions.test.i: test/util/text_conversions.test.cpp.i

.PHONY : test/util/text_conversions.test.i

# target to preprocess a source file
test/util/text_conversions.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/text_conversions.test.cpp.i
.PHONY : test/util/text_conversions.test.cpp.i

test/util/text_conversions.test.s: test/util/text_conversions.test.cpp.s

.PHONY : test/util/text_conversions.test.s

# target to generate assembly for a file
test/util/text_conversions.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/text_conversions.test.cpp.s
.PHONY : test/util/text_conversions.test.cpp.s

test/util/thread.test.o: test/util/thread.test.cpp.o

.PHONY : test/util/thread.test.o

# target to build an object file
test/util/thread.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/thread.test.cpp.o
.PHONY : test/util/thread.test.cpp.o

test/util/thread.test.i: test/util/thread.test.cpp.i

.PHONY : test/util/thread.test.i

# target to preprocess a source file
test/util/thread.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/thread.test.cpp.i
.PHONY : test/util/thread.test.cpp.i

test/util/thread.test.s: test/util/thread.test.cpp.s

.PHONY : test/util/thread.test.s

# target to generate assembly for a file
test/util/thread.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/thread.test.cpp.s
.PHONY : test/util/thread.test.cpp.s

test/util/thread_local.test.o: test/util/thread_local.test.cpp.o

.PHONY : test/util/thread_local.test.o

# target to build an object file
test/util/thread_local.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/thread_local.test.cpp.o
.PHONY : test/util/thread_local.test.cpp.o

test/util/thread_local.test.i: test/util/thread_local.test.cpp.i

.PHONY : test/util/thread_local.test.i

# target to preprocess a source file
test/util/thread_local.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/thread_local.test.cpp.i
.PHONY : test/util/thread_local.test.cpp.i

test/util/thread_local.test.s: test/util/thread_local.test.cpp.s

.PHONY : test/util/thread_local.test.s

# target to generate assembly for a file
test/util/thread_local.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/thread_local.test.cpp.s
.PHONY : test/util/thread_local.test.cpp.s

test/util/tile_cover.test.o: test/util/tile_cover.test.cpp.o

.PHONY : test/util/tile_cover.test.o

# target to build an object file
test/util/tile_cover.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/tile_cover.test.cpp.o
.PHONY : test/util/tile_cover.test.cpp.o

test/util/tile_cover.test.i: test/util/tile_cover.test.cpp.i

.PHONY : test/util/tile_cover.test.i

# target to preprocess a source file
test/util/tile_cover.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/tile_cover.test.cpp.i
.PHONY : test/util/tile_cover.test.cpp.i

test/util/tile_cover.test.s: test/util/tile_cover.test.cpp.s

.PHONY : test/util/tile_cover.test.s

# target to generate assembly for a file
test/util/tile_cover.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/tile_cover.test.cpp.s
.PHONY : test/util/tile_cover.test.cpp.s

test/util/timer.test.o: test/util/timer.test.cpp.o

.PHONY : test/util/timer.test.o

# target to build an object file
test/util/timer.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/timer.test.cpp.o
.PHONY : test/util/timer.test.cpp.o

test/util/timer.test.i: test/util/timer.test.cpp.i

.PHONY : test/util/timer.test.i

# target to preprocess a source file
test/util/timer.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/timer.test.cpp.i
.PHONY : test/util/timer.test.cpp.i

test/util/timer.test.s: test/util/timer.test.cpp.s

.PHONY : test/util/timer.test.s

# target to generate assembly for a file
test/util/timer.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/timer.test.cpp.s
.PHONY : test/util/timer.test.cpp.s

test/util/token.test.o: test/util/token.test.cpp.o

.PHONY : test/util/token.test.o

# target to build an object file
test/util/token.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/token.test.cpp.o
.PHONY : test/util/token.test.cpp.o

test/util/token.test.i: test/util/token.test.cpp.i

.PHONY : test/util/token.test.i

# target to preprocess a source file
test/util/token.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/token.test.cpp.i
.PHONY : test/util/token.test.cpp.i

test/util/token.test.s: test/util/token.test.cpp.s

.PHONY : test/util/token.test.s

# target to generate assembly for a file
test/util/token.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/token.test.cpp.s
.PHONY : test/util/token.test.cpp.s

test/util/url.test.o: test/util/url.test.cpp.o

.PHONY : test/util/url.test.o

# target to build an object file
test/util/url.test.cpp.o:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/url.test.cpp.o
.PHONY : test/util/url.test.cpp.o

test/util/url.test.i: test/util/url.test.cpp.i

.PHONY : test/util/url.test.i

# target to preprocess a source file
test/util/url.test.cpp.i:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/url.test.cpp.i
.PHONY : test/util/url.test.cpp.i

test/util/url.test.s: test/util/url.test.cpp.s

.PHONY : test/util/url.test.s

# target to generate assembly for a file
test/util/url.test.cpp.s:
	$(MAKE) -f CMakeFiles/mbgl-test.dir/build.make CMakeFiles/mbgl-test.dir/test/util/url.test.cpp.s
.PHONY : test/util/url.test.cpp.s

# Help Target
help:
	@echo "The following are some of the valid targets for this Makefile:"
	@echo "... all (the default if no target is provided)"
	@echo "... clean"
	@echo "... depend"
	@echo "... rebuild_cache"
	@echo "... mbgl-node"
	@echo "... mbgl-offline"
	@echo "... mbgl-glfw"
	@echo "... mbgl-benchmark"
	@echo "... npm-install"
	@echo "... alk-rts"
	@echo "... mbgl-render"
	@echo "... mbgl-core"
	@echo "... mbgl-test"
	@echo "... update-submodules"
	@echo "... edit_cache"
	@echo "... mbgl-loop-uv"
	@echo "... mbgl-filesource"
	@echo "... alk/Frontend.o"
	@echo "... alk/Frontend.i"
	@echo "... alk/Frontend.s"
	@echo "... alk/Map.o"
	@echo "... alk/Map.i"
	@echo "... alk/Map.s"
	@echo "... alk/RasterTileRenderer.o"
	@echo "... alk/RasterTileRenderer.i"
	@echo "... alk/RasterTileRenderer.s"
	@echo "... alk/RenderCache.o"
	@echo "... alk/RenderCache.i"
	@echo "... alk/RenderCache.s"
	@echo "... alk/Tile.o"
	@echo "... alk/Tile.i"
	@echo "... alk/Tile.s"
	@echo "... alk/TileHandler.o"
	@echo "... alk/TileHandler.i"
	@echo "... alk/TileHandler.s"
	@echo "... alk/TileLoader.o"
	@echo "... alk/TileLoader.i"
	@echo "... alk/TileLoader.s"
	@echo "... alk/TilePath.o"
	@echo "... alk/TilePath.i"
	@echo "... alk/TilePath.s"
	@echo "... alk/TileServer.o"
	@echo "... alk/TileServer.i"
	@echo "... alk/TileServer.s"
	@echo "... benchmark/api/query.benchmark.o"
	@echo "... benchmark/api/query.benchmark.i"
	@echo "... benchmark/api/query.benchmark.s"
	@echo "... benchmark/api/render.benchmark.o"
	@echo "... benchmark/api/render.benchmark.i"
	@echo "... benchmark/api/render.benchmark.s"
	@echo "... benchmark/function/camera_function.benchmark.o"
	@echo "... benchmark/function/camera_function.benchmark.i"
	@echo "... benchmark/function/camera_function.benchmark.s"
	@echo "... benchmark/function/composite_function.benchmark.o"
	@echo "... benchmark/function/composite_function.benchmark.i"
	@echo "... benchmark/function/composite_function.benchmark.s"
	@echo "... benchmark/function/source_function.benchmark.o"
	@echo "... benchmark/function/source_function.benchmark.i"
	@echo "... benchmark/function/source_function.benchmark.s"
	@echo "... benchmark/parse/filter.benchmark.o"
	@echo "... benchmark/parse/filter.benchmark.i"
	@echo "... benchmark/parse/filter.benchmark.s"
	@echo "... benchmark/parse/tile_mask.benchmark.o"
	@echo "... benchmark/parse/tile_mask.benchmark.i"
	@echo "... benchmark/parse/tile_mask.benchmark.s"
	@echo "... benchmark/parse/vector_tile.benchmark.o"
	@echo "... benchmark/parse/vector_tile.benchmark.i"
	@echo "... benchmark/parse/vector_tile.benchmark.s"
	@echo "... benchmark/src/main.o"
	@echo "... benchmark/src/main.i"
	@echo "... benchmark/src/main.s"
	@echo "... benchmark/src/mbgl/benchmark/benchmark.o"
	@echo "... benchmark/src/mbgl/benchmark/benchmark.i"
	@echo "... benchmark/src/mbgl/benchmark/benchmark.s"
	@echo "... benchmark/util/dtoa.benchmark.o"
	@echo "... benchmark/util/dtoa.benchmark.i"
	@echo "... benchmark/util/dtoa.benchmark.s"
	@echo "... bin/offline.o"
	@echo "... bin/offline.i"
	@echo "... bin/offline.s"
	@echo "... bin/render.o"
	@echo "... bin/render.i"
	@echo "... bin/render.s"
	@echo "... platform/default/asset_file_source.o"
	@echo "... platform/default/asset_file_source.i"
	@echo "... platform/default/asset_file_source.s"
	@echo "... platform/default/async_task.o"
	@echo "... platform/default/async_task.i"
	@echo "... platform/default/async_task.s"
	@echo "... platform/default/bidi.o"
	@echo "... platform/default/bidi.i"
	@echo "... platform/default/bidi.s"
	@echo "... platform/default/default_file_source.o"
	@echo "... platform/default/default_file_source.i"
	@echo "... platform/default/default_file_source.s"
	@echo "... platform/default/file_source_request.o"
	@echo "... platform/default/file_source_request.i"
	@echo "... platform/default/file_source_request.s"
	@echo "... platform/default/http_file_source.o"
	@echo "... platform/default/http_file_source.i"
	@echo "... platform/default/http_file_source.s"
	@echo "... platform/default/image.o"
	@echo "... platform/default/image.i"
	@echo "... platform/default/image.s"
	@echo "... platform/default/jpeg_reader.o"
	@echo "... platform/default/jpeg_reader.i"
	@echo "... platform/default/jpeg_reader.s"
	@echo "... platform/default/local_file_source.o"
	@echo "... platform/default/local_file_source.i"
	@echo "... platform/default/local_file_source.s"
	@echo "... platform/default/logging_stderr.o"
	@echo "... platform/default/logging_stderr.i"
	@echo "... platform/default/logging_stderr.s"
	@echo "... platform/default/mbgl/gl/headless_backend.o"
	@echo "... platform/default/mbgl/gl/headless_backend.i"
	@echo "... platform/default/mbgl/gl/headless_backend.s"
	@echo "... platform/default/mbgl/gl/headless_frontend.o"
	@echo "... platform/default/mbgl/gl/headless_frontend.i"
	@echo "... platform/default/mbgl/gl/headless_frontend.s"
	@echo "... platform/default/mbgl/storage/offline.o"
	@echo "... platform/default/mbgl/storage/offline.i"
	@echo "... platform/default/mbgl/storage/offline.s"
	@echo "... platform/default/mbgl/storage/offline_database.o"
	@echo "... platform/default/mbgl/storage/offline_database.i"
	@echo "... platform/default/mbgl/storage/offline_database.s"
	@echo "... platform/default/mbgl/storage/offline_download.o"
	@echo "... platform/default/mbgl/storage/offline_download.i"
	@echo "... platform/default/mbgl/storage/offline_download.s"
	@echo "... platform/default/mbgl/test/main.o"
	@echo "... platform/default/mbgl/test/main.i"
	@echo "... platform/default/mbgl/test/main.s"
	@echo "... platform/default/mbgl/util/default_thread_pool.o"
	@echo "... platform/default/mbgl/util/default_thread_pool.i"
	@echo "... platform/default/mbgl/util/default_thread_pool.s"
	@echo "... platform/default/mbgl/util/shared_thread_pool.o"
	@echo "... platform/default/mbgl/util/shared_thread_pool.i"
	@echo "... platform/default/mbgl/util/shared_thread_pool.s"
	@echo "... platform/default/online_file_source.o"
	@echo "... platform/default/online_file_source.i"
	@echo "... platform/default/online_file_source.s"
	@echo "... platform/default/png_reader.o"
	@echo "... platform/default/png_reader.i"
	@echo "... platform/default/png_reader.s"
	@echo "... platform/default/png_writer.o"
	@echo "... platform/default/png_writer.i"
	@echo "... platform/default/png_writer.s"
	@echo "... platform/default/run_loop.o"
	@echo "... platform/default/run_loop.i"
	@echo "... platform/default/run_loop.s"
	@echo "... platform/default/sqlite3.o"
	@echo "... platform/default/sqlite3.i"
	@echo "... platform/default/sqlite3.s"
	@echo "... platform/default/string_stdlib.o"
	@echo "... platform/default/string_stdlib.i"
	@echo "... platform/default/string_stdlib.s"
	@echo "... platform/default/thread.o"
	@echo "... platform/default/thread.i"
	@echo "... platform/default/thread.s"
	@echo "... platform/default/thread_local.o"
	@echo "... platform/default/thread_local.i"
	@echo "... platform/default/thread_local.s"
	@echo "... platform/default/timer.o"
	@echo "... platform/default/timer.i"
	@echo "... platform/default/timer.s"
	@echo "... platform/default/utf.o"
	@echo "... platform/default/utf.i"
	@echo "... platform/default/utf.s"
	@echo "... platform/default/webp_reader.o"
	@echo "... platform/default/webp_reader.i"
	@echo "... platform/default/webp_reader.s"
	@echo "... platform/glfw/glfw_renderer_frontend.o"
	@echo "... platform/glfw/glfw_renderer_frontend.i"
	@echo "... platform/glfw/glfw_renderer_frontend.s"
	@echo "... platform/glfw/glfw_view.o"
	@echo "... platform/glfw/glfw_view.i"
	@echo "... platform/glfw/glfw_view.s"
	@echo "... platform/glfw/main.o"
	@echo "... platform/glfw/main.i"
	@echo "... platform/glfw/main.s"
	@echo "... platform/glfw/settings_json.o"
	@echo "... platform/glfw/settings_json.i"
	@echo "... platform/glfw/settings_json.s"
	@echo "... platform/linux/src/headless_backend_glx.o"
	@echo "... platform/linux/src/headless_backend_glx.i"
	@echo "... platform/linux/src/headless_backend_glx.s"
	@echo "... platform/linux/src/headless_display_glx.o"
	@echo "... platform/linux/src/headless_display_glx.i"
	@echo "... platform/linux/src/headless_display_glx.s"
	@echo "... platform/node/src/node_feature.o"
	@echo "... platform/node/src/node_feature.i"
	@echo "... platform/node/src/node_feature.s"
	@echo "... platform/node/src/node_logging.o"
	@echo "... platform/node/src/node_logging.i"
	@echo "... platform/node/src/node_logging.s"
	@echo "... platform/node/src/node_map.o"
	@echo "... platform/node/src/node_map.i"
	@echo "... platform/node/src/node_map.s"
	@echo "... platform/node/src/node_mapbox_gl_native.o"
	@echo "... platform/node/src/node_mapbox_gl_native.i"
	@echo "... platform/node/src/node_mapbox_gl_native.s"
	@echo "... platform/node/src/node_request.o"
	@echo "... platform/node/src/node_request.i"
	@echo "... platform/node/src/node_request.s"
	@echo "... platform/node/src/node_thread_pool.o"
	@echo "... platform/node/src/node_thread_pool.i"
	@echo "... platform/node/src/node_thread_pool.s"
	@echo "... src/csscolorparser/csscolorparser.o"
	@echo "... src/csscolorparser/csscolorparser.i"
	@echo "... src/csscolorparser/csscolorparser.s"
	@echo "... src/mbgl/actor/mailbox.o"
	@echo "... src/mbgl/actor/mailbox.i"
	@echo "... src/mbgl/actor/mailbox.s"
	@echo "... src/mbgl/actor/scheduler.o"
	@echo "... src/mbgl/actor/scheduler.i"
	@echo "... src/mbgl/actor/scheduler.s"
	@echo "... src/mbgl/algorithm/generate_clip_ids.o"
	@echo "... src/mbgl/algorithm/generate_clip_ids.i"
	@echo "... src/mbgl/algorithm/generate_clip_ids.s"
	@echo "... src/mbgl/annotation/annotation_manager.o"
	@echo "... src/mbgl/annotation/annotation_manager.i"
	@echo "... src/mbgl/annotation/annotation_manager.s"
	@echo "... src/mbgl/annotation/annotation_source.o"
	@echo "... src/mbgl/annotation/annotation_source.i"
	@echo "... src/mbgl/annotation/annotation_source.s"
	@echo "... src/mbgl/annotation/annotation_tile.o"
	@echo "... src/mbgl/annotation/annotation_tile.i"
	@echo "... src/mbgl/annotation/annotation_tile.s"
	@echo "... src/mbgl/annotation/fill_annotation_impl.o"
	@echo "... src/mbgl/annotation/fill_annotation_impl.i"
	@echo "... src/mbgl/annotation/fill_annotation_impl.s"
	@echo "... src/mbgl/annotation/line_annotation_impl.o"
	@echo "... src/mbgl/annotation/line_annotation_impl.i"
	@echo "... src/mbgl/annotation/line_annotation_impl.s"
	@echo "... src/mbgl/annotation/render_annotation_source.o"
	@echo "... src/mbgl/annotation/render_annotation_source.i"
	@echo "... src/mbgl/annotation/render_annotation_source.s"
	@echo "... src/mbgl/annotation/shape_annotation_impl.o"
	@echo "... src/mbgl/annotation/shape_annotation_impl.i"
	@echo "... src/mbgl/annotation/shape_annotation_impl.s"
	@echo "... src/mbgl/annotation/symbol_annotation_impl.o"
	@echo "... src/mbgl/annotation/symbol_annotation_impl.i"
	@echo "... src/mbgl/annotation/symbol_annotation_impl.s"
	@echo "... src/mbgl/geometry/feature_index.o"
	@echo "... src/mbgl/geometry/feature_index.i"
	@echo "... src/mbgl/geometry/feature_index.s"
	@echo "... src/mbgl/geometry/line_atlas.o"
	@echo "... src/mbgl/geometry/line_atlas.i"
	@echo "... src/mbgl/geometry/line_atlas.s"
	@echo "... src/mbgl/gl/attribute.o"
	@echo "... src/mbgl/gl/attribute.i"
	@echo "... src/mbgl/gl/attribute.s"
	@echo "... src/mbgl/gl/color_mode.o"
	@echo "... src/mbgl/gl/color_mode.i"
	@echo "... src/mbgl/gl/color_mode.s"
	@echo "... src/mbgl/gl/context.o"
	@echo "... src/mbgl/gl/context.i"
	@echo "... src/mbgl/gl/context.s"
	@echo "... src/mbgl/gl/debugging.o"
	@echo "... src/mbgl/gl/debugging.i"
	@echo "... src/mbgl/gl/debugging.s"
	@echo "... src/mbgl/gl/debugging_extension.o"
	@echo "... src/mbgl/gl/debugging_extension.i"
	@echo "... src/mbgl/gl/debugging_extension.s"
	@echo "... src/mbgl/gl/depth_mode.o"
	@echo "... src/mbgl/gl/depth_mode.i"
	@echo "... src/mbgl/gl/depth_mode.s"
	@echo "... src/mbgl/gl/gl.o"
	@echo "... src/mbgl/gl/gl.i"
	@echo "... src/mbgl/gl/gl.s"
	@echo "... src/mbgl/gl/object.o"
	@echo "... src/mbgl/gl/object.i"
	@echo "... src/mbgl/gl/object.s"
	@echo "... src/mbgl/gl/stencil_mode.o"
	@echo "... src/mbgl/gl/stencil_mode.i"
	@echo "... src/mbgl/gl/stencil_mode.s"
	@echo "... src/mbgl/gl/uniform.o"
	@echo "... src/mbgl/gl/uniform.i"
	@echo "... src/mbgl/gl/uniform.s"
	@echo "... src/mbgl/gl/value.o"
	@echo "... src/mbgl/gl/value.i"
	@echo "... src/mbgl/gl/value.s"
	@echo "... src/mbgl/gl/vertex_array.o"
	@echo "... src/mbgl/gl/vertex_array.i"
	@echo "... src/mbgl/gl/vertex_array.s"
	@echo "... src/mbgl/layout/clip_lines.o"
	@echo "... src/mbgl/layout/clip_lines.i"
	@echo "... src/mbgl/layout/clip_lines.s"
	@echo "... src/mbgl/layout/merge_lines.o"
	@echo "... src/mbgl/layout/merge_lines.i"
	@echo "... src/mbgl/layout/merge_lines.s"
	@echo "... src/mbgl/layout/symbol_instance.o"
	@echo "... src/mbgl/layout/symbol_instance.i"
	@echo "... src/mbgl/layout/symbol_instance.s"
	@echo "... src/mbgl/layout/symbol_layout.o"
	@echo "... src/mbgl/layout/symbol_layout.i"
	@echo "... src/mbgl/layout/symbol_layout.s"
	@echo "... src/mbgl/layout/symbol_projection.o"
	@echo "... src/mbgl/layout/symbol_projection.i"
	@echo "... src/mbgl/layout/symbol_projection.s"
	@echo "... src/mbgl/map/map.o"
	@echo "... src/mbgl/map/map.i"
	@echo "... src/mbgl/map/map.s"
	@echo "... src/mbgl/map/transform.o"
	@echo "... src/mbgl/map/transform.i"
	@echo "... src/mbgl/map/transform.s"
	@echo "... src/mbgl/map/transform_state.o"
	@echo "... src/mbgl/map/transform_state.i"
	@echo "... src/mbgl/map/transform_state.s"
	@echo "... src/mbgl/math/log2.o"
	@echo "... src/mbgl/math/log2.i"
	@echo "... src/mbgl/math/log2.s"
	@echo "... src/mbgl/programs/binary_program.o"
	@echo "... src/mbgl/programs/binary_program.i"
	@echo "... src/mbgl/programs/binary_program.s"
	@echo "... src/mbgl/programs/circle_program.o"
	@echo "... src/mbgl/programs/circle_program.i"
	@echo "... src/mbgl/programs/circle_program.s"
	@echo "... src/mbgl/programs/collision_box_program.o"
	@echo "... src/mbgl/programs/collision_box_program.i"
	@echo "... src/mbgl/programs/collision_box_program.s"
	@echo "... src/mbgl/programs/extrusion_texture_program.o"
	@echo "... src/mbgl/programs/extrusion_texture_program.i"
	@echo "... src/mbgl/programs/extrusion_texture_program.s"
	@echo "... src/mbgl/programs/fill_extrusion_program.o"
	@echo "... src/mbgl/programs/fill_extrusion_program.i"
	@echo "... src/mbgl/programs/fill_extrusion_program.s"
	@echo "... src/mbgl/programs/fill_program.o"
	@echo "... src/mbgl/programs/fill_program.i"
	@echo "... src/mbgl/programs/fill_program.s"
	@echo "... src/mbgl/programs/line_program.o"
	@echo "... src/mbgl/programs/line_program.i"
	@echo "... src/mbgl/programs/line_program.s"
	@echo "... src/mbgl/programs/program_parameters.o"
	@echo "... src/mbgl/programs/program_parameters.i"
	@echo "... src/mbgl/programs/program_parameters.s"
	@echo "... src/mbgl/programs/raster_program.o"
	@echo "... src/mbgl/programs/raster_program.i"
	@echo "... src/mbgl/programs/raster_program.s"
	@echo "... src/mbgl/programs/symbol_program.o"
	@echo "... src/mbgl/programs/symbol_program.i"
	@echo "... src/mbgl/programs/symbol_program.s"
	@echo "... src/mbgl/renderer/backend_scope.o"
	@echo "... src/mbgl/renderer/backend_scope.i"
	@echo "... src/mbgl/renderer/backend_scope.s"
	@echo "... src/mbgl/renderer/bucket_parameters.o"
	@echo "... src/mbgl/renderer/bucket_parameters.i"
	@echo "... src/mbgl/renderer/bucket_parameters.s"
	@echo "... src/mbgl/renderer/buckets/circle_bucket.o"
	@echo "... src/mbgl/renderer/buckets/circle_bucket.i"
	@echo "... src/mbgl/renderer/buckets/circle_bucket.s"
	@echo "... src/mbgl/renderer/buckets/debug_bucket.o"
	@echo "... src/mbgl/renderer/buckets/debug_bucket.i"
	@echo "... src/mbgl/renderer/buckets/debug_bucket.s"
	@echo "... src/mbgl/renderer/buckets/fill_bucket.o"
	@echo "... src/mbgl/renderer/buckets/fill_bucket.i"
	@echo "... src/mbgl/renderer/buckets/fill_bucket.s"
	@echo "... src/mbgl/renderer/buckets/fill_extrusion_bucket.o"
	@echo "... src/mbgl/renderer/buckets/fill_extrusion_bucket.i"
	@echo "... src/mbgl/renderer/buckets/fill_extrusion_bucket.s"
	@echo "... src/mbgl/renderer/buckets/line_bucket.o"
	@echo "... src/mbgl/renderer/buckets/line_bucket.i"
	@echo "... src/mbgl/renderer/buckets/line_bucket.s"
	@echo "... src/mbgl/renderer/buckets/raster_bucket.o"
	@echo "... src/mbgl/renderer/buckets/raster_bucket.i"
	@echo "... src/mbgl/renderer/buckets/raster_bucket.s"
	@echo "... src/mbgl/renderer/buckets/symbol_bucket.o"
	@echo "... src/mbgl/renderer/buckets/symbol_bucket.i"
	@echo "... src/mbgl/renderer/buckets/symbol_bucket.s"
	@echo "... src/mbgl/renderer/cross_faded_property_evaluator.o"
	@echo "... src/mbgl/renderer/cross_faded_property_evaluator.i"
	@echo "... src/mbgl/renderer/cross_faded_property_evaluator.s"
	@echo "... src/mbgl/renderer/frame_history.o"
	@echo "... src/mbgl/renderer/frame_history.i"
	@echo "... src/mbgl/renderer/frame_history.s"
	@echo "... src/mbgl/renderer/group_by_layout.o"
	@echo "... src/mbgl/renderer/group_by_layout.i"
	@echo "... src/mbgl/renderer/group_by_layout.s"
	@echo "... src/mbgl/renderer/image_atlas.o"
	@echo "... src/mbgl/renderer/image_atlas.i"
	@echo "... src/mbgl/renderer/image_atlas.s"
	@echo "... src/mbgl/renderer/image_manager.o"
	@echo "... src/mbgl/renderer/image_manager.i"
	@echo "... src/mbgl/renderer/image_manager.s"
	@echo "... src/mbgl/renderer/layers/render_background_layer.o"
	@echo "... src/mbgl/renderer/layers/render_background_layer.i"
	@echo "... src/mbgl/renderer/layers/render_background_layer.s"
	@echo "... src/mbgl/renderer/layers/render_circle_layer.o"
	@echo "... src/mbgl/renderer/layers/render_circle_layer.i"
	@echo "... src/mbgl/renderer/layers/render_circle_layer.s"
	@echo "... src/mbgl/renderer/layers/render_custom_layer.o"
	@echo "... src/mbgl/renderer/layers/render_custom_layer.i"
	@echo "... src/mbgl/renderer/layers/render_custom_layer.s"
	@echo "... src/mbgl/renderer/layers/render_fill_extrusion_layer.o"
	@echo "... src/mbgl/renderer/layers/render_fill_extrusion_layer.i"
	@echo "... src/mbgl/renderer/layers/render_fill_extrusion_layer.s"
	@echo "... src/mbgl/renderer/layers/render_fill_layer.o"
	@echo "... src/mbgl/renderer/layers/render_fill_layer.i"
	@echo "... src/mbgl/renderer/layers/render_fill_layer.s"
	@echo "... src/mbgl/renderer/layers/render_line_layer.o"
	@echo "... src/mbgl/renderer/layers/render_line_layer.i"
	@echo "... src/mbgl/renderer/layers/render_line_layer.s"
	@echo "... src/mbgl/renderer/layers/render_raster_layer.o"
	@echo "... src/mbgl/renderer/layers/render_raster_layer.i"
	@echo "... src/mbgl/renderer/layers/render_raster_layer.s"
	@echo "... src/mbgl/renderer/layers/render_symbol_layer.o"
	@echo "... src/mbgl/renderer/layers/render_symbol_layer.i"
	@echo "... src/mbgl/renderer/layers/render_symbol_layer.s"
	@echo "... src/mbgl/renderer/paint_parameters.o"
	@echo "... src/mbgl/renderer/paint_parameters.i"
	@echo "... src/mbgl/renderer/paint_parameters.s"
	@echo "... src/mbgl/renderer/render_layer.o"
	@echo "... src/mbgl/renderer/render_layer.i"
	@echo "... src/mbgl/renderer/render_layer.s"
	@echo "... src/mbgl/renderer/render_light.o"
	@echo "... src/mbgl/renderer/render_light.i"
	@echo "... src/mbgl/renderer/render_light.s"
	@echo "... src/mbgl/renderer/render_source.o"
	@echo "... src/mbgl/renderer/render_source.i"
	@echo "... src/mbgl/renderer/render_source.s"
	@echo "... src/mbgl/renderer/render_static_data.o"
	@echo "... src/mbgl/renderer/render_static_data.i"
	@echo "... src/mbgl/renderer/render_static_data.s"
	@echo "... src/mbgl/renderer/render_tile.o"
	@echo "... src/mbgl/renderer/render_tile.i"
	@echo "... src/mbgl/renderer/render_tile.s"
	@echo "... src/mbgl/renderer/renderer.o"
	@echo "... src/mbgl/renderer/renderer.i"
	@echo "... src/mbgl/renderer/renderer.s"
	@echo "... src/mbgl/renderer/renderer_backend.o"
	@echo "... src/mbgl/renderer/renderer_backend.i"
	@echo "... src/mbgl/renderer/renderer_backend.s"
	@echo "... src/mbgl/renderer/renderer_impl.o"
	@echo "... src/mbgl/renderer/renderer_impl.i"
	@echo "... src/mbgl/renderer/renderer_impl.s"
	@echo "... src/mbgl/renderer/sources/render_geojson_source.o"
	@echo "... src/mbgl/renderer/sources/render_geojson_source.i"
	@echo "... src/mbgl/renderer/sources/render_geojson_source.s"
	@echo "... src/mbgl/renderer/sources/render_image_source.o"
	@echo "... src/mbgl/renderer/sources/render_image_source.i"
	@echo "... src/mbgl/renderer/sources/render_image_source.s"
	@echo "... src/mbgl/renderer/sources/render_raster_source.o"
	@echo "... src/mbgl/renderer/sources/render_raster_source.i"
	@echo "... src/mbgl/renderer/sources/render_raster_source.s"
	@echo "... src/mbgl/renderer/sources/render_vector_source.o"
	@echo "... src/mbgl/renderer/sources/render_vector_source.i"
	@echo "... src/mbgl/renderer/sources/render_vector_source.s"
	@echo "... src/mbgl/renderer/style_diff.o"
	@echo "... src/mbgl/renderer/style_diff.i"
	@echo "... src/mbgl/renderer/style_diff.s"
	@echo "... src/mbgl/renderer/tile_pyramid.o"
	@echo "... src/mbgl/renderer/tile_pyramid.i"
	@echo "... src/mbgl/renderer/tile_pyramid.s"
	@echo "... src/mbgl/shaders/circle.o"
	@echo "... src/mbgl/shaders/circle.i"
	@echo "... src/mbgl/shaders/circle.s"
	@echo "... src/mbgl/shaders/collision_box.o"
	@echo "... src/mbgl/shaders/collision_box.i"
	@echo "... src/mbgl/shaders/collision_box.s"
	@echo "... src/mbgl/shaders/debug.o"
	@echo "... src/mbgl/shaders/debug.i"
	@echo "... src/mbgl/shaders/debug.s"
	@echo "... src/mbgl/shaders/extrusion_texture.o"
	@echo "... src/mbgl/shaders/extrusion_texture.i"
	@echo "... src/mbgl/shaders/extrusion_texture.s"
	@echo "... src/mbgl/shaders/fill.o"
	@echo "... src/mbgl/shaders/fill.i"
	@echo "... src/mbgl/shaders/fill.s"
	@echo "... src/mbgl/shaders/fill_extrusion.o"
	@echo "... src/mbgl/shaders/fill_extrusion.i"
	@echo "... src/mbgl/shaders/fill_extrusion.s"
	@echo "... src/mbgl/shaders/fill_extrusion_pattern.o"
	@echo "... src/mbgl/shaders/fill_extrusion_pattern.i"
	@echo "... src/mbgl/shaders/fill_extrusion_pattern.s"
	@echo "... src/mbgl/shaders/fill_outline.o"
	@echo "... src/mbgl/shaders/fill_outline.i"
	@echo "... src/mbgl/shaders/fill_outline.s"
	@echo "... src/mbgl/shaders/fill_outline_pattern.o"
	@echo "... src/mbgl/shaders/fill_outline_pattern.i"
	@echo "... src/mbgl/shaders/fill_outline_pattern.s"
	@echo "... src/mbgl/shaders/fill_pattern.o"
	@echo "... src/mbgl/shaders/fill_pattern.i"
	@echo "... src/mbgl/shaders/fill_pattern.s"
	@echo "... src/mbgl/shaders/line.o"
	@echo "... src/mbgl/shaders/line.i"
	@echo "... src/mbgl/shaders/line.s"
	@echo "... src/mbgl/shaders/line_pattern.o"
	@echo "... src/mbgl/shaders/line_pattern.i"
	@echo "... src/mbgl/shaders/line_pattern.s"
	@echo "... src/mbgl/shaders/line_sdf.o"
	@echo "... src/mbgl/shaders/line_sdf.i"
	@echo "... src/mbgl/shaders/line_sdf.s"
	@echo "... src/mbgl/shaders/preludes.o"
	@echo "... src/mbgl/shaders/preludes.i"
	@echo "... src/mbgl/shaders/preludes.s"
	@echo "... src/mbgl/shaders/raster.o"
	@echo "... src/mbgl/shaders/raster.i"
	@echo "... src/mbgl/shaders/raster.s"
	@echo "... src/mbgl/shaders/shaders.o"
	@echo "... src/mbgl/shaders/shaders.i"
	@echo "... src/mbgl/shaders/shaders.s"
	@echo "... src/mbgl/shaders/symbol_icon.o"
	@echo "... src/mbgl/shaders/symbol_icon.i"
	@echo "... src/mbgl/shaders/symbol_icon.s"
	@echo "... src/mbgl/shaders/symbol_sdf.o"
	@echo "... src/mbgl/shaders/symbol_sdf.i"
	@echo "... src/mbgl/shaders/symbol_sdf.s"
	@echo "... src/mbgl/sprite/sprite_loader.o"
	@echo "... src/mbgl/sprite/sprite_loader.i"
	@echo "... src/mbgl/sprite/sprite_loader.s"
	@echo "... src/mbgl/sprite/sprite_loader_worker.o"
	@echo "... src/mbgl/sprite/sprite_loader_worker.i"
	@echo "... src/mbgl/sprite/sprite_loader_worker.s"
	@echo "... src/mbgl/sprite/sprite_parser.o"
	@echo "... src/mbgl/sprite/sprite_parser.i"
	@echo "... src/mbgl/sprite/sprite_parser.s"
	@echo "... src/mbgl/storage/network_status.o"
	@echo "... src/mbgl/storage/network_status.i"
	@echo "... src/mbgl/storage/network_status.s"
	@echo "... src/mbgl/storage/resource.o"
	@echo "... src/mbgl/storage/resource.i"
	@echo "... src/mbgl/storage/resource.s"
	@echo "... src/mbgl/storage/resource_transform.o"
	@echo "... src/mbgl/storage/resource_transform.i"
	@echo "... src/mbgl/storage/resource_transform.s"
	@echo "... src/mbgl/storage/response.o"
	@echo "... src/mbgl/storage/response.i"
	@echo "... src/mbgl/storage/response.s"
	@echo "... src/mbgl/style/conversion/constant.o"
	@echo "... src/mbgl/style/conversion/constant.i"
	@echo "... src/mbgl/style/conversion/constant.s"
	@echo "... src/mbgl/style/conversion/coordinate.o"
	@echo "... src/mbgl/style/conversion/coordinate.i"
	@echo "... src/mbgl/style/conversion/coordinate.s"
	@echo "... src/mbgl/style/conversion/filter.o"
	@echo "... src/mbgl/style/conversion/filter.i"
	@echo "... src/mbgl/style/conversion/filter.s"
	@echo "... src/mbgl/style/conversion/geojson.o"
	@echo "... src/mbgl/style/conversion/geojson.i"
	@echo "... src/mbgl/style/conversion/geojson.s"
	@echo "... src/mbgl/style/conversion/geojson_options.o"
	@echo "... src/mbgl/style/conversion/geojson_options.i"
	@echo "... src/mbgl/style/conversion/geojson_options.s"
	@echo "... src/mbgl/style/conversion/layer.o"
	@echo "... src/mbgl/style/conversion/layer.i"
	@echo "... src/mbgl/style/conversion/layer.s"
	@echo "... src/mbgl/style/conversion/light.o"
	@echo "... src/mbgl/style/conversion/light.i"
	@echo "... src/mbgl/style/conversion/light.s"
	@echo "... src/mbgl/style/conversion/position.o"
	@echo "... src/mbgl/style/conversion/position.i"
	@echo "... src/mbgl/style/conversion/position.s"
	@echo "... src/mbgl/style/conversion/source.o"
	@echo "... src/mbgl/style/conversion/source.i"
	@echo "... src/mbgl/style/conversion/source.s"
	@echo "... src/mbgl/style/conversion/tileset.o"
	@echo "... src/mbgl/style/conversion/tileset.i"
	@echo "... src/mbgl/style/conversion/tileset.s"
	@echo "... src/mbgl/style/conversion/transition_options.o"
	@echo "... src/mbgl/style/conversion/transition_options.i"
	@echo "... src/mbgl/style/conversion/transition_options.s"
	@echo "... src/mbgl/style/function/categorical_stops.o"
	@echo "... src/mbgl/style/function/categorical_stops.i"
	@echo "... src/mbgl/style/function/categorical_stops.s"
	@echo "... src/mbgl/style/function/identity_stops.o"
	@echo "... src/mbgl/style/function/identity_stops.i"
	@echo "... src/mbgl/style/function/identity_stops.s"
	@echo "... src/mbgl/style/image.o"
	@echo "... src/mbgl/style/image.i"
	@echo "... src/mbgl/style/image.s"
	@echo "... src/mbgl/style/image_impl.o"
	@echo "... src/mbgl/style/image_impl.i"
	@echo "... src/mbgl/style/image_impl.s"
	@echo "... src/mbgl/style/layer.o"
	@echo "... src/mbgl/style/layer.i"
	@echo "... src/mbgl/style/layer.s"
	@echo "... src/mbgl/style/layer_impl.o"
	@echo "... src/mbgl/style/layer_impl.i"
	@echo "... src/mbgl/style/layer_impl.s"
	@echo "... src/mbgl/style/layers/background_layer.o"
	@echo "... src/mbgl/style/layers/background_layer.i"
	@echo "... src/mbgl/style/layers/background_layer.s"
	@echo "... src/mbgl/style/layers/background_layer_impl.o"
	@echo "... src/mbgl/style/layers/background_layer_impl.i"
	@echo "... src/mbgl/style/layers/background_layer_impl.s"
	@echo "... src/mbgl/style/layers/background_layer_properties.o"
	@echo "... src/mbgl/style/layers/background_layer_properties.i"
	@echo "... src/mbgl/style/layers/background_layer_properties.s"
	@echo "... src/mbgl/style/layers/circle_layer.o"
	@echo "... src/mbgl/style/layers/circle_layer.i"
	@echo "... src/mbgl/style/layers/circle_layer.s"
	@echo "... src/mbgl/style/layers/circle_layer_impl.o"
	@echo "... src/mbgl/style/layers/circle_layer_impl.i"
	@echo "... src/mbgl/style/layers/circle_layer_impl.s"
	@echo "... src/mbgl/style/layers/circle_layer_properties.o"
	@echo "... src/mbgl/style/layers/circle_layer_properties.i"
	@echo "... src/mbgl/style/layers/circle_layer_properties.s"
	@echo "... src/mbgl/style/layers/custom_layer.o"
	@echo "... src/mbgl/style/layers/custom_layer.i"
	@echo "... src/mbgl/style/layers/custom_layer.s"
	@echo "... src/mbgl/style/layers/custom_layer_impl.o"
	@echo "... src/mbgl/style/layers/custom_layer_impl.i"
	@echo "... src/mbgl/style/layers/custom_layer_impl.s"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer.o"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer.i"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer.s"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer_impl.o"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer_impl.i"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer_impl.s"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer_properties.o"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer_properties.i"
	@echo "... src/mbgl/style/layers/fill_extrusion_layer_properties.s"
	@echo "... src/mbgl/style/layers/fill_layer.o"
	@echo "... src/mbgl/style/layers/fill_layer.i"
	@echo "... src/mbgl/style/layers/fill_layer.s"
	@echo "... src/mbgl/style/layers/fill_layer_impl.o"
	@echo "... src/mbgl/style/layers/fill_layer_impl.i"
	@echo "... src/mbgl/style/layers/fill_layer_impl.s"
	@echo "... src/mbgl/style/layers/fill_layer_properties.o"
	@echo "... src/mbgl/style/layers/fill_layer_properties.i"
	@echo "... src/mbgl/style/layers/fill_layer_properties.s"
	@echo "... src/mbgl/style/layers/line_layer.o"
	@echo "... src/mbgl/style/layers/line_layer.i"
	@echo "... src/mbgl/style/layers/line_layer.s"
	@echo "... src/mbgl/style/layers/line_layer_impl.o"
	@echo "... src/mbgl/style/layers/line_layer_impl.i"
	@echo "... src/mbgl/style/layers/line_layer_impl.s"
	@echo "... src/mbgl/style/layers/line_layer_properties.o"
	@echo "... src/mbgl/style/layers/line_layer_properties.i"
	@echo "... src/mbgl/style/layers/line_layer_properties.s"
	@echo "... src/mbgl/style/layers/raster_layer.o"
	@echo "... src/mbgl/style/layers/raster_layer.i"
	@echo "... src/mbgl/style/layers/raster_layer.s"
	@echo "... src/mbgl/style/layers/raster_layer_impl.o"
	@echo "... src/mbgl/style/layers/raster_layer_impl.i"
	@echo "... src/mbgl/style/layers/raster_layer_impl.s"
	@echo "... src/mbgl/style/layers/raster_layer_properties.o"
	@echo "... src/mbgl/style/layers/raster_layer_properties.i"
	@echo "... src/mbgl/style/layers/raster_layer_properties.s"
	@echo "... src/mbgl/style/layers/symbol_layer.o"
	@echo "... src/mbgl/style/layers/symbol_layer.i"
	@echo "... src/mbgl/style/layers/symbol_layer.s"
	@echo "... src/mbgl/style/layers/symbol_layer_impl.o"
	@echo "... src/mbgl/style/layers/symbol_layer_impl.i"
	@echo "... src/mbgl/style/layers/symbol_layer_impl.s"
	@echo "... src/mbgl/style/layers/symbol_layer_properties.o"
	@echo "... src/mbgl/style/layers/symbol_layer_properties.i"
	@echo "... src/mbgl/style/layers/symbol_layer_properties.s"
	@echo "... src/mbgl/style/light.o"
	@echo "... src/mbgl/style/light.i"
	@echo "... src/mbgl/style/light.s"
	@echo "... src/mbgl/style/light_impl.o"
	@echo "... src/mbgl/style/light_impl.i"
	@echo "... src/mbgl/style/light_impl.s"
	@echo "... src/mbgl/style/parser.o"
	@echo "... src/mbgl/style/parser.i"
	@echo "... src/mbgl/style/parser.s"
	@echo "... src/mbgl/style/source.o"
	@echo "... src/mbgl/style/source.i"
	@echo "... src/mbgl/style/source.s"
	@echo "... src/mbgl/style/source_impl.o"
	@echo "... src/mbgl/style/source_impl.i"
	@echo "... src/mbgl/style/source_impl.s"
	@echo "... src/mbgl/style/sources/geojson_source.o"
	@echo "... src/mbgl/style/sources/geojson_source.i"
	@echo "... src/mbgl/style/sources/geojson_source.s"
	@echo "... src/mbgl/style/sources/geojson_source_impl.o"
	@echo "... src/mbgl/style/sources/geojson_source_impl.i"
	@echo "... src/mbgl/style/sources/geojson_source_impl.s"
	@echo "... src/mbgl/style/sources/image_source.o"
	@echo "... src/mbgl/style/sources/image_source.i"
	@echo "... src/mbgl/style/sources/image_source.s"
	@echo "... src/mbgl/style/sources/image_source_impl.o"
	@echo "... src/mbgl/style/sources/image_source_impl.i"
	@echo "... src/mbgl/style/sources/image_source_impl.s"
	@echo "... src/mbgl/style/sources/raster_source.o"
	@echo "... src/mbgl/style/sources/raster_source.i"
	@echo "... src/mbgl/style/sources/raster_source.s"
	@echo "... src/mbgl/style/sources/raster_source_impl.o"
	@echo "... src/mbgl/style/sources/raster_source_impl.i"
	@echo "... src/mbgl/style/sources/raster_source_impl.s"
	@echo "... src/mbgl/style/sources/vector_source.o"
	@echo "... src/mbgl/style/sources/vector_source.i"
	@echo "... src/mbgl/style/sources/vector_source.s"
	@echo "... src/mbgl/style/sources/vector_source_impl.o"
	@echo "... src/mbgl/style/sources/vector_source_impl.i"
	@echo "... src/mbgl/style/sources/vector_source_impl.s"
	@echo "... src/mbgl/style/style.o"
	@echo "... src/mbgl/style/style.i"
	@echo "... src/mbgl/style/style.s"
	@echo "... src/mbgl/style/style_impl.o"
	@echo "... src/mbgl/style/style_impl.i"
	@echo "... src/mbgl/style/style_impl.s"
	@echo "... src/mbgl/style/types.o"
	@echo "... src/mbgl/style/types.i"
	@echo "... src/mbgl/style/types.s"
	@echo "... src/mbgl/text/check_max_angle.o"
	@echo "... src/mbgl/text/check_max_angle.i"
	@echo "... src/mbgl/text/check_max_angle.s"
	@echo "... src/mbgl/text/collision_feature.o"
	@echo "... src/mbgl/text/collision_feature.i"
	@echo "... src/mbgl/text/collision_feature.s"
	@echo "... src/mbgl/text/collision_tile.o"
	@echo "... src/mbgl/text/collision_tile.i"
	@echo "... src/mbgl/text/collision_tile.s"
	@echo "... src/mbgl/text/get_anchors.o"
	@echo "... src/mbgl/text/get_anchors.i"
	@echo "... src/mbgl/text/get_anchors.s"
	@echo "... src/mbgl/text/glyph.o"
	@echo "... src/mbgl/text/glyph.i"
	@echo "... src/mbgl/text/glyph.s"
	@echo "... src/mbgl/text/glyph_atlas.o"
	@echo "... src/mbgl/text/glyph_atlas.i"
	@echo "... src/mbgl/text/glyph_atlas.s"
	@echo "... src/mbgl/text/glyph_manager.o"
	@echo "... src/mbgl/text/glyph_manager.i"
	@echo "... src/mbgl/text/glyph_manager.s"
	@echo "... src/mbgl/text/glyph_pbf.o"
	@echo "... src/mbgl/text/glyph_pbf.i"
	@echo "... src/mbgl/text/glyph_pbf.s"
	@echo "... src/mbgl/text/quads.o"
	@echo "... src/mbgl/text/quads.i"
	@echo "... src/mbgl/text/quads.s"
	@echo "... src/mbgl/text/shaping.o"
	@echo "... src/mbgl/text/shaping.i"
	@echo "... src/mbgl/text/shaping.s"
	@echo "... src/mbgl/tile/geojson_tile.o"
	@echo "... src/mbgl/tile/geojson_tile.i"
	@echo "... src/mbgl/tile/geojson_tile.s"
	@echo "... src/mbgl/tile/geometry_tile.o"
	@echo "... src/mbgl/tile/geometry_tile.i"
	@echo "... src/mbgl/tile/geometry_tile.s"
	@echo "... src/mbgl/tile/geometry_tile_data.o"
	@echo "... src/mbgl/tile/geometry_tile_data.i"
	@echo "... src/mbgl/tile/geometry_tile_data.s"
	@echo "... src/mbgl/tile/geometry_tile_worker.o"
	@echo "... src/mbgl/tile/geometry_tile_worker.i"
	@echo "... src/mbgl/tile/geometry_tile_worker.s"
	@echo "... src/mbgl/tile/raster_tile.o"
	@echo "... src/mbgl/tile/raster_tile.i"
	@echo "... src/mbgl/tile/raster_tile.s"
	@echo "... src/mbgl/tile/raster_tile_worker.o"
	@echo "... src/mbgl/tile/raster_tile_worker.i"
	@echo "... src/mbgl/tile/raster_tile_worker.s"
	@echo "... src/mbgl/tile/tile.o"
	@echo "... src/mbgl/tile/tile.i"
	@echo "... src/mbgl/tile/tile.s"
	@echo "... src/mbgl/tile/tile_cache.o"
	@echo "... src/mbgl/tile/tile_cache.i"
	@echo "... src/mbgl/tile/tile_cache.s"
	@echo "... src/mbgl/tile/tile_id_hash.o"
	@echo "... src/mbgl/tile/tile_id_hash.i"
	@echo "... src/mbgl/tile/tile_id_hash.s"
	@echo "... src/mbgl/tile/tile_id_io.o"
	@echo "... src/mbgl/tile/tile_id_io.i"
	@echo "... src/mbgl/tile/tile_id_io.s"
	@echo "... src/mbgl/tile/vector_tile.o"
	@echo "... src/mbgl/tile/vector_tile.i"
	@echo "... src/mbgl/tile/vector_tile.s"
	@echo "... src/mbgl/tile/vector_tile_data.o"
	@echo "... src/mbgl/tile/vector_tile_data.i"
	@echo "... src/mbgl/tile/vector_tile_data.s"
	@echo "... src/mbgl/util/chrono.o"
	@echo "... src/mbgl/util/chrono.i"
	@echo "... src/mbgl/util/chrono.s"
	@echo "... src/mbgl/util/clip_id.o"
	@echo "... src/mbgl/util/clip_id.i"
	@echo "... src/mbgl/util/clip_id.s"
	@echo "... src/mbgl/util/color.o"
	@echo "... src/mbgl/util/color.i"
	@echo "... src/mbgl/util/color.s"
	@echo "... src/mbgl/util/compression.o"
	@echo "... src/mbgl/util/compression.i"
	@echo "... src/mbgl/util/compression.s"
	@echo "... src/mbgl/util/constants.o"
	@echo "... src/mbgl/util/constants.i"
	@echo "... src/mbgl/util/constants.s"
	@echo "... src/mbgl/util/convert.o"
	@echo "... src/mbgl/util/convert.i"
	@echo "... src/mbgl/util/convert.s"
	@echo "... src/mbgl/util/dtoa.o"
	@echo "... src/mbgl/util/dtoa.i"
	@echo "... src/mbgl/util/dtoa.s"
	@echo "... src/mbgl/util/event.o"
	@echo "... src/mbgl/util/event.i"
	@echo "... src/mbgl/util/event.s"
	@echo "... src/mbgl/util/font_stack.o"
	@echo "... src/mbgl/util/font_stack.i"
	@echo "... src/mbgl/util/font_stack.s"
	@echo "... src/mbgl/util/geo.o"
	@echo "... src/mbgl/util/geo.i"
	@echo "... src/mbgl/util/geo.s"
	@echo "... src/mbgl/util/geojson_impl.o"
	@echo "... src/mbgl/util/geojson_impl.i"
	@echo "... src/mbgl/util/geojson_impl.s"
	@echo "... src/mbgl/util/grid_index.o"
	@echo "... src/mbgl/util/grid_index.i"
	@echo "... src/mbgl/util/grid_index.s"
	@echo "... src/mbgl/util/http_header.o"
	@echo "... src/mbgl/util/http_header.i"
	@echo "... src/mbgl/util/http_header.s"
	@echo "... src/mbgl/util/http_timeout.o"
	@echo "... src/mbgl/util/http_timeout.i"
	@echo "... src/mbgl/util/http_timeout.s"
	@echo "... src/mbgl/util/i18n.o"
	@echo "... src/mbgl/util/i18n.i"
	@echo "... src/mbgl/util/i18n.s"
	@echo "... src/mbgl/util/interpolate.o"
	@echo "... src/mbgl/util/interpolate.i"
	@echo "... src/mbgl/util/interpolate.s"
	@echo "... src/mbgl/util/intersection_tests.o"
	@echo "... src/mbgl/util/intersection_tests.i"
	@echo "... src/mbgl/util/intersection_tests.s"
	@echo "... src/mbgl/util/io.o"
	@echo "... src/mbgl/util/io.i"
	@echo "... src/mbgl/util/io.s"
	@echo "... src/mbgl/util/logging.o"
	@echo "... src/mbgl/util/logging.i"
	@echo "... src/mbgl/util/logging.s"
	@echo "... src/mbgl/util/mapbox.o"
	@echo "... src/mbgl/util/mapbox.i"
	@echo "... src/mbgl/util/mapbox.s"
	@echo "... src/mbgl/util/mat2.o"
	@echo "... src/mbgl/util/mat2.i"
	@echo "... src/mbgl/util/mat2.s"
	@echo "... src/mbgl/util/mat3.o"
	@echo "... src/mbgl/util/mat3.i"
	@echo "... src/mbgl/util/mat3.s"
	@echo "... src/mbgl/util/mat4.o"
	@echo "... src/mbgl/util/mat4.i"
	@echo "... src/mbgl/util/mat4.s"
	@echo "... src/mbgl/util/offscreen_texture.o"
	@echo "... src/mbgl/util/offscreen_texture.i"
	@echo "... src/mbgl/util/offscreen_texture.s"
	@echo "... src/mbgl/util/premultiply.o"
	@echo "... src/mbgl/util/premultiply.i"
	@echo "... src/mbgl/util/premultiply.s"
	@echo "... src/mbgl/util/stopwatch.o"
	@echo "... src/mbgl/util/stopwatch.i"
	@echo "... src/mbgl/util/stopwatch.s"
	@echo "... src/mbgl/util/string.o"
	@echo "... src/mbgl/util/string.i"
	@echo "... src/mbgl/util/string.s"
	@echo "... src/mbgl/util/throttler.o"
	@echo "... src/mbgl/util/throttler.i"
	@echo "... src/mbgl/util/throttler.s"
	@echo "... src/mbgl/util/tile_cover.o"
	@echo "... src/mbgl/util/tile_cover.i"
	@echo "... src/mbgl/util/tile_cover.s"
	@echo "... src/mbgl/util/url.o"
	@echo "... src/mbgl/util/url.i"
	@echo "... src/mbgl/util/url.s"
	@echo "... src/mbgl/util/version.o"
	@echo "... src/mbgl/util/version.i"
	@echo "... src/mbgl/util/version.s"
	@echo "... src/mbgl/util/work_request.o"
	@echo "... src/mbgl/util/work_request.i"
	@echo "... src/mbgl/util/work_request.s"
	@echo "... src/parsedate/parsedate.o"
	@echo "... src/parsedate/parsedate.i"
	@echo "... src/parsedate/parsedate.s"
	@echo "... test/actor/actor.test.o"
	@echo "... test/actor/actor.test.i"
	@echo "... test/actor/actor.test.s"
	@echo "... test/actor/actor_ref.test.o"
	@echo "... test/actor/actor_ref.test.i"
	@echo "... test/actor/actor_ref.test.s"
	@echo "... test/algorithm/covered_by_children.test.o"
	@echo "... test/algorithm/covered_by_children.test.i"
	@echo "... test/algorithm/covered_by_children.test.s"
	@echo "... test/algorithm/generate_clip_ids.test.o"
	@echo "... test/algorithm/generate_clip_ids.test.i"
	@echo "... test/algorithm/generate_clip_ids.test.s"
	@echo "... test/algorithm/update_renderables.test.o"
	@echo "... test/algorithm/update_renderables.test.i"
	@echo "... test/algorithm/update_renderables.test.s"
	@echo "... test/algorithm/update_tile_masks.test.o"
	@echo "... test/algorithm/update_tile_masks.test.i"
	@echo "... test/algorithm/update_tile_masks.test.s"
	@echo "... test/api/annotations.test.o"
	@echo "... test/api/annotations.test.i"
	@echo "... test/api/annotations.test.s"
	@echo "... test/api/api_misuse.test.o"
	@echo "... test/api/api_misuse.test.i"
	@echo "... test/api/api_misuse.test.s"
	@echo "... test/api/custom_layer.test.o"
	@echo "... test/api/custom_layer.test.i"
	@echo "... test/api/custom_layer.test.s"
	@echo "... test/api/query.test.o"
	@echo "... test/api/query.test.i"
	@echo "... test/api/query.test.s"
	@echo "... test/api/recycle_map.o"
	@echo "... test/api/recycle_map.i"
	@echo "... test/api/recycle_map.s"
	@echo "... test/api/zoom_history.o"
	@echo "... test/api/zoom_history.i"
	@echo "... test/api/zoom_history.s"
	@echo "... test/gl/bucket.test.o"
	@echo "... test/gl/bucket.test.i"
	@echo "... test/gl/bucket.test.s"
	@echo "... test/gl/context.test.o"
	@echo "... test/gl/context.test.i"
	@echo "... test/gl/context.test.s"
	@echo "... test/gl/object.test.o"
	@echo "... test/gl/object.test.i"
	@echo "... test/gl/object.test.s"
	@echo "... test/map/map.test.o"
	@echo "... test/map/map.test.i"
	@echo "... test/map/map.test.s"
	@echo "... test/map/prefetch.test.o"
	@echo "... test/map/prefetch.test.i"
	@echo "... test/map/prefetch.test.s"
	@echo "... test/map/transform.test.o"
	@echo "... test/map/transform.test.i"
	@echo "... test/map/transform.test.s"
	@echo "... test/math/clamp.test.o"
	@echo "... test/math/clamp.test.i"
	@echo "... test/math/clamp.test.s"
	@echo "... test/math/minmax.test.o"
	@echo "... test/math/minmax.test.i"
	@echo "... test/math/minmax.test.s"
	@echo "... test/math/wrap.test.o"
	@echo "... test/math/wrap.test.i"
	@echo "... test/math/wrap.test.s"
	@echo "... test/programs/binary_program.test.o"
	@echo "... test/programs/binary_program.test.i"
	@echo "... test/programs/binary_program.test.s"
	@echo "... test/programs/symbol_program.test.o"
	@echo "... test/programs/symbol_program.test.i"
	@echo "... test/programs/symbol_program.test.s"
	@echo "... test/renderer/backend_scope.test.o"
	@echo "... test/renderer/backend_scope.test.i"
	@echo "... test/renderer/backend_scope.test.s"
	@echo "... test/renderer/group_by_layout.test.o"
	@echo "... test/renderer/group_by_layout.test.i"
	@echo "... test/renderer/group_by_layout.test.s"
	@echo "... test/renderer/image_manager.test.o"
	@echo "... test/renderer/image_manager.test.i"
	@echo "... test/renderer/image_manager.test.s"
	@echo "... test/sprite/sprite_loader.test.o"
	@echo "... test/sprite/sprite_loader.test.i"
	@echo "... test/sprite/sprite_loader.test.s"
	@echo "... test/sprite/sprite_parser.test.o"
	@echo "... test/sprite/sprite_parser.test.i"
	@echo "... test/sprite/sprite_parser.test.s"
	@echo "... test/src/mbgl/test/fixture_log_observer.o"
	@echo "... test/src/mbgl/test/fixture_log_observer.i"
	@echo "... test/src/mbgl/test/fixture_log_observer.s"
	@echo "... test/src/mbgl/test/getrss.o"
	@echo "... test/src/mbgl/test/getrss.i"
	@echo "... test/src/mbgl/test/getrss.s"
	@echo "... test/src/mbgl/test/stub_file_source.o"
	@echo "... test/src/mbgl/test/stub_file_source.i"
	@echo "... test/src/mbgl/test/stub_file_source.s"
	@echo "... test/src/mbgl/test/test.o"
	@echo "... test/src/mbgl/test/test.i"
	@echo "... test/src/mbgl/test/test.s"
	@echo "... test/src/mbgl/test/util.o"
	@echo "... test/src/mbgl/test/util.i"
	@echo "... test/src/mbgl/test/util.s"
	@echo "... test/storage/asset_file_source.test.o"
	@echo "... test/storage/asset_file_source.test.i"
	@echo "... test/storage/asset_file_source.test.s"
	@echo "... test/storage/default_file_source.test.o"
	@echo "... test/storage/default_file_source.test.i"
	@echo "... test/storage/default_file_source.test.s"
	@echo "... test/storage/headers.test.o"
	@echo "... test/storage/headers.test.i"
	@echo "... test/storage/headers.test.s"
	@echo "... test/storage/http_file_source.test.o"
	@echo "... test/storage/http_file_source.test.i"
	@echo "... test/storage/http_file_source.test.s"
	@echo "... test/storage/local_file_source.test.o"
	@echo "... test/storage/local_file_source.test.i"
	@echo "... test/storage/local_file_source.test.s"
	@echo "... test/storage/offline.test.o"
	@echo "... test/storage/offline.test.i"
	@echo "... test/storage/offline.test.s"
	@echo "... test/storage/offline_database.test.o"
	@echo "... test/storage/offline_database.test.i"
	@echo "... test/storage/offline_database.test.s"
	@echo "... test/storage/offline_download.test.o"
	@echo "... test/storage/offline_download.test.i"
	@echo "... test/storage/offline_download.test.s"
	@echo "... test/storage/online_file_source.test.o"
	@echo "... test/storage/online_file_source.test.i"
	@echo "... test/storage/online_file_source.test.s"
	@echo "... test/storage/resource.test.o"
	@echo "... test/storage/resource.test.i"
	@echo "... test/storage/resource.test.s"
	@echo "... test/storage/sqlite.test.o"
	@echo "... test/storage/sqlite.test.i"
	@echo "... test/storage/sqlite.test.s"
	@echo "... test/style/conversion/function.test.o"
	@echo "... test/style/conversion/function.test.i"
	@echo "... test/style/conversion/function.test.s"
	@echo "... test/style/conversion/geojson_options.test.o"
	@echo "... test/style/conversion/geojson_options.test.i"
	@echo "... test/style/conversion/geojson_options.test.s"
	@echo "... test/style/conversion/layer.test.o"
	@echo "... test/style/conversion/layer.test.i"
	@echo "... test/style/conversion/layer.test.s"
	@echo "... test/style/conversion/light.test.o"
	@echo "... test/style/conversion/light.test.i"
	@echo "... test/style/conversion/light.test.s"
	@echo "... test/style/conversion/stringify.test.o"
	@echo "... test/style/conversion/stringify.test.i"
	@echo "... test/style/conversion/stringify.test.s"
	@echo "... test/style/filter.test.o"
	@echo "... test/style/filter.test.i"
	@echo "... test/style/filter.test.s"
	@echo "... test/style/function/camera_function.test.o"
	@echo "... test/style/function/camera_function.test.i"
	@echo "... test/style/function/camera_function.test.s"
	@echo "... test/style/function/composite_function.test.o"
	@echo "... test/style/function/composite_function.test.i"
	@echo "... test/style/function/composite_function.test.s"
	@echo "... test/style/function/exponential_stops.test.o"
	@echo "... test/style/function/exponential_stops.test.i"
	@echo "... test/style/function/exponential_stops.test.s"
	@echo "... test/style/function/interval_stops.test.o"
	@echo "... test/style/function/interval_stops.test.i"
	@echo "... test/style/function/interval_stops.test.s"
	@echo "... test/style/function/source_function.test.o"
	@echo "... test/style/function/source_function.test.i"
	@echo "... test/style/function/source_function.test.s"
	@echo "... test/style/properties.test.o"
	@echo "... test/style/properties.test.i"
	@echo "... test/style/properties.test.s"
	@echo "... test/style/source.test.o"
	@echo "... test/style/source.test.i"
	@echo "... test/style/source.test.s"
	@echo "... test/style/style.test.o"
	@echo "... test/style/style.test.i"
	@echo "... test/style/style.test.s"
	@echo "... test/style/style_image.test.o"
	@echo "... test/style/style_image.test.i"
	@echo "... test/style/style_image.test.s"
	@echo "... test/style/style_layer.test.o"
	@echo "... test/style/style_layer.test.i"
	@echo "... test/style/style_layer.test.s"
	@echo "... test/style/style_parser.test.o"
	@echo "... test/style/style_parser.test.i"
	@echo "... test/style/style_parser.test.s"
	@echo "... test/text/glyph_loader.test.o"
	@echo "... test/text/glyph_loader.test.i"
	@echo "... test/text/glyph_loader.test.s"
	@echo "... test/text/glyph_pbf.test.o"
	@echo "... test/text/glyph_pbf.test.i"
	@echo "... test/text/glyph_pbf.test.s"
	@echo "... test/text/quads.test.o"
	@echo "... test/text/quads.test.i"
	@echo "... test/text/quads.test.s"
	@echo "... test/tile/annotation_tile.test.o"
	@echo "... test/tile/annotation_tile.test.i"
	@echo "... test/tile/annotation_tile.test.s"
	@echo "... test/tile/geojson_tile.test.o"
	@echo "... test/tile/geojson_tile.test.i"
	@echo "... test/tile/geojson_tile.test.s"
	@echo "... test/tile/geometry_tile_data.test.o"
	@echo "... test/tile/geometry_tile_data.test.i"
	@echo "... test/tile/geometry_tile_data.test.s"
	@echo "... test/tile/raster_tile.test.o"
	@echo "... test/tile/raster_tile.test.i"
	@echo "... test/tile/raster_tile.test.s"
	@echo "... test/tile/tile_coordinate.test.o"
	@echo "... test/tile/tile_coordinate.test.i"
	@echo "... test/tile/tile_coordinate.test.s"
	@echo "... test/tile/tile_id.test.o"
	@echo "... test/tile/tile_id.test.i"
	@echo "... test/tile/tile_id.test.s"
	@echo "... test/tile/vector_tile.test.o"
	@echo "... test/tile/vector_tile.test.i"
	@echo "... test/tile/vector_tile.test.s"
	@echo "... test/util/async_task.test.o"
	@echo "... test/util/async_task.test.i"
	@echo "... test/util/async_task.test.s"
	@echo "... test/util/dtoa.test.o"
	@echo "... test/util/dtoa.test.i"
	@echo "... test/util/dtoa.test.s"
	@echo "... test/util/geo.test.o"
	@echo "... test/util/geo.test.i"
	@echo "... test/util/geo.test.s"
	@echo "... test/util/http_timeout.test.o"
	@echo "... test/util/http_timeout.test.i"
	@echo "... test/util/http_timeout.test.s"
	@echo "... test/util/image.test.o"
	@echo "... test/util/image.test.i"
	@echo "... test/util/image.test.s"
	@echo "... test/util/mapbox.test.o"
	@echo "... test/util/mapbox.test.i"
	@echo "... test/util/mapbox.test.s"
	@echo "... test/util/memory.test.o"
	@echo "... test/util/memory.test.i"
	@echo "... test/util/memory.test.s"
	@echo "... test/util/merge_lines.test.o"
	@echo "... test/util/merge_lines.test.i"
	@echo "... test/util/merge_lines.test.s"
	@echo "... test/util/number_conversions.test.o"
	@echo "... test/util/number_conversions.test.i"
	@echo "... test/util/number_conversions.test.s"
	@echo "... test/util/offscreen_texture.test.o"
	@echo "... test/util/offscreen_texture.test.i"
	@echo "... test/util/offscreen_texture.test.s"
	@echo "... test/util/position.test.o"
	@echo "... test/util/position.test.i"
	@echo "... test/util/position.test.s"
	@echo "... test/util/projection.test.o"
	@echo "... test/util/projection.test.i"
	@echo "... test/util/projection.test.s"
	@echo "... test/util/run_loop.test.o"
	@echo "... test/util/run_loop.test.i"
	@echo "... test/util/run_loop.test.s"
	@echo "... test/util/text_conversions.test.o"
	@echo "... test/util/text_conversions.test.i"
	@echo "... test/util/text_conversions.test.s"
	@echo "... test/util/thread.test.o"
	@echo "... test/util/thread.test.i"
	@echo "... test/util/thread.test.s"
	@echo "... test/util/thread_local.test.o"
	@echo "... test/util/thread_local.test.i"
	@echo "... test/util/thread_local.test.s"
	@echo "... test/util/tile_cover.test.o"
	@echo "... test/util/tile_cover.test.i"
	@echo "... test/util/tile_cover.test.s"
	@echo "... test/util/timer.test.o"
	@echo "... test/util/timer.test.i"
	@echo "... test/util/timer.test.s"
	@echo "... test/util/token.test.o"
	@echo "... test/util/token.test.i"
	@echo "... test/util/token.test.s"
	@echo "... test/util/url.test.o"
	@echo "... test/util/url.test.i"
	@echo "... test/util/url.test.s"
.PHONY : help



#=============================================================================
# Special targets to cleanup operation of make.

# Special rule to run CMake to check the build system integrity.
# No rule that depends on this can have commands that come from listfiles
# because they might be regenerated.
cmake_check_build_system:
	$(CMAKE_COMMAND) -H$(CMAKE_SOURCE_DIR) -B$(CMAKE_BINARY_DIR) --check-build-system CMakeFiles/Makefile.cmake 0
.PHONY : cmake_check_build_system

