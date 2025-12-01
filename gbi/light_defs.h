#ifndef GBI_LIGHT_DEFS_H
#define GBI_LIGHT_DEFS_H

#define gDefAmbient(r, g, b)    \
    {{                          \
        { (r), (g), (b) }, 0,   \
        { (r), (g), (b) }, 0,   \
    }}

#define gDefLight(r, g, b, x, y, z) \
    {{                              \
        { (r), (g), (b) }, 0,       \
        { (r), (g), (b) }, 0,       \
        { (x), (y), (z) }, 0,       \
        {  0,   0,   0  }, 0,       \
    }}

#define gdSPDefLights0(ar, ag, ab)                  \
        {                                           \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights1(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights2(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights3(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2)      \
                       r3, g3, b3, x3, y3, z3)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
                gDefLight(r3, g3, b3, x3, y3, z3),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights4(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2,      \
                       r3, g3, b3, x3, y3, z3,      \
                       r4, g4, b4, x4, y4, z4)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
                gDefLight(r3, g3, b3, x3, y3, z3),  \
                gDefLight(r4, g4, b4, x4, y4, z4),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights5(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2,      \
                       r3, g3, b3, x3, y3, z3,      \
                       r4, g4, b4, x4, y4, z4,      \
                       r5, g5, b5, x5, y5, z5)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
                gDefLight(r3, g3, b3, x3, y3, z3),  \
                gDefLight(r4, g4, b4, x4, y4, z4),  \
                gDefLight(r5, g5, b5, x5, y5, z5),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights6(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2,      \
                       r3, g3, b3, x3, y3, z3,      \
                       r4, g4, b4, x4, y4, z4,      \
                       r5, g5, b5, x5, y5, z5,      \
                       r6, g6, b6, x6, y6, z6)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
                gDefLight(r3, g3, b3, x3, y3, z3),  \
                gDefLight(r4, g4, b4, x4, y4, z4),  \
                gDefLight(r5, g5, b5, x5, y5, z5),  \
                gDefLight(r6, g6, b6, x6, y6, z6),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights7(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2,      \
                       r3, g3, b3, x3, y3, z3,      \
                       r4, g4, b4, x4, y4, z4,      \
                       r5, g5, b5, x5, y5, z5,      \
                       r6, g6, b6, x6, y6, z6,      \
                       r7, g7, b7, x7, y7, z7)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
                gDefLight(r3, g3, b3, x3, y3, z3),  \
                gDefLight(r4, g4, b4, x4, y4, z4),  \
                gDefLight(r5, g5, b5, x5, y5, z5),  \
                gDefLight(r6, g6, b6, x6, y6, z6),  \
                gDefLight(r7, g7, b7, x7, y7, z7),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights8(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2,      \
                       r3, g3, b3, x3, y3, z3,      \
                       r4, g4, b4, x4, y4, z4,      \
                       r5, g5, b5, x5, y5, z5,      \
                       r6, g6, b6, x6, y6, z6,      \
                       r7, g7, b7, x7, y7, z7,      \
                       r8, g8, b8, x8, y8, z8)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
                gDefLight(r3, g3, b3, x3, y3, z3),  \
                gDefLight(r4, g4, b4, x4, y4, z4),  \
                gDefLight(r5, g5, b5, x5, y5, z5),  \
                gDefLight(r6, g6, b6, x6, y6, z6),  \
                gDefLight(r7, g7, b7, x7, y7, z7),  \
                gDefLight(r8, g8, b8, x8, y8, z8),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gdSPDefLights9(ar, ag, ab,                  \
                       r1, g1, b1, x1, y1, z1,      \
                       r2, g2, b2, x2, y2, z2,      \
                       r3, g3, b3, x3, y3, z3,      \
                       r4, g4, b4, x4, y4, z4,      \
                       r5, g5, b5, x5, y5, z5,      \
                       r6, g6, b6, x6, y6, z6,      \
                       r7, g7, b7, x7, y7, z7,      \
                       r8, g8, b8, x8, y8, z8,      \
                       r9, g9, b9, x9, y9, z9)      \
        {                                           \
            {                                       \
                gDefLight(r1, g1, b1, x1, y1, z1),  \
                gDefLight(r2, g2, b2, x2, y2, z2),  \
                gDefLight(r3, g3, b3, x3, y3, z3),  \
                gDefLight(r4, g4, b4, x4, y4, z4),  \
                gDefLight(r5, g5, b5, x5, y5, z5),  \
                gDefLight(r6, g6, b6, x6, y6, z6),  \
                gDefLight(r7, g7, b7, x7, y7, z7),  \
                gDefLight(r8, g8, b8, x8, y8, z8),  \
                gDefLight(r9, g9, b9, x9, y9, z9),  \
            },                                      \
            gDefAmbient(ar, ag, ab),                \
        }

#define gDefPointLight(r, g, b, x, y, z, kc, kl, kq)    \
    {{                                                  \
        { (r1), (g1), (b1) }, (kc),                     \
        { (r1), (g1), (b1) }, (kl),                     \
        { (x1), (y1), (z1) }, (kq),                     \
        0,                                              \
    }}

#define gdSPDefPointLights0(ar, ag, ab)                     \
        {                                                   \
            gDefAmbient(ar, ag, ab),                        \
        }

#define gdSPDefPointLights1(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights2(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights3(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2,     \
                            r3, g3, b3, x3, y3, z3, c3, l3, q3)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
                gDefPointLight(r3, g3, b3, x3, y3, z3, c3, l3, q3), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights4(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2,     \
                            r3, g3, b3, x3, y3, z3, c3, l3, q3,     \
                            r4, g4, b4, x4, y4, z4, c4, l4, q4)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
                gDefPointLight(r3, g3, b3, x3, y3, z3, c3, l3, q3), \
                gDefPointLight(r4, g4, b4, x4, y4, z4, c4, l4, q4), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights5(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2,     \
                            r3, g3, b3, x3, y3, z3, c3, l3, q3,     \
                            r4, g4, b4, x4, y4, z4, c4, l4, q4,     \
                            r5, g5, b5, x5, y5, z5, c5, l5, q5)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
                gDefPointLight(r3, g3, b3, x3, y3, z3, c3, l3, q3), \
                gDefPointLight(r4, g4, b4, x4, y4, z4, c4, l4, q4), \
                gDefPointLight(r5, g5, b5, x5, y5, z5, c5, l5, q5), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights6(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2,     \
                            r3, g3, b3, x3, y3, z3, c3, l3, q3,     \
                            r4, g4, b4, x4, y4, z4, c4, l4, q4,     \
                            r5, g5, b5, x5, y5, z5, c5, l5, q5,     \
                            r6, g6, b6, x6, y6, z6, c6, l6, q6)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
                gDefPointLight(r3, g3, b3, x3, y3, z3, c3, l3, q3), \
                gDefPointLight(r4, g4, b4, x4, y4, z4, c4, l4, q4), \
                gDefPointLight(r5, g5, b5, x5, y5, z5, c5, l5, q5), \
                gDefPointLight(r6, g6, b6, x6, y6, z6, c6, l6, q6), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights7(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2,     \
                            r3, g3, b3, x3, y3, z3, c3, l3, q3,     \
                            r4, g4, b4, x4, y4, z4, c4, l4, q4,     \
                            r5, g5, b5, x5, y5, z5, c5, l5, q5,     \
                            r6, g6, b6, x6, y6, z6, c6, l6, q6,     \
                            r7, g7, b7, x7, y7, z7, c7, l7, q7)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
                gDefPointLight(r3, g3, b3, x3, y3, z3, c3, l3, q3), \
                gDefPointLight(r4, g4, b4, x4, y4, z4, c4, l4, q4), \
                gDefPointLight(r5, g5, b5, x5, y5, z5, c5, l5, q5), \
                gDefPointLight(r6, g6, b6, x6, y6, z6, c6, l6, q6), \
                gDefPointLight(r7, g7, b7, x7, y7, z7, c7, l7, q7), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights8(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2,     \
                            r3, g3, b3, x3, y3, z3, c3, l3, q3,     \
                            r4, g4, b4, x4, y4, z4, c4, l4, q4,     \
                            r5, g5, b5, x5, y5, z5, c5, l5, q5,     \
                            r6, g6, b6, x6, y6, z6, c6, l6, q6,     \
                            r7, g7, b7, x7, y7, z7, c7, l7, q7,     \
                            r8, g8, b8, x8, y8, z8, c8, l8, q8)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
                gDefPointLight(r3, g3, b3, x3, y3, z3, c3, l3, q3), \
                gDefPointLight(r4, g4, b4, x4, y4, z4, c4, l4, q4), \
                gDefPointLight(r5, g5, b5, x5, y5, z5, c5, l5, q5), \
                gDefPointLight(r6, g6, b6, x6, y6, z6, c6, l6, q6), \
                gDefPointLight(r7, g7, b7, x7, y7, z7, c7, l7, q7), \
                gDefPointLight(r8, g8, b8, x8, y8, z8, c8, l8, q8), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefPointLights9(ar, ag, ab,                             \
                            r1, g1, b1, x1, y1, z1, c1, l1, q1,     \
                            r2, g2, b2, x2, y2, z2, c2, l2, q2,     \
                            r3, g3, b3, x3, y3, z3, c3, l3, q3,     \
                            r4, g4, b4, x4, y4, z4, c4, l4, q4,     \
                            r5, g5, b5, x5, y5, z5, c5, l5, q5,     \
                            r6, g6, b6, x6, y6, z6, c6, l6, q6,     \
                            r7, g7, b7, x7, y7, z7, c7, l7, q7,     \
                            r8, g8, b8, x8, y8, z8, c8, l8, q8,     \
                            r9, g9, b9, x9, y9, z9, c9, l9, q9)     \
        {                                                           \
            {                                                       \
                gDefPointLight(r1, g1, b1, x1, y1, z1, c1, l1, q1), \
                gDefPointLight(r2, g2, b2, x2, y2, z2, c2, l2, q2), \
                gDefPointLight(r3, g3, b3, x3, y3, z3, c3, l3, q3), \
                gDefPointLight(r4, g4, b4, x4, y4, z4, c4, l4, q4), \
                gDefPointLight(r5, g5, b5, x5, y5, z5, c5, l5, q5), \
                gDefPointLight(r6, g6, b6, x6, y6, z6, c6, l6, q6), \
                gDefPointLight(r7, g7, b7, x7, y7, z7, c7, l7, q7), \
                gDefPointLight(r8, g8, b8, x8, y8, z8, c8, l8, q8), \
                gDefPointLight(r9, g9, b9, x9, y9, z9, c9, l9, q9), \
            },                                                      \
            gDefAmbient(ar, ag, ab),                                \
        }

#define gdSPDefLookAt(rightx, righty, rightz, upx, upy, upz)    \
    {                                                           \
        {{{ rightx, righty, rightz }, 0 }},                     \
        {{{ upx, upy, upz }, 0 }},                              \
    }

#endif // GBI_LIGHT_DEFS_H
