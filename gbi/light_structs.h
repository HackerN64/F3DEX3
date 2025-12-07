#ifndef GBI_LIGHT_STRUCTS_H
#define GBI_LIGHT_STRUCTS_H

/*
 * Light types, encoded in the kc coefficient.
 */
/**
 * Standard directional light. Equivalent to kc = 0.
 */
#define LIGHT_TYPE_DIR 0
/**
 * Identifies the light as a point light, with the given kc coefficient (nonzero).
 */
#define LIGHT_TYPE_POINT(kc) kc

/**
 * Light structure.
 *
 * Note: the weird order is for the DMEM alignment benefit of
 * the microcode.
 */
typedef struct {
    unsigned char col[3];   /** diffuse light color (rgb) */
    unsigned char type;     /** formerly pad1; MUST SET TO 0 to indicate directional light */
    unsigned char colc[3];  /** copy of diffuse light color (rgb) */
    char          pad2;
    signed char   dir[3];   /** direction of light (normalized) */
    char          pad3;
    char          pad4[3];
    unsigned char size;     /** For specular only; reasonable values are 1-4 */
} Light_t;

/**
 * Light structure.
 *
 * Note: the weird order is for the DMEM alignment benefit of
 * the microcode.
 */
typedef struct {
    unsigned char col[3];   /** point light color (rgb) */
    unsigned char kc;       /** constant attenuation (> 0 indicates point light) */
    unsigned char colc[3];  /** copy of point light color (rgb) */
    unsigned char kl;       /** linear attenuation */
    short         pos[3];   /** world-space position of light */
    unsigned char kq;       /** quadratic attenuation */
    unsigned char size;     /** For specular only; reasonable values are 1-4 */
} PointLight_t;

/**
 * @copydetails PointLight_t
 */
typedef struct {
    unsigned char col[3];   /** ambient light color (rgb) */
    char          pad1;
    unsigned char colc[3];  /** copy of ambient light color (rgb) */
    char          pad2;
} Ambient_t;

typedef struct {
    signed char   dir[3];   /** direction of lookat (normalized) */
    char          pad1;
} LookAt_t;

typedef struct {
    LookAt_t      l;        /** for backwards compatibility */
} LookAtWrapper;

typedef struct {
    /* texture offsets for highlight 1/2 */
    int x1;
    int y1;
    int x2;
    int y2;
} Hilite_t;

typedef struct {
    short c0;
    short c1;
    short c2;
    short c3;
    short c4;
    short c5;
    short c6;
    short c7;
    short kx;
    short ky;
    short kz;
    short kc;
} OcclusionPlane_t;

typedef struct {
    struct {
        short x;
        short y;
        short z;
    } v[4]; /** Four vertices of a quad, XYZ components in world space */
    float weight; /** Higher if there's a lot of stuff behind it */
} OcclusionPlaneCandidate;

typedef union {
    Light_t       l;
    PointLight_t  p;
    long long int force_structure_alignment[2];
} Light;

typedef union {
    Ambient_t l;
    long long int force_structure_alignment[1];
} Ambient;

typedef union {
    LookAtWrapper l[2];
    long long int force_structure_alignment[1];
} LookAt;

typedef union {
    Hilite_t h;
    long int force_structure_alignment;
} Hilite;

typedef union {
    OcclusionPlane_t o;
    short c[12];
    long long int force_structure_alignment[3];
} OcclusionPlane;

typedef struct {
    Light   l[9];
    Ambient a;
} Lightsn;

typedef struct {
    /* F3DEX3 properly supports zero lights, unlike F3DEX2 where you need
    to include one black directional light. */
    Ambient a;
} Lights0;

typedef struct {
    Light   l[1];
    Ambient a;
} Lights1;

typedef struct {
    Light   l[2];
    Ambient a;
} Lights2;

typedef struct {
    Light   l[3];
    Ambient a;
} Lights3;

typedef struct {
    Light   l[4];
    Ambient a;
} Lights4;

typedef struct {
    Light   l[5];
    Ambient a;
} Lights5;

typedef struct {
    Light   l[6];
    Ambient a;
} Lights6;

typedef struct {
    Light   l[7];
    Ambient a;
} Lights7;

typedef struct {
    Light   l[8];
    Ambient a;
} Lights8;

typedef struct {
    Light   l[9];
    Ambient a;
} Lights9;

#endif // GBI_LIGHT_STRUCTS_H
