# Selects the microcode to assemble. Options are F3DEX2 and F3DZEX
UCODE ?= F3DEX2

# Set to 1 to enable NoN(No Nearclipping). Note that no official F3DZEX exists without NoN.
NoN ?= 0

# Selects which version of a given microcode to build:
# F3DEX2:
#  2.08  (Banjo-Tooie, the best game on the N64)
#  2.07  (Rocket: Robot on Wheels)
#  2.04H (Kirby 64, Smash 64)
#  2.08PL (Paper Mario, F3DEX2.08 with point lighting added)
#  
# F3DZEX:
#  2.08J (Animal Forest) (Recommended over 2.08I due to a change properly zeroes out $v0)
#  2.08I (Majora's Mask)
#  2.06H (Ocarina of Time)
VERSION ?= 2.08

ARMIPS ?= armips

OUTPUT_DIR ?= ./

# List of all microcodes buildable with this codebase
UCODES := F3DEX2_2.08 F3DEX2_2.07 F3DEX2_2.04H F3DEX2_2.08PL \
          F3DEX2_NoN_2.08 F3DEX2_NoN_2.07 F3DEX2_NoN_2.04H F3DEX2_NoN_2.08PL \
          F3DZEX_2.08J F3DZEX_2.08I F3DZEX_2.06H \
		      F3DZEX_NoN_2.08J F3DZEX_NoN_2.08I F3DZEX_NoN_2.06H

# F3DEX2
MD5_CODE_F3DEX2_2.08      := 6ccf5fc392e440fb23bc7d7f7d71047c
MD5_DATA_F3DEX2_2.08      := 3a3a406acb4295d33fa6e918dd3a7ae4
MD5_CODE_F3DEX2_2.08PL    := 6a5117e62e51d87020fb81dc493efcb6
MD5_DATA_F3DEX2_2.08PL    := 1a6b826322aab9c93da61356af5ead40
MD5_CODE_F3DEX2_2.07      := 1523b8e38a9eae698b48909a0c0c0279
MD5_DATA_F3DEX2_2.07      := 25be72ec04e2e6a23dfa7666645f0662
MD5_CODE_F3DEX2_NoN_2.08  := b5c366b55a032f232aa309cda21be3d7
MD5_DATA_F3DEX2_NoN_2.08  := 2c8dedc1b1e2fe6405c9895c4290cf2b
MD5_CODE_F3DEX2_2.04H     := d3a58568fa7cf042de370912a47c3b5f
MD5_DATA_F3DEX2_2.04H     := 6639b2fd15a73c5446aff592bb599983
# F3DZEX
MD5_CODE_F3DZEX_NoN_2.08J := a7f45433a67950cdd239ee40f1dd36c1
MD5_DATA_F3DZEX_NoN_2.08J := f17544afa0dce84d589ec3d8c38254c7
MD5_CODE_F3DZEX_NoN_2.08I := ca0a31df36dbeda69f09e9850e68c7f7
MD5_DATA_F3DZEX_NoN_2.08I := d31cea0e173c6a4a09e4dfe8f259c91b
MD5_CODE_F3DZEX_NoN_2.06H := 96a1a7a8eab45e0882aab9e4d8ccbcc3
MD5_DATA_F3DZEX_NoN_2.06H := e48c7679f1224b7c0947dcd5a4d0c713

# Microcode strings
# F3DEX2
NAME_F3DEX2_2.08       := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
NAME_F3DEX2_2.07       := RSP Gfx ucode F3DEX       fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
NAME_F3DEX2_2.04H      := RSP Gfx ucode F3DEX       fifo 2.04H Yoshitaka Yasumoto 1998 Nintendo.
NAME_F3DEX2_2.08PL     := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
NAME_F3DEX2_NoN_2.08   := RSP Gfx ucode F3DEX.NoN   fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
NAME_F3DEX2_NoN_2.07   := RSP Gfx ucode F3DEX.NoN   fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
NAME_F3DEX2_NoN_2.04H  := RSP Gfx ucode F3DEX.NoN   fifo 2.04H Yoshitaka Yasumoto 1998 Nintendo.
# Use the same name as no NoN so that emulators recognize it since there was no F3DEX2PL with NoN
NAME_F3DEX2_NoN_2.08PL := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
# F3DZEX
NAME_F3DZEX_2.08J      := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
NAME_F3DZEX_2.08I      := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
NAME_F3DZEX_2.06H      := RSP Gfx ucode F3DZEX.NoN  fifo 2.06H Yoshitaka Yasumoto 1998 Nintendo.
# Use the same name as NoN so that emulators recognize it since there was no F3DZEX without NoN
NAME_F3DZEX_NoN_2.08J  := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
NAME_F3DZEX_NoN_2.08I  := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
NAME_F3DZEX_NoN_2.06H  := RSP Gfx ucode F3DZEX.NoN  fifo 2.06H Yoshitaka Yasumoto 1998 Nintendo.

ID_F3DEX2_2.04H  := 0
ID_F3DEX2_2.07   := 1
ID_F3DEX2_2.08   := 2
ID_F3DEX2_2.08PL := 3

