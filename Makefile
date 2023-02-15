default:
	@echo "How to use this Makefile"
	@echo "Method 1) Select a microcode, just run e.g. `make F3DZEX_NoN_2.06H`"
	@echo "Method 2) `make ok`, builds all ucodes which have MD5 sums, to check if :OK:"
	@echo "Method 3) `make all`, builds all ucodes in database"
	@echo "Method 4) Custom microcode build via custom.mk file. Create a file custom.mk"
	@echo "with contents like this:"
	@echo "NAME := your_custom_ucode_name"
	@echo "GAMES := Your Romhack Name"
	@echo "ID_STR := Modded F3DZEX by LeEtHaCkEr64 / Real N64 or RSP LLE only. NO PROJECT64"
	@echo "          ^ (this must be the exact number of characters)"
	@echo "CFG_NoN := 1"
	@echo "etc. You only need to set the options you want to enable. Then run `make custom`."
	@echo "See the Makefile for the list of options."

# The default is all of these options as 0 (or unset). With the defaults, you
# get 2.08, which has none of the bugs / the latest versions of everything,
# except G_BRANCH_Z (F3DEX2), no point lighting, and no NoN. Enabling the
# different BUG_ options *gives* you the bugs--the default is always with the
# bugs fixed.
ALL_OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_XBUS \
  CFG_NoN \
  CFG_POINT_LIGHTING \
  CFG_OLD_TRI_WRITE \
  CFG_EXTRA_0A_BEFORE_ID_STR \
  CFG_G_SPECIAL_1_IS_RECALC_MVP \
  CFG_CLIPPING_SUBDIVIDE_DESCENDING \
  BUG_CLIPPING_FAIL_WHEN_SUM_ZERO \
  BUG_NO_CLAMP_SCREEN_Z_POSITIVE \
  BUG_TEXGEN_LINEAR_CLOBBER_S_T \
  BUG_WRONG_INIT_VZERO \
  BUG_HARMLESS_EXTRA_INIT_VONE \
  BUG_HARMLESS_TASKDONE_WRONG_ADDR
  
ARMIPS ?= armips
PARENT_OUTPUT_DIR ?= ./

