/* This is a crazy optimization, and it was completely accidental!
When G_RELSEGMENT was implemented, we did not notice the G_MOVEWORD behavior of
subtracting (G_MOVEWORD << 8) from the movewordTable address in order to remove
the command byte. Since the command byte is G_RELSEGMENT, not G_MOVEWORD, the
final address is completely wrong. However, DMEM wraps at 4 KiB--only the lowest
4 bits of any address are significant. And, G_RELSEGMENT **happened** to end in
0xB, the same as G_MOVEWORD! So the wrong address aliases to the correct one!
I only noticed this when I tried to move G_RELSEGMENT to a different command
byte and got crashes. */
.if (G_RELSEGMENT & 0xF) != (G_MOVEWORD & 0xF)
    .error "Crazy relsegment optimization broken, don't change command byte assignments"
.endif
G_RELSEGMENT_handler: // 9
    jal     segmented_to_physical    // Resolve new segment address relative to existing segment
G_MOVEWORD_handler:
     srl    $2, cmd_w0, 16           // load the moveword command and word index into $2 (e.g. 0xDB06 for G_MW_SEGMENT)
    lhu     $10, (movewordTable - ((G_MOVEWORD & 0xF) << 8))($2) // subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
do_moveword:
    sll     $11, cmd_w0, 16          // Sign bit = upper bit of offset
    add     $10, $10, cmd_w0         // Offset + base; only lower 12 bits matter
    bltz    $11, run_next_DL_command // If upper bit of offset is set, exit after halfword
     sh     cmd_w1_dram, ($10)       // Store value from cmd into halfword
    j       run_next_DL_command
     sw     cmd_w1_dram, ($10)       // Store value from cmd into word (offset + moveword_table[index])
