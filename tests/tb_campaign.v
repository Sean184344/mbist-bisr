`timescale 1ns/1ps
module tb_campaign;
parameter READ_LATENCY=0;
localparam AW=4,DW=8,SPARES=4,DEPTH=16,TOTAL=20;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0,user_en=0,user_we=0;
reg [3:0] user_addr=0;
reg [7:0] user_wdata=0;
wire busy,done,fault_found,unrepairable,repair_pass,user_ready,user_rvalid,mem_en,mem_we;
wire [4:0] fail_count,first_fail_addr,mem_addr;
wire [3:0] spare_bad;
wire [7:0] first_fail_mask,user_rdata,mem_wdata,mem_rdata;
reg [7:0] memory[0:TOTAL-1], stuck_zero[0:TOTAL-1], stuck_one[0:TOTAL-1];
reg [7:0] registered_data;
wire [7:0] fault_data=(memory[mem_addr] & ~stuck_zero[mem_addr]) | stuck_one[mem_addr];
assign mem_rdata=READ_LATENCY ? registered_data : fault_data;
integer a,cycles,trace_fd,result_fd;
reg [1023:0] zero_file,one_file,trace_file,result_file,wave_file;
mbist_subsystem #(.SPARES(SPARES),.READ_LATENCY(READ_LATENCY)) dut(.*);
always @(posedge clk) begin
 if(mem_en && mem_we) memory[mem_addr]<=mem_wdata;
 if(mem_en && !mem_we) registered_data<=fault_data;
 if(busy && mem_en) $fdisplay(trace_fd,"%0d %0d %0d",mem_addr,mem_we,mem_we ? mem_wdata : 0);
end
initial begin
 if($value$plusargs("waves=%s",wave_file)) begin $dumpfile(wave_file); $dumpvars(0,tb_campaign); end
 if(!$value$plusargs("zero=%s",zero_file) || !$value$plusargs("one=%s",one_file) ||
    !$value$plusargs("trace=%s",trace_file) || !$value$plusargs("result=%s",result_file))
   $fatal(1,"missing campaign files");
 $readmemh(zero_file,stuck_zero); $readmemh(one_file,stuck_one);
 trace_fd=$fopen(trace_file,"w"); result_fd=$fopen(result_file,"w");
 if(!trace_fd || !result_fd) $fatal(1,"cannot open output");
 repeat(2) @(negedge clk); rst_n=1; start=1;
 @(negedge clk); start=0; cycles=0;
 while(!done && cycles<550) begin @(negedge clk); cycles=cycles+1; end
 if(!done) $fatal(1,"timeout");
 $fdisplay(result_fd,"%0d %0d %0d %0d %0d %0d %0d %0d",cycles,fault_found,unrepairable,repair_pass,fail_count,first_fail_addr,first_fail_mask,spare_bad);
 for(a=0;a<DEPTH;a=a+1) begin
   user_addr=a; #1; $fdisplay(result_fd,"%0d",mem_addr);
 end
 if(repair_pass) begin
   for(a=0;a<DEPTH;a=a+1) begin
     @(negedge clk); user_en=1; user_we=1; user_addr=a; user_wdata=a*13;
   end
   @(negedge clk); user_we=0;
   for(a=0;a<DEPTH;a=a+1) begin
     user_addr=a;
     if(READ_LATENCY) @(posedge clk);
     #1;
     if(!user_rvalid || user_rdata!==8'(a*13)) $fatal(1,"repaired user data address=%0d",a);
     @(negedge clk);
   end
 end
 $fclose(trace_fd); $fclose(result_fd); $finish;
end
endmodule
