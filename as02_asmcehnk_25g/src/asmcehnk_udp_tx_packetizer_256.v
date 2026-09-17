`timescale 1ns / 1ps
////////////////////////////////////English///////////////////////////////////////
// Company:			Erie
// Engineer:		Erie
//
// Create Date: 	2026/07/28 18:24:28
// Design Name: 	asmcehnk_udp_tx_packetizer_256
// Module Name: 	asmcehnk_udp_tx_packetizer_256
// Description: 	Description/asmcehnk_udp_tx_packetizer_256_Design.pdf
// Dependencies:	None
// Simulations:		TestBench/Vivado/2021.1/asmcehnk_udp_tx_packetizer_256
//
// Referrences:		None
//
//
// Version:			V1.0
// Revision Date:	2026/07/28 18:24:28
// History:
//    Time			   Version	   Revised by			Contents
// 2026/07/28			V1.0		 Erie		Create file.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:		Erie
// 开发人员:		Erie
//
// 创建日期: 		2026年07月28日
// 设计名称: 		asmcehnk_udp_tx_packetizer_256
// 模块名称: 		asmcehnk_udp_tx_packetizer_256
// 模块说明:		Description/asmcehnk_udp_tx_packetizer_256_Design.pdf
// 依赖文件:		None
// 仿真工程: 		TestBench/Vivado/2021.1/asmcehnk_udp_tx_packetizer_256
//
// 参考资料:		None
//
//
// 当前版本:		V1.0
// 修订日期:		2026年07月28日
// 修订历史:
//	时间			    版本		修订人				修订内容
// 2026年07月28日		V1.0		 Erie		创建文件
module asmcehnk_udp_tx_packetizer_256
#(
	parameter C_MAX_WORDS = 32'd32,             // 单个UDP负载最多容纳的256位字数
	parameter C_IDLE_CYCLES = 32'd16            // 判定当前响应结束所需的连续空闲周期
)
(
	//-----------------全局信号-----------------//
	input i_clk,                                // SFP1网络域时钟
	input i_rstn,                               // 网络域低有效复位

	//---------------用户输入接口---------------//
	input [255:0]i_data,                        // asmcehnk复用器输出的256位响应字
	input i_data_valid,                         // 当前响应字有效指示
	output o_data_ready,                        // 允许asmcehnk继续产生响应字

	//-------------AXIS负载输出接口-------------//

	//AXIS接口
	output o_axis_tvalid,                       // UDP负载字有效指示
	input i_axis_tready,                        // 下游帧FIFO接收许可
	output o_axis_tlast,                        // 当前UDP负载帧结束指示
	output [255:0]o_axis_tdata,                 // 尚未降宽的UDP负载数据
	output [31:0]o_axis_tkeep,                  // 每个256位响应字的字节有效掩码

	//------------长度描述符输出接口------------//

	//DESC接口
	output [15:0]o_desc_length,                 // 包含8字节UDP头的报文长度
	output o_desc_valid,                        // 长度描述符与最后负载字同时提交
	input i_desc_ready                          // 描述符FIFO接收许可
);

	//---------------配置参数区域---------------//
	localparam CNT_WORD_WIDTH = $clog2(C_MAX_WORDS + 1); // 帧内256位字计数宽度
	localparam CNT_IDLE_WIDTH = $clog2(C_IDLE_CYCLES + 1); // 空闲周期饱和计数宽度

	//-----------------计数信号-----------------//
	reg [CNT_WORD_WIDTH - 1:0]cnt_frame_words = {CNT_WORD_WIDTH{1'b0}}; // 当前帧中已经缓存的256位字数量
	reg [CNT_IDLE_WIDTH - 1:0]cnt_idle_cycles = {CNT_IDLE_WIDTH{1'b0}}; // 当前响应输入的连续空闲周期数

	//----------------寄存器信号----------------//
	reg [255:0]reg_hold_data = 256'd0;          // 等待确定帧边界的最新响应字

	//-----------------标志信号-----------------//
	reg flag_hold_valid = 1'b0;                 // 延迟字缓存占用状态
	wire flag_size_last;                        // 达到最大UDP负载时强制结束报文
	wire flag_idle_last;                        // 上游空闲达到阈值时结束当前响应
	wire flag_emit_last;                        // 当前缓存字需要作为帧尾提交
	wire flag_emit_body;                        // 新字到达时提交前一个非帧尾字
	wire flag_last_fire;                        // 负载尾字和长度描述符原子提交
	wire flag_body_fire;                        // 普通负载字完成下游握手

	//-----------------其他信号-----------------//
	// 负载长度计算在这里统一扩展位宽，避免移位时截断高位。
	wire [15:0]frame_payload_bytes;             // 将帧内字数扩展为16位字节长度

	//-----------------输出信号-----------------//
	//用户输入接口
	wire data_ready_o;                          // 输出桥接前的上游接收许可

	//AXIS负载输出接口
	wire [255:0]axis_tdata_o;                   // 输出桥接前的256位负载数据
	wire [31:0]axis_tkeep_o;                    // 输出桥接前的全字节有效掩码
	wire axis_tvalid_o;                         // 输出桥接前的负载有效信号
	wire axis_tlast_o;                          // 输出桥接前的负载结束信号

	//长度描述符输出接口
	wire [15:0]desc_length_o;                   // 输出桥接前的UDP总长度
	wire desc_valid_o;                          // 输出桥接前的描述符有效信号

	//---------------其他信号连线---------------//
	//其他信号连线
	assign flag_size_last = flag_hold_valid && (cnt_frame_words == C_MAX_WORDS); // 固定上限防止产生jumbo负载
	assign flag_idle_last = flag_hold_valid && (cnt_idle_cycles == C_IDLE_CYCLES); // 空闲仅用于识别缺少显式last的AMDUSB4输出
	assign flag_emit_last = flag_size_last || flag_idle_last; // 两类边界共享同一个帧尾提交路径
	assign flag_emit_body = flag_hold_valid && !flag_emit_last && i_data_valid; // 连续响应时每拍前移一个256位字

	//其他信号连线
	assign flag_last_fire = flag_emit_last && i_axis_tready && i_desc_ready; // 帧尾与长度不能分开入队
	assign flag_body_fire = flag_emit_body && i_axis_tready; // 普通字只依赖负载FIFO许可
	assign axis_tdata_o = reg_hold_data;        // 缓存字保持稳定直到握手成功
	assign axis_tkeep_o = 32'hffff_ffff;        // asmcehnk_mux始终产生完整256位字
	assign axis_tvalid_o = flag_emit_body || (flag_emit_last && i_desc_ready); // 帧尾等待描述符FIFO同时可写
	assign axis_tlast_o = flag_emit_last;       // 只有尺寸或空闲边界产生tlast
	assign frame_payload_bytes = {{(16 - CNT_WORD_WIDTH){1'b0}}, cnt_frame_words} << 5; // 防止窄位宽左移截断长度
	assign desc_length_o = 16'd8 + frame_payload_bytes; // UDP长度等于8字节头加实际负载字节数

	//AXIS接口
	assign desc_valid_o = flag_emit_last && i_axis_tready; // 描述符等待负载FIFO同时接收帧尾
	assign data_ready_o = !flag_hold_valid || (!flag_emit_last && i_axis_tready); // 帧尾提交周期暂停新输入以简化边界

	//---------------输出信号连线---------------//
	//用户输入接口
	assign o_data_ready = data_ready_o;         // 向asmcehnk复用器施加网络回压

	//AXIS负载输出接口
	assign o_axis_tdata = axis_tdata_o;         // 导出稳定的UDP负载数据
	assign o_axis_tkeep = axis_tkeep_o;         // 导出完整响应字的字节掩码
	assign o_axis_tvalid = axis_tvalid_o;       // 导出负载有效握手
	assign o_axis_tlast = axis_tlast_o;         // 导出UDP负载帧尾

	//长度描述符输出接口
	assign o_desc_length = desc_length_o;       // 导出与负载帧匹配的UDP长度
	assign o_desc_valid = desc_valid_o;         // 导出长度描述符写入请求

	//-------------主要任务处理区域-------------//
	// 帧内字计数只在首字捕获、普通字前移或帧尾提交时改变。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			cnt_frame_words <= {CNT_WORD_WIDTH{1'b0}}; // 新帧尚未包含任何响应字
		end else begin
			if(flag_last_fire == 1'b1)begin
				cnt_frame_words <= {CNT_WORD_WIDTH{1'b0}}; // 下一响应从第一个字重新计数
			end else if(flag_body_fire == 1'b1)begin
				cnt_frame_words <= cnt_frame_words + 1'b1; // 记录新缓存字所属的帧长度
			end else if(flag_hold_valid == 1'b0 && i_data_valid == 1'b1 && data_ready_o == 1'b1)begin
				cnt_frame_words <= {{(CNT_WORD_WIDTH - 1){1'b0}}, 1'b1}; // 首字计入当前UDP负载长度
			end else begin
				cnt_frame_words <= cnt_frame_words; // 其余周期保持当前UDP帧长度
			end
		end
	end

	// 空闲计数器仅在持有待定帧尾且上游没有新响应字时累加。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			cnt_idle_cycles <= {CNT_IDLE_WIDTH{1'b0}}; // 空闲判包从零重新计时
		end else begin
			if(flag_last_fire == 1'b1)begin
				cnt_idle_cycles <= {CNT_IDLE_WIDTH{1'b0}}; // 成功分包后清除空闲历史
			end else if(flag_body_fire == 1'b1)begin
				cnt_idle_cycles <= {CNT_IDLE_WIDTH{1'b0}}; // 新数据到达后重新开始空闲检测
			end else if(flag_hold_valid == 1'b0 && i_data_valid == 1'b1 && data_ready_o == 1'b1)begin
				cnt_idle_cycles <= {CNT_IDLE_WIDTH{1'b0}}; // 首字到达时没有累计空闲
			end else if(flag_hold_valid == 1'b1 && i_data_valid == 1'b0 && flag_emit_last == 1'b0)begin
				cnt_idle_cycles <= cnt_idle_cycles + 1'b1; // 没有后续字时等待空闲阈值形成短包
			end else begin
				cnt_idle_cycles <= cnt_idle_cycles; // 数据停顿未满足判包条件时保持计数
			end
		end
	end

	// 延迟缓存占用标志定义当前是否存在尚未确定last属性的响应字。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			flag_hold_valid <= 1'b0;            // 复位后不保留未完成响应
		end else begin
			if(flag_last_fire == 1'b1)begin
				flag_hold_valid <= 1'b0;        // 帧尾和描述符提交后释放延迟字缓存
			end else if(flag_body_fire == 1'b1)begin
				flag_hold_valid <= 1'b1;        // 连续数据流始终保持一个延迟字
			end else if(flag_hold_valid == 1'b0 && i_data_valid == 1'b1 && data_ready_o == 1'b1)begin
				flag_hold_valid <= 1'b1;        // 首字进入延迟边界判定状态
			end else begin
				flag_hold_valid <= flag_hold_valid; // 没有握手事件时维持缓存占用状态
			end
		end
	end

	// 数据寄存器在首字或连续字握手时更新，回压期间必须保持稳定。
	always@(posedge i_clk or negedge i_rstn)begin
		if(i_rstn == 1'b0)begin
			reg_hold_data <= 256'd0;            // 复位时清空尚未提交的数据内容
		end else begin
			if(flag_last_fire == 1'b1)begin
				reg_hold_data <= reg_hold_data; // 帧尾提交无需改写已发送的数据内容
			end else if(flag_body_fire == 1'b1)begin
				reg_hold_data <= i_data;        // 前一字提交后立即保留同周期的新响应字
			end else if(flag_hold_valid == 1'b0 && i_data_valid == 1'b1 && data_ready_o == 1'b1)begin
				reg_hold_data <= i_data;        // 捕获新响应的首个256位字
			end else begin
				reg_hold_data <= reg_hold_data; // 没有新输入时保持AXIS输出稳定
			end
		end
	end

endmodule
