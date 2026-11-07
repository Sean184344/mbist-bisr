`timescale 1ns/1ps
// Arbitration/translation wrapper for a RAM with read latency zero or one.
// User accesses are enabled only after a successful destructive MBIST run.
module mbist_subsystem #(
 parameter AW=4, DW=8, SPARES=2, READ_LATENCY=0
)(
 input wire clk, rst_n, start,
 output wire busy, done, fault_found, unrepairable, repair_pass,
 output wire [AW:0] fail_count, first_fail_addr,
 output wire [DW-1:0] first_fail_mask,
 output wire [SPARES-1:0] spare_bad,
 input wire user_en, user_we,
 input wire [AW-1:0] user_addr,
 input wire [DW-1:0] user_wdata,
 output wire user_ready, user_rvalid,
 output wire [DW-1:0] user_rdata,
 output wire mem_en, mem_we,
 output wire [AW:0] mem_addr,
 output wire [DW-1:0] mem_wdata,
 input wire [DW-1:0] mem_rdata
);
 wire test_en,test_we;
 wire [AW:0] test_addr,mapped_addr;
 wire [DW-1:0] test_wdata;
 mbist_bisr #(.AW(AW),.DW(DW),.SPARES(SPARES),.READ_LATENCY(READ_LATENCY)) controller (
   .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),
   .fault_found(fault_found),.unrepairable(unrepairable),.repair_pass(repair_pass),
   .fail_count(fail_count),.first_fail_addr(first_fail_addr),
   .first_fail_mask(first_fail_mask),.spare_bad(spare_bad),
   .user_addr(user_addr),.mapped_addr(mapped_addr),
   .mem_en(test_en),.mem_we(test_we),.mem_addr(test_addr),
   .mem_wdata(test_wdata),.mem_rdata(mem_rdata)
 );
 assign user_ready=rst_n && !start && !busy && done && repair_pass;
 assign mem_en=rst_n && (busy ? test_en : user_ready && user_en);
 assign mem_we=mem_en && (busy ? test_we : user_we);
 assign mem_addr=busy ? test_addr : mapped_addr;
 assign mem_wdata=busy ? test_wdata : user_wdata;
 reg read_response;
 always @(posedge clk) begin
   if(!rst_n || start) read_response<=0;
   else read_response<=user_ready && user_en && !user_we;
 end
 assign user_rvalid=user_ready && ((READ_LATENCY==0) ? (user_en && !user_we) : read_response);
 assign user_rdata=user_rvalid ? mem_rdata : {DW{1'b0}};
endmodule
