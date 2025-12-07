#ifndef GBI_MACRO_BASE_H
#define GBI_MACRO_BASE_H

#ifdef REQUIRE_SEMICOLONS_AFTER_GBI_COMMANDS
/* OoT style, semicolons required after using macros, cleaner code. If modding
SM64, will have to fix a few places the codebase omits the semicolons. */
#define _DW(macro) do {macro} while (0)
#else
/* SM64 style, semicolons optional, uglier code, will produce tens of thousands
of warnings if you use -Wpedantic. */
#define _DW(macro) macro
#endif

/*
 * Macros to assemble the graphics display list
 */

/*
 * Command where only the first word (containing the command byte) is used,
 * saving one CPU instruction to write the second word as zero.
 */
#define g1Word(pkt, c, l)                   \
_DW({                                       \
    Gfx *_g = (Gfx *)(pkt);                 \
    _g->words.w0 = (_SHIFTL((c), 24,  8) |  \
                    _SHIFTL((l),  0, 24));  \
})
/*
 * The static version has to fill in the second word with something.
 */
#define gs1Word(c, l)       \
{                           \
   (_SHIFTL((c), 24,  8) |  \
    _SHIFTL((l),  0, 24)),  \
    0                       \
}

/*
 * DMA macros
 */
#define gDma0p(pkt, c, s, l)                \
_DW({                                       \
    Gfx *_g = (Gfx *)(pkt);                 \
                                            \
    _g->words.w0 = (_SHIFTL((c), 24,  8) |  \
                    _SHIFTL((l),  0, 24));  \
    _g->words.w1 = (unsigned int)(s);       \
})

#define gsDma0p(c, s, l)    \
{                           \
   (_SHIFTL((c), 24,  8) |  \
    _SHIFTL((l),  0, 24)),  \
    (unsigned int)(s)       \
}

#define gDma1p(pkt, c, s, l, p)             \
_DW({                                       \
    Gfx *_g = (Gfx *)(pkt);                 \
                                            \
    _g->words.w0 = (_SHIFTL((c), 24,  8) |  \
                    _SHIFTL((p), 16,  8) |  \
                    _SHIFTL((l),  0, 16));  \
    _g->words.w1 = (unsigned int)(s);       \
})

#define gsDma1p(c, s, l, p) \
{                           \
   (_SHIFTL((c), 24,  8) |  \
    _SHIFTL((p), 16,  8) |  \
    _SHIFTL((l),  0, 16)),  \
    (unsigned int)(s)       \
}

#define gDma2p(pkt, c, adrs, len, idx, ofs)             \
_DW({                                                   \
    Gfx *_g = (Gfx *)(pkt);                             \
                                                        \
    _g->words.w0 = (_SHIFTL((c),             24, 8) |   \
                    _SHIFTL(((len) - 1) / 8, 19, 5) |   \
                    _SHIFTL((ofs) / 8,        8, 9) |   \
                    _SHIFTL((idx),            0, 5));   \
    _g->words.w1 = (unsigned int)(adrs);                \
})

#define gsDma2p(c, adrs, len, idx, ofs) \
{                                       \
   (_SHIFTL((c),             24, 8) |   \
    _SHIFTL(((len) - 1) / 8, 19, 5) |   \
    _SHIFTL((ofs) / 8,        8, 9) |   \
    _SHIFTL((idx),            0, 5)),   \
    (unsigned int)(adrs)                \
}

/*
 * RSP short command (no DMA required) macros
 */

#define gImmp1(pkt, c, p0)              \
_DW({                                   \
    Gfx *_g = (Gfx *)(pkt);             \
                                        \
    _g->words.w0 = _SHIFTL((c), 24, 8); \
    _g->words.w1 = (unsigned int)(p0);  \
})

#define gsImmp1(c, p0)      \
{                           \
    _SHIFTL((c), 24, 8),    \
    (unsigned int)(p0)      \
}


#define gDPNoParam(pkt, cmd)   g1Word(pkt, cmd, 0)
#define gsDPNoParam(cmd)      gs1Word(     cmd, 0)

#define gDPParam(pkt, cmd, param)       \
_DW({                                   \
    Gfx *_g = (Gfx *)(pkt);             \
                                        \
    _g->words.w0 = _SHIFTL(cmd, 24, 8); \
    _g->words.w1 = (param);             \
})

#define gsDPParam(cmd, param)   \
{                               \
    _SHIFTL(cmd, 24, 8),        \
    (param)                     \
}

#endif // GBI_MACRO_BASE_H
