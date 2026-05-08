#include "xil_printf.h"
#include "xstatus.h"
#include "ntt_axi_accelerator.h"
#include "xparameters.h"

// 加速器基地址（替换为xparameters.h中的实际值）
#define NTT_ACCELERATOR_BASEADDR XPAR_NTT_AXI_ACCELERATOR_0_S00_AXI_BASEADDR

int main(void)
{
    XStatus status;

    // 初始化串口（用于打印日志）
    xil_printf("NTT AXI Accelerator Test Start...\n\r");

    // 步骤1：运行寄存器自测试（验证AXI通路是否正常）
    status = NTT_AXI_ACCELERATOR_Reg_SelfTest((void *)NTT_ACCELERATOR_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("Self Test Failed! \n\r");
        return XST_FAILURE;
    }
    xil_printf("Self Test Passed! \n\r");

    // 步骤2：自定义寄存器读写（验证业务逻辑）
    // 示例：向REG0写入数据，从REG0读取并验证
    u32 write_data = 0x12345678;
    NTT_AXI_ACCELERATOR_mWriteReg(NTT_ACCELERATOR_BASEADDR, NTT_AXI_ACCELERATOR_S00_AXI_SLV_REG0_OFFSET, write_data);
    u32 read_data = NTT_AXI_ACCELERATOR_mReadReg(NTT_ACCELERATOR_BASEADDR, NTT_AXI_ACCELERATOR_S00_AXI_SLV_REG0_OFFSET);

    if (read_data == write_data) {
        xil_printf("REG0 Write/Read OK: Write=0x%08X, Read=0x%08X \n\r", write_data, read_data);
    } else {
        xil_printf("REG0 Write/Read ERROR: Write=0x%08X, Read=0x%08X \n\r", write_data, read_data);
        return XST_FAILURE;
    }

    // 步骤3：扩展业务逻辑（根据你的NTT加速器功能编写）
    // 例如：配置NTT参数、启动加速计算、读取计算结果等
    // NTT_AXI_ACCELERATOR_mWriteReg(NTT_ACCELERATOR_BASEADDR, NTT_AXI_ACCELERATOR_S00_AXI_SLV_REG1_OFFSET, 0x00000001); // 启动位
    // u32 result = NTT_AXI_ACCELERATOR_mReadReg(NTT_ACCELERATOR_BASEADDR, NTT_AXI_ACCELERATOR_S00_AXI_SLV_REG2_OFFSET); // 读取结果

    xil_printf("NTT AXI Accelerator Test Finish! \n\r");
    return XST_SUCCESS;
}
