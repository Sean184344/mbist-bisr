`timescale 1ns/1ps
module tb_system;
parameter AW=4,DW=8,SPARES=2,READ_LATENCY=0;
localparam DEPTH=1<<AW, TOTAL=DEPTH+SPARES, MARCH_COST=10+5*READ_LATENCY, CYCLES=MARCH_COST*(2*DEPTH+SPARES);
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0,user_en=0,user_we=0;
reg [AW-1:0] user_addr=0;
reg [DW-1:0] user_wdata=0;
wire busy,done,fault_found,unrepairable,repair_pass,user_ready,user_rvalid,mem_en,mem_we;
wire [AW:0] fail_count,first_fail_addr,mem_addr;
wire [SPARES-1:0] spare_bad;
wire [DW-1:0] first_fail_mask,user_rdata,mem_wdata;
wire [DW-1:0] mem_rdata;
reg [DW-1:0] raw_rdata, registered_rdata;
reg [DW-1:0] memory[0:TOTAL-1];
integer kind=0, physical, cycles, a, round, k, commands, reads;
// kind: 0 clean; 1 rising transition; 2 falling transition;
// 3 decoder alias (logical physical address 1 selects 0);
// 4 inversion coupling (write address 0 toggles bit 0 at address 1);
// 5 every spare stuck at zero; 6 every main row stuck at zero.
mbist_subsystem #(.AW(AW),.DW(DW),.SPARES(SPARES),.READ_LATENCY(READ_LATENCY)) dut(.*);
always @* begin
 physical=(kind==3 && mem_addr==1) ? 0 : int'(mem_addr);
 raw_rdata=memory[physical];
 if((kind==5 && mem_addr>=DEPTH) || (kind==6 && mem_addr<DEPTH)) raw_rdata=0;
end
assign mem_rdata=(READ_LATENCY==0) ? raw_rdata : registered_rdata;
always @(posedge clk) if(mem_en && !mem_we) registered_rdata<=raw_rdata;
always @(posedge clk) if(mem_en && mem_we) begin
 if(kind==1 && physical==0)
   memory[physical]<=mem_wdata & (memory[physical] | {{(DW-1){1'b1}},1'b0});
 else if(kind==2 && physical==0)
   memory[physical]<=mem_wdata | (memory[physical] & {{(DW-1){1'b0}},1'b1});
 else memory[physical]<=mem_wdata;
 if(kind==4 && physical==0) memory[1]<=memory[1] ^ {{(DW-1){1'b0}},1'b1};
end
function [DW-1:0] pattern;
input integer address, pass;
begin pattern=(((address & 1) ^ pass)!=0) ? {DW{1'b1}} : {DW{1'b0}}; end
endfunction
task run_case;
input integer fault_kind, expect_pass;
begin
 @(negedge clk); kind=fault_kind; start=1; user_en=1; user_we=1;
 @(negedge clk); start=0; cycles=0; commands=0; reads=0;
 while(!done && cycles<=CYCLES) begin
   if(user_ready) $fatal(1,"user access during MBIST");
   if(mem_en) begin commands=commands+1; if(!mem_we) reads=reads+1; end
   // A start pulse during busy must be ignored.
   start=(cycles==5);
   @(negedge clk); cycles=cycles+1;
 end
 start=0; user_en=0; user_we=0; #1;
 if(!done || cycles!=CYCLES) $fatal(1,"cycle count kind=%0d cycles=%0d",kind,cycles);
 if(commands!=10*(2*DEPTH+SPARES) || reads!=5*(2*DEPTH+SPARES))
   $fatal(1,"duplicate or missing memory transactions");
 if(repair_pass!==expect_pass[0] || unrepairable!==!expect_pass[0])
   $fatal(1,"status kind=%0d pass=%0d expected=%0d",kind,repair_pass,expect_pass);
 if(fault_found!==(kind!=0)) $fatal(1,"detection kind=%0d",kind);
 if(kind==5 && spare_bad!=={SPARES{1'b1}}) $fatal(1,"spare bitmap");
 if(kind==6 && fail_count!=={(AW+1){1'b1}}) $fatal(1,"counter saturation");
 if(expect_pass!=0) begin
   if(!user_ready) $fatal(1,"user port not enabled");
   for(round=0;round<2;round=round+1) begin
     for(a=0;a<DEPTH;a=a+1) begin
       @(negedge clk); user_en=1; user_we=1; user_addr=AW'(a); user_wdata=pattern(a,round);
     end
     @(negedge clk); user_we=0;
     for(a=0;a<DEPTH;a=a+1) begin
       user_addr=AW'(a);
       if(READ_LATENCY==1) @(posedge clk);
       #1;
       if(!user_rvalid) $fatal(1,"missing read response");
       if(user_rdata!==pattern(a,round)) $fatal(1,"user data kind=%0d addr=%0d",kind,a);
       @(negedge clk);
     end
   end
   // A registered response must survive deassertion of the request.
   user_addr=0; user_en=1; user_we=0;
   @(posedge clk); #1; user_en=0; #1;
   if(READ_LATENCY==1) begin
     if(!user_rvalid || user_rdata!==pattern(0,1)) $fatal(1,"response lost on request release");
   end else if(user_rvalid) $fatal(1,"unexpected asynchronous response");
   @(negedge clk); @(posedge clk); #1;
   if(user_rvalid) $fatal(1,"response valid did not clear");
 end else begin
   user_en=1; user_we=1; #1;
   if(user_ready || mem_en || mem_we) $fatal(1,"failed memory accessible");
 end
 user_en=0; user_we=0;
end
endtask
task abort_test;
input integer delay_cycles;
begin
 @(negedge clk); start=1;
 @(negedge clk); start=0;
 repeat(delay_cycles) @(negedge clk);
 rst_n=0; user_en=1; user_we=1; #1;
 if(mem_en || mem_we || user_ready) $fatal(1,"reset arbitration");
 @(negedge clk);
 if(busy || done || repair_pass || (spare_bad!=0) || (fail_count!=0) || fault_found || unrepairable)
   $fatal(1,"reset status");
 rst_n=1; user_en=0; user_we=0;
 run_case(0,1);
end
endtask
initial begin
 for(k=0;k<TOTAL;k=k+1) memory[k]=0;
 repeat(2) @(negedge clk); rst_n=1;
 #1; if(user_ready || mem_en) $fatal(1,"unqualified memory accessible");
 run_case(0,1); run_case(1,1); run_case(2,1);
 run_case(3,int'(SPARES>=2)); run_case(4,1); run_case(5,1);
 run_case(6,int'(SPARES>=DEPTH)); run_case(0,1);
 // Abort in each of spare qualification, raw diagnosis, and verification.
 abort_test(3); abort_test(MARCH_COST*SPARES+3); abort_test(MARCH_COST*(SPARES+DEPTH)+3);
 repeat(3) @(negedge clk);
 if(!done || !repair_pass || !user_ready || busy) $fatal(1,"completion not sticky");
 @(negedge clk); rst_n=0; user_en=1; user_we=1; #1;
 if(mem_en || mem_we || user_ready) $fatal(1,"reset does not gate port");
 $display("PASS system AW=%0d DW=%0d SPARES=%0d READ_LATENCY=%0d",AW,DW,SPARES,READ_LATENCY); $finish;
end
endmodule
