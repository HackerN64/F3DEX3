#ifndef GBI_GFX_LEGACY_H
#define GBI_GFX_LEGACY_H

typedef struct {
    int          cmd  : 8;
    unsigned int type : 8;
    unsigned int len  : 16;
    union {
        /* The exact form of this callback is intentionally left unspecified, a display list
        parser may choose the return value and parameters so long as it is consistent. */
        void       (*callback)();
        const char*  str;
        unsigned int u32;
        float        f32;
        void*        addr;
    } value;
} Gnoop;

/**
 *  Graphics DMA Packet
 */
typedef struct {
    int          cmd : 8;
    unsigned int par : 8;
    unsigned int len : 16;
    unsigned int addr;
} Gdma;

/**
 * @copydoc Gdma
 */
typedef struct {
    int          cmd : 8;
    unsigned int len : 8;
    unsigned int ofs : 8;
    unsigned int par : 8;
    unsigned int addr;
} Gdma2;

/**
 * Graphics Moveword Packet
 */
typedef struct {
    int          cmd    : 8;
    unsigned int index  : 8;
    unsigned int offset : 16;
    unsigned int data;
} Gmovewd;

/**
 * @copydetails Gmovewd
 */
typedef struct {
    int          cmd    : 8;
    unsigned int size   : 8;
    unsigned int offset : 8;
    unsigned int index  : 8;
    unsigned int data;
} Gmovemem;

/**
 * Graphics Immediate Mode Packet types
 */
typedef struct {
    int cmd : 8;
    int pad : 24;
    Tri tri;
} Gtri;

typedef struct {
    Tri tri1; /* flag is the command byte */
    Tri tri2;
} Gtri2;

typedef struct {
    Tri tri1; /* flag is the command byte */
    Tri tri2;
} Gquad;

typedef struct {
    int            cmd : 8;
    unsigned int   pad : 8;
    unsigned short vstart_x2;
    unsigned short pad2;
    unsigned short vend_x2;
} Gcull;

typedef struct {
    int            cmd : 8;
    unsigned int   pad : 24;
    unsigned short z;
    unsigned short dz;
} Gsetprimdepth;

typedef struct {
    int           cmd   : 8;
    int           pad1  : 24;
    unsigned int  param;
} Gpopmtx;

typedef struct {
    int cmd      : 8;
    int mw_index : 8;
    int pad0     : 8;
    int number   : 8;
    int pad1     : 8;
    int base     : 24;
} Gsegment;

typedef struct {
    int          cmd  : 8;
    int          pad0 : 8;
    unsigned int sft  : 8;
    unsigned int len  : 8;
    unsigned int data : 32;
} GsetothermodeL;

typedef struct {
    int          cmd  : 8;
    int          pad0 : 8;
    unsigned int sft  : 8;
    unsigned int len  : 8;
    unsigned int data : 32;
} GsetothermodeH;

typedef struct {
    unsigned char  cmd;
    unsigned char  lodscale;
    unsigned char  pad   : 2;
    unsigned char  level : 3;
    unsigned char  tile  : 3;
    unsigned char  on;
    unsigned short s;
    unsigned short t;
} Gtexture;

typedef struct {
    int       cmd  : 8;
    int       pad1 : 24;
    short int pad2;
    short int scale;
} Gperspnorm;


/**
 * RDP Packet types
 */
typedef struct {
    int          cmd : 8;
    unsigned int fmt : 3;
    unsigned int siz : 2;
    unsigned int pad : 7;
    unsigned int wd  : 12;  /* really only 10 bits, extra  */
    unsigned int dram;      /* to account for 1024  */
} Gsetimg;

typedef struct {
    int          cmd : 8;
    /* muxs0 */
    unsigned int a0  : 4;
    unsigned int c0  : 5;
    unsigned int Aa0 : 3;
    unsigned int Ac0 : 3;
    unsigned int a1  : 4;
    unsigned int c1  : 5;
    /* muxs1 */
    unsigned int b0  : 4;
    unsigned int b1  : 4;
    unsigned int Aa1 : 3;
    unsigned int Ac1 : 3;
    unsigned int d0  : 3;
    unsigned int Ab0 : 3;
    unsigned int Ad0 : 3;
    unsigned int d1  : 3;
    unsigned int Ab1 : 3;
    unsigned int Ad1 : 3;
} Gsetcombine;

