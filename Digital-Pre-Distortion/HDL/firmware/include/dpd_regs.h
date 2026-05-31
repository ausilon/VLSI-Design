#ifndef DPD_REGS_H
#define DPD_REGS_H

#include <stdint.h>

#define DPD_BASE              0x40000000u

#define DPD_CONTROL           (*(volatile uint32_t *)(DPD_BASE + 0x000u))
#define DPD_STATUS            (*(volatile uint32_t *)(DPD_BASE + 0x004u))
#define DPD_IRQ_STATUS        (*(volatile uint32_t *)(DPD_BASE + 0x008u))
#define DPD_IRQ_MASK          (*(volatile uint32_t *)(DPD_BASE + 0x00Cu))

#define DPD_METRIC_POWER      (*(volatile uint32_t *)(DPD_BASE + 0x010u))
#define DPD_METRIC_ERROR      (*(volatile uint32_t *)(DPD_BASE + 0x014u))
#define DPD_METRIC_CLIPPING   (*(volatile uint32_t *)(DPD_BASE + 0x018u))
#define DPD_METRIC_DRIFT      (*(volatile uint32_t *)(DPD_BASE + 0x01Cu))

#define DPD_THRESH_ERROR      (*(volatile uint32_t *)(DPD_BASE + 0x020u))
#define DPD_THRESH_CLIP       (*(volatile uint32_t *)(DPD_BASE + 0x024u))
#define DPD_THRESH_DRIFT      (*(volatile uint32_t *)(DPD_BASE + 0x028u))

#define DPD_COEF_ADDR         (*(volatile uint32_t *)(DPD_BASE + 0x030u))
#define DPD_COEF_WDATA        (*(volatile uint32_t *)(DPD_BASE + 0x034u))
#define DPD_COEF_CTRL         (*(volatile uint32_t *)(DPD_BASE + 0x038u))
#define DPD_COEF_RDATA_A      (*(volatile uint32_t *)(DPD_BASE + 0x03Cu))
#define DPD_COEF_RDATA_B      (*(volatile uint32_t *)(DPD_BASE + 0x040u))

#define DPD_CAPTURE_CTRL      (*(volatile uint32_t *)(DPD_BASE + 0x050u))
#define DPD_DELAY_CTRL        (*(volatile uint32_t *)(DPD_BASE + 0x054u))

#define DPD_CTRL_ENABLE       (1u << 0)
#define DPD_CTRL_FORCE_BYPASS (1u << 1)
#define DPD_CTRL_CAPTURE      (1u << 2)  /* W1P */
#define DPD_CTRL_COEF_SWITCH  (1u << 3)  /* W1P */
#define DPD_CTRL_IRQ_CLEAR    (1u << 4)  /* W1P */

#define DPD_STATUS_ACTIVE     (1u << 0)
#define DPD_STATUS_CAP_BUSY   (1u << 1)
#define DPD_STATUS_CAP_DONE   (1u << 2)
#define DPD_STATUS_SW_BUSY    (1u << 3)
#define DPD_STATUS_BANK       (1u << 4)
#define DPD_STATUS_IRQ        (1u << 5)

#define DPD_IRQ_CAPTURE_DONE  (1u << 0)
#define DPD_IRQ_COEF_SWITCH   (1u << 1)
#define DPD_IRQ_RETRAIN_REQ   (1u << 2)

static inline void dpd_write_coef_a(uint32_t addr, uint32_t data)
{
    DPD_COEF_ADDR = addr;
    DPD_COEF_WDATA = data;
    DPD_COEF_CTRL = 1u;
}

static inline void dpd_write_coef_b(uint32_t addr, uint32_t data)
{
    DPD_COEF_ADDR = addr;
    DPD_COEF_WDATA = data;
    DPD_COEF_CTRL = 2u;
}

static inline void dpd_request_bank_switch(void)
{
    DPD_CONTROL = DPD_CTRL_ENABLE | DPD_CTRL_COEF_SWITCH;
}

#endif
