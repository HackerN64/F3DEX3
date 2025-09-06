# To build, run something like `make F3DEX3_BrZ` or`make F3DEX3_BrW_NOC_PA`.
# For an explanation of what all the suffixes mean, see README.md.

MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables
.SUFFIXES:

default: F3DEX3_BrZ F3DEX3_BrW

# The F3DEX3 version letter is incremented when there are major, GBI-breaking
# changes. This goes in the microcode ID string so HLE can detect the version.
VERSION = _B

# List of all compile-time options supported by the microcode source.
ALL_OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_NO_OCCLUSION_PLANE \
  CFG_PROFILING_A \
  CFG_PROFILING_B \
  CFG_PROFILING_C

ARMIPS ?= armips
PARENT_OUTPUT_DIR ?= ./build
ifeq ($(PARENT_OUTPUT_DIR),.)
  $(error Cannot build directly in repo directory; see Makefile for details.)
  # The problem is that we want to be able to have targets like F3DEX2_2.08,
  # but this would also be the directory itself, whose existence and possible
  # modification needs to be handled by the Makefile. It is possible to write
  # the Makefile where the directory is the main target for that microcode, but
  # this has worse behavior in case of modification to the directory. Worse, if
  # it was done this way, then it would break if the user tried to set
  # PARENT_OUTPUT_DIR anywhere else. So, better to support building everywhere
  # but here than to support only building here.
endif

# Find the N64 toolchain, for creating object files.
ifneq (, $(shell which mips64-elf-as))
  AS := mips64-elf-as
else ifneq (, $(shell which mips-n64-as))
  AS := mips-n64-as
else ifneq (, $(shell which mips64-as))
  AS := mips64-as
else ifneq (, $(shell which mips-linux-gnu-as))
  AS := mips-linux-gnu-as
else ifneq (, $(shell which mips64-linux-gnu-as))
  AS := mips64-linux-gnu-as
else ifneq (, $(shell which mips-as))
  AS := mips-as
else ifneq (, $(shell which mips64-linux-gnuabi64-as))
  AS := mips64-linux-gnuabi64-as
else ifneq (, $(shell which mips64-ultra-elf-as))
  AS := mips64-ultra-elf-as
else
  $(warning Could not find N64 assembler, not building object files)
  AS := 
endif