typedef struct {
    int           cmd : 8;
    unsigned char pad;
    unsigned char prim_min_level;
    unsigned char prim_level;
    union {
        unsigned long color;
        struct {
            unsigned char r;
            unsigned char g;
            unsigned char b;
            unsigned char a;
        };
    };
} Gsetcolor;

typedef struct {
    int          cmd    : 8;
    int          x0     : 10;
    int          x0frac : 2;
    int          y0     : 10;
    int          y0frac : 2;
    unsigned int pad    : 8;
    int          x1     : 10;
    int          x1frac : 2;
    int          y1     : 10;
    int          y1frac : 2;
} Gfillrect;

typedef struct {
    int          cmd     : 8;
    unsigned int fmt     : 3;
    unsigned int siz     : 2;
    unsigned int pad0    : 1;
    unsigned int line    : 9;
    unsigned int tmem    : 9;
    unsigned int pad1    : 5;
    unsigned int tile    : 3;
    unsigned int palette : 4;
    unsigned int ct      : 1;
    unsigned int mt      : 1;
    unsigned int maskt   : 4;
    unsigned int shiftt  : 4;
    unsigned int cs      : 1;
    unsigned int ms      : 1;
    unsigned int masks   : 4;
    unsigned int shifts  : 4;
} Gsettile;

typedef struct {
    int          cmd  : 8;
    unsigned int sl   : 12;
    unsigned int tl   : 12;
    int          pad  : 5;
    unsigned int tile : 3;
    unsigned int sh   : 12;
    unsigned int th   : 12;
} Gloadtile;

typedef Gloadtile Gloadblock;

typedef Gloadtile Gsettilesize;

typedef Gloadtile Gloadtlut;

typedef struct {
    unsigned int cmd  : 8;  /* command                      */
    unsigned int xl   : 12; /* X coordinate of upper left   */
    unsigned int yl   : 12; /* Y coordinate of upper left   */
    unsigned int pad1 : 5;  /* Padding                      */
    unsigned int tile : 3;  /* Tile descriptor index        */
    unsigned int xh   : 12; /* X coordinate of lower right  */
    unsigned int yh   : 12; /* Y coordinate of lower right  */
    unsigned int s    : 16; /* S texture coord at top left  */
    unsigned int t    : 16; /* T texture coord at top left  */
    unsigned int dsdx : 16; /* Change in S per change in X  */
    unsigned int dtdy : 16; /* Change in T per change in Y  */
} Gtexrect;

#define MakeTexRect(xh,yh,flip,tile,xl,yl,s,t,dsdx,dtdy)        \
    G_TEXRECT, xh, yh, 0, flip, 0, tile, xl, yl, s, t, dsdx, dtdy

/**
 * Textured rectangles are 128 bits not 64 bits
 */
typedef struct {
    unsigned long w0;
    unsigned long w1;
    unsigned long w2;
    unsigned long w3;
} TexRect;

typedef struct {
    int           cmd  : 8;
    unsigned int  pad  : 4;
    unsigned int  len  : 8; /* n */
    unsigned int  pad2 : 4;
    unsigned char par;      /* v0 */
    unsigned int  addr;
} Gvtx;

/**
 * Generic Gfx Packet
 */
typedef struct {
    unsigned int w0;
    unsigned int w1;
} Gwords;

/**
 * This union is the fundamental type of the display list.
 * It is, by law, exactly 64 bits in size.
 */
typedef union {
    Gwords          words;
    Gnoop           noop;
    Gdma            dma;
    Gdma2           dma2;
    Gvtx            vtx;
    Gtri            tri;
    Gtri2           tri2;
    Gquad           quad;
    Gcull           cull;
    Gmovewd         movewd;
    Gmovemem        movemem;
    Gpopmtx         popmtx;
    Gsegment        segment;
    GsetothermodeH  setothermodeH;
    GsetothermodeL  setothermodeL;
    Gtexture        texture;
    Gperspnorm      perspnorm;
    Gsetimg         setimg;
    Gsetcombine     setcombine;
    Gsetcolor       setcolor;
    Gfillrect       fillrect;   /* use for setscissor also */
    Gsettile        settile;
    Gloadtile       loadtile;   /* use for loadblock also, th is dxt */
    Gsettilesize    settilesize;
    Gloadtlut       loadtlut;
    Gsetprimdepth   setprimdepth;
    long long int force_structure_alignment;
} Gfx;

#endif // GBI_GFX_LEGACY_H
