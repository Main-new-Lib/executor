# Makefile for iOS Roblox Executor
# Replacement for CMake build system

# Compiler and flags
CXX := clang++
CC := clang
OBJCXX := clang++
AR := ar

# Build type (Debug or Release)
BUILD_TYPE ?= Release
# iOS SDK settings
SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
ARCHS ?= arm64
MIN_IOS_VERSION ?= 15.0

# Basic flags
ifeq ($(BUILD_TYPE),Debug)
    OPT_FLAGS := -g -O0
    DEFS := -DDEBUG_BUILD=1
else
    OPT_FLAGS := -O3 
    DEFS := -DPRODUCTION_BUILD=1
endif

CXXFLAGS := -std=c++17 -fPIC $(OPT_FLAGS) -Wall -Wextra -fvisibility=hidden -ferror-limit=0 -fno-limit-debug-info
CFLAGS := -fPIC $(OPT_FLAGS) -Wall -Wextra -fvisibility=hidden -ferror-limit=0 -fno-limit-debug-info
OBJCXXFLAGS := -std=c++17 -fPIC $(OPT_FLAGS) -Wall -Wextra -fvisibility=hidden -ferror-limit=0 -fno-limit-debug-info
LDFLAGS := -shared

# Define platform
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    IS_APPLE := 1
    # iOS-specific compiler flags
    CXXFLAGS += -isysroot $(SDK) -arch $(ARCHS) -mios-version-min=$(MIN_IOS_VERSION)
    CFLAGS += -isysroot $(SDK) -arch $(ARCHS) -mios-version-min=$(MIN_IOS_VERSION)
    OBJCXXFLAGS += -isysroot $(SDK) -arch $(ARCHS) -mios-version-min=$(MIN_IOS_VERSION)
    CXXFLAGS += -fobjc-arc
    OBJCXXFLAGS += -fobjc-arc
    LDFLAGS += -dynamiclib
endif

# iOS-specific settings
ifdef IS_APPLE
    FRAMEWORKS := -framework Foundation -framework UIKit -framework Security -framework CoreData
    SYSTEM_NAME := $(shell test -d /Applications/Xcode.app && echo "iOS" || echo "macOS")
    ifeq ($(SYSTEM_NAME),iOS)
        CXXFLAGS += -mios-version-min=13.0 -fembed-bitcode
        CFLAGS += -mios-version-min=13.0 -fembed-bitcode
        OBJCXXFLAGS += -mios-version-min=13.0 -fembed-bitcode
    endif
else
    FRAMEWORKS :=
endif

# Feature flags
USE_DOBBY := 1
USE_LUAU := 1
ENABLE_AI_FEATURES := 1
ENABLE_ADVANCED_BYPASS := 1

# Define directories
ROOT_DIR := .
VM_DIR := $(ROOT_DIR)/VM
SOURCE_DIR := $(ROOT_DIR)/source
CPP_DIR := $(SOURCE_DIR)/cpp
VM_SRC_DIR := $(VM_DIR)/src
VM_INCLUDE_DIR := $(VM_DIR)/include

# Include paths
INCLUDES := -I$(VM_INCLUDE_DIR) -I$(VM_SRC_DIR) -I$(SOURCE_DIR) -I$(CPP_DIR) -I$(ROOT_DIR)

# Preprocessor definitions
DEFS += -DUSE_LUAU=1 -DLUAU_FASTINT_SUPPORT=1 -DUSE_LUA=1 -DENABLE_ERROR_REPORTING=1 -DENABLE_ANTI_TAMPER=1
DEFS += -DLUA_API="__attribute__((visibility(\"default\")))" -DLUALIB_API="__attribute__((visibility(\"default\")))" -DLUAI_FUNC="__attribute__((visibility(\"hidden\")))"

ifdef USE_DOBBY
    DEFS += -DUSE_DOBBY=1
endif

ifdef IS_APPLE
    DEFS += -D__APPLE__=1
    ifeq ($(SYSTEM_NAME),iOS)
        DEFS += -DIOS_TARGET=1 -DIOS_BUILD=1 -DSHOW_ALL_WARNINGS=1
    endif
endif

