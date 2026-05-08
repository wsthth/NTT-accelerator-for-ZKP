#include "xil_printf.h"
#include "xil_io.h"
#include "xparameters.h"

// 你的 NTT 加速器基地址
#define NTT_BASE XPAR_NTT_AXI_ACCELERATOR_0_S00_AXI_BASEADDR

int main()
{
    // ↓↓↓ 这一句一定会打印！！！ ↓↓↓
    xil_printf("===================================\r\n");
    xil_printf("   NTT AXI 测试开始！\r\n");
    xil_printf("===================================\r\n");
    print("Hello World\n\r");
    // 测试寄存器读写
    Xil_Out32(NTT_BASE, 0x12345678);
    int read = Xil_In32(NTT_BASE);

    xil_printf("写入: 0x12345678\r\n");
    xil_printf("读出: 0x%08X\r\n", read);

    if (read == 0x12345678) {
        xil_printf("\r\n✅ AXI 通信成功！NTT 加速器正常！\r\n");
    } else {
        xil_printf("\r\n❌ 通信失败\r\n");
    }

    // 死循环，保证程序不退出
    while (1);
    return 0;
}