ID_F3DZEX_2.06H := 0
ID_F3DZEX_2.08I := 1
ID_F3DZEX_2.08J := 2

TYPE_F3DEX2 := 0
TYPE_F3DZEX := 1

NO_COL := \033[0m
BOLD   := # \033[1m
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m

INFO    := $(NO_COL)
SUCCESS := $(GREEN)
FAILURE := $(RED)
WARNING := $(YELLOW)

# Sets up the variables for a microcode rule
define set_vars
  FULL_UCODE := $(1)
  # These need to be eval'd to use their values in this same function
  CUR_UCODE_WITHOUT_NON := $(subst _NoN,,$(1))
  CUR_VERSION := $$(subst F3DZEX_,,$$(subst F3DEX2_,,$$(CUR_UCODE_WITHOUT_NON)))
  CUR_UCODE := $$(patsubst %_$$(CUR_VERSION),%,$$(CUR_UCODE_WITHOUT_NON))
  FULL_OUTPUT_DIR := $$(OUTPUT_DIR)/$(1)
ifeq ($(OS),Windows_NT)
  FULL_OUTPUT_DIR := $$(subst /,\,$$(FULL_OUTPUT_DIR))
endif
  CODE_FILE := $$(FULL_OUTPUT_DIR)/$(1).code
  DATA_FILE := $$(FULL_OUTPUT_DIR)/$(1).data
  SYM_FILE  := $$(FULL_OUTPUT_DIR)/$(1).sym
  TEMP_FILE := $$(FULL_OUTPUT_DIR)/$(1).tmp.s

  ifeq ($(findstring _NoN,$(1)),)
    CUR_NoN := 0
  else
    CUR_NoN := 1
  endif

  NAME := $(NAME_$(1))
  ID := $$(ID_$$(CUR_UCODE_WITHOUT_NON))
  TYPE := $$(TYPE_$$(CUR_UCODE))
  CODE_MD5 := $$(MD5_CODE_$(1))
  DATA_MD5 := $$(MD5_DATA_$(1))
endef

# Sets up the microcode make rules
define ucode_rule
  $(eval $(call set_vars,$(1)))

  $(CODE_FILE) $(DATA_FILE) $(SYM_FILE) $(SYM2_FILE) $(TEMP_FILE): ./f3dex2.s ./rsp/* $(FULL_OUTPUT_DIR)
	@printf "$(INFO)Building microcode: $(FULL_UCODE)$(NO_COL)\n"
	@$(ARMIPS) -strequ DATA_FILE $(DATA_FILE) -strequ CODE_FILE $(CODE_FILE) -strequ NAME "$(NAME)" -equ UCODE_TYPE $(TYPE) -equ UCODE_ID $(ID) -equ NoN $(CUR_NoN) f3dex2.s -sym2 $(SYM_FILE) -temp $(TEMP_FILE)
  ifeq ($(CODE_MD5),)
	@printf "  $(WARNING)Nothing to compare $(1) to!$(NO_COL)\n"
  else
	@(printf "$(CODE_MD5) *$(CODE_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(1) code matches$(NO_COL)\n" || printf "  $(FAILURE)$(1) code differs$(NO_COL)\n"
	@(printf "$(DATA_MD5) *$(DATA_FILE)" | md5sum --status -c -) && printf "  $(SUCCESS)$(1) data matches$(NO_COL)\n" || printf "  $(FAILURE)$(1) data differs$(NO_COL)\n"

  endif

  $(FULL_OUTPUT_DIR): | $(OUTPUT_DIR)
	@printf "$(INFO)Creating directory: $(FULL_OUTPUT_DIR)$(NO_COL)\n"
ifeq ($(OS),Windows_NT)
	@mkdir $(FULL_OUTPUT_DIR)
else
	@mkdir -p $(FULL_OUTPUT_DIR)
endif

  FULL_OUTPUT_DIRS += $(FULL_OUTPUT_DIR)
  CODE_FILES += $(CODE_FILE)
endef

ifeq ($(NoN),1)
  SUFFIX := _NoN
else
  SUFFIX := 
endif
INPUT_UCODE := $(UCODE)$(SUFFIX)_$(VERSION)
FULL_OUTPUT_DIR := $(OUTPUT_DIR)/$(INPUT_UCODE)
ifeq ($(OS),Windows_NT)
  FULL_OUTPUT_DIR := $(subst /,\,$(FULL_OUTPUT_DIR))
endif
CODE_FILE := $(FULL_OUTPUT_DIR)/$(INPUT_UCODE).code
DATA_FILE := $(FULL_OUTPUT_DIR)/$(INPUT_UCODE).data

default: $(CODE_FILE) $(DATA_FILE)

$(foreach ucode,$(UCODES),$(eval $(call ucode_rule,$(ucode))))

all: $(CODE_FILES)

$(OUTPUT_DIR):
	@printf "$(INFO)Creating output directory$(NO_COL)\n"
ifeq ($(OS),Windows_NT)
	@mkdir $@
else
	@mkdir -p $@
endif

clean:
	@printf "$(WARNING)Deleting all built microcode files$(NO_COL)\n"
	@rm -rf $(FULL_OUTPUT_DIRS)

.PHONY: default check all clean
