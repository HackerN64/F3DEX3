

#ifndef GBI_GFX_MODERN_H
#define GBI_GFX_MODERN_H

/**
 * TODO
 * This replaces the legacy union definition of Gfx. The problems with that are:
 * - The union members were rarely used; the GBI was almost always accessed via
 *   gDP, gsDP, etc. macros.
 * - The union members were not kept up-to-date with macro changes.
 * - Using the union version requires extra braces in modern C unless you
 *   disable a warning.
 * 
 * Of course, the IDO compiler will not accept this, and some decomp codebase
 * somewhere might use the union members.
 * 
 * One other note, _Alignas(8) does not work, C11 prohibits that on typedefs.
 * But GCC allows the attribute version and does enforce the alignment.
*/

typedef __attribute__((aligned(8))) struct {
    unsigned int w0;
    unsigned int w1;
} GfxStatic;
_Static_assert(_Alignof(GfxStatic) == 8, "Gfx struct alignment broken");

typedef union {
    struct {
        unsigned int w0;
        unsigned int w1;
    } words;
    unsigned long long align8;
} Gfx;

#endif // GBI_GFX_MODERN_H
