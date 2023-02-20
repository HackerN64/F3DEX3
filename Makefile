MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables
.SUFFIXES:

default:
	@echo 'How to use this Makefile'
	@echo 'Method 1) Select a microcode, just run e.g. `make F3DZEX_NoN_2.06H`'
	@echo 'Method 2) `make ok`, builds all ucodes which have MD5 sums, to check if :OK:'
	@echo 'Method 3) `make all`, builds all ucodes in database'
	@echo 'Method 4) Custom microcode build via custom.mk file. Create a file custom.mk'
	@echo 'with contents like this:'
	@echo 'NAME := your_custom_ucode_name'
	@echo 'DESCRIPTION := Your Romhack Name'
	@echo 'ID_STR := Modded F3DZEX by _your_name_, real N64 hardware or RSP LLE is required'
	@echo '          ^ (this must be the exact number of characters)'
	@echo 'OPTIONS := CFG_NoN CFG_POINT_LIGHTING etc.'
	@echo 'Then run `make your_custom_ucode_name`. See the Makefile for the list of options.'

# With the defaults--all of these options unset--you get 2.08 (Banjo-Tooie),
# which has none of the bugs / the latest versions of everything, except
# G_BRANCH_Z (F3DEX2), no point lighting, and no NoN. Enabling the different
# BUG_ options *gives* you the bugs--the default is always with the bugs fixed.
# If you are modding and adding options, you just have to add them here, and
# in the options list for your custom configuration.
ALL_OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_XBUS \
  CFG_NoN \
  CFG_POINT_LIGHTING \
  CFG_OLD_TRI_WRITE \
  CFG_EXTRA_0A_BEFORE_ID_STR \
  CFG_G_SPECIAL_1_IS_RECALC_MVP \
  CFG_CLIPPING_SUBDIVIDE_DESCENDING \
  CFG_DONT_SKIP_FIRST_INSTR_NEW_UCODE \
  BUG_CLIPPING_FAIL_WHEN_SUM_ZERO \
  BUG_NO_CLAMP_SCREEN_Z_POSITIVE \
  BUG_TEXGEN_LINEAR_CLOBBER_S_T \
  BUG_WRONG_INIT_VZERO \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
  
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
   f3dex2.s \
   -sym2 $$(SYM_FILE) \
   -temp $$(TEMP_FILE)
  # Microcode target
  .PHONY: $(NAME)
  $(NAME): $$(CODE_FILE)
  # Directory target variables, see below.
  $$(UCODE_OUTPUT_DIR): UCODE_OUTPUT_DIR:=$$(UCODE_OUTPUT_DIR)
  # Directory target recipe
  $$(UCODE_OUTPUT_DIR):
	@echo "$(INFO)Creating directory $$(UCODE_OUTPUT_DIR)$(NO_COL)"
  ifeq ($(OS),Windows_NT)
	@mkdir $$(UCODE_OUTPUT_DIR)
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
  $$(CODE_FILE): ./f3dex2.s ./rsp/* ucodes_database.mk $(EXTRA_DEPS) | $$(UCODE_OUTPUT_DIR)
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

ifneq ("$(wildcard custom.mk)","")
  include custom.mk
  EXTRA_DEPS := custom.mk
  $(eval $(call ucode_rule))
endif

include ucodes_database.mk

.PHONY: default ok all clean

all: $(ALL_UCODES)

ok: $(ALL_UCODES_WITH_MD5S)

clean:
	@printf "$(WARNING)Deleting all built microcode files$(NO_COL)\n"
	@rm -rf $(ALL_OUTPUT_DIRS)
