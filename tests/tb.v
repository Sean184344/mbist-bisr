`timescale 1ns/1ps
module tb;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0;
wire busy,done,fault_found,unrepairable,repair_pass,mem_en,mem_we;
wire [1:0] spare_bad;
wire [4:0] fail_count,mem_addr,mapped_addr,first_fail_addr;
wire [7:0] first_fail_mask,mem_wdata;
reg [3:0] user_addr=0;
reg [7:0] mem_rdata;
reg [7:0] memory [0:17];
integer faults=0,cycles=0,spare_fault=0,transition_fault=0,late_fault=0;
mbist_bisr dut(.*);
always @* begin
 mem_rdata=memory[mem_addr];
 if(faults>=1 && mem_addr==3) mem_rdata=mem_rdata & 8'hfe;
 if(faults>=2 && mem_addr==7) mem_rdata=mem_rdata | 8'h80;
 if(faults>=3 && mem_addr==11) mem_rdata=mem_rdata & 8'hfd;
 if(spare_fault && mem_addr==16) mem_rdata=mem_rdata & 8'hfe;
 if(late_fault && dut.mode==2 && mem_addr==16) mem_rdata=mem_rdata & 8'hfe;
end
always @(posedge clk) if(mem_en && mem_we) begin
 if(transition_fault && mem_addr==5)
   memory[mem_addr]<=mem_wdata & (memory[mem_addr] | 8'hfe);
 else memory[mem_addr]<=mem_wdata;
end
task run_case;
input integer n,s,t,l;
input integer should_pass;
integer a;
begin
 @(negedge clk); faults=n; spare_fault=s; transition_fault=t; late_fault=l; start=1;
 @(negedge clk); start=0; cycles=0;
 while(!done && cycles<350) begin @(negedge clk); cycles=cycles+1; end
 if(!done || cycles!=340) $fatal(1,"completion cycles=%0d",cycles);
 if(repair_pass !== should_pass[0] || unrepairable !== !should_pass[0])
   $fatal(1,"repair status n=%0d s=%0d t=%0d l=%0d",n,s,t,l);
 if(fault_found !== ((n+s+t+l)!=0)) $fatal(1,"fault status");
 if(spare_bad !== (s ? 2'b01 : 2'b00)) $fatal(1,"spare qualification");
 if(n==1 && !s && !t) begin
   user_addr=3; #1; if(mapped_addr!=16) $fatal(1,"mapping");
   if(first_fail_addr!=3 || first_fail_mask!=1) $fatal(1,"first failure");
 end
 if(n==1 && s) begin
   user_addr=3; #1; if(mapped_addr!=17) $fatal(1,"bad spare used");
 end
 if(should_pass) for(a=0;a<16;a=a+1) begin
   user_addr=a; #1;
   if(memory[mapped_addr]!==0) $fatal(1,"repaired memory not zero");
 end
end
endtask
initial begin
 if($test$plusargs("waves")) begin $dumpfile("build/mbist.vcd"); $dumpvars(0,tb); end
 repeat(2) @(negedge clk); rst_n=1;
 run_case(0,0,0,0,1); run_case(1,0,0,0,1);
 run_case(2,0,0,0,1); run_case(3,0,0,0,0);
 run_case(1,1,0,0,1); run_case(2,1,0,0,0);
 run_case(0,0,1,0,1); run_case(1,0,0,1,0);
 @(negedge clk); start=1;
 @(negedge clk); start=0;
 repeat(30) @(negedge clk);
 rst_n=0; @(negedge clk);
 if(busy || done || repair_pass || spare_bad) $fatal(1,"reset abort");
 rst_n=1; run_case(0,0,0,0,1);
 $display("PASS: repair verification, bad spares, exhaustion, transition, late fault, reset/restart");
 $finish;
end
endmodule