NO_COL := \033[0m
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
INFO    := $(BLUE)
SUCCESS := $(GREEN)
FAILURE := $(RED)
WARNING := $(YELLOW)

$(PARENT_OUTPUT_DIR):
	@printf "$(INFO)Creating parent output directory$(NO_COL)\n"
ifeq ($(OS),Windows_NT)
	mkdir $@
else
	mkdir -p $@
endif
ALL_UCODES :=
ALL_UCODES_WITH_MD5S :=
ALL_OUTPUT_DIRS :=

ifneq (, $(AS))
%.o: %.o.s
	@$(AS) -march=vr4300 -mabi=32 -I . $< -o $@
endif

define reset_vars
  NAME := 
  DESCRIPTION := 
  ID_STR := 
  MD5_CODE := 
  MD5_DATA := 
  OPTIONS := 
  EXTRA_DEPS := 
endef

define ucode_rule
  # Variables defined outside the function need one dollar sign, whereas
  # variables defined within the function need two. This is because make first
  # expands all this text, substituting single-dollar-sign variables, and then
  # executes all of it, causing all the assignments to actually happen.
  ifeq ($(NAME),)
   $$(error Microcode name not set!)
  endif
  UCODE_OUTPUT_DIR := $(PARENT_OUTPUT_DIR)/$(NAME)
  CODE_FILE := $$(UCODE_OUTPUT_DIR)/$(NAME).code
  DATA_FILE := $$(UCODE_OUTPUT_DIR)/$(NAME).data
  SYM_FILE  := $$(UCODE_OUTPUT_DIR)/$(NAME).sym
  TEMP_FILE := $$(UCODE_OUTPUT_DIR)/$(NAME).tmp.s
  OS_FILE   := $$(UCODE_OUTPUT_DIR)/gsp$(NAME).o.s
  O_FILE    := $$(UCODE_OUTPUT_DIR)/gsp$(NAME).o
  ALL_UCODES += $(NAME)
  ifneq ($(MD5_CODE),)
   ALL_UCODES_WITH_MD5S += $(NAME)
  endif
  ALL_OUTPUT_DIRS += $$(UCODE_OUTPUT_DIR)
  OFF_OPTIONS := $(filter-out $(OPTIONS),$(ALL_OPTIONS))
  OPTIONS_EQU := 
  $$(foreach option,$(OPTIONS),$$(eval OPTIONS_EQU += -equ $$(option) 1))
  OFF_OPTIONS_EQU := 
  $$(foreach o2,$$(OFF_OPTIONS),$$(eval OFF_OPTIONS_EQU += -equ $$(o2) 0))
  ARMIPS_CMDLINE := \
   -strequ CODE_FILE $$(CODE_FILE) \
   -strequ DATA_FILE $$(DATA_FILE) \
   $$(OPTIONS_EQU) \
   $$(OFF_OPTIONS_EQU) \
   f3dex3.s \
   -sym2 $$(SYM_FILE) \
   -temp $$(TEMP_FILE)
  # Microcode target
  .PHONY: $(NAME)
  $(NAME): $$(CODE_FILE)
  ifneq (, $(AS))
  $(NAME): $$(O_FILE)
  endif
  # Directory target variables, see below.
  $$(UCODE_OUTPUT_DIR): UCODE_OUTPUT_DIR:=$$(UCODE_OUTPUT_DIR)
  # Directory target recipe
  $$(UCODE_OUTPUT_DIR):
	@printf "$(INFO)Creating directory $$(UCODE_OUTPUT_DIR)$(NO_COL)\n"
  ifeq ($(OS),Windows_NT)
	@mkdir $$(subst /,\,$$(UCODE_OUTPUT_DIR))
  else
	@mkdir -p $$(UCODE_OUTPUT_DIR)
  endif
  # Code file target variables. make does not expand variables within recipes
  # until the recipe is executed, meaning that all the parts of the recipe would
  # have the values from the very last microcode in the file. Here, we set
  # target-specific variables--effectively local variables within the recipe--
  # to the values from the global variables have right now. We are only
  # targeting CODE_FILE even though we also want DATA_FILE, because target-
  # specific variables may not work as expected with multiple targets from one
  # recipe.
  $$(CODE_FILE): ARMIPS_CMDLINE:=$$(ARMIPS_CMDLINE)
  $$(CODE_FILE): CODE_FILE:=$$(CODE_FILE)
  $$(CODE_FILE): DATA_FILE:=$$(DATA_FILE)
  $$(OS_FILE): OS_FILE:=$$(OS_FILE)
  $$(OS_FILE): NAME:=$$(NAME)
  # Target recipe
  $$(CODE_FILE): ./f3dex3.s ./rsp/* $(EXTRA_DEPS) | $$(UCODE_OUTPUT_DIR)
	@printf "$(INFO)Building microcode: $(NAME): $(DESCRIPTION)$(NO_COL)\n"
	@$(ARMIPS) -strequ ID_STR "$(ID_STR)" $$(ARMIPS_CMDLINE)
  ifneq ($(MD5_CODE),)
	@(printf "$(MD5_CODE) *$$(CODE_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(NAME) code matches$(NO_COL)\n" || printf "  $(FAILURE)$(NAME) code differs$(NO_COL)\n"
	@(printf "$(MD5_DATA) *$$(DATA_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(NAME) data matches$(NO_COL)\n" || printf "  $(FAILURE)$(NAME) data differs$(NO_COL)\n"
  endif
  ifneq (, $(AS))
  $$(OS_FILE): $$(CODE_FILE)
	@sed "s|XXX|$(NAME)|g" ./template.o.s > $$(OS_FILE)
  endif
  $$(eval $$(call reset_vars))
endef

$(eval $(call reset_vars))

define rule_builder_final
  NAME := F3DEX3$(NAME_FINAL)
  DESCRIPTION := Will make you want to finally ditch HLE ($(OPTIONS_FINAL))
  ID_STR := F3DEX3$(NAME_FINAL)$(VERSION) by Sauraen & Yoshitaka Yasumoto/Nintendo
  OPTIONS := $(OPTIONS_FINAL)
  $$(eval $$(call ucode_rule))
endef

define rule_builder_prof
  NAME_FINAL := $(NAME_PROF)
  OPTIONS_FINAL := $(OPTIONS_PROF)
  $$(eval $$(call rule_builder_final))
  
  NAME_FINAL := $(NAME_PROF)_PA
  OPTIONS_FINAL := $(OPTIONS_PROF) CFG_PROFILING_A
  $$(eval $$(call rule_builder_final))
  
  NAME_FINAL := $(NAME_PROF)_PB
  OPTIONS_FINAL := $(OPTIONS_PROF) CFG_PROFILING_B
  $$(eval $$(call rule_builder_final))
  
  NAME_FINAL := $(NAME_PROF)_PC
  OPTIONS_FINAL := $(OPTIONS_PROF) CFG_PROFILING_C
  $$(eval $$(call rule_builder_final))
endef

define rule_builder_noc
  NAME_PROF := $(NAME_NOC)
  OPTIONS_PROF := $(OPTIONS_NOC)
  $$(eval $$(call rule_builder_prof))
  
  NAME_PROF := $(NAME_NOC)_NOC
  OPTIONS_PROF := $(OPTIONS_NOC) CFG_NO_OCCLUSION_PLANE
  $$(eval $$(call rule_builder_prof))
endef

define rule_builder_br
  NAME_NOC := $(NAME_BR)_BrZ
  OPTIONS_NOC := $(OPTIONS_BR)
  $$(eval $$(call rule_builder_noc))
  
  NAME_NOC := $(NAME_BR)_BrW
  OPTIONS_NOC := $(OPTIONS_BR) CFG_G_BRANCH_W
  $$(eval $$(call rule_builder_noc))
endef

NAME_BR := 
OPTIONS_BR := 
$(eval $(call rule_builder_br))

.PHONY: default ok all clean

all: $(ALL_UCODES)

clean:
	@printf "$(WARNING)Deleting all built microcode files$(NO_COL)\n"
	@rm -rf $(ALL_OUTPUT_DIRS)

doc:
	doxygen Doxyfile
