`timescale 1ns/1ps
// Cocotb-owned stimulus with a Verilog memory model so read timing is simulated
// by the same event scheduling as a physical RAM, including registered reads.
module cocotb_top #(
 parameter READ_LATENCY=0
)(
 input wire clk,rst_n,start,user_en,user_we,
 input wire [3:0] user_addr,
 input wire [7:0] user_wdata,
 input wire [159:0] stuck_zero,stuck_one,
 output wire busy,done,fault_found,unrepairable,repair_pass,user_ready,user_rvalid,
 output wire [4:0] fail_count,first_fail_addr,mem_addr,
 output wire [3:0] spare_bad,
 output wire [7:0] first_fail_mask,user_rdata,mem_wdata,
 output wire mem_en,mem_we
);
 wire [7:0] mem_rdata;
 reg [7:0] memory[0:19], registered_data;
 wire [7:0] fault_data=(memory[mem_addr] & ~stuck_zero[8*mem_addr +: 8]) |
                      stuck_one[8*mem_addr +: 8];
 assign mem_rdata=READ_LATENCY ? registered_data : fault_data;
 always @(posedge clk) begin
   if(mem_en && mem_we) memory[mem_addr]<=mem_wdata;
   if(mem_en && !mem_we) registered_data<=fault_data;
 end
 mbist_subsystem #(.SPARES(4),.READ_LATENCY(READ_LATENCY)) dut(.*);
endmodule
