`timescale 1ns/1ps
// Execute the Cocotb Verilog fixture even when the Python package is unavailable.
module tb_cocotb_fixture;
parameter READ_LATENCY=0;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0,user_en=0,user_we=0;
reg [3:0] user_addr=0;
reg [7:0] user_wdata=0;
reg [159:0] stuck_zero=0,stuck_one=0;
wire busy,done,fault_found,unrepairable,repair_pass,user_ready,user_rvalid,mem_en,mem_we;
wire [4:0] fail_count,first_fail_addr,mem_addr;
wire [3:0] spare_bad;
wire [7:0] first_fail_mask,user_rdata,mem_wdata;
integer cycles,a,n;
cocotb_top #(.READ_LATENCY(READ_LATENCY)) dut(.*);
initial begin
 repeat(2) @(negedge clk); rst_n=1;
 for(n=0;n<2;n=n+1) begin
   if(n==1) begin stuck_zero[3*8]=1; stuck_one[16*8]=1; end
   start=1; @(negedge clk); start=0; cycles=0;
   while(!done && cycles<550) begin @(negedge clk); cycles=cycles+1; end
   if(!done || !repair_pass || unrepairable || cycles!=(10+5*READ_LATENCY)*36)
     $fatal(1,"fixture completion");
   if(fault_found!==(n!=0) || spare_bad!==(n==1 ? 4'b0001 : 4'b0000))
     $fatal(1,"fixture fault injection");
   if(n==1) begin
     user_addr=3; #1;
     if(mem_addr!=17 || first_fail_addr!=16 || first_fail_mask!=1) $fatal(1,"fixture diagnosis");
   end
   for(a=0;a<16;a=a+1) begin
     @(negedge clk); user_en=1; user_we=1; user_addr=a; user_wdata=a*13;
   end
   @(negedge clk); user_we=0;
   for(a=0;a<16;a=a+1) begin
     user_addr=a;
     if(READ_LATENCY) @(posedge clk);
     #1;
     if(!user_rvalid || user_rdata!==8'(a*13)) $fatal(1,"fixture user data");
     @(negedge clk);
   end
   user_en=0; user_we=0;
 end
 $display("PASS Cocotb HDL fixture READ_LATENCY=%0d",READ_LATENCY); $finish;
end
endmodule