# Find VM sources
VM_SOURCES := $(wildcard $(VM_SRC_DIR)/*.cpp)
VM_OBJECTS := $(VM_SOURCES:.cpp=.o)

# Main library sources 
LIB_CPP_SOURCES := $(SOURCE_DIR)/library.cpp
LIB_C_SOURCES := $(SOURCE_DIR)/lfs.c
LIB_OBJECTS := $(LIB_CPP_SOURCES:.cpp=.o) $(LIB_C_SOURCES:.c=.o)

# Find all cpp sources for roblox_execution
EXEC_CPP_SOURCES := $(shell find $(CPP_DIR) -name "*.cpp" -not -path "$(CPP_DIR)/ios/*" -not -path "$(CPP_DIR)/tests/*")
EXEC_OBJECTS := $(EXEC_CPP_SOURCES:.cpp=.o)

# iOS-specific sources
iOS_CPP_SOURCES :=
iOS_MM_SOURCES :=
ifdef IS_APPLE
    iOS_CPP_SOURCES += $(shell find $(CPP_DIR)/ios -name "*.cpp" 2>/dev/null)
    iOS_MM_SOURCES += $(shell find $(CPP_DIR)/ios -name "*.mm" 2>/dev/null)
    
    ifdef ENABLE_AI_FEATURES
        iOS_CPP_SOURCES += $(shell find $(CPP_DIR)/ios/ai_features -name "*.cpp" 2>/dev/null)
        iOS_MM_SOURCES += $(shell find $(CPP_DIR)/ios/ai_features -name "*.mm" 2>/dev/null)
    endif
    
    ifdef ENABLE_ADVANCED_BYPASS
        iOS_CPP_SOURCES += $(shell find $(CPP_DIR)/ios/advanced_bypass -name "*.cpp" 2>/dev/null)
        iOS_MM_SOURCES += $(shell find $(CPP_DIR)/ios/advanced_bypass -name "*.mm" 2>/dev/null)
    endif
endif

iOS_CPP_OBJECTS := $(iOS_CPP_SOURCES:.cpp=.o)
iOS_MM_OBJECTS := $(iOS_MM_SOURCES:.mm=.o)

# Combine objects for roblox_execution static library
ROBLOX_EXEC_OBJECTS := $(EXEC_OBJECTS) $(iOS_CPP_OBJECTS) $(iOS_MM_OBJECTS)

# Output files
STATIC_LIB := lib/libroblox_execution.a
DYLIB := lib/mylibrary.dylib

# Dobby handling
ifdef USE_DOBBY
    DOBBY_INCLUDE := -I$(ROOT_DIR)/external/dobby/include
    DOBBY_LIB := -L$(ROOT_DIR)/external/dobby/lib -ldobby
    INCLUDES += $(DOBBY_INCLUDE)
endif

# Main rule
all: directories $(STATIC_LIB) $(DYLIB)

# Create necessary directories
directories:
	@mkdir -p lib

# Build static library
$(STATIC_LIB): $(ROBLOX_EXEC_OBJECTS)
	$(AR) rcs $@ $^

# Build dynamic library
$(DYLIB): $(VM_OBJECTS) $(LIB_OBJECTS) $(STATIC_LIB)
	$(CXX) $(LDFLAGS) -o $@ $(VM_OBJECTS) $(LIB_OBJECTS) -L./lib -lroblox_execution $(DOBBY_LIB) $(FRAMEWORKS)
ifdef IS_APPLE
	@install_name_tool -id @executable_path/lib/mylibrary.dylib $@
endif

# Compilation rules
%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) $(DEFS) -c $< -o $@

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDES) $(DEFS) -c $< -o $@

%.o: %.mm
	$(OBJCXX) $(OBJCXXFLAGS) $(INCLUDES) $(DEFS) -c $< -o $@

# Clean rule
clean:
	rm -rf $(VM_OBJECTS) $(LIB_OBJECTS) $(ROBLOX_EXEC_OBJECTS) $(STATIC_LIB) $(DYLIB)

# Install rule
install: all
	@mkdir -p $(ROOT_DIR)/output
	cp $(DYLIB) $(ROOT_DIR)/output/libmylibrary.dylib

# Print info about build (useful for debugging)
info:
	@echo "Build Type: $(BUILD_TYPE)"
	@echo "Platform: $(UNAME_S)"
	@echo "VM Sources: $(VM_SOURCES)"
	@echo "Exec Sources: $(EXEC_CPP_SOURCES)"
	@echo "iOS CPP Sources: $(iOS_CPP_SOURCES)"
	@echo "iOS MM Sources: $(iOS_MM_SOURCES)"

# Help target
help:
	@echo "Available targets:"
	@echo "  all     - Build everything (default)"
	@echo "  clean   - Remove build artifacts"
	@echo "  install - Install dylib to /usr/local/lib"
	@echo "  info    - Print build information"
	@echo ""
	@echo "Configuration variables:"
	@echo "  BUILD_TYPE=Debug|Release - Set build type (default: Release)"
	@echo "  USE_DOBBY=0|1           - Enable Dobby hooking (default: 1)"
	@echo "  ENABLE_AI_FEATURES=0|1   - Enable AI features (default: 1)"
	@echo "  ENABLE_ADVANCED_BYPASS=0|1 - Enable advanced bypass (default: 1)"

.PHONY: all clean install directories info help
