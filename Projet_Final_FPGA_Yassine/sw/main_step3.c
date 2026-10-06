/*
 * SoC Tracking - Application PS, etape 3 (image memoire par DMA)
 * Source = memoire (SRC_SEL = 0). L'image doit etre chargee en DDR par XSCT
 * a l'adresse cablee sur le DMA (image_in = 0x10000000) AVANT ce test.
 * Registres (base 0x43C00000) :
 *   0x00 MAX_VAL RO | 0x04 MAX_X RO | 0x08 MAX_Y RO
 *   0x0C THRESHOLD RW | 0x10 MODE RW(bit0) | 0x14 SRC_SEL RW(bit0)
 */
#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"

#ifdef XPAR_VIDEO_BASEADDR
  #define REG_BASE   XPAR_VIDEO_BASEADDR
#else
  #define REG_BASE   0x43C00000u
#endif

#define REG_MAX_VAL    0x00u
#define REG_MAX_X      0x04u
#define REG_MAX_Y      0x08u
#define REG_THRESHOLD  0x0Cu
#define REG_MODE       0x10u
#define REG_SRC_SEL    0x14u

#define SRC_MEMORY     0u      /* image DDR relue par le DMA (PL-IP-000) */
#define MODE_OVERLAY   1u      /* mode B : points surlignes en vert */
#define THRESHOLD_INIT 30u

static inline void reg_write(u32 off, u32 val) { Xil_Out32(REG_BASE + off, val); }
static inline u32  reg_read (u32 off)          { return Xil_In32(REG_BASE + off); }

int main(void)
{
    xil_printf("\r\n=== SoC Tracking - etape 3 (image memoire + overlay) ===\r\n");
    xil_printf("Base registres : 0x%08x\r\n", (unsigned)REG_BASE);
    xil_printf("Rappel : image a charger en DDR (XSCT) avant ce test.\r\n");

    reg_write(REG_THRESHOLD, THRESHOLD_INIT);
    reg_write(REG_MODE,      MODE_OVERLAY);
    reg_write(REG_SRC_SEL,   SRC_MEMORY);

    xil_printf("Config : SRC_SEL=%u  MODE=%u  THRESHOLD=%u\r\n",
               (unsigned)(reg_read(REG_SRC_SEL) & 1u),
               (unsigned)(reg_read(REG_MODE) & 1u),
               (unsigned)reg_read(REG_THRESHOLD));
    xil_printf("Lecture du maximum :\r\n");

    for (;;) {
        u32 v = reg_read(REG_MAX_VAL);
        u32 x = reg_read(REG_MAX_X);
        u32 y = reg_read(REG_MAX_Y);
        xil_printf("  max=%4u  a (x=%3u, y=%3u)\r\n",
                   (unsigned)v, (unsigned)x, (unsigned)y);
        sleep(1);
    }
    return 0;
}
