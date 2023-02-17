NAME := F3DEX2_2.04H
DESCRIPTION := Kirby 64, Smash 64
ID_STR := RSP Gfx ucode F3DEX       fifo 2.04H Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := d3a58568fa7cf042de370912a47c3b5f
MD5_DATA := 6639b2fd15a73c5446aff592bb599983
OPTIONS := \
  CFG_OLD_TRI_WRITE \
  CFG_EXTRA_0A_BEFORE_ID_STR \
  CFG_G_SPECIAL_1_IS_RECALC_MVP \
  CFG_CLIPPING_SUBDIVIDE_DESCENDING \
  CFG_DONT_SKIP_FIRST_INSTR_NEW_UCODE \
  BUG_CLIPPING_FAIL_WHEN_SUM_ZERO \
  BUG_NO_CLAMP_SCREEN_Z_POSITIVE \
  BUG_TEXGEN_LINEAR_CLOBBER_S_T \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
$(eval $(call ucode_rule))

NAME := F3DEX2_NoN_2.04H
DESCRIPTION := Not in retail games; NoN added to F3DEX2_2.04H
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.04H Yoshitaka Yasumoto 1998 Nintendo.
OPTIONS := \
  CFG_NoN \
  CFG_OLD_TRI_WRITE \
  CFG_EXTRA_0A_BEFORE_ID_STR \
  CFG_G_SPECIAL_1_IS_RECALC_MVP \
  CFG_CLIPPING_SUBDIVIDE_DESCENDING \
  CFG_DONT_SKIP_FIRST_INSTR_NEW_UCODE \
  BUG_CLIPPING_FAIL_WHEN_SUM_ZERO \
  BUG_NO_CLAMP_SCREEN_Z_POSITIVE \
  BUG_TEXGEN_LINEAR_CLOBBER_S_T \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
$(eval $(call ucode_rule))

NAME := F3DEX2_2.07
DESCRIPTION := Rocket: Robot on Wheels
ID_STR := RSP Gfx ucode F3DEX       fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := 1523b8e38a9eae698b48909a0c0c0279
MD5_DATA := 25be72ec04e2e6a23dfa7666645f0662
OPTIONS := \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
$(eval $(call ucode_rule))

NAME := F3DEX2_2.07_XBUS
DESCRIPTION := Lode Runner 3-D
ID_STR := RSP Gfx ucode F3DEX       xbus 2.07  Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := b882f402e115ffaf05a9ee44f354c441
MD5_DATA := 71436bdc62d9263d5c2fefa783cffd4f
OPTIONS := \
  CFG_XBUS \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
$(eval $(call ucode_rule))

NAME := F3DEX2_NoN_2.07
DESCRIPTION := Not in retail games; NoN added to F3DEX2_2.07
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.07  Yoshitaka Yasumoto 1998 Nintendo.
OPTIONS := \
  CFG_NoN \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
$(eval $(call ucode_rule))

NAME := F3DEX2_2.08
DESCRIPTION := Banjo-Tooie
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := 6ccf5fc392e440fb23bc7d7f7d71047c
MD5_DATA := 3a3a406acb4295d33fa6e918dd3a7ae4
OPTIONS := 
$(eval $(call ucode_rule))

NAME := F3DEX2_2.08_XBUS
DESCRIPTION := Power Rangers
ID_STR := RSP Gfx ucode F3DEX       xbus 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := 38cbd8ef2cd168141347047cf7ec4fba
MD5_DATA := dcb9a145381557d146683ddb853c6cfd
OPTIONS := \
  CFG_XBUS
$(eval $(call ucode_rule))

NAME := F3DEX2_NoN_2.08
DESCRIPTION := Not in retail games; NoN added to F3DEX2_2.08
ID_STR := RSP Gfx ucode F3DEX.NoN   fifo 2.08  Yoshitaka Yasumoto 1999 Nintendo.
MD5_CODE := b5c366b55a032f232aa309cda21be3d7
MD5_DATA := 2c8dedc1b1e2fe6405c9895c4290cf2b
OPTIONS := \
  CFG_NoN
$(eval $(call ucode_rule))

NAME := F3DEX2_2.08PL
DESCRIPTION := Paper Mario
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := 6a5117e62e51d87020fb81dc493efcb6
MD5_DATA := 1a6b826322aab9c93da61356af5ead40
OPTIONS := \
  CFG_POINT_LIGHTING
$(eval $(call ucode_rule))

NAME := F3DEX2_NoN_2.08PL
DESCRIPTION := Not in retail games; NoN added to F3DEX2_2.08PL
ID_STR := RSP Gfx ucode F3DEX       fifo 2.08  Yoshitaka Yasumoto/Kawasedo 1999.
OPTIONS := \
  CFG_NoN \
  CFG_POINT_LIGHTING
$(eval $(call ucode_rule))

NAME := F3DZEX_2.06H
DESCRIPTION := Not in retail games; nearclipping added to F3DZEX_NoN_2.06H
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.06H Yoshitaka Yasumoto 1998 Nintendo.
OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_OLD_TRI_WRITE \
  BUG_WRONG_INIT_VZERO \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
$(eval $(call ucode_rule))

NAME := F3DZEX_NoN_2.06H
DESCRIPTION := Ocarina of Time
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.06H Yoshitaka Yasumoto 1998 Nintendo.
MD5_CODE := 96a1a7a8eab45e0882aab9e4d8ccbcc3
MD5_DATA := e48c7679f1224b7c0947dcd5a4d0c713
OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_NoN \
  CFG_OLD_TRI_WRITE \
  BUG_WRONG_INIT_VZERO \
  BUG_FAIL_IF_CARRY_SET_AT_INIT
$(eval $(call ucode_rule))

NAME := F3DZEX_2.08I
DESCRIPTION := Not in retail games; nearclipping added to F3DZEX_NoN_2.08I
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_POINT_LIGHTING \
  BUG_WRONG_INIT_VZERO
$(eval $(call ucode_rule))

NAME := F3DZEX_NoN_2.08I
DESCRIPTION := Majora's Mask
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08I Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := ca0a31df36dbeda69f09e9850e68c7f7
MD5_DATA := d31cea0e173c6a4a09e4dfe8f259c91b
OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_NoN \
  CFG_POINT_LIGHTING \
  BUG_WRONG_INIT_VZERO
$(eval $(call ucode_rule))

NAME := F3DZEX_2.08J
DESCRIPTION := Not in retail games; nearclipping added to F3DZEX_NoN_2.08J
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_POINT_LIGHTING
$(eval $(call ucode_rule))

NAME := F3DZEX_NoN_2.08J
DESCRIPTION := Animal Forest
ID_STR := RSP Gfx ucode F3DZEX.NoN  fifo 2.08J Yoshitaka Yasumoto/Kawasedo 1999.
MD5_CODE := a7f45433a67950cdd239ee40f1dd36c1
MD5_DATA := f17544afa0dce84d589ec3d8c38254c7
OPTIONS := \
  CFG_G_BRANCH_W \
  CFG_NoN \
  CFG_POINT_LIGHTING
$(eval $(call ucode_rule))
