#include "xil_printf.h"
#include "xuartps.h"
#include "xparameters.h"

int main()
{
    // 手动初始化 UART1
    XUartPs Uart;
    XUartPs_Config *Config = XUartPs_LookupConfig(XPAR_PS7_UART_1_DEVICE_ID);
    XUartPs_CfgInitialize(&Uart, Config, Config->BaseAddress);
    XUartPs_SetBaudRate(&Uart, 115200); // 改成你 Vivado 里的波特率

    // 直接用 UART 发送字符串，绕过 xil_printf 的潜在问题
    XUartPs_Send(&Uart, (u8*)"Hello from UART1!\r\n", 18);

    while(1);
    return 0;
}
