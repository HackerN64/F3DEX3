MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables
.SUFFIXES:

default: F3DEX3_BrZ F3DEX3_BrW

# List of all compile-time options supported by the microcode source.
ALL_OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_DEBUG_NORMALS \
  CFG_GCLK_SAMPLE

ARMIPS ?= armips
PARENT_OUTPUT_DIR ?= ../test
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

define reset_vars
  NAME := 
  DESCRIPTION := (Not used in any retail games)
  ID_STR := Custom F3DEX2-based microcode, github.com/Mr-Wiseguy/f3dex2 & Nintendo
  ID_STR := RSP Gfx ucode F3DEX       fifo 2.04H Yoshitaka Yasumoto 1998 Nintendo.
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
  # Target recipe
  $$(CODE_FILE): ./f3dex3.s ./rsp/* $(EXTRA_DEPS) | $$(UCODE_OUTPUT_DIR)
	@printf "$(INFO)Building microcode: $(NAME): $(DESCRIPTION)$(NO_COL)\n"
	@$(ARMIPS) -strequ ID_STR "$(ID_STR)" $$(ARMIPS_CMDLINE)
  ifneq ($(MD5_CODE),)
	@(printf "$(MD5_CODE) *$$(CODE_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(NAME) code matches$(NO_COL)\n" || printf "  $(FAILURE)$(NAME) code differs$(NO_COL)\n"
	@(printf "$(MD5_DATA) *$$(DATA_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(NAME) data matches$(NO_COL)\n" || printf "  $(FAILURE)$(NAME) data differs$(NO_COL)\n"
  else ifneq ($(1),1)
	@printf "  $(WARNING)MD5 sums not in database for $(NAME)$(NO_COL)\n"
  endif
  $$(eval $$(call reset_vars))
endef

$(eval $(call reset_vars))

NAME := F3DEX3_BrZ
DESCRIPTION := Will make you want to finally ditch HLE (G_BRANCH_Z version)
ID_STR := F3DEX3 by Sauraen & Nintendo, G_BRANCH_Z version______________________
# Add options you want here, e.g. CFG_GCLK_SAMPLE
OPTIONS := 
$(eval $(call ucode_rule))

NAME := F3DEX3_BrW
DESCRIPTION := Will make you want to finally ditch HLE (G_BRANCH_W version)
ID_STR := F3DEX3 by Sauraen & Nintendo, G_BRANCH_W version______________________
# Add options you want here, e.g. CFG_GCLK_SAMPLE
OPTIONS := \
  CFG_GCLK_SAMPLE \
  CFG_G_BRANCH_W
$(eval $(call ucode_rule))

.PHONY: default ok all clean

all: $(ALL_UCODES)

ok: $(ALL_UCODES_WITH_MD5S)

clean:
	@printf "$(WARNING)Deleting all built microcode files$(NO_COL)\n"
	@rm -rf $(ALL_OUTPUT_DIRS)
