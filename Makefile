default: show_usage

define clear_vars
  NAME := ERROR_NAME_NOT_SET
  GAMES := 
  ID_STR := Custom F3DEX2-based microcode, github.com/Mr-Wiseguy/f3dex2 & Nintendo
  MD5_CODE := NONE
  MD5_DATA := NONE
  # With the defaults, you get 2.08, which has none of the bugs / the latest
  # versions of everything, except G_BRANCH_Z (F3DEX2), no point lighting, and
  # no NoN. Enabling the different BUG_ options *gives* you the bugs--the
  # default is always with the bugs fixed.
  CFG_G_BRANCH_W := 0
  CFG_XBUS := 0
  CFG_NoN := 0
  CFG_POINT_LIGHTING := 0
  CFG_OLD_TRI_WRITE := 0
  CFG_EXTRA_0A_BEFORE_ID_STR := 0
  CFG_G_SPECIAL_1_IS_RECALC_MVP := 0
  CFG_CLIPPING_SUBDIVIDE_DESCENDING := 0
  BUG_CLIPPING_FAIL_WHEN_SUM_ZERO := 0
  BUG_NO_CLAMP_SCREEN_Z_POSITIVE := 0
  BUG_TEXGEN_LINEAR_CLOBBER_S_T := 0
  BUG_HARMLESS_EXTRA_INIT_VONE := 0
  BUG_HARMLESS_TASKDONE_WRONG_ADDR := 0
  BUG_WRONG_INIT_VZERO := 0
endef
$(eval $(call clear_vars))

ifneq ("$(wildcard custom.mk)","")
  # This file should have defines for any settings which are not at defaults.
  # So the file should look something like:
  # NAME := your_custom_ucode_name
  # ID_STR := Modded F3DZEX by LeEtHaCkEr64 / Real N64 or RSP LLE only. NO PROJECT64
  #           ^ (this must be the exact number of characters)
  # CFG_NoN := 1
  # etc.
  include custom.mk
  $(eval $(call ucode_rule,1))
else
  custom:
	@printf "To use make custom, create a file custom.mk containing your"
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

NAME := F3DEX2_2.07
GAMES := Rocket: Robot on Wheels
ID_STR := RSP Gfx ucode F3DEX       fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := 1523b8e38a9eae698b48909a0c0c0279
MD5_DATA := 25be72ec04e2e6a23dfa7666645f0662
BUG_HARMLESS_EXTRA_INIT_VONE := 1

NAME := F3DEX2_2.07_XBUS
GAMES := Lode Runner 3-D
ID_STR := RSP Gfx ucode F3DEX       xbus 2.07  Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := b882f402e115ffaf05a9ee44f354c441
MD5_DATA := 71436bdc62d9263d5c2fefa783cffd4f
CFG_XBUS := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1
BUG_HARMLESS_TASKDONE_WRONG_ADDR := 1

NAME := F3DEX2_NoN_2.07
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
CFG_NoN := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1

NAME := F3DEX2_2.08
GAMES := Banjo-Tooie
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := 6ccf5fc392e440fb23bc7d7f7d71047c
MD5_DATA := 3a3a406acb4295d33fa6e918dd3a7ae4

NAME := F3DEX2_2.08_XBUS
GAMES := Power Rangers
ID_STR := RSP Gfx ucode F3DEX       xbus 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := 38cbd8ef2cd168141347047cf7ec4fba
MD5_DATA := dcb9a145381557d146683ddb853c6cfd
CFG_XBUS := 1
BUG_HARMLESS_TASKDONE_WRONG_ADDR := 1

NAME := F3DEX2_NoN_2.08
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := b5c366b55a032f232aa309cda21be3d7
MD5_DATA := 2c8dedc1b1e2fe6405c9895c4290cf2b
CFG_NoN := 1

NAME := F3DEX2_2.08PL
GAMES := Paper Mario
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := 6a5117e62e51d87020fb81dc493efcb6
MD5_DATA := 1a6b826322aab9c93da61356af5ead40
CFG_POINT_LIGHTING := 1

NAME := F3DEX2_NoN_2.08PL
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
CFG_NoN := 1
CFG_POINT_LIGHTING := 1

NAME := F3DZEX_2.06H
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.06H Yoshitaka Yasumoto 1998 Nintendo.
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_OLD_TRI_WRITE := 1
BUG_WRONG_INIT_VZERO := 1
BUG_HARMLESS_EXTRA_INIT_VONE := 1

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

NAME := F3DZEX_2.08I
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
BUG_WRONG_INIT_VZERO := 1

NAME := F3DZEX_NoN_2.08I
GAMES := Majora's Mask
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := ca0a31df36dbeda69f09e9850e68c7f7
MD5_DATA := d31cea0e173c6a4a09e4dfe8f259c91b
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
BUG_WRONG_INIT_VZERO := 1

NAME := F3DZEX_2.08J
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1

NAME := F3DZEX_NoN_2.08J
GAMES := Animal Forest
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := a7f45433a67950cdd239ee40f1dd36c1
MD5_DATA := f17544afa0dce84d589ec3d8c38254c7
CFG_G_BRANCH_W := 1
CFG_NoN := 1
CFG_POINT_LIGHTING := 1