NO_COL := \033[0m
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
INFO    := $(NO_COL)
SUCCESS := $(GREEN)
FAILURE := $(RED)
WARNING := $(YELLOW)

define reset_all_options
  NAME := 
  GAMES := (Not used in any retail games)
  ID_STR := Custom F3DEX2-based microcode, github.com/Mr-Wiseguy/f3dex2 & Nintendo
  MD5_CODE := NONE
  MD5_DATA := NONE
  $(foreach option,$(ALL_OPTIONS),$(eval $(option) := 0))
endef

$(PARENT_OUTPUT_DIR):
	@printf "$(INFO)Creating parent output directory$(NO_COL)\n"
ifeq ($(OS),Windows_NT)
	@mkdir $@
else
	@mkdir -p $@
endif
ALL_UCODES :=
ALL_UCODES_WITH_MD5S :=
ALL_OUTPUT_DIRS :=

define ucode_rule
  ifeq ($(NAME),)
   $(error Microcode name has not been set!)
  endif
  UCODE_OUTPUT_DIR := $$(PARENT_OUTPUT_DIR)/$(NAME)
  ifeq ($(OS),Windows_NT)
   FULL_OUTPUT_DIR := $$(subst /,\,$$(FULL_OUTPUT_DIR))
  endif
  CODE_FILE := $$(UCODE_OUTPUT_DIR)/$(NAME).code
  DATA_FILE := $$(UCODE_OUTPUT_DIR)/$(NAME).data
  SYM_FILE  := $$(UCODE_OUTPUT_DIR)/$(NAME).sym
  TEMP_FILE := $$(UCODE_OUTPUT_DIR)/$(NAME).tmp.s
  ALL_UCODES += $(NAME)
  ifneq ($(MD5_CODE),NONE)
   ALL_UCODES_WITH_MD5S += $(NAME)
  endif
  ALL_OUTPUT_DIRS += $(UCODE_OUTPUT_DIR)
  OPTIONS_AS_EQU :=
  $(foreach option,$(ALL_OPTIONS),$(eval OPTIONS_AS_EQU += -equ $(option) $($(option))))
  ARMIPS_CMDLINE := \
   -strequ DATA_FILE $(DATA_FILE) \
   -strequ CODE_FILE $(CODE_FILE) \
   -strequ ID_STR "$(ID_STR)" \
   $(OPTIONS_AS_EQU) \
   f3dex2.s \
   -sym2 $(SYM_FILE) \
   -temp $(TEMP_FILE)
  ifeq ($(1),1)
   TARGET_NAME := custom
  else
   TARGET_NAME := $(NAME)
  endif
  # Phony target rule
  .PHONY: $(TARGET_NAME)
  $(TARGET_NAME): $(CODE_FILE) $(DATA_FILE)
  # Output directory rule
  $(UCODE_OUTPUT_DIR): | $(PARENT_OUTPUT_DIR)
  @printf "$(INFO)Creating directory: $(UCODE_OUTPUT_DIR)$(NO_COL)\n"
  ifeq ($(OS),Windows_NT)
	@mkdir $(UCODE_OUTPUT_DIR)
  else
	@mkdir -p $(UCODE_OUTPUT_DIR)
  endif
  # File build rule
  $(CODE_FILE) $(DATA_FILE) $(SYM_FILE) $(TEMP_FILE): ./f3dex2.s ./rsp/* $(UCODE_OUTPUT_DIR)
	@printf "$(INFO)Building microcode: $(NAME) for $(GAMES)$(NO_COL)\n"
	@echo $(ARMIPS) $(ARMIPS_CMDLINE)
	#@$(ARMIPS) $(ARMIPS_CMDLINE)
  ifneq ($(MD5_CODE),NONE)
	@(printf "$(MD5_CODE) *$(CODE_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(NAME) code matches$(NO_COL)\n" || printf "  $(FAILURE)$(NAME) code differs$(NO_COL)\n"
	@(printf "$(MD5_DATA) *$(DATA_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(NAME) data matches$(NO_COL)\n" || printf "  $(FAILURE)$(NAME) data differs$(NO_COL)\n"
  elifneq ($(1),1)
	@printf "  $(WARNING)MD5 sums not in database for $(NAME)$(NO_COL)\n"
  endif
  # Done
  $(eval $(call reset_all_options))
endef

$(eval $(call reset_all_options))

ifneq ("$(wildcard custom.mk)","")
  include custom.mk
  $(eval $(call ucode_rule,1))
else
  .PHONY: custom
  custom:
	@printf "To use `make custom`, create a file custom.mk containing your"
	@printf "desired configuration. See the Makefile for more details."
endif

NAME := F3DEX2_2.04H
GAMES := Kirby 64, Smash 64
ID_STR := RSP Gfx ucode F3DEX       fifo 2.04H Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := d3a58568fa7cf042de370912a47c3b5f
MD5_DATA := 6639b2fd15a73c5446aff592bb599983
CFG_OLD_TRI_WRITE := 1
CFG_EXTRA_0A_BEFORE_ID_STR := 1
CFG_G_SPECIAL_1_IS_RECALC_MVP := 1
CFG_CLIPPING_SUBDIVIDE_DESCENDING := 1
BUG_CLIPPING_FAIL_WHEN_SUM_ZERO := 1
BUG_NO_CLAMP_SCREEN_Z_POSITIVE := 1
BUG_TEXGEN_LINEAR_CLOBBER_S_T := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1
BUG_HARMLESS_TASKDONE_WRONG_ADDR := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_NoN_2.04H
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.04H Yoshitaka Yasumoto 1998 Nintendo.
CFG_NoN := 1
CFG_OLD_TRI_WRITE := 1
CFG_EXTRA_0A_BEFORE_ID_STR := 1
CFG_G_SPECIAL_1_IS_RECALC_MVP := 1
CFG_CLIPPING_SUBDIVIDE_DESCENDING := 1
BUG_CLIPPING_FAIL_WHEN_SUM_ZERO := 1
BUG_NO_CLAMP_SCREEN_Z_POSITIVE := 1
BUG_TEXGEN_LINEAR_CLOBBER_S_T := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1
BUG_HARMLESS_TASKDONE_WRONG_ADDR := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_2.07
GAMES := Rocket: Robot on Wheels
ID_STR := RSP Gfx ucode F3DEX       fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := 1523b8e38a9eae698b48909a0c0c0279
MD5_DATA := 25be72ec04e2e6a23dfa7666645f0662
BUG_HARMLESS_EXTRA_INIT_VONE := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_2.07_XBUS
GAMES := Lode Runner 3-D
ID_STR := RSP Gfx ucode F3DEX       xbus 2.07  Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := b882f402e115ffaf05a9ee44f354c441
MD5_DATA := 71436bdc62d9263d5c2fefa783cffd4f
CFG_XBUS := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1
BUG_HARMLESS_TASKDONE_WRONG_ADDR := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_NoN_2.07
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
CFG_NoN := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_2.08
GAMES := Banjo-Tooie
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := 6ccf5fc392e440fb23bc7d7f7d71047c
MD5_DATA := 3a3a406acb4295d33fa6e918dd3a7ae4
$(eval $(call ucode_rule,0))

NAME := F3DEX2_2.08_XBUS
GAMES := Power Rangers
ID_STR := RSP Gfx ucode F3DEX       xbus 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := 38cbd8ef2cd168141347047cf7ec4fba
MD5_DATA := dcb9a145381557d146683ddb853c6cfd
CFG_XBUS := 1
BUG_HARMLESS_TASKDONE_WRONG_ADDR := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_NoN_2.08
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := b5c366b55a032f232aa309cda21be3d7
MD5_DATA := 2c8dedc1b1e2fe6405c9895c4290cf2b
CFG_NoN := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_2.08PL
GAMES := Paper Mario
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := 6a5117e62e51d87020fb81dc493efcb6
MD5_DATA := 1a6b826322aab9c93da61356af5ead40
CFG_POINT_LIGHTING := 1
$(eval $(call ucode_rule,0))

NAME := F3DEX2_NoN_2.08PL
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
$(eval $(call ucode_rule,0))

NAME := F3DZEX_2.06H
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.06H Yoshitaka Yasumoto 1998 Nintendo.
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_OLD_TRI_WRITE := 1
BUG_WRONG_INIT_VZERO := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1
$(eval $(call ucode_rule,0))

NAME := F3DZEX_NoN_2.06H
GAMES := Ocarina of Time
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.06H Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := 96a1a7a8eab45e0882aab9e4d8ccbcc3
MD5_DATA := e48c7679f1224b7c0947dcd5a4d0c713
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_OLD_TRI_WRITE := 1
BUG_WRONG_INIT_VZERO := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1
$(eval $(call ucode_rule,0))

NAME := F3DZEX_2.08I
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
BUG_WRONG_INIT_VZERO := 1
$(eval $(call ucode_rule,0))

NAME := F3DZEX_NoN_2.08I
GAMES := Majora's Mask
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := ca0a31df36dbeda69f09e9850e68c7f7
MD5_DATA := d31cea0e173c6a4a09e4dfe8f259c91b
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
BUG_WRONG_INIT_VZERO := 1
$(eval $(call ucode_rule,0))

NAME := F3DZEX_2.08J
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
$(eval $(call ucode_rule,0))

NAME := F3DZEX_NoN_2.08J
GAMES := Animal Forest
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := a7f45433a67950cdd239ee40f1dd36c1
MD5_DATA := f17544afa0dce84d589ec3d8c38254c7
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
$(eval $(call ucode_rule,0))

.PHONY: default ok all clean

all: $(ALL_UCODES)

ok: $(ALL_UCODES_WITH_MD5S)

clean:
	@printf "$(WARNING)Deleting all built microcode files$(NO_COL)\n"
	@echo "rm -rf ${ALL_OUTPUT_DIRS}"
