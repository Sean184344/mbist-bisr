`timescale 1ns/1ps
// Self-contained logical memory: MBIST/BISR, access arbitration, and reference RAM.
// Pulse start after reset, wait for done, and use the memory only when user_ready.
module mbist_memory #(
 parameter AW=4, DW=8, SPARES=2, READ_LATENCY=1
)(
 input wire clk,rst_n,start,
 output wire busy,done,fault_found,unrepairable,repair_pass,
 output wire [AW:0] fail_count,first_fail_addr,
 output wire [DW-1:0] first_fail_mask,
 output wire [SPARES-1:0] spare_bad,
 input wire user_en,user_we,
 input wire [AW-1:0] user_addr,
 input wire [DW-1:0] user_wdata,
 output wire user_ready,user_rvalid,
 output wire [DW-1:0] user_rdata
);
 wire mem_en,mem_we;
 wire [AW:0] mem_addr;
 wire [DW-1:0] mem_wdata,mem_rdata;
 mbist_subsystem #(.AW(AW),.DW(DW),.SPARES(SPARES),.READ_LATENCY(READ_LATENCY)) subsystem (
   .clk(clk),.rst_n(rst_n),.start(start),
   .busy(busy),.done(done),.fault_found(fault_found),.unrepairable(unrepairable),.repair_pass(repair_pass),
   .fail_count(fail_count),.first_fail_addr(first_fail_addr),.first_fail_mask(first_fail_mask),.spare_bad(spare_bad),
   .user_en(user_en),.user_we(user_we),.user_addr(user_addr),.user_wdata(user_wdata),
   .user_ready(user_ready),.user_rvalid(user_rvalid),.user_rdata(user_rdata),
   .mem_en(mem_en),.mem_we(mem_we),.mem_addr(mem_addr),.mem_wdata(mem_wdata),.mem_rdata(mem_rdata)
 );
 mbist_ram #(.AW(AW),.DW(DW),.SPARES(SPARES),.READ_LATENCY(READ_LATENCY)) ram (
   .clk(clk),.mem_en(mem_en),.mem_we(mem_we),.mem_addr(mem_addr),.mem_wdata(mem_wdata),.mem_rdata(mem_rdata)
 );
endmodule
