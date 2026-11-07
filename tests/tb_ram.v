`timescale 1ns/1ps
module tb_ram;
parameter READ_LATENCY=1;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0,user_en=0,user_we=0;
reg [3:0] user_addr=0;
reg [7:0] user_wdata=0;
wire busy,done,fault_found,unrepairable,repair_pass,user_ready,user_rvalid,mem_en,mem_we;
wire [4:0] fail_count,first_fail_addr,mem_addr;
wire [1:0] spare_bad;
wire [7:0] first_fail_mask,user_rdata,mem_wdata,mem_rdata;
integer cycles,a;
mbist_subsystem #(.READ_LATENCY(READ_LATENCY)) dut(.*);
mbist_ram #(.READ_LATENCY(READ_LATENCY)) ram(.*);
initial begin
 repeat(2) @(negedge clk); rst_n=1; start=1;
 @(negedge clk); start=0; cycles=0;
 while(!done && cycles<511) begin @(negedge clk); cycles=cycles+1; end
 if(!done || !repair_pass || fault_found) $fatal(1,"reference RAM qualification");
 for(a=0;a<16;a=a+1) begin
   user_en=1; user_we=1; user_addr=a; user_wdata=a*13;
   @(negedge clk);
 end
 user_we=0;
 for(a=0;a<16;a=a+1) begin
   user_addr=a;
   if(READ_LATENCY==1) @(posedge clk);
   #1;
   if(!user_rvalid || user_rdata!==8'(a*13)) $fatal(1,"reference RAM data");
   @(negedge clk);
 end
 $display("PASS reference RAM READ_LATENCY=%0d",READ_LATENCY); $finish;
end
endmodule
